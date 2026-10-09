from leveling import calculate_level


def test_new_user_starts_at_level_0():
    assert calculate_level(0) == 0


def test_just_below_first_threshold_is_still_level_0():
    assert calculate_level(99) == 0


def test_each_threshold_reaches_the_next_level():
    assert calculate_level(100) == 1
    assert calculate_level(500) == 2
    assert calculate_level(1500) == 3
    assert calculate_level(3000) == 4


def test_one_point_below_each_threshold_stays_on_previous_level():
    assert calculate_level(499) == 1
    assert calculate_level(1499) == 2
    assert calculate_level(2999) == 3


def test_level_stays_at_4_after_max():
    assert calculate_level(10000) == 4