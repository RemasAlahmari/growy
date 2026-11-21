# Points needed to reach each level. Every user starts at Level 1.
# Level 1 = 0-499, Level 2 = 500-1499, Level 3 = 1500-2999, Level 4 = 3000+ (max)
# The Flutter app uses the same numbers for its progress bar
# (_levelFloors in home_screen.dart). The avatar stage is the same as the level.
LEVEL_THRESHOLDS = [500, 1500, 3000]  # points to reach Level 2, 3 and 4
MIN_LEVEL = 1
MAX_LEVEL = MIN_LEVEL + len(LEVEL_THRESHOLDS)  # 4


def calculate_level(total_points: int) -> int:
    # Start at Level 1 and add one for every threshold the user has reached.
    # After 3000, points keep growing but the level stays at 4.
    level = MIN_LEVEL
    for threshold in LEVEL_THRESHOLDS:
        if total_points >= threshold:
            level += 1
    return level


def level_floor(level: int) -> int:
    # Points at which `level` starts (Level 1 starts at 0).
    level = max(MIN_LEVEL, min(level, MAX_LEVEL))
    return 0 if level == MIN_LEVEL else LEVEL_THRESHOLDS[level - 2]


def xp_progress(total_points: int) -> tuple[int, int | None]:
    # (points earned inside the current level, points needed for the next level).
    # The second value is None at the max level.
    level = calculate_level(total_points)
    into_level = total_points - level_floor(level)
    if level >= MAX_LEVEL:
        return into_level, None
    return into_level, level_floor(level + 1) - level_floor(level)
