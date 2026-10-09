# Points needed to reach each level.
# Level 0 = 0-99, Level 1 = 100+, Level 2 = 500+, Level 3 = 1500+, Level 4 = 3000+ (max)
LEVEL_THRESHOLDS = [100, 500, 1500, 3000]
MAX_LEVEL = len(LEVEL_THRESHOLDS)


def calculate_level(total_points: int) -> int:
    # Count how many thresholds the user has reached.
    # After 3000, points keep growing but the level stays at 4.
    level = 0
    for threshold in LEVEL_THRESHOLDS:
        if total_points >= threshold:
            level += 1
    return level