# Points needed to reach each level.
# Level 0 = 0-99, Level 1 = 100+, Level 2 = 500+, Level 3 = 1500+, Level 4 = 3000+ (max)
# The Flutter app uses the same numbers for its progress bars
# (_levelFloors in home_screen.dart, _kLevelFloors in me_screen.dart).
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


def level_floor(level: int) -> int:
    # Points at which `level` starts (Level 0 starts at 0).
    level = max(0, min(level, MAX_LEVEL))
    return 0 if level == 0 else LEVEL_THRESHOLDS[level - 1]


def xp_progress(total_points: int) -> tuple[int, int | None]:
    # (points earned inside the current level, points needed for the next level).
    # The second value is None at the max level.
    level = calculate_level(total_points)
    into_level = total_points - level_floor(level)
    if level >= MAX_LEVEL:
        return into_level, None
    return into_level, LEVEL_THRESHOLDS[level] - level_floor(level)
