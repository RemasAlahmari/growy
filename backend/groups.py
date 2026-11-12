"""Groups ("rooms"): My Groups, Groups to join, join by code, leaderboard, goals.

Rules (documented choices):
- A member's group points = XP from their verified habits AFTER they joined that
  group, so people who join later compete fairly.
- Leaderboard: most points first; ties go to whoever joined first.
- Group goal: XP all current members earned together this calendar month
  (Saudi time), counting only XP earned after each member joined.
- The invite code is only sent to members (they are the ones who share it).
"""
import calendar
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import and_, func
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, SQLModel, select

from auth import verify_token
from database import get_session
from deps import get_current_user
from models import KSA_TZ, HabitLog, Room, RoomDismissal, RoomMember, User, today_ksa

router = APIRouter(prefix="/groups", tags=["groups"])


class JoinByCode(SQLModel):
    room_code: str


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


def _points_rows(session: Session, room_id: int, since: Optional[datetime] = None):
    # One row per member: (user_id, username, display_name, joined_at, points).
    log_filter = [
        HabitLog.user_id == RoomMember.user_id,
        HabitLog.verification_status == "verified",
        HabitLog.completed_at >= RoomMember.joined_at,
    ]
    if since is not None:
        log_filter.append(HabitLog.completed_at >= since)
    return session.exec(
        select(
            RoomMember.user_id,
            User.username,
            User.display_name,
            RoomMember.joined_at,
            func.coalesce(func.sum(HabitLog.points_earned), 0),
        )
        .join(User, User.id == RoomMember.user_id)
        .outerjoin(HabitLog, and_(*log_filter))
        .where(RoomMember.room_id == room_id)
        .group_by(RoomMember.user_id, User.username, User.display_name, RoomMember.joined_at)
    ).all()


def leaderboard(session: Session, room_id: int) -> list[BoardRow]:
    rows = sorted(
        _points_rows(session, room_id),
        key=lambda r: (-int(r[4]), r[3], r[0]),  # points desc, joined first, id
    )
    return [
        BoardRow(rank=i + 1, user_id=uid, name=display or username, points=int(points))
        for i, (uid, username, display, _joined, points) in enumerate(rows)
    ]


def group_to_dict(session: Session, room: Room, user_id: int) -> dict:
    # The shape _Group.fromJson expects in groups_screen.dart.
    board = leaderboard(session, room.id)
    me = next((row for row in board if row.user_id == user_id), None)
    goal = None
    if room.goal_target:
        month_start, month_end = _month_window()
        current = sum(int(r[4]) for r in _points_rows(session, room.id, since=month_start))
        goal = {
            "title": room.goal_title or f"Earn {room.goal_target:,} XP together this month",
            "current": current,
            "target": room.goal_target,
            "end_date": month_end.isoformat(),
        }
    return {
        "id": room.id,
        "room_name": room.name,
        "description": room.description,
        "category": room.category,
        "icon_key": room.icon_key,
        "room_code": room.code if me else None,
        "member_count": len(board),
        "is_joined": me is not None,
        "user_rank": me.rank if me else 0,
        "user_points": me.points if me else 0,
        "goal": goal,
    }


def _get_room(session: Session, room_id: int) -> Room:
    room = session.get(Room, room_id)
    if not room:
        raise HTTPException(status_code=404, detail="Group not found.")
    return room


def _membership(session: Session, room_id: int, user_id: int) -> Optional[RoomMember]:
    return session.exec(
        select(RoomMember).where(RoomMember.room_id == room_id, RoomMember.user_id == user_id)
    ).first()


def _join(session: Session, room: Room, user_id: int) -> dict:
    if _membership(session, room.id, user_id) is None:
        session.add(RoomMember(room_id=room.id, user_id=user_id))
        dismissal = session.exec(
            select(RoomDismissal).where(RoomDismissal.room_id == room.id, RoomDismissal.user_id == user_id)
        ).first()
        if dismissal:
            session.delete(dismissal)
        try:
            session.commit()
        except IntegrityError:  # two quick taps: already joined
            session.rollback()
    return group_to_dict(session, room, user_id)


