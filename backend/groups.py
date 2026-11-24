"""Groups: My Groups, Groups to join, join by code, leaderboard, goals.

Rules (documented choices):
- A member's group points = XP from their verified habits AFTER they joined that
  group, so everyone starts from zero and people who join later compete fairly.
  Only the group's own habit counts (GROUP_HABIT: a Book group counts Reading only).
  Leaving deletes the membership, so rejoining starts from zero again.
- Leaderboard: most points first; ties go to whoever joined first.
- Group goal: XP all current members earned together this calendar month
  (Saudi time), counting only the group's habit and only after each member joined.
- The invite code is only sent to members (they are the ones who share it).
"""
import calendar
import secrets
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import and_, false, func
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, SQLModel, select

from auth import verify_token
from database import get_session
from deps import get_current_user
from models import KSA_TZ, Habit, HabitLog, Group, GroupDismissal, GroupMember, User, today_ksa

router = APIRouter(prefix="/groups", tags=["groups"])


class JoinByCode(SQLModel):
    group_code: str


# Each group type decides its icon and its category ("Study" or "Health").
# The app also uses the type to pick which habits the group needs.
GROUP_TYPES = {"run": "Health", "book": "Study", "water": "Health", "workout": "Health"}

# The one habit that earns points inside each group type (habit names from seed_habits.py,
# compared in lower case). Points from other habits don't count in that group.
GROUP_HABIT = {"run": "walking", "book": "reading", "water": "drink water", "workout": "workout"}

# Invite codes: no 0/O or 1/I/L, so friends can't mistype them.
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 6


class CreateGroup(SQLModel):
    # The body of POST /groups (the "Create group" card in the app).
    name: str
    description: str = ""
    icon_key: str = "run"                 # "run", "book", "water" or "workout"
    goal_target: Optional[int] = None     # optional monthly XP goal, e.g. 1000


@dataclass
class BoardRow:
    rank: int
    user_id: int
    name: str
    points: int


def _utc_naive(value: datetime) -> datetime:
    # Timestamps are stored as UTC without a timezone; compare in the same form.
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _month_window():
    # Start of this month (Saudi time) as stored-UTC, and the month's last day.
    today = today_ksa()
    start = datetime(today.year, today.month, 1, tzinfo=KSA_TZ)
    last_day = calendar.monthrange(today.year, today.month)[1]
    return _utc_naive(start), today.replace(day=last_day)


def _points_rows(session: Session, group_id: int, since: Optional[datetime] = None):
    # One row per member: (user_id, username, display_name, joined_at, points).
    # Counts only the group's habit, verified after the member joined.
    group = session.get(Group, group_id)
    habit_name = GROUP_HABIT.get((group.icon_key or "").lower()) if group else None
    if habit_name:
        habit_ids = select(Habit.id).where(func.lower(Habit.name) == habit_name)
        habit_filter = HabitLog.habit_id.in_(habit_ids)
    else:
        habit_filter = false()  # unknown group type: no habit earns points here
    log_filter = [
        HabitLog.user_id == GroupMember.user_id,
        HabitLog.verification_status == "verified",
        HabitLog.completed_at >= GroupMember.joined_at,
        habit_filter,
    ]
    if since is not None:
        log_filter.append(HabitLog.completed_at >= since)
    return session.exec(
        select(
            GroupMember.user_id,
            User.username,
            User.display_name,
            GroupMember.joined_at,
            func.coalesce(func.sum(HabitLog.points_earned), 0),
        )
        .join(User, User.id == GroupMember.user_id)
        .outerjoin(HabitLog, and_(*log_filter))
        .where(GroupMember.group_id == group_id)
        .group_by(GroupMember.user_id, User.username, User.display_name, GroupMember.joined_at)
    ).all()


