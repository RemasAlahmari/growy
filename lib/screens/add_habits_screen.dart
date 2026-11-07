import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/home_service.dart';
import '../services/my_habits_store.dart';
import '../theme/app_theme.dart';

/// "My habits": the user picks which of Growy's habits appear on Home.
///
/// Habits required by the user's groups always appear on Home, whether or
/// not they're picked here; this screen just says so on the card.
/// Pops with `true` after saving, so the caller can reload.
class AddHabitScreen extends StatefulWidget {
  const AddHabitScreen({super.key});

  @override
  State<AddHabitScreen> createState() => _AddHabitScreenState();
}

class _AddHabitScreenState extends State<AddHabitScreen> {
  final HomeService _service = HomeService();

  List<HabitEntry>? _catalog;
  List<JoinedGroup> _groups = [];
  Set<String> _selected = {};
  Set<String> _initial = {};
  bool _neverSaved = false;
  bool _failed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final catalog = await _service.getHabitCatalog();
      final groups = await _service.getMyGroups().catchError((Object e) {
        debugPrint('Could not load groups: $e');
        return <JoinedGroup>[];
      });
      final saved = await MyHabitsStore.load();
      final allIds = catalog.map((e) => e.habit.id).toSet();
      final selected = saved == null ? allIds : saved.intersection(allIds);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _groups = groups;
        _selected = {...selected};
        _initial = {...selected};
        _neverSaved = saved == null;
      });
    } catch (e) {
      debugPrint('Could not load habits: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  bool get _hasChanges =>
      _neverSaved ||
      _selected.length != _initial.length ||
      !_selected.containsAll(_initial);

  void _toggle(String habitId) {
    setState(() {
      if (!_selected.remove(habitId)) _selected.add(habitId);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await MyHabitsStore.save(_selected);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  List<String> _groupsNeeding(HabitEntry entry) => _groups
      .where((g) => g.category == entry.category)
      .map((g) => g.name)
      .toList();

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: Text(
          'My habits',
          style: GoogleFonts.fraunces(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ),
      body: SafeArea(
        child: catalog == null
            ? Center(
                child: _failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Couldn't load habits.",
                            style: GoogleFonts.poppins(
                              color: GrowyPalette.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _load,
                            child: const Text('Try again'),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  Text(
                    'Pick the habits you want on your Home page. '
                    'Habits your groups need show up there automatically.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: GrowyPalette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final category in const ['Study', 'Health']) ...[
                    if (catalog.any((e) => e.category == category)) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, top: 6),
                        child: Text(
                          category,
                          style: GoogleFonts.fraunces(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      for (final entry
                          in catalog.where((e) => e.category == category))
                        _HabitOption(
                          entry: entry,
                          selected: _selected.contains(entry.habit.id),
                          requiredBy: _groupsNeeding(entry),
                          onTap: () => _toggle(entry.habit.id),
                        ),
                    ],
                  ],
                ],
              ),
      ),
      bottomNavigationBar: catalog == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _hasChanges && !_saving ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          AppColors.primary.withOpacity(0.4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Save (${_selected.length} selected)',
                      style: GoogleFonts.fraunces(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _HabitOption extends StatelessWidget {
  const _HabitOption({
    required this.entry,
    required this.selected,
    required this.requiredBy,
    required this.onTap,
  });

  final HabitEntry entry;
  final bool selected;
  final List<String> requiredBy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final habit = entry.habit;
    final isStudy = entry.category == 'Study';
    final radius = BorderRadius.circular(16);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? AppColors.primary.withOpacity(0.10)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? AppColors.primary : GrowyPalette.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primary.withOpacity(0.15),
                  child: Icon(
                    isStudy ? Icons.menu_book_rounded : Icons.favorite_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habit.name,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        '+${habit.xpValue} XP · daily',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: GrowyPalette.textSecondary,
                        ),
                      ),
                      if (requiredBy.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Needed by ${requiredBy.join(', ')}',
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: GrowyPalette.secondaryDeep,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.add_circle_outline_rounded,
                  color: selected
                      ? AppColors.primary
                      : GrowyPalette.textSecondary,
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}