@router.get("/mine")
def my_groups(session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    user = get_current_user(session, decoded_token)
    rooms = session.exec(
        select(Room).join(RoomMember, RoomMember.room_id == Room.id)
        .where(RoomMember.user_id == user.id)
        .order_by(RoomMember.joined_at)
    ).all()
    return [group_to_dict(session, room, user.id) for room in rooms]


@router.get("/discover")
def discover_groups(session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    # Groups the user hasn't joined or hidden, biggest first.
    user = get_current_user(session, decoded_token)
    joined = select(RoomMember.room_id).where(RoomMember.user_id == user.id)
    hidden = select(RoomDismissal.room_id).where(RoomDismissal.user_id == user.id)
    rooms = session.exec(
        select(Room).where(Room.id.not_in(joined), Room.id.not_in(hidden)).order_by(Room.id)
    ).all()
    groups = [group_to_dict(session, room, user.id) for room in rooms]
    return sorted(groups, key=lambda g: (-g["member_count"], g["id"]))


@router.post("/join")
def join_by_code(
    data: JoinByCode,
    session: Session = Depends(get_session),
    decoded_token: dict = Depends(verify_token),
):
    user = get_current_user(session, decoded_token)
    code = data.room_code.strip().upper()
    if not code:
        raise HTTPException(status_code=422, detail="Enter the group code.")
    room = session.exec(select(Room).where(Room.code == code)).first()
    if not room:
        raise HTTPException(status_code=404, detail="No group found with that code.")
    return _join(session, room, user.id)


@router.post("/{room_id}/join")
def join_group(room_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    user = get_current_user(session, decoded_token)
    return _join(session, _get_room(session, room_id), user.id)


@router.post("/{room_id}/dismiss")
def dismiss_group(room_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    # "Not interested": hide the group from Groups to join.
    user = get_current_user(session, decoded_token)
    _get_room(session, room_id)
    exists = session.exec(
        select(RoomDismissal.id).where(RoomDismissal.room_id == room_id, RoomDismissal.user_id == user.id)
    ).first()
    if exists is None:
        session.add(RoomDismissal(room_id=room_id, user_id=user.id))
        try:
            session.commit()
        except IntegrityError:
            session.rollback()
    return {"status": "ok"}


@router.delete("/{room_id}/dismiss")
def undo_dismiss_group(room_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    # "Undo" on the snack bar: show the group in suggestions again.
    user = get_current_user(session, decoded_token)
    dismissal = session.exec(
        select(RoomDismissal).where(RoomDismissal.room_id == room_id, RoomDismissal.user_id == user.id)
    ).first()
    if dismissal:
        session.delete(dismissal)
        session.commit()
    return {"status": "ok"}


@router.delete("/{room_id}/membership")
def leave_group(room_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    user = get_current_user(session, decoded_token)
    _get_room(session, room_id)
    member = _membership(session, room_id, user.id)
    if member:
        session.delete(member)
        session.commit()
    return {"status": "ok"}


@router.get("/{room_id}/leaderboard")
def group_leaderboard(room_id: int, session: Session = Depends(get_session), decoded_token: dict = Depends(verify_token)):
    # Every member, ranked. Also used as the member list.
    user = get_current_user(session, decoded_token)
    _get_room(session, room_id)
    if _membership(session, room_id, user.id) is None:
        raise HTTPException(status_code=403, detail="Join this group to see its leaderboard.")
    return [
        {
            "rank": row.rank,
            "user_id": row.user_id,
            "display_name": row.name,
            "points": row.points,
            "is_me": row.user_id == user.id,
        }
        for row in leaderboard(session, room_id)
    ]


def groups_joined(session: Session, user_id: int) -> int:
    return session.exec(
        select(func.count()).select_from(RoomMember).where(RoomMember.user_id == user_id)
    ).one()
