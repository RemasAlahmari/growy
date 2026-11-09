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


def longest_streak(done_dates: set) -> int:
    # The most consecutive days ever in done_dates (shown on the Me page).
    best = 0
    for day in done_dates:
        if day - timedelta(days=1) in done_dates:
            continue  # not the first day of a run
        length = 1
        while day + timedelta(days=length) in done_dates:
            length += 1
        best = max(best, length)
    return best
