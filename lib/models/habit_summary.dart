class HabitSummary {
  final String id;
  final String name;
  final String category; //Health ,Study used in CLIP#for AI verification; not shown in the UI anymore

  final int xpValue;
  final bool completedToday;
  final int streak;

  const HabitSummary({
    required this.id,
    required this.name,
    required this.category,
    required this.xpValue,
    this.completedToday = false,
    this.streak = 0,
  });
}
