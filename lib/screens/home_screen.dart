import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/motion/motion.dart';
import 'avatar_customizer_screen.dart';
import 'verify_habit_screen.dart';
import 'groups_screen.dart';
import 'habits_screen.dart';
import 'me_screen.dart';
import '../models/character_config.dart';
import '../models/habit_summary.dart';
import '../services/avatar_service.dart';
import '../services/home_service.dart';
import '../theme/app_theme.dart';
import '../widgets/character_preview.dart';
import '../widgets/habit_card.dart';

Color get _secondaryText => GrowyPalette.textSecondary;
Color get _pink => GrowyPalette.secondary;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.config});

  // Optional starting look (e.g. passed right after first-time avatar setup).
  // The saved avatar is then loaded from GET /users/me/avatar.
  final CharacterConfig? config;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late CharacterConfig _config;
  final AvatarService _avatarService = AvatarService();
  final HomeService _homeService = HomeService();

  // Data from the backend (GET /users/me and GET /habits/today)
  UserProfile? _profile;
  List<HabitSummary> _habits = [];
  bool _isLoading = true;
  String? _error;

  int get _totalXp => _profile?.totalPoints ?? 0;

  @override
  void initState() {
    super.initState();
    _config = widget.config ?? CharacterConfig.defaultConfig();
    _loadHomeData();
    _loadSavedAvatar();
  }

  Future<void> _loadHomeData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _homeService.getMe(),
        _homeService.getTodayHabits(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as UserProfile;
        _habits = results[1] as List<HabitSummary>;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Could not load home data: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error =
            'Could not load your data. Check your connection and try again.';
      });
    }
  }

  // GET /users/me/avatar — shows the user's saved colors when Home opens.
  // The backend returns default colors if nothing was saved yet. If the request
  // fails (e.g. backend not running), Home just keeps the default look.
  Future<void> _loadSavedAvatar() async {
    try {
      final saved = await _avatarService.getMyAvatar();
      if (!mounted) return;
      setState(() => _config = saved);
    } catch (e) {
      debugPrint('Could not load saved avatar: $e');
    }
  }

  // Opens AI photo verification for a habit, then reloads Home so the
  // points, streak, and "done" state update after a successful check.
  Future<void> _openVerification(HabitSummary habit) async {
    if (habit.completedToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already completed today. Nice!')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VerifyHabitScreen(habit: habit)),
    );
    if (!mounted) return;
    _loadHomeData();
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

  // The level comes from the backend (current_level, 0–4).
  // These floors match the backend and are only used for the progress bar:
  // 0–99 -> Level 0, 100–499 -> 1, 500–1499 -> 2, 1500–2999 -> 3, 3000+ -> 4 (max)
  static const List<int> _levelFloors = [0, 100, 500, 1500, 3000];
  static const int _maxLevel = 4;

  int get _level {
    final level = _profile?.currentLevel ?? 0;
    if (level < 0) return 0;
    if (level > _maxLevel) return _maxLevel;
    return level;
  }

  bool get _isMaxLevel => _level >= _maxLevel;
  int get _currentLevelFloor => _levelFloors[_level];
  int? get _nextLevelFloor => _isMaxLevel ? null : _levelFloors[_level + 1];
  int get _xpIntoLevel {
    final xp = _totalXp - _currentLevelFloor;
    return xp < 0 ? 0 : xp;
  }

  int? get _xpToNextLevel {
    final next = _nextLevelFloor;
    if (next == null) return null;
    final left = next - _totalXp;
    return left < 0 ? 0 : left;
  }

  double get _levelProgress {
    final next = _nextLevelFloor;
    if (next == null) return 1.0;
    return (_xpIntoLevel / (next - _currentLevelFloor)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: GrowyBackgroundBlobs(preset: GrowyBlobPreset.home),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(child: _buildBody()),
                const _BottomNav(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _profile == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: _secondaryText),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadHomeData,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final habits = _habits;
    final doneCount = habits.where((h) => h.completedToday).length;

    return RefreshIndicator(
      // Pull down to reload points, streak, and habits
      onRefresh: _loadHomeData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          GrowyFadeIn(
            offset: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  'Hello, ${_profile?.username ?? ''}!',
                  style: GoogleFonts.fraunces(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Avatar hero — the level-up "evolve" moment lives here
          GrowyFadeIn(
            delay: const Duration(milliseconds: 80),
            child: Center(
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
                      // XP bar fills smoothly when points change (600 ms).
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: _levelProgress),
                        duration: GrowyMotion.count,
                        curve: GrowyMotion.enterCurve,
                        builder: (context, value, _) => LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor: AppColors.primary.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  GrowyCountUp(
                    value: _isMaxLevel ? _totalXp : _xpIntoLevel,
                    builder: (xp) => Text(
                      _isMaxLevel
                          ? '$xp XP'
                          : '$xp / ${_nextLevelFloor! - _currentLevelFloor} XP',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: _secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Streak + Today's XP only — Rank intentionally left out for now
          Row(
            children: [
              Expanded(
                child: GrowySlideIn(
                  index: 0,
                  baseDelay: const Duration(milliseconds: 120),
                  child: _StatCard(
                    icon: Icons.local_fire_department,
                    color: _pink,
                    label: 'Streak',
                    value: '${_profile?.streakDays ?? 0}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GrowySlideIn(
                  index: 1,
                  baseDelay: const Duration(milliseconds: 120),
                  child: GrowyCountUp(
                    value: _profile?.todayPoints ?? 0,
                    builder: (xp) => _StatCard(
                      icon: Icons.bolt,
                      color: AppColors.primary,
                      label: 'Today',
                      value: '$xp XP',
                    ),
                  ),
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
          for (var i = 0; i < habits.length; i++)
            Padding(
              key: ValueKey(habits[i].id),
              padding: const EdgeInsets.only(bottom: 10),
              child: GrowySlideIn(
                index: i,
                baseDelay: const Duration(milliseconds: 200),
                child: GrowyPressEffect(
                  child: HabitCard(
                    habit: habits[i],
                    onTap: () => _openVerification(habits[i]),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          // Suggested groups come after today's habits, so the daily loop stays first.
          const GroupsToJoinStrip(),
        ],
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

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

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
            children: [
              _NavItem(
                icon: Icons.groups_outlined,
                label: 'Groups',
                onTap: () => _open(context, const GroupsScreen()),
              ),
              _NavItem(
                icon: Icons.track_changes_outlined,
                label: 'Habits',
                onTap: () => _open(context, const HabitsScreen()),
              ),
              const _NavItem(
                icon: Icons.home_filled,
                label: 'Home',
                active: true,
              ),
              _NavItem(
                icon: Icons.person_outline,
                label: 'Me',
                onTap: () => _open(context, const MeScreen()),
              ),
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
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : _secondaryText;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
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
        ),
      ),
    );
  }
}
