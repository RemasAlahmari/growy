
class HabitSummary {

  final String id;
  final String name;
  final String category; // the habit's photo instruction (ai_label), shown on the verify screen

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
