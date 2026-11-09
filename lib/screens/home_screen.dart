import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/motion/growy_level_up_animation.dart';
import '../core/motion/motion.dart';
import 'add_habits_screen.dart';
import 'avatar_customizer_screen.dart';
import 'verify_habit_screen.dart';
import 'groups_screen.dart';
import 'habits_screen.dart';
import 'me_screen.dart';
import '../models/character_config.dart';
import '../models/habit_summary.dart';
import '../services/avatar_gender_store.dart';
import '../services/avatar_service.dart';
import '../services/home_service.dart';
import '../services/my_habits_store.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_stage.dart';
import '../widgets/character_preview.dart';
import '../widgets/evolving_avatar.dart';
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

  // Boy or girl character (saved on the phone, or from the backend later).
  AvatarGender _gender = AvatarGender.girl;

  // While the avatar evolves, these hold the old and new level.
  // null = no evolution playing, Home shows the normal CharacterPreview.
  int? _evolveFrom;
  int? _evolveTo;

  // Debug only: which evolution the long-press test plays next (1→2, 2→3, 3→4).
  int _debugNextFrom = 1;

  // Data from the backend (GET /users/me, GET /habits/today, GET /groups/mine)
  UserProfile? _profile;

  // Today's list: the user's own habits + habits their groups need,
  // each habit once, still-to-do first.
  List<_TodayItem> _items = [];
  bool _isLoading = true;
  String? _error;

  int get _totalXp => _profile?.totalPoints ?? 0;

  @override
  void initState() {
    super.initState();
    _config = widget.config ?? CharacterConfig.defaultConfig();
    _loadGender();
    _loadHomeData();
    _loadSavedAvatar();
  }

  // Picks boy/girl: saved on this phone first, then the backend value
  // (once GET /users/me returns "gender"), otherwise girl.
  Future<void> _loadGender() async {
    final gender = await AvatarGenderStore.resolve(
      backendValue: _profile?.gender,
    );
    if (!mounted) return;
    setState(() => _gender = gender);
  }

  Future<void> _loadHomeData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        _homeService.getMe(),
        _homeService.getHabitCatalog(),
        // Groups failing (e.g. older backend) shouldn't break Home.
        _homeService.getMyGroups().catchError((Object e) {
          debugPrint('Could not load groups: $e');
          return <JoinedGroup>[];
        }),
        MyHabitsStore.load(),
      ]);
      if (!mounted) return;

      // The level before this reload (null on the very first load, so
      // opening the app never plays a level-up).
      final oldLevel = _profile == null ? null : _level;

      setState(() {
        _profile = results[0] as UserProfile;
        _items = _buildTodayList(
          results[1] as List<HabitEntry>,
          results[3] as Set<String>?,
          results[2] as List<JoinedGroup>,
        );
        _isLoading = false;
      });
      _loadGender();

      final newLevel = _level;
      if (oldLevel != null && newLevel > oldLevel) {
        _celebrateLevelUp(oldLevel, newLevel);
      }
    } catch (e) {
      debugPrint('Could not load home data: $e');
      if (!mounted) return;
      const message =
          'Could not load your data. Check your connection and try again.';
      final hadData = _profile != null;
      setState(() {
        _isLoading = false;
        _error = message;
      });
      // Pull-to-refresh failed: keep showing the old data, explain in a snack bar.
      if (hadData) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  // A habit is on today's list if the user added it (or never chose, which
  // means all habits) OR one of their groups needs it (same category as the
  // group). A habit in both appears once, so one photo counts for both.
  List<_TodayItem> _buildTodayList(
    List<HabitEntry> catalog,
    Set<String>? myHabitIds,
    List<JoinedGroup> groups,
  ) {
    final todo = <_TodayItem>[];
    final done = <_TodayItem>[];
    for (final entry in catalog) {
      final isPersonal = myHabitIds == null || myHabitIds.contains(entry.habit.id);
      final groupNames = groups
          .where((g) => g.category == entry.category)
          .map((g) => g.name)
          .toList();
      if (!isPersonal && groupNames.isEmpty) continue;
      final item = _TodayItem(
        habit: entry.habit,
        isPersonal: isPersonal,
        groupNames: groupNames,
      );
      (entry.habit.completedToday ? done : todo).add(item);
    }
    return [...todo, ...done];
  }

  // Opens "My habits", then reloads Home if the user saved a change.
  Future<void> _openAddHabits() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddHabitScreen()),
    );
    if (changed == true && mounted) _loadHomeData();
  }

  // Level went up. If the character changes (1→2, 2→3, 3→4), the avatar
  // evolves first and the level-up card opens after. Otherwise (0→1) only
  // the card opens.
  void _celebrateLevelUp(int fromLevel, int toLevel) {
    if (avatarStageForLevel(toLevel) > avatarStageForLevel(fromLevel)) {
      setState(() {
        _evolveFrom = fromLevel;
        _evolveTo = toLevel;
      });
    } else {
      _showLevelUpCard(toLevel, evolved: false);
    }
  }

  // Called by EvolvingAvatar when its animation is done.
  void _onEvolutionFinished() {
    final toLevel = _evolveTo ?? _level;
    setState(() {
      _evolveFrom = null;
      _evolveTo = null;
    });
    _showLevelUpCard(toLevel, evolved: true);
  }

  // The teammate's level-up card (growy_level_up_animation.dart), with the
  // new character glowing inside it.
  void _showLevelUpCard(int level, {required bool evolved}) {
    if (!mounted) return;
    showGrowyLevelUp(
      context,
      level: level,
      message: evolved
          ? null // default text: "...Your avatar evolved!"
          : "You're now Level $level. Keep going to evolve!",
      avatar: SizedBox(
        height: 130,
        child: CharacterPreview(
          config: _config,
          gender: _gender,
          level: level,
        ),
      ),
    );
  }

  // DEBUG ONLY (long-press the avatar): plays 1→2, then 2→3, then 3→4,
  // without needing real XP. Does nothing in release builds.
  void _debugEvolve() {
    if (_evolveFrom != null) return; // one at a time
    final from = _debugNextFrom;
    _debugNextFrom = from == 3 ? 1 : from + 1;
    setState(() {
      _evolveFrom = from;
      _evolveTo = from + 1;
    });
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

  // Back from Groups, Habits or Me: habits may have been verified, the gender
  // or profile changed, so refresh what Home shows.
  void _onBackFromTab() {
    if (!mounted) return;
    _loadHomeData();
    _loadSavedAvatar();
  }

  // Opens the customizer with the current look, gender and level, then
  // updates Home if the user pressed Save (pressing back returns null = no change).
  Future<void> _openCustomizer() async {
    final result = await Navigator.push<CharacterConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => AvatarCustomizerScreen(
          initialConfig: _config,
          initialGender: _gender,
          level: _level,
        ),
      ),
    );
    if (result != null) {
      setState(() => _config = result);
      _loadGender(); // the user may have switched girl/boy
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
                // Reload when coming back from Groups/Habits/Me, in case the
                // user joined or left a group or changed their habits.
                _BottomNav(onReturn: _onBackFromTab),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // The avatar spot: the evolution while it plays, otherwise the normal avatar.
  Widget _buildAvatar() {
    final evolveFrom = _evolveFrom;
    final evolveTo = _evolveTo;
    if (evolveFrom != null && evolveTo != null) {
      return EvolvingAvatar(
        key: ValueKey('evolve-$evolveFrom-$evolveTo'),
        config: _config,
        gender: _gender,
        fromLevel: evolveFrom,
        toLevel: evolveTo,
        width: 178,
        onFinished: _onEvolutionFinished,
      );
    }
    return GestureDetector(
      onTap: _openCustomizer,
      onLongPress: kDebugMode ? _debugEvolve : null,
      child: CharacterPreview(
        config: _config,
        gender: _gender,
        level: _level,
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

    final items = _items;
    final doneCount = items.where((i) => i.habit.completedToday).length;

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
                            width: 178, // keeps the 520:820 ratio, so height follows at about 280
                            child: _buildAvatar(),
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
              Row(
                children: [
                  Text(
                    '$doneCount/${items.length} Done',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _secondaryText,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add habits',
                    onPressed: _openAddHabits,
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            _NoHabitsCard(onAdd: _openAddHabits),
          for (var i = 0; i < items.length; i++)
            Padding(
              key: ValueKey(items[i].habit.id),
              padding: const EdgeInsets.only(bottom: 10),
              child: GrowySlideIn(
                index: i,
                baseDelay: const Duration(milliseconds: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GrowyPressEffect(
                      child: HabitCard(
                        habit: items[i].habit,
                        onTap: () => _openVerification(items[i].habit),
                      ),
                    ),
                    _SourceTags(item: items[i]),
                  ],
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

/// One habit on today's list and where it comes from.
class _TodayItem {
  const _TodayItem({
    required this.habit,
    required this.isPersonal,
    required this.groupNames,
  });

  final HabitSummary habit;

  /// The user added it themselves (in "My habits").
  final bool isPersonal;

  /// Joined groups that need this habit today.
  final List<String> groupNames;
}

/// Small chips under a habit card: "Personal" and/or the group names.
class _SourceTags extends StatelessWidget {
  const _SourceTags({required this.item});

  final _TodayItem item;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (item.isPersonal)
        _chip(Icons.person_rounded, 'Personal', AppColors.primary),
      for (final name in item.groupNames)
        _chip(Icons.groups_rounded, name, GrowyPalette.secondaryDeep),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 6),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the user removed every habit and isn't in any group.
class _NoHabitsCard extends StatelessWidget {
  const _NoHabitsCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GrowyPalette.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            'No habits for today yet',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add habits or join a group to get started.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, color: _secondaryText),
          ),
          TextButton(onPressed: onAdd, child: const Text('Add habits')),
        ],
      ),
    );
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
  const _BottomNav({required this.onReturn});

  /// Called when the user comes back from Groups, Habits or Me.
  final VoidCallback onReturn;

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    onReturn();
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