# Same thresholds as lib/screens/home_screen.dart (_levelFloors):
# 0-499 -> Level 1, 500-1499 -> Level 2, 1500-2999 -> Level 3, 3000+ -> Level 4 (max)
LEVEL_FLOORS = [0, 500, 1500, 3000]


def level_for_points(total_points: int) -> int:
    level = 1
    for i, floor in enumerate(LEVEL_FLOORS):
        if total_points >= floor:
            level = i + 1
    return level
