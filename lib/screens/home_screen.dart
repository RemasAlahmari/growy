import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'avatar_customizer_screen.dart';
import '../models/character_config.dart';
import '../models/habit_summary.dart';
import '../theme/app_theme.dart';
import '../widgets/character_preview.dart';
import '../widgets/habit_card.dart';

const Color _secondaryText = Color(0xFF8A8A8A);
const Color _pink = Color(0xFFF0B8AE);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.config, // from GET /users/me -> avatar customization
    this.userName = 'Zad',
    this.totalXp = 260, //from GET /users/me -> total_points
    this.streakDays = 15, //  from GET /users/me -> streak_days
    this.todayXp = 40, //  sum today's habit_logs.points_earned // all these need to be done later after the backend
    this.habits = const [
      HabitSummary(
        id: '1',
        name: 'Read 20 Pages',
        category: 'Study', // CLIP label: "a person reading a book"
        xpValue: 10,
        completedToday: true,
        streak: 7,
      ),
      HabitSummary(
        id: '2',
        name: 'Morning Workout',
        category: 'Health', // CLIP label: "a person working out or exercising"
        xpValue: 10,
        completedToday: true,
        streak: 12,
      ),
      HabitSummary(
        id: '3',
        name: 'Drink a Glass of Water',
        category: 'Health', // CLIP label: "a glass of water"
        xpValue: 10,
        completedToday: false,
        streak: 21,
      ),
      HabitSummary(
        id: '4',
        name: 'Evening Walk',
        category: 'Health', // CLIP label: "a person walking outdoor"
        xpValue: 10,
        completedToday: false,
        streak: 4,
      ),
    ],
  });

  final CharacterConfig? config;
  final String userName;
  final int totalXp;
  final int streakDays;
  final int todayXp;
  final List<HabitSummary> habits;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // The avatar currently shown on Home. Starts from what was passed in
  // (later: from GET /users/me) and changes when the user saves in the customizer.
  late CharacterConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.config ?? CharacterConfig.defaultConfig();
  }

  // Opens the customizer with the current look, then updates Home
  // if the user pressed Save (pressing back returns null = no change).
  Future<void> _openCustomizer() async {
    final result = await Navigator.push<CharacterConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => AvatarCustomizerScreen(initialConfig: _config),
      ),
    );
    if (result != null) {
      setState(() => _config = result);
    }
  }

  // 0–499 -> Level 1, 500–1499 -> Level 2, 1500–2999 -> Level 3, 3000+ -> Level 4 (max)
  static const List<int> _levelFloors = [0, 500, 1500, 3000];
  static const int _maxLevel = 4;

  int get _level {
    var level = 1;
    for (var i = 0; i < _levelFloors.length; i++) {
      if (widget.totalXp >= _levelFloors[i]) level = i + 1;
    }
    return level;
  }

  bool get _isMaxLevel => _level >= _maxLevel;
  int get _currentLevelFloor => _levelFloors[_level - 1];
  int? get _nextLevelFloor => _isMaxLevel ? null : _levelFloors[_level];
  int get _xpIntoLevel => widget.totalXp - _currentLevelFloor;
  int? get _xpToNextLevel =>
      _nextLevelFloor == null ? null : _nextLevelFloor! - widget.totalXp;
  double get _levelProgress {
    final next = _nextLevelFloor;
    if (next == null) return 1.0;
    return _xpIntoLevel / (next - _currentLevelFloor);
  }

  @override
  Widget build(BuildContext context) {
    final habits = widget.habits;
    final doneCount = habits.where((h) => h.completedToday).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Text(
                    _formatDate(DateTime.now()),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _secondaryText,
                    ),
                  ),
                  Text(
                    'Hello, ${widget.userName}!',
                    style: GoogleFonts.fraunces(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Avatar hero — the level-up "evolve" moment lives here
                  Center(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 300,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                bottom: 6,
                                child: Container(
                                  width: 190,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 20,
                                child: SizedBox(
                                  width: 140, // CharacterPreview keeps its 400:800 ratio, so height follows at 280
                                  child: GestureDetector(
                                    onTap: _openCustomizer,
                                    child: CharacterPreview(
                                      config: _config,
                                      level: _level,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        TextButton.icon(
                          onPressed: _openCustomizer,
                          icon: const Icon(Icons.edit),
                          label: const Text('Customize'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Lvl. $_level',
                          style: GoogleFonts.fraunces(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          _isMaxLevel
                              ? 'Max level reached!'
                              : '$_xpToNextLevel XP to Evolve',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: _secondaryText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: SizedBox(
                            width: 220,
                            child: LinearProgressIndicator(
                              value: _levelProgress,
                              minHeight: 8,
                              backgroundColor: AppColors.primary.withOpacity(
                                0.15,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isMaxLevel
                              ? '${widget.totalXp} XP'
                              : '$_xpIntoLevel / ${_nextLevelFloor! - _currentLevelFloor} XP',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: _secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Streak + Today's XP only — Rank intentionally left out for now
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.local_fire_department,
                          color: _pink,
                          label: 'Streak',
                          value: '${widget.streakDays}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.bolt,
                          color: AppColors.primary,
                          label: 'Today',
                          value: '${widget.todayXp} XP',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Today's Habits",
                        style: GoogleFonts.fraunces(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        '$doneCount/${habits.length} Done',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _secondaryText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...habits.map(
                    (h) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: HabitCard(
                        habit: h,
                        onTap: () {
                          // TODO: route to the right completion flow based on h.method
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const _BottomNav(),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.poppins(fontSize: 12, color: _secondaryText),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _pink.withOpacity(0.35),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const [
              _NavItem(icon: Icons.groups_outlined, label: 'Groups'),
              _NavItem(icon: Icons.track_changes_outlined, label: 'Habits'),
              _NavItem(icon: Icons.home_filled, label: 'Home', active: true),
              _NavItem(icon: Icons.person_outline, label: 'Me'),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : _secondaryText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: color,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}