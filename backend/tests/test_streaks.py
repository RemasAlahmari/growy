from datetime import date, timedelta
from streaks import count_streak

TODAY = date(2026, 10, 9)


def days_ago(n):
    return TODAY - timedelta(days=n)


def test_no_completions_is_zero():
    assert count_streak(set(), TODAY) == 0


def test_only_today_is_one():
    assert count_streak({TODAY}, TODAY) == 1


def test_only_yesterday_still_counts():
    # Not done today yet, but the streak isn't broken
    assert count_streak({days_ago(1)}, TODAY) == 1


def test_three_days_in_a_row():
    assert count_streak({TODAY, days_ago(1), days_ago(2)}, TODAY) == 3


def test_gap_breaks_the_streak():
    # Today and 2 days ago, but not yesterday
    assert count_streak({TODAY, days_ago(2)}, TODAY) == 1


def test_missed_yesterday_and_today_is_zero():
    assert count_streak({days_ago(2), days_ago(3)}, TODAY) == 0
    