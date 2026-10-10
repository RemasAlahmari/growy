// Growy — Habits page (calendar + history of photo-verified habits).
// Self-contained: every helper below is private to this file.
// Open it with: HabitsScreen()
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/motion/motion.dart';
import '../theme/app_theme.dart';

/// Habits tab: a calendar of verified completions and the history for the
/// selected day. Every entry was verified with a photo taken in the app;
/// this page only displays those photos and never lets the user add one.
class HabitsScreen extends StatefulWidget {
  /// Opens the habit list with edit/delete. Wire it to your My Habits screen.
  final VoidCallback? onManageHabits;

  /// Opens Create Habit.
  final VoidCallback? onAddHabit;

  /// Shown on a brand-new account; typically switches to the Home tab.
  final VoidCallback? onGoVerify;

  const HabitsScreen({
    super.key,
    this.onManageHabits,
    this.onAddHabit,
    this.onGoVerify,
  });

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  late DateTime _month;
  late DateTime _selected;

  /// Months already fetched, keyed "2026-10", so going back is instant.
  final Map<String, _MonthHistory> _cache = {};
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _month = DateTime(today.year, today.month);
    _selected = today;
    _loadMonth(_month);
  }

  String _key(DateTime m) => '${m.year}-${m.month}';

  _MonthHistory? get _history => _cache[_key(_month)];

  Future<void> _loadMonth(DateTime month, {bool force = false}) async {
    if (!force && _cache.containsKey(_key(month))) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final history = await _habitsData.getMonthHistory(month);
      if (!mounted) return;
      setState(() => _cache[_key(month)] = history);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _month = next;
      // Select today in the current month, otherwise the last day of the month.
      _selected = (next.year == today.year && next.month == today.month)
          ? today
          : DateTime(
              next.year,
              next.month,
              DateUtils.getDaysInMonth(next.year, next.month),
            );
    });
    _loadMonth(next);
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what will open here once it is connected.')),
    );
  }

  void _openPhoto(_HabitLog log) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PhotoViewerScreen(log: log),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    final dayLogs = history?.logsOn(_selected) ?? const <_HabitLog>[];
    final dayXp = dayLogs.fold<int>(0, (sum, l) => sum + l.pointsEarned);

    return Scaffold(
      backgroundColor: _GrowyColors.background,
      body: Stack(
        children: [
          const Positioned.fill(
            child: GrowyBackgroundBlobs(preset: GrowyBlobPreset.quiet),
          ),
          SafeArea(
            child: RefreshIndicator(
              color: _GrowyColors.primary,
              onRefresh: () => _loadMonth(_month, force: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  _GrowySpacing.screen,
                  _GrowySpacing.lg,
                  _GrowySpacing.screen,
                  _GrowySpacing.xxl,
                ),
                children: [
                  _buildHeader(),
                  const SizedBox(height: _GrowySpacing.lg),
                  GrowyFadeIn(child: _buildSummary(history)),
                  const SizedBox(height: _GrowySpacing.md),
                  _CalendarMonth(
                    month: _month,
                    dayCounts: history?.dayCounts ?? const <int, int>{},
                    selectedDate: _selected,
                    isLoading: _loading,
                    onSelect: (date) => setState(() => _selected = date),
                    onPreviousMonth: () => _changeMonth(-1),
                    onNextMonth: _isCurrentMonth ? null : () => _changeMonth(1),
                  ),
                  const SizedBox(height: _GrowySpacing.xl),
                  if (_failed && history == null)
                    _LoadError(onRetry: () => _loadMonth(_month, force: true))
                  else if (history == null)
                    Padding(
                      padding: EdgeInsets.all(_GrowySpacing.xl),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _GrowyColors.primary,
                        ),
                      ),
                    )
                  else ...[
                    _SectionHeader(
                      title: _formatLongDate(_selected),
                      subtitle: dayLogs.isEmpty
                          ? 'No habits completed'
                          : '${dayLogs.length} ${dayLogs.length == 1 ? 'habit' : 'habits'} completed · +$dayXp XP',
                    ),
                    if (dayLogs.isEmpty)
                      GrowyFadeIn(
                        key: ValueKey('empty-$_selected'),
                        offset: 8,
                        child: _buildEmptyDay(history),
                      )
                    else
                      // Keyed by date, so the cards stagger in again when the
                      // user picks another day.
                      for (var i = 0; i < dayLogs.length; i++)
                        Padding(
                          key: ValueKey('$_selected-${dayLogs[i].id}'),
                          padding: const EdgeInsets.only(
                            bottom: _GrowySpacing.md,
                          ),
                          child: GrowySlideIn(
                            index: i,
                            child: _HistoryEntryCard(
                              log: dayLogs[i],
                              onPhotoTap: () => _openPhoto(dayLogs[i]),
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const _BackToHome(),
        Expanded(child: Text('My Habits', style: _GrowyText.screenTitle)),
        TextButton(
          onPressed:
              widget.onManageHabits ?? () => _comingSoon('Manage habits'),
          style: TextButton.styleFrom(foregroundColor: _GrowyColors.primary),
          child: Text(
            'Manage',
            style: _GrowyText.body.copyWith(
              color: _GrowyColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: _GrowySpacing.xs),
        Material(
          color: _GrowyColors.primary,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: 'Add habit',
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            onPressed: widget.onAddHabit ?? () => _comingSoon('Create habit'),
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(_MonthHistory? history) {
    String value(int? n) => n == null ? '–' : _formatNumber(n);
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            value: value(history?.habitsCompleted),
            label: 'Completed',
          ),
        ),
        const SizedBox(width: _GrowySpacing.sm),
        Expanded(
          child: _StatTile(value: value(history?.xpEarned), label: 'XP earned'),
        ),
        const SizedBox(width: _GrowySpacing.sm),
        Expanded(
          child: _StatTile(
            value: value(history?.daysActive),
            label: 'Days active',
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyDay(_MonthHistory history) {
    final brandNew = history.logs.isEmpty && _isCurrentMonth;
    if (brandNew) {
      return _EmptyState(
        icon: Icons.photo_camera_outlined,
        message: 'Your completed habits will appear here.',
        detail: 'Verify a habit with a photo to start your history.',
        buttonLabel: widget.onGoVerify == null ? null : 'Verify a habit',
        onPressed: widget.onGoVerify,
      );
    }
    return const _EmptyState(
      icon: Icons.event_available_outlined,
      message: 'No habits completed on this day.',
    );
  }
}

class _BackToHome extends StatelessWidget {
  const _BackToHome();

  @override
  Widget build(BuildContext context) {
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: _GrowySpacing.xs),
      child: IconButton(
        tooltip: 'Back to Home',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded),
        color: _GrowyColors.textMain,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
    );
  }
}

/// Full-screen, read-only view of a past verification photo.
/// No share, download, replace or upload actions: it is a record only.
class _PhotoViewerScreen extends StatelessWidget {
  final _HabitLog log;
  const _PhotoViewerScreen({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(_GrowySpacing.sm),
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Hero(
                    tag: 'log-photo-${log.id}',
                    child: _LogPhoto(
                      source: log.imageUrl,
                      fit: BoxFit.contain,
                      borderRadius: 0,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(_GrowySpacing.screen),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        color: _GrowyColors.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Verification photo',
                        style: _GrowyText.cardTitle.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: _GrowySpacing.xs),
                  Text(
                    '${log.habitName} · ${_formatShortDate(log.completedAt)}, '
                    '${_formatTime(log.completedAt)} · Taken with camera',
                    textAlign: TextAlign.center,
                    style: _GrowyText.caption.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// First column of the calendar. Sunday-first matches the usual Saudi
/// calendar; change to DateTime.monday for Monday-first.
const int _kFirstWeekday = DateTime.sunday;

/// Month grid with activity levels. Built from plain widgets, no packages.
///
/// Day looks: none = plain number · 1 habit = small dot · 2 = light green
/// circle · 3+ = solid green circle · selected = dark ring · today = bold.
class _CalendarMonth extends StatelessWidget {
  final DateTime month;
  final Map<int, int> dayCounts;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPreviousMonth;
  final VoidCallback? onNextMonth;
  final bool isLoading;

  const _CalendarMonth({
    super.key,
    required this.month,
    required this.dayCounts,
    required this.selectedDate,
    required this.onSelect,
    required this.onPreviousMonth,
    required this.onNextMonth,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final leadingBlanks = (first.weekday - _kFirstWeekday + 7) % 7;
    final today = DateUtils.dateOnly(DateTime.now());

    // Weekday labels starting at kFirstWeekday.
    final labels = List.generate(
      7,
      (i) => _kWeekdayShort[(_kFirstWeekday - 1 + i) % 7],
    );

    return _GrowyCard(
      padding: const EdgeInsets.fromLTRB(
        _GrowySpacing.sm,
        _GrowySpacing.sm,
        _GrowySpacing.sm,
        _GrowySpacing.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPreviousMonth,
                icon: const Icon(Icons.chevron_left_rounded),
                color: _GrowyColors.textMain,
              ),
              Expanded(
                child: Text(
                  _formatMonthYear(month),
                  textAlign: TextAlign.center,
                  style: _GrowyText.sectionTitle,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right_rounded),
                color: _GrowyColors.textMain,
                disabledColor: _GrowyColors.textDisabled,
              ),
            ],
          ),
          const SizedBox(height: _GrowySpacing.xs),
          Row(
            children: [
              for (final label in labels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: _GrowyText.caption,
                  ),
                ),
            ],
          ),
          const SizedBox(height: _GrowySpacing.sm),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isLoading ? 0.4 : 1,
            child: GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
                for (var day = 1; day <= daysInMonth; day++)
                  _DayCell(
                    date: DateTime(month.year, month.month, day),
                    count: dayCounts[day] ?? 0,
                    isSelected: _isSameDay(
                      selectedDate,
                      DateTime(month.year, month.month, day),
                    ),
                    isToday: _isSameDay(
                      today,
                      DateTime(month.year, month.month, day),
                    ),
                    isFuture: DateTime(
                      month.year,
                      month.month,
                      day,
                    ).isAfter(today),
                    onTap: onSelect,
                  ),
              ],
            ),
          ),
          const SizedBox(height: _GrowySpacing.sm),
          const _CalendarLegend(),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final int count;
  final bool isSelected;
  final bool isToday;
  final bool isFuture;
  final ValueChanged<DateTime> onTap;

  const _DayCell({
    required this.date,
    required this.count,
    required this.isSelected,
    required this.isToday,
    required this.isFuture,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fill = count >= 3
        ? _GrowyColors.primary
        : count == 2
        ? _GrowyColors.primaryTint
        : Colors.transparent;
    final Color numberColor = isFuture
        ? _GrowyColors.textDisabled
        : count >= 3
        ? Colors.white
        : _GrowyColors.textMain;

    return Semantics(
      button: !isFuture,
      selected: isSelected,
      label: '${_formatLongDate(date)}, $count habits completed',
      child: InkResponse(
        onTap: isFuture ? null : () => onTap(date),
        radius: 22,
        child: Center(
          // Selection ring and completion fill change smoothly (200 ms).
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? _GrowyColors.textMain : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: _GrowyText.caption.copyWith(
                    fontSize: 13,
                    color: numberColor,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (count == 1)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: _GrowyColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend();

  Widget _item(Widget marker, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      marker,
      const SizedBox(width: 4),
      Text(label, style: _GrowyText.caption),
    ],
  );

  @override
  Widget build(BuildContext context) {
    Widget circle(Color color) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: _GrowySpacing.lg,
      runSpacing: _GrowySpacing.xs,
      children: [
        _item(
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _GrowyColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          '1 habit',
        ),
        _item(circle(_GrowyColors.primaryTint), '2'),
        _item(circle(_GrowyColors.primary), '3+'),
      ],
    );
  }
}

/// One verified completion in the history: photo thumbnail, name,
/// category and time, "Verified with photo" badge, and XP earned.
class _HistoryEntryCard extends StatelessWidget {
  final _HabitLog log;
  final VoidCallback onPhotoTap;

  const _HistoryEntryCard({
    super.key,
    required this.log,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    return _GrowyCard(
      padding: const EdgeInsets.all(_GrowySpacing.md),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'View verification photo for ${log.habitName}',
            child: GestureDetector(
              onTap: onPhotoTap,
              child: Hero(
                tag: 'log-photo-${log.id}',
                child: _LogPhoto(source: log.imageUrl, width: 56, height: 56),
              ),
            ),
          ),
          const SizedBox(width: _GrowySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.habitName,
                  style: _GrowyText.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      _HabitCategories.icon(log.category),
                      size: 13,
                      color: _GrowyColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${_HabitCategories.label(log.category)} · ${_formatTime(log.completedAt)}',
                        style: _GrowyText.caption,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const _VerificationBadge(),
              ],
            ),
          ),
          const SizedBox(width: _GrowySpacing.sm),
          Text(
            '+${log.pointsEarned} XP',
            style: _GrowyText.cardTitle.copyWith(color: _GrowyColors.primary),
          ),
        ],
      ),
    );
  }
}

/// Shows a verification photo from a URL (stored by the backend) or a local
/// file path (just captured with the in-app camera). Read-only by design.
class _LogPhoto extends StatelessWidget {
  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  const _LogPhoto({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = _GrowyRadius.thumb,
  });

  bool get _isNetwork =>
      source.startsWith('http://') || source.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (source.isEmpty) {
      image = _placeholder(broken: true);
    } else if (_isNetwork) {
      image = Image.network(
        source,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(),
        errorBuilder: (_, __, ___) => _placeholder(broken: true),
      );
    } else {
      image = Image.file(
        File(source),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _placeholder(broken: true),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: image,
    );
  }

  Widget _placeholder({bool broken = false}) {
    return Container(
      width: width,
      height: height,
      color: _GrowyColors.cardBorder,
      alignment: Alignment.center,
      child: Icon(
        broken ? Icons.broken_image_outlined : Icons.photo_camera_outlined,
        color: _GrowyColors.textSecondary,
        size: 20,
      ),
    );
  }
}

/// White rounded card with a 1px border. The base of every Growy card.
class _GrowyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  Color get _color => color ?? _GrowyColors.background;
  final Color? borderColor;
  Color get _borderColor => borderColor ?? _GrowyColors.cardBorder;
  final double borderWidth;
  final VoidCallback? onTap;

  const _GrowyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(_GrowySpacing.lg),
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(_GrowyRadius.card);
    return Material(
      color: _color,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: _borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Section title on the left, optional caption or text button on the right.
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  const _SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _GrowySpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _GrowyText.sectionTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: _GrowyText.caption),
                ],
              ],
            ),
          ),
          if (trailing != null)
            onTrailingTap == null
                ? Text(trailing!, style: _GrowyText.caption)
                : TextButton(
                    onPressed: onTrailingTap,
                    style: TextButton.styleFrom(
                      foregroundColor: _GrowyColors.primary,
                    ),
                    child: Text(
                      trailing!,
                      style: _GrowyText.caption.copyWith(
                        color: _GrowyColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}

/// A bordered card with an optional icon, a big number and a label.
/// Used for the Me page stats and the Habits month summary.
class _StatTile extends StatelessWidget {
  final IconData? icon;
  final String value;
  final String label;
  final Color? iconColor;
  Color get _iconColor => iconColor ?? _GrowyColors.primary;
  final Color? iconBackground;
  Color get _iconBackground => iconBackground ?? _GrowyColors.primaryTint;

  const _StatTile({
    super.key,
    this.icon,
    required this.value,
    required this.label,
    this.iconColor,
    this.iconBackground,
  });

  @override
  Widget build(BuildContext context) {
    return _GrowyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: _GrowySpacing.md,
        vertical: _GrowySpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            _IconCircle(
              icon: icon!,
              size: 32,
              foreground: _iconColor,
              background: _iconBackground,
            ),
            const SizedBox(height: _GrowySpacing.sm),
          ],
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: _GrowyText.bigNumber),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: _GrowyText.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Tinted circle with a centred Material icon.
class _IconCircle extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? foreground;
  Color get _foreground => foreground ?? _GrowyColors.primary;
  final Color? background;
  Color get _background => background ?? _GrowyColors.primaryTint;

  const _IconCircle({
    super.key,
    required this.icon,
    this.size = 48,
    this.foreground,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _background, shape: BoxShape.circle),
      child: Icon(icon, color: _foreground, size: size * 0.5),
    );
  }
}

/// Rounded pill with optional icon. Base for XP and verification badges.
class _GrowyPill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? background;
  Color get _background => background ?? _GrowyColors.primaryTint;
  final Color? foreground;
  Color get _foreground => foreground ?? _GrowyColors.primary;

  const _GrowyPill({
    super.key,
    required this.text,
    this.icon,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(_GrowyRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: _foreground),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: _GrowyText.caption.copyWith(
              color: _foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Verified with photo"
class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({super.key});

  @override
  Widget build(BuildContext context) => const _GrowyPill(
    text: 'Verified with photo',
    icon: Icons.photo_camera_rounded,
  );
}

/// Friendly empty or error message with an optional button.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? detail;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const _EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.detail,
    this.buttonLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return _GrowyCard(
      padding: const EdgeInsets.all(_GrowySpacing.xl),
      child: Column(
        children: [
          _IconCircle(icon: icon, size: 56),
          const SizedBox(height: _GrowySpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: _GrowyText.cardTitle,
          ),
          if (detail != null) ...[
            const SizedBox(height: _GrowySpacing.xs),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: _GrowyText.caption,
            ),
          ],
          if (buttonLabel != null && onPressed != null) ...[
            const SizedBox(height: _GrowySpacing.lg),
            _GrowySmallButtonLink(label: buttonLabel!, onPressed: onPressed!),
          ],
        ],
      ),
    );
  }
}

/// Text-style action used inside EmptyState.
class _GrowySmallButtonLink extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _GrowySmallButtonLink({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: _GrowyColors.primary),
      child: Text(
        label,
        style: _GrowyText.body.copyWith(
          color: _GrowyColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Small centred error with a retry button, used when a page fails to load.
class _LoadError extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadError({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _EmptyState(
      icon: Icons.wifi_off_rounded,
      message: "Couldn't load this page.",
      detail: 'Check your connection and try again.',
      buttonLabel: 'Try again',
      onPressed: onRetry,
    );
  }
}

/// One photo-verified habit completion, as shown in the Habits history.
class _HabitLog {
  final String id;
  final String habitId;
  final String habitName;

  /// "Study" or "Health".
  final String category;
  final DateTime completedAt;
  final int pointsEarned;

  /// Where the verification photo lives. A URL (http/https) once the backend
  /// stores it, or a local file path for photos taken in this session.
  /// These photos were always captured with the in-app camera; nothing is uploaded from the gallery.
  final String imageUrl;

  const _HabitLog({
    required this.id,
    required this.habitId,
    required this.habitName,
    required this.category,
    required this.completedAt,
    required this.pointsEarned,
    required this.imageUrl,
  });

  factory _HabitLog.fromJson(Map<String, dynamic> json) {
    return _HabitLog(
      id: json['id'].toString(),
      habitId: json['habit_id'].toString(),
      habitName: (json['habit_name'] ?? '') as String,
      category: (json['category'] ?? '') as String,
      completedAt: DateTime.parse(json['completed_at'] as String).toLocal(),
      pointsEarned: (json['points_earned'] ?? 0) as int,
      imageUrl: (json['image_url'] ?? '') as String,
    );
  }
}

/// All verified logs in one calendar month, plus the numbers the Habits page shows.
class _MonthHistory {
  /// First day of the month (time ignored).
  final DateTime month;
  final List<_HabitLog> logs;

  _MonthHistory({required DateTime month, required List<_HabitLog> logs})
    : month = DateTime(month.year, month.month),
      logs = List.unmodifiable(
        [...logs]..sort((a, b) => b.completedAt.compareTo(a.completedAt)),
      );

  /// Day of month (1–31) → number of habits completed that day.
  Map<int, int> get dayCounts {
    final counts = <int, int>{};
    for (final log in logs) {
      final day = log.completedAt.day;
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return counts;
  }

  int get habitsCompleted => logs.length;

  int get xpEarned => logs.fold(0, (sum, log) => sum + log.pointsEarned);

  int get daysActive => dayCounts.length;

  /// Logs for one day, newest first.
  List<_HabitLog> logsOn(DateTime date) => logs
      .where(
        (log) =>
            log.completedAt.year == date.year &&
            log.completedAt.month == date.month &&
            log.completedAt.day == date.day,
      )
      .toList();
}

/// The two real habit categories (backend `HABIT_CATEGORIES`): Study and Health.
class _HabitCategories {
  _HabitCategories._();

  static const String study = 'Study';
  static const String health = 'Health';

  static bool isStudy(String category) =>
      category.trim().toLowerCase() == 'study';

  /// Display label with consistent capitalisation.
  static String label(String category) => isStudy(category) ? study : health;

  static IconData icon(String category) =>
      isStudy(category) ? Icons.menu_book_rounded : Icons.favorite_rounded;

  /// What to photograph. Keep these in line with the CLIP candidate labels
  /// on the backend, so users photograph what the model is checking for.
  static String photoHint(String category) => isStudy(category)
      ? 'Your open book or notes on your desk'
      : 'Your workout, running shoes or healthy meal';
}

// ───────────────────────────────────────────────────────────── sample data
// Sample history so the page works before the backend is ready.
// TODO(backend): replace getMonthHistory with GET /habit-logs?month=YYYY-MM.

class _HabitsData {
  final List<_HabitLog> _logs = [];

  _HabitsData() {
    const habits = [
      ['h1', 'Read 20 Pages', 'Study', 30],
      ['h2', 'Morning Run', 'Health', 30],
      ['h3', 'Study Session', 'Study', 40],
      ['h4', 'Drink 8 Glasses of Water', 'Health', 30],
      ['h5', 'Healthy Breakfast', 'Health', 30],
    ];
    const pattern = [2, 1, 3, 0, 2, 1, 0, 3, 1, 2, 0, 1];
    final now = DateTime.now();
    var nextId = 1;
    for (var back = 60; back >= 0; back--) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: back));
      final count = pattern[(day.day + day.month) % pattern.length];
      for (var i = 0; i < count; i++) {
        final h = habits[(day.day + i * 2) % habits.length];
        final time = day.add(Duration(hours: 7 + i * 4, minutes: 14 + i * 7));
        if (time.isAfter(now)) continue;
        final id = 'log${nextId++}';
        _logs.add(
          _HabitLog(
            id: id,
            habitId: h[0] as String,
            habitName: h[1] as String,
            category: h[2] as String,
            completedAt: time,
            pointsEarned: h[3] as int,
            imageUrl: 'https://picsum.photos/seed/growy-$id/600/600',
          ),
        );
      }
    }
  }

  Future<_MonthHistory> getMonthHistory(DateTime month) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _MonthHistory(
      month: month,
      logs: _logs
          .where(
            (l) =>
                l.completedAt.year == month.year &&
                l.completedAt.month == month.month,
          )
          .toList(),
    );
  }
}

final _HabitsData _habitsData = _HabitsData();

/// Growy colour tokens. Every widget reads colours from here instead of
/// typing hex codes, so a palette change happens in one place.
class _GrowyColors {
  _GrowyColors._();

  static Color get primary => GrowyPalette.primary;
  static Color get primaryTint => GrowyPalette.primaryTint;

  /// Decorative only (streak flame, group icon backgrounds).
  static Color get secondary => GrowyPalette.secondary;
  static Color get secondaryTint => GrowyPalette.secondaryTint;

  /// Darker pink for icons drawn on [secondaryTint] (secondary itself is too light to read).
  static Color get secondaryDeep => GrowyPalette.secondaryDeep;

  static Color get background => GrowyPalette.surface;
  static Color get cardBorder => GrowyPalette.cardBorder;
  static Color get inputBorder => GrowyPalette.inputBorder;

  static Color get textMain => GrowyPalette.textMain;
  static Color get textSecondary => GrowyPalette.textSecondary;
  static Color get textDisabled => GrowyPalette.textDisabled;

  static Color get error => GrowyPalette.error;

  /// Error at ~12% opacity, for the failed-verification circle.
  static Color get errorTint => GrowyPalette.errorTint;

  /// Leaderboard medals (ranks 1–3).
  static Color get gold => GrowyPalette.gold;
  static Color get silver => GrowyPalette.silver;
  static Color get bronze => GrowyPalette.bronze;

  /// Primary at 35% opacity, for the primary button's soft shadow.
  static Color get buttonShadow => GrowyPalette.buttonShadow;

  /// White at 60% opacity, dims the photo while it is being checked.
  static Color get checkingOverlay => GrowyPalette.checkingOverlay;

  /// Black at 55% opacity, for buttons/pills over the camera preview.
  static Color get cameraScrim => GrowyPalette.cameraScrim;
}

/// Spacing scale: 4, 8, 12, 16, 24, 32. Screens use 20 at the sides.
class _GrowySpacing {
  _GrowySpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double screen = 20;
}

class _GrowyRadius {
  _GrowyRadius._();

  static const double button = 14;
  static const double input = 12;
  static const double card = 16;
  static const double pill = 20;
  static const double thumb = 10;
}

/// The seven Growy text styles.
/// Fraunces = titles, big numbers, buttons. Poppins = everything else.
class _GrowyText {
  _GrowyText._();

  /// "Groups", "My Habits", "Me" at the top of each tab.
  static TextStyle get screenTitle => GoogleFonts.fraunces(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: _GrowyColors.textMain,
  );

  /// "My Groups", "Leaderboard", the date header in the history.
  static TextStyle get sectionTitle => GoogleFonts.fraunces(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    color: _GrowyColors.textMain,
  );

  /// Rank "#2", XP totals, stat tiles, "+30 XP" on success.
  static TextStyle get bigNumber => GoogleFonts.fraunces(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: _GrowyColors.textMain,
  );

  static TextStyle get button => GoogleFonts.fraunces(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  /// Group name, habit name, member name.
  static TextStyle get cardTitle => GoogleFonts.poppins(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: _GrowyColors.textMain,
  );

  static TextStyle get body => GoogleFonts.poppins(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: _GrowyColors.textMain,
  );

  /// Member counts, categories, dates, labels.
  static TextStyle get caption => GoogleFonts.poppins(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: _GrowyColors.textSecondary,
  );
}

/// Small formatting helpers so the pages don't need the `intl` package.

const List<String> _kMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _kMonthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Index 0 = Monday … 6 = Sunday (matches DateTime.weekday - 1).
const List<String> _kWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _kWeekdayShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// 2450 → "2,450"
String _formatNumber(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

/// "October 2026"
String _formatMonthYear(DateTime d) => '${_kMonthNames[d.month - 1]} ${d.year}';

/// "Thursday, October 8"
String _formatLongDate(DateTime d) =>
    '${_kWeekdayNames[d.weekday - 1]}, ${_kMonthNames[d.month - 1]} ${d.day}';

/// "Oct 8"
String _formatShortDate(DateTime d) => '${_kMonthShort[d.month - 1]} ${d.day}';

/// "8:14 AM"
String _formatTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