def leaderboard(session: Session, group_id: int) -> list[BoardRow]:
    rows = sorted(
        _points_rows(session, group_id),
        key=lambda r: (-int(r[4]), r[3], r[0]),  # points desc, joined first, id
    )
    return [
        BoardRow(rank=i + 1, user_id=uid, name=display or username, points=int(points))
        for i, (uid, username, display, _joined, points) in enumerate(rows)
    ]


def group_to_dict(session: Session, group: Group, user_id: int) -> dict:
    # The shape _Group.fromJson expects in groups_screen.dart.
    board = leaderboard(session, group.id)
    me = next((row for row in board if row.user_id == user_id), None)
    goal = None
    if group.goal_target:
        month_start, month_end = _month_window()
        current = sum(int(r[4]) for r in _points_rows(session, group.id, since=month_start))
        goal = {
            "title": group.goal_title or f"Earn {group.goal_target:,} XP together this month",
            "current": current,
            "target": group.goal_target,
            "end_date": month_end.isoformat(),
        }
    return {
        "id": group.id,
        "group_name": group.name,
        "description": group.description,
        "category": group.category,
        "icon_key": group.icon_key,
        "group_code": group.code if me else None,
        "member_count": len(board),
        "is_joined": me is not None,
        "user_rank": me.rank if me else 0,
        "user_points": me.points if me else 0,
        "goal": goal,
    }


def _get_group(session: Session, group_id: int) -> Group:
    group = session.get(Group, group_id)
    if not group:
        raise HTTPException(status_code=404, detail="Group not found.")
    return group


def _membership(session: Session, group_id: int, user_id: int) -> Optional[GroupMember]:
    return session.exec(
        select(GroupMember).where(GroupMember.group_id == group_id, GroupMember.user_id == user_id)
    ).first()


def _join(session: Session, group: Group, user_id: int) -> dict:
    if _membership(session, group.id, user_id) is None:
        session.add(GroupMember(group_id=group.id, user_id=user_id))
        dismissal = session.exec(
            select(GroupDismissal).where(GroupDismissal.group_id == group.id, GroupDismissal.user_id == user_id)
        ).first()
        if dismissal:
            session.delete(dismissal)
        try:
            session.commit()
        except IntegrityError:  # two quick taps: already joined
            session.rollback()
    return group_to_dict(session, group, user_id)


def _new_code(session: Session) -> str:
    # A random 6-character invite code that no other group uses yet.
    while True:
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        if session.exec(select(Group.id).where(Group.code == code)).first() is None:
            return code


@router.post("")
def create_group(
    data: CreateGroup,
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token),
):
    # Creates a group with a fresh invite code. The creator joins it right away,
    # so the reply includes the code for them to share.
    user = get_current_user(session, decoded_token)

    name = " ".join(data.name.split())  # trims and collapses extra spaces
    if not 3 <= len(name) <= 40:
        raise HTTPException(status_code=422, detail="Group name must be 3-40 characters.")
    description = data.description.strip()
    if len(description) > 200:
        raise HTTPException(status_code=422, detail="Description must be 200 characters or fewer.")
    icon_key = data.icon_key.strip().lower()
    if icon_key not in GROUP_TYPES:
        raise HTTPException(status_code=422, detail="Group type must be run, book, water or workout.")
    goal_target = data.goal_target
    if goal_target is not None and not 100 <= goal_target <= 100_000:
        raise HTTPException(status_code=422, detail="The group goal must be between 100 and 100,000 XP.")

    if session.exec(select(Group.id).where(func.lower(Group.name) == name.lower())).first() is not None:
        raise HTTPException(status_code=409, detail="A group with that name already exists.")

    group = Group(
        name=name,
        description=description,
        category=GROUP_TYPES[icon_key],
        icon_key=icon_key,
        code=_new_code(session),
        goal_title=f"Earn {goal_target:,} XP together this month" if goal_target else None,
        goal_target=goal_target,
    )
    session.add(group)
    try:
        session.flush()  # gives the group its id
        session.add(GroupMember(group_id=group.id, user_id=user.id))
        session.commit()
    except IntegrityError:
        # Someone created a group with the same name (or code) at the same moment.
        session.rollback()
        raise HTTPException(status_code=409, detail="A group with that name already exists.")
    session.refresh(group)
    return group_to_dict(session, group, user.id)


