from datetime import date, timedelta


def count_streak(done_dates: set, today: date) -> int:
    # Counts consecutive days in done_dates, ending today.
    # If today isn't done yet, count from yesterday instead,
    # so the streak doesn't look broken in the morning.
    day = today if today in done_dates else today - timedelta(days=1)
    streak = 0
    while day in done_dates:
        streak += 1
        day -= timedelta(days=1)
    return streak