@router.get("/mine")
def my_groups(session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    user = get_current_user(session, decoded_token)
    groups = session.exec(
        select(Group).join(GroupMember, GroupMember.group_id == Group.id)
        .where(GroupMember.user_id == user.id)
        .order_by(GroupMember.joined_at)
    ).all()
    return [group_to_dict(session, group, user.id) for group in groups]


@router.get("/discover")
def discover_groups(session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    # Groups the user hasn't joined or hidden, biggest first.
    user = get_current_user(session, decoded_token)
    joined = select(GroupMember.group_id).where(GroupMember.user_id == user.id)
    hidden = select(GroupDismissal.group_id).where(GroupDismissal.user_id == user.id)
    candidates = session.exec(
        select(Group).where(Group.id.not_in(joined), Group.id.not_in(hidden)).order_by(Group.id)
    ).all()
    groups = [group_to_dict(session, group, user.id) for group in candidates]
    return sorted(groups, key=lambda g: (-g["member_count"], g["id"]))


@router.post("/join")
def join_by_code(
    data: JoinByCode,
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token),
):
    user = get_current_user(session, decoded_token)
    code = data.group_code.strip().upper()
    if not code:
        raise HTTPException(status_code=422, detail="Enter the group code.")
    group = session.exec(select(Group).where(Group.code == code)).first()
    if not group:
        raise HTTPException(status_code=404, detail="No group found with that code.")
    return _join(session, group, user.id)


@router.post("/{group_id}/join")
def join_group(group_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    user = get_current_user(session, decoded_token)
    return _join(session, _get_group(session, group_id), user.id)


@router.post("/{group_id}/dismiss")
def dismiss_group(group_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    # "Not interested": hide the group from Groups to join.
    user = get_current_user(session, decoded_token)
    _get_group(session, group_id)
    exists = session.exec(
        select(GroupDismissal.id).where(GroupDismissal.group_id == group_id, GroupDismissal.user_id == user.id)
    ).first()
    if exists is None:
        session.add(GroupDismissal(group_id=group_id, user_id=user.id))
        try:
            session.commit()
        except IntegrityError:
            session.rollback()
    return {"status": "ok"}


@router.delete("/{group_id}/dismiss")
def undo_dismiss_group(group_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    # "Undo" on the snack bar: show the group in suggestions again.
    user = get_current_user(session, decoded_token)
    dismissal = session.exec(
        select(GroupDismissal).where(GroupDismissal.group_id == group_id, GroupDismissal.user_id == user.id)
    ).first()
    if dismissal:
        session.delete(dismissal)
        session.commit()
    return {"status": "ok"}


@router.delete("/{group_id}/membership")
def leave_group(group_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    user = get_current_user(session, decoded_token)
    _get_group(session, group_id)
    member = _membership(session, group_id, user.id)
    if member:
        session.delete(member)
        session.commit()
    return {"status": "ok"}


@router.get("/{group_id}/leaderboard")
def group_leaderboard(group_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    # Every member, ranked. Also used as the member list.
    user = get_current_user(session, decoded_token)
    _get_group(session, group_id)
    if _membership(session, group_id, user.id) is None:
        raise HTTPException(status_code=403, detail="Join this group to see its leaderboard.")
    return [
        {
            "rank": row.rank,
            "user_id": row.user_id,
            "display_name": row.name,
            "points": row.points,
            "is_me": row.user_id == user.id,
        }
        for row in leaderboard(session, group_id)
    ]


def groups_joined(session: Session, user_id: int) -> int:
    return session.exec(
        select(func.count()).select_from(GroupMember).where(GroupMember.user_id == user_id)
    ).one()
