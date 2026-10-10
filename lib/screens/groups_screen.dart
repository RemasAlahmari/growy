// Growy — Groups page (My Groups, Discover Groups, Group Details, leaderboard).

// Open it with: GroupsScreen()
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../core/motion/motion.dart';
import '../theme/app_theme.dart';

/// Groups tab. "Groups to join" (suggestions) sits at the top as a swipeable
/// strip; "My Groups" follows below it.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  static const int _maxSuggestions = 5;

  List<_Group>? _myGroups;
  List<_Group> _discover = [];
  final Set<String> _joining = {};
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _groupsData.getMyGroups(),
        _groupsData.getDiscoverGroups(),
      ]);
      if (!mounted) return;
      setState(() {
        _myGroups = results[0];
        _discover = results[1];
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _toast(String message, {SnackBarAction? action}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _join(_Group group) async {
    setState(() => _joining.add(group.id));
    try {
      final joined = await _groupsData.joinGroup(group.id);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _discover.removeWhere((g) => g.id == group.id);
        _myGroups = [...?_myGroups, joined];
      });
      _toast('You joined ${group.name}');
    } catch (_) {
      if (mounted) _toast("Couldn't join ${group.name}. Try again.");
    } finally {
      if (mounted) setState(() => _joining.remove(group.id));
    }
  }

  Future<void> _dismiss(_Group group) async {
    final index = _discover.indexWhere((g) => g.id == group.id);
    if (index == -1) return;
    setState(() => _discover.removeAt(index));
    await _groupsData.dismissGroup(group.id);
    if (!mounted) return;
    _toast(
      'Hidden from suggestions',
      action: SnackBarAction(
        label: 'Undo',
        textColor: _GrowyColors.primaryTint,
        onPressed: () async {
          await _groupsData.undoDismissGroup(group.id);
          if (!mounted) return;
          setState(() {
            if (!_discover.any((g) => g.id == group.id)) {
              _discover.insert(index.clamp(0, _discover.length), group);
            }
          });
        },
      ),
    );
  }

  Future<void> _openGroup(_Group group) async {
    final left = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _GroupDetailsScreen(group: group)),
    );
    if (left == true && mounted) {
      _toast('You left ${group.name}');
      _load();
    }
  }

  Future<void> _showJoinWithCode() async {
    final joined = await showModalBottomSheet<_Group>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _GrowyColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_GrowyRadius.card),
        ),
      ),
      builder: (_) => const _JoinWithCodeSheet(),
    );
    if (joined != null && mounted) {
      _toast('You joined ${joined.name}');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final myGroups = _myGroups;
    final suggestions = _discover.take(_maxSuggestions).toList();

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
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              _GrowySpacing.screen,
              _GrowySpacing.lg,
              _GrowySpacing.screen,
              _GrowySpacing.xxl,
            ),
            children: [
              Row(
                children: [ 
                  const _BackToHome(),
                  Expanded(child: Text('Groups', style: _GrowyText.screenTitle)),
                 
                  IconButton(
                    tooltip: 'Join with a code',
                    onPressed: _showJoinWithCode,
                    icon: Icon(
                      Icons.group_add_outlined,
                      color: _GrowyColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: _GrowySpacing.lg),
              if (myGroups == null && _failed)
                _LoadError(onRetry: _load)
              else if (myGroups == null)
                Padding(
                  padding: EdgeInsets.all(_GrowySpacing.xxl),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: _GrowyColors.primary,
                    ),
                  ),
                )
              else ...[
                if (suggestions.isNotEmpty) ...[
                  const _SectionHeader(
                    title: 'Groups to join',
                    subtitle: 'Swipe to see more',
                  ),
                  _DiscoverStrip(
                    groups: suggestions,
                    joining: _joining,
                    onJoin: _join,
                    onDismiss: _dismiss,
                  ),
                  const SizedBox(height: _GrowySpacing.xl),
                ],
                _SectionHeader(
                  title: 'My Groups',
                  trailing:
                      '${myGroups.length} ${myGroups.length == 1 ? 'group' : 'groups'}',
                ),
                if (myGroups.isEmpty)
                  GrowyFadeIn(
                    child: _EmptyState(
                      icon: Icons.groups_outlined,
                      message: "You haven't joined a group yet",
                      detail: suggestions.isEmpty
                          ? 'Ask a friend for their group code to join.'
                          : 'Pick one above to start competing with friends.',
                    ),
                  )
                else
                  for (var i = 0; i < myGroups.length; i++)
                    Padding(
                      key: ValueKey(myGroups[i].id),
                      padding: const EdgeInsets.only(bottom: _GrowySpacing.md),
                      child: GrowySlideIn(
                        index: i,
                        baseDelay: suggestions.isEmpty
                            ? Duration.zero
                            : const Duration(milliseconds: 120),
                        child: GrowyPressEffect(
                          child: _JoinedGroupCard(
                            group: myGroups[i],
                            onTap: () => _openGroup(myGroups[i]),
                          ),
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
/// Bottom sheet: type a room code and join.
class _JoinWithCodeSheet extends StatefulWidget {
  const _JoinWithCodeSheet();

  @override
  State<_JoinWithCodeSheet> createState() => _JoinWithCodeSheetState();
}

class _JoinWithCodeSheetState extends State<_JoinWithCodeSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code your friend shared.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final group = await _groupsData.joinGroupByCode(code);
      if (mounted) Navigator.of(context).pop(group);
    } on _GroupCodeNotFoundException {
      if (mounted) setState(() => _error = 'No group found with that code.');
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't join right now. Try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _GrowySpacing.screen,
        _GrowySpacing.xl,
        _GrowySpacing.screen,
        MediaQuery.of(context).viewInsets.bottom + _GrowySpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Join with a code', style: _GrowyText.sectionTitle),
          const SizedBox(height: _GrowySpacing.xs),
          Text(
            'Ask a group member for its code.',
            style: _GrowyText.caption,
          ),
          const SizedBox(height: _GrowySpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: _GrowyText.body,
            decoration: InputDecoration(
              hintText: 'e.g. GROWY1',
              hintStyle: _GrowyText.body.copyWith(
                color: _GrowyColors.textSecondary,
              ),
              errorText: _error,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: _GrowySpacing.lg,
                vertical: 16,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_GrowyRadius.input),
                borderSide: BorderSide(color: _GrowyColors.inputBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_GrowyRadius.input),
                borderSide: BorderSide(
                  color: _GrowyColors.primary,
                  width: 1.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_GrowyRadius.input),
                borderSide: BorderSide(color: _GrowyColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(_GrowyRadius.input),
                borderSide: BorderSide(
                  color: _GrowyColors.error,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: _GrowySpacing.lg),
          _GrowyButton(label: 'Join', isLoading: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}

/// One group: header, the user's standing, the group goal and the leaderboard.
/// Pops with `true` if the user left the group.
class _GroupDetailsScreen extends StatefulWidget {
  final _Group group;
  const _GroupDetailsScreen({super.key, required this.group});

  @override
  State<_GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<_GroupDetailsScreen> {
  static const int _topCount = 10;

  List<_LeaderboardEntry>? _entries;
  bool _failed = false;
  bool _leaving = false;

  _Group get group => widget.group;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final entries = await _groupsData.getLeaderboard(group.id);
      if (mounted) setState(() => _entries = entries);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _GrowyColors.background,
        surfaceTintColor: _GrowyColors.background,
        title: Text('Leave ${group.name}?', style: _GrowyText.sectionTitle),
        content: Text(
          'Your points in this group will no longer count toward its leaderboard.',
          style: _GrowyText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: _GrowyText.body.copyWith(color: _GrowyColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Leave',
              style: _GrowyText.body.copyWith(
                color: _GrowyColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _leaving = true);
    try {
      await _groupsData.leaveGroup(group.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _leaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't leave the group. Try again.")),
      );
    }
  }

  /// "120 XP behind Sara (#1)" or "You're leading the group!"
  String _standingLine(List<_LeaderboardEntry> entries) {
    if (group.userRank <= 1) return "You're leading the group!";
    final ahead = entries.where((e) => e.rank == group.userRank - 1);
    if (ahead.isEmpty) return 'Keep verifying habits to climb the board.';
    final next = ahead.first;
    final gap = (next.points - group.userPoints).clamp(0, 1 << 30);
    return '${_formatNumber(gap.toInt())} XP behind ${next.displayName} (#${next.rank})';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

    return Scaffold(
      backgroundColor: _GrowyColors.background,
      appBar: AppBar(
        backgroundColor: _GrowyColors.background,
        surfaceTintColor: _GrowyColors.background,
        foregroundColor: _GrowyColors.textMain,
        elevation: 0,
        actions: [
          if (_leaving)
            const Padding(
              padding: EdgeInsets.all(_GrowySpacing.lg),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == 'leave') _confirmLeave();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(
                        Icons.logout_rounded,
                        size: 20,
                        color: _GrowyColors.error,
                      ),
                      const SizedBox(width: _GrowySpacing.md),
                      Text(
                        'Leave group',
                        style: _GrowyText.body.copyWith(color: _GrowyColors.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        color: _GrowyColors.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            _GrowySpacing.screen,
            0,
            _GrowySpacing.screen,
            _GrowySpacing.xxl,
          ),
          children: [
            // Header
            GrowyFadeIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: _GroupAvatar(group: group, size: 72)),
                  const SizedBox(height: _GrowySpacing.md),
                  Text(
                    group.name,
                    textAlign: TextAlign.center,
                    style: _GrowyText.screenTitle,
                  ),
                  const SizedBox(height: _GrowySpacing.xs),
                  Text(
                    '${group.category} · ${_formatNumber(group.memberCount)} members',
                    textAlign: TextAlign.center,
                    style: _GrowyText.caption,
                  ),
                  const SizedBox(height: _GrowySpacing.sm),
                  Text(
                    group.description,
                    textAlign: TextAlign.center,
                    style: _GrowyText.body.copyWith(color: _GrowyColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _GrowySpacing.xl),

            // Invite code to share
            if (group.inviteCode != null) ...[
              GrowyFadeIn(
                delay: const Duration(milliseconds: 80),
                child: _InviteCodeCard(group: group),
              ),
              const SizedBox(height: _GrowySpacing.md),
            ],

            // Your standing
            _GrowyCard(
              color: _GrowyColors.primaryTint,
              borderColor: _GrowyColors.primaryTint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Your standing', style: _GrowyText.caption),
                  const SizedBox(height: _GrowySpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _StatBlock(
                          label: 'Rank',
                          value:
                              '#${group.userRank} of ${_formatNumber(group.memberCount)}',
                          valueColor: _GrowyColors.primary,
                        ),
                      ),
                      Expanded(
                        child: _StatBlock(
                          label: 'Points',
                          value: '${_formatNumber(group.userPoints)} XP',
                        ),
                      ),
                    ],
                  ),
                  if (entries != null) ...[
                    const SizedBox(height: _GrowySpacing.md),
                    Row(
                      children: [
                        Icon(
                          Icons.trending_up_rounded,
                          size: 18,
                          color: _GrowyColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _standingLine(entries),
                            style: _GrowyText.body,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Goal
            if (group.goal != null) ...[
              const SizedBox(height: _GrowySpacing.md),
              _GroupProgressCard(goal: group.goal!),
            ],

            // Leaderboard
            const SizedBox(height: _GrowySpacing.xl),
            const _SectionHeader(title: 'Leaderboard'),
            if (entries == null && _failed)
              _LoadError(onRetry: _load)
            else if (entries == null)
              Padding(
                padding: EdgeInsets.all(_GrowySpacing.xl),
                child: Center(
                  child: CircularProgressIndicator(color: _GrowyColors.primary),
                ),
              )
            else
              ..._leaderboard(entries),
          ],
        ),
      ),
    );
  }

  /// The user's own row gets one soft shimmer once the list has settled,
  /// so they can find themselves at a glance.
  Widget _highlightIfMe(_LeaderboardEntry entry) {
    final row = _LeaderboardItem(entry: entry);
    if (!entry.isMe || GrowyMotion.reduced(context)) return row;
    return row.animate(delay: 900.ms).shimmer(
          duration: GrowyMotion.highlight + 300.ms,
          color: _GrowyColors.primary.withValues(alpha: 0.25),
        );
  }

  List<Widget> _leaderboard(List<_LeaderboardEntry> entries) {
    final top = entries.take(_topCount).toList();
    final me = entries.where((e) => e.isMe);
    final meOutsideTop = me.isNotEmpty && me.first.rank > _topCount;

    return [
      for (var i = 0; i < top.length; i++)
        GrowySlideIn(index: i, child: _highlightIfMe(top[i])),
      if (meOutsideTop) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: _GrowySpacing.sm),
          child: Center(
            child: Text(
              '···',
              style: _GrowyText.sectionTitle.copyWith(
                color: _GrowyColors.textSecondary,
              ),
            ),
          ),
        ),
        GrowySlideIn(index: top.length, child: _highlightIfMe(me.first)),
      ],
      if (entries.length > _topCount)
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _GroupMembersScreen(
                  groupName: group.name,
                  entries: entries,
                ),
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: _GrowyColors.primary),
            child: Text(
              'See all ${_formatNumber(group.memberCount)} members',
              style: _GrowyText.body.copyWith(
                color: _GrowyColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
    ];
  }
}

/// The full leaderboard, which doubles as the member list.
class _GroupMembersScreen extends StatelessWidget {
  final String groupName;
  final List<_LeaderboardEntry> entries;

  const _GroupMembersScreen({
    super.key,
    required this.groupName,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _GrowyColors.background,
      appBar: AppBar(
        backgroundColor: _GrowyColors.background,
        surfaceTintColor: _GrowyColors.background,
        foregroundColor: _GrowyColors.textMain,
        elevation: 0,
        title: Text(groupName, style: _GrowyText.sectionTitle),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          _GrowySpacing.screen,
          _GrowySpacing.sm,
          _GrowySpacing.screen,
          _GrowySpacing.xxl,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) => _LeaderboardItem(entry: entries[index]),
      ),
    );
  }
}

/// Circle with the group's category icon. Alternates green/pink tints
/// so a list of groups doesn't look identical.
class _GroupAvatar extends StatelessWidget {
  final _Group group;
  final double size;

  const _GroupAvatar({super.key, required this.group, this.size = 48});

  static IconData iconFor(String iconKey) {
    switch (iconKey) {
      case 'run':
        return Icons.directions_run_rounded;
      case 'book':
        return Icons.menu_book_rounded;
      case 'water':
        return Icons.water_drop_rounded;
      case 'mind':
        return Icons.self_improvement_rounded;
      default:
        return Icons.groups_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pink = group.id.hashCode.isOdd;
    return _IconCircle(
      icon: iconFor(group.iconKey),
      size: size,
      background: pink ? _GrowyColors.secondaryTint : _GrowyColors.primaryTint,
      foreground: pink ? _GrowyColors.secondaryDeep : _GrowyColors.primary,
    );
  }
}

/// A group the user belongs to. Rank and points are the visual focus.
/// The whole card is tappable and opens Group Details.
class _JoinedGroupCard extends StatelessWidget {
  final _Group group;
  final VoidCallback onTap;

  const _JoinedGroupCard({super.key, required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final goal = group.goal;
    return _GrowyCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _GroupAvatar(group: group),
              const SizedBox(width: _GrowySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: _GrowyText.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatCompact(group.memberCount)} members · ${group.category}',
                      style: _GrowyText.caption,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: _GrowyColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: _GrowySpacing.lg),
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  label: 'Your rank',
                  value: '#${group.userRank}',
                  valueColor: _GrowyColors.primary,
                ),
              ),
              Container(width: 1, height: 36, color: _GrowyColors.cardBorder),
              const SizedBox(width: _GrowySpacing.lg),
              Expanded(
                child: _StatBlock(
                  label: 'Your points',
                  value: '${_formatNumber(group.userPoints)} XP',
                ),
              ),
            ],
          ),
          if (goal != null) ...[
            const SizedBox(height: _GrowySpacing.lg),
            Text(
              goal.title,
              style: _GrowyText.caption.copyWith(color: _GrowyColors.textMain),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            _ProgressBarRow(
              value: goal.progress,
              rightText: '${(goal.progress * 100).round()}%',
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────── groups to join

/// Horizontal strip of suggested groups ("Groups to join"). Used at the top
/// of the Groups page and, through [GroupsToJoinStrip], on Home.
class _DiscoverStrip extends StatelessWidget {
  final List<_Group> groups;
  final Set<String> joining;
  final void Function(_Group group) onJoin;
  final void Function(_Group group)? onDismiss;
  final Duration baseDelay;

  const _DiscoverStrip({
    required this.groups,
    required this.joining,
    required this.onJoin,
    this.onDismiss,
    this.baseDelay = Duration.zero,
  });

  static const double cardWidth = 256;
  static const double height = 176;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      // Lets the strip be dragged with a mouse too (web / desktop / emulator),
      // not only swiped with a finger.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: ListView.separated(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: _GrowySpacing.md),
        itemBuilder: (context, i) {
          final group = groups[i];
          return GrowySlideIn(
            key: ValueKey(group.id),
            index: i,
            axis: Axis.horizontal,
            baseDelay: baseDelay,
            child: SizedBox(
              width: cardWidth,
              child: GrowyPressEffect(
                child: _DiscoverStripCard(
                  group: group,
                  isJoining: joining.contains(group.id),
                  onJoin: () => onJoin(group),
                  onDismiss: onDismiss == null ? null : () => onDismiss!(group),
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

/// One suggested group in the strip: icon, name, two lines of description,
/// "Join", and a menu with "Not interested".
class _DiscoverStripCard extends StatelessWidget {
  final _Group group;
  final bool isJoining;
  final VoidCallback onJoin;
  final VoidCallback? onDismiss;

  const _DiscoverStripCard({
    required this.group,
    required this.onJoin,
    this.onDismiss,
    this.isJoining = false,
  });

  @override
  Widget build(BuildContext context) {
    return _GrowyCard(
      padding: const EdgeInsets.fromLTRB(
        _GrowySpacing.md,
        _GrowySpacing.md,
        _GrowySpacing.xs,
        _GrowySpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _GroupAvatar(group: group, size: 40),
              const SizedBox(width: _GrowySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: _GrowyText.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${group.category} · ${_formatCompact(group.memberCount)} members',
                      style: _GrowyText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onDismiss != null)
                PopupMenuButton<String>(
                  tooltip: 'More options',
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: _GrowyColors.textSecondary,
                  ),
                  onSelected: (value) {
                    if (value == 'dismiss') onDismiss!();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'dismiss',
                      child: Row(
                        children: [
                          Icon(
                            Icons.visibility_off_outlined,
                            size: 20,
                            color: _GrowyColors.textSecondary,
                          ),
                          const SizedBox(width: _GrowySpacing.md),
                          Text('Not interested', style: _GrowyText.body),
                        ],
                      ),
                    ),
                  ],
                )
              else
                const SizedBox(width: _GrowySpacing.sm),
            ],
          ),
          const SizedBox(height: _GrowySpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: _GrowySpacing.sm),
              child: Text(
                group.description,
                style: _GrowyText.caption.copyWith(fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: _GrowySpacing.sm),
              child: _GrowySmallButton(
                label: 'Join',
                isLoading: isJoining,
                onPressed: onJoin,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Groups to join" strip for the Home page. Loads its own suggestions,
/// lets the user join in place, and links to the full Groups page.
/// Hides itself when there is nothing to suggest.
class GroupsToJoinStrip extends StatefulWidget {
  const GroupsToJoinStrip({super.key});

  @override
  State<GroupsToJoinStrip> createState() => _GroupsToJoinStripState();
}

class _GroupsToJoinStripState extends State<GroupsToJoinStrip> {
  List<_Group> _groups = [];
  final Set<String> _joining = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final groups = await _groupsData.getDiscoverGroups();
      if (mounted) setState(() => _groups = groups.take(5).toList());
    } catch (e) {
      debugPrint('Could not load group suggestions: $e');
    }
  }

  Future<void> _join(_Group group) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _joining.add(group.id));
    try {
      await _groupsData.joinGroup(group.id);
      HapticFeedback.lightImpact();
      if (!mounted) return;
      setState(() => _groups.removeWhere((g) => g.id == group.id));
      messenger.showSnackBar(SnackBar(content: Text('You joined ${group.name}')));
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't join ${group.name}. Try again.")),
      );
    } finally {
      if (mounted) setState(() => _joining.remove(group.id));
    }
  }

  Future<void> _openGroups() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GroupsScreen()),
    );
    _load(); // the user may have joined or hidden groups there
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: GrowyMotion.enterCurve,
      alignment: Alignment.topCenter,
      child: _groups.isEmpty
          ? const SizedBox(width: double.infinity)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeader(
                  title: 'Groups to join',
                  trailing: 'See all',
                  onTrailingTap: _openGroups,
                ),
                _DiscoverStrip(
                  groups: _groups,
                  joining: _joining,
                  onJoin: _join,
                  // Arrives after the habit list, so it never competes with it.
                  baseDelay: const Duration(milliseconds: 300),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────── invite code

/// The group's invite code, with Copy and Share, so members can bring
/// friends in through "Join with a code".
class _InviteCodeCard extends StatefulWidget {
  final _Group group;
  const _InviteCodeCard({required this.group});

  @override
  State<_InviteCodeCard> createState() => _InviteCodeCardState();
}

class _InviteCodeCardState extends State<_InviteCodeCard> {
  bool _copied = false;

  String get _code => widget.group.inviteCode ?? '';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _code));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Join my group "${widget.group.name}" on Growy! '
              'Open Groups, tap "Join with a code" and enter: $_code',
          subject: 'Join ${widget.group.name} on Growy',
        ),
      );
    } catch (e) {
      debugPrint('Share failed: $e');
      _copy(); // fall back to copying the code
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GrowyCard(
      padding: const EdgeInsets.fromLTRB(
        _GrowySpacing.lg,
        _GrowySpacing.md,
        _GrowySpacing.sm,
        _GrowySpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite friends with this code', style: _GrowyText.caption),
                const SizedBox(height: 2),
                Semantics(
                  label: 'Group code ${_code.split('').join(' ')}',
                  excludeSemantics: true,
                  child: SelectableText(
                    _code,
                    style: _GrowyText.bigNumber.copyWith(
                      letterSpacing: 3,
                      color: _GrowyColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _copied ? 'Copied' : 'Copy code',
            onPressed: _copy,
            icon: AnimatedSwitcher(
              duration: GrowyMotion.micro,
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                key: ValueKey(_copied),
                color: _GrowyColors.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Share code',
            onPressed: _share,
            icon: Icon(Icons.ios_share_rounded, color: _GrowyColors.primary),
          ),
        ],
      ),
    );
  }
}

/// The group's shared goal with its progress bar and end date.
class _GroupProgressCard extends StatelessWidget {
  final _GroupGoal goal;
  const _GroupProgressCard({super.key, required this.goal});

  @override
  Widget build(BuildContext context) {
    return _GrowyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, size: 18, color: _GrowyColors.primary),
              const SizedBox(width: 6),
              Text('Group goal', style: _GrowyText.caption),
              const Spacer(),
              Text(
                '${(goal.progress * 100).round()}%',
                style: _GrowyText.caption.copyWith(
                  color: _GrowyColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: _GrowySpacing.sm),
          Text(goal.title, style: _GrowyText.cardTitle),
          const SizedBox(height: _GrowySpacing.md),
          _ProgressBarRow(
            value: goal.progress,
            leftText:
                '${_formatNumber(goal.current)} / ${_formatNumber(goal.target)} XP',
            rightText: 'Ends ${_formatShortDate(goal.endDate)}',
          ),
        ],
      ),
    );
  }
}

/// One leaderboard row. Ranks 1–3 get a medal; the user's own row is highlighted.
class _LeaderboardItem extends StatelessWidget {
  final _LeaderboardEntry entry;
  const _LeaderboardItem({super.key, required this.entry});

  Color? get _medalColor {
    switch (entry.rank) {
      case 1:
        return _GrowyColors.gold;
      case 2:
        return _GrowyColors.silver;
      case 3:
        return _GrowyColors.bronze;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final medal = _medalColor;
    return Container(
      margin: const EdgeInsets.only(bottom: _GrowySpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: _GrowySpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: entry.isMe ? _GrowyColors.primaryTint : _GrowyColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.isMe ? _GrowyColors.primary : _GrowyColors.cardBorder,
          width: entry.isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: medal != null
                ? Icon(Icons.emoji_events_rounded, color: medal, size: 24)
                : Text(
                    '#${entry.rank}',
                    style: _GrowyText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _GrowyColors.textMain,
                    ),
                  ),
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor:
                entry.isMe ? _GrowyColors.primary : _GrowyColors.secondaryTint,
            child: Text(
              _initialsOf(entry.displayName),
              style: _GrowyText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: entry.isMe ? Colors.white : _GrowyColors.textMain,
              ),
            ),
          ),
          const SizedBox(width: _GrowySpacing.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: entry.displayName,
                style: _GrowyText.cardTitle,
                children: [
                  if (entry.isMe)
                    TextSpan(text: '  (You)', style: _GrowyText.caption),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${_formatNumber(entry.points)} XP',
            style: _GrowyText.cardTitle.copyWith(color: _GrowyColors.primary),
          ),
        ],
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

/// Caption label over a big Fraunces number.
class _StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  Color get _valueColor => valueColor ?? _GrowyColors.textMain;
  final CrossAxisAlignment alignment;

  const _StatBlock({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.alignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _GrowyText.caption),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: _GrowyText.bigNumber.copyWith(color: _valueColor),
          ),
        ),
      ],
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

/// Rounded progress bar with captions on the left and right.
class _ProgressBarRow extends StatelessWidget {
  final double value;
  final String? leftText;
  final String? rightText;

  const _ProgressBarRow({
    super.key,
    required this.value,
    this.leftText,
    this.rightText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: _GrowyColors.primaryTint,
            color: _GrowyColors.primary,
          ),
        ),
        if (leftText != null || rightText != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (leftText != null)
                Expanded(child: Text(leftText!, style: _GrowyText.caption)),
              if (rightText != null) Text(rightText!, style: _GrowyText.caption),
            ],
          ),
        ],
      ],
    );
  }
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
            Text(detail!, textAlign: TextAlign.center, style: _GrowyText.caption),
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

enum _GrowyButtonStyle { primary, secondary }

/// Full-width 54px Growy button.
/// Primary: green fill + soft shadow. Secondary: white with green border.
/// Pass `onPressed: null` to disable it.
class _GrowyButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final _GrowyButtonStyle style;
  final IconData? icon;
  final bool isLoading;
  final double height;

  const _GrowyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = _GrowyButtonStyle.primary,
    this.icon,
    this.isLoading = false,
    this.height = 54,
  });

  const _GrowyButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.height = 54,
  }) : style = _GrowyButtonStyle.secondary;

  @override
  Widget build(BuildContext context) {
    final isPrimary = style == _GrowyButtonStyle.primary;
    final enabled = onPressed != null && !isLoading;
    final foreground = isPrimary ? Colors.white : _GrowyColors.primary;
    final radius = BorderRadius.circular(_GrowyRadius.button);

    return Opacity(
      opacity: enabled || isLoading ? 1 : 0.5,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isPrimary ? _GrowyColors.primary : _GrowyColors.background,
          borderRadius: radius,
          border: isPrimary
              ? null
              : Border.all(color: _GrowyColors.primary, width: 1.5),
          boxShadow: isPrimary && enabled
              ? [
                  BoxShadow(
                    color: _GrowyColors.buttonShadow,
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled ? onPressed : null,
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: foreground,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: foreground, size: 20),
                          const SizedBox(width: _GrowySpacing.sm),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: _GrowyText.button.copyWith(color: foreground),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 36px compact button for "Join" and similar inline actions.
/// The tap area is padded to 48px for accessibility.
class _GrowySmallButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final _GrowyButtonStyle style;
  final bool isLoading;

  const _GrowySmallButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = _GrowyButtonStyle.primary,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPrimary = style == _GrowyButtonStyle.primary;
    final enabled = onPressed != null && !isLoading;
    final foreground = isPrimary ? Colors.white : _GrowyColors.primary;
    final radius = BorderRadius.circular(12);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: isPrimary ? _GrowyColors.primary : _GrowyColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: isPrimary
              ? BorderSide.none
              : BorderSide(color: _GrowyColors.primary, width: 1.5),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                widthFactor: 1,
                child: isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Text(
                        label,
                        style: _GrowyText.button
                            .copyWith(fontSize: 14, color: foreground),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A shared goal the whole group works toward.
class _GroupGoal {
  final String title;
  final int current;
  final int target;
  final DateTime endDate;

  const _GroupGoal({
    required this.title,
    required this.current,
    required this.target,
    required this.endDate,
  });

  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0.0, 1.0).toDouble();

  _GroupGoal copyWith({int? current}) => _GroupGoal(
        title: title,
        current: current ?? this.current,
        target: target,
        endDate: endDate,
      );

  factory _GroupGoal.fromJson(Map<String, dynamic> json) => _GroupGoal(
        title: json['title'] as String,
        current: (json['current'] ?? 0) as int,
        target: (json['target'] ?? 0) as int,
        endDate: DateTime.parse(json['end_date'] as String),
      );
}

/// A group (room). Used for both "My Groups" and "Discover Groups".
class _Group {
  final String id;
  final String name;
  final String description;

  /// "Study" or "Health".
  final String category;

  /// Picks the Material icon: "run", "book", "water", "mind".
  final String iconKey;

  /// Code friends type in "Join with a code". Shown on the group page.
  final String? inviteCode;
  final int memberCount;
  final bool isJoined;

  /// Only meaningful when [isJoined] is true.
  final int userRank;
  final int userPoints;

  final _GroupGoal? goal;

  const _Group({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.iconKey,
    this.inviteCode,
    required this.memberCount,
    required this.isJoined,
    this.userRank = 0,
    this.userPoints = 0,
    this.goal,
  });

  _Group copyWith({
    int? memberCount,
    bool? isJoined,
    int? userRank,
    int? userPoints,
    _GroupGoal? goal,
  }) {
    return _Group(
      id: id,
      name: name,
      description: description,
      category: category,
      iconKey: iconKey,
      inviteCode: inviteCode,
      memberCount: memberCount ?? this.memberCount,
      isJoined: isJoined ?? this.isJoined,
      userRank: userRank ?? this.userRank,
      userPoints: userPoints ?? this.userPoints,
      goal: goal ?? this.goal,
    );
  }

  factory _Group.fromJson(Map<String, dynamic> json) => _Group(
        id: json['id'].toString(),
        name: json['room_name'] as String? ?? json['name'] as String,
        description: (json['description'] ?? '') as String,
        category: (json['category'] ?? '') as String,
        iconKey: (json['icon_key'] ?? '') as String,
        inviteCode: json['room_code'] as String?,
        memberCount: (json['member_count'] ?? 0) as int,
        isJoined: (json['is_joined'] ?? false) as bool,
        userRank: (json['user_rank'] ?? 0) as int,
        userPoints: (json['user_points'] ?? 0) as int,
        goal: json['goal'] == null
            ? null
            : _GroupGoal.fromJson(json['goal'] as Map<String, dynamic>),
      );
}

/// One row of a group's leaderboard.
class _LeaderboardEntry {
  final int rank;
  final String userId;
  final String displayName;
  final int points;

  /// True for the signed-in user's own row (highlighted).
  final bool isMe;

  const _LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.points,
    required this.isMe,
  });

  factory _LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      _LeaderboardEntry(
        rank: json['rank'] as int,
        userId: json['user_id'].toString(),
        displayName: (json['display_name'] ?? json['username'] ?? '') as String,
        points: (json['points'] ?? 0) as int,
        isMe: (json['is_me'] ?? false) as bool,
      );
}

// ───────────────────────────────────────────────────────────── sample data
// Sample groups so the page works before the backend is ready.
// TODO(backend): replace each method with its endpoint (named in the comment).

class _GroupCodeNotFoundException implements Exception {
  const _GroupCodeNotFoundException();
}

class _GroupsData {
  static const Duration _latency = Duration(milliseconds: 300);

  final List<_Group> _mine = [];
  final List<_Group> _discover = [];
  final Map<String, _Group> _dismissed = {};
  final Map<String, int> _dismissedIndex = {};

  _GroupsData() {
    final now = DateTime.now();
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    _mine.addAll([
      _Group(
        id: 'g1',
        name: '10K Steps Squad',
        description:
            'Walk, run or hike your way to 10,000 steps a day with friends who keep you honest.',
        category: 'Health',
        iconKey: 'run',
        inviteCode: 'STEPS10',
        memberCount: 24,
        isJoined: true,
        userRank: 2,
        userPoints: 850,
        goal: _GroupGoal(
          title: 'Earn 10,000 XP together this month',
          current: 6800,
          target: 10000,
          endDate: monthEnd,
        ),
      ),
      _Group(
        id: 'g2',
        name: 'Study Together',
        description:
            'Daily reading and focused study sessions. Snap your desk, earn XP, climb the board.',
        category: 'Study',
        iconKey: 'book',
        inviteCode: 'STUDY24',
        memberCount: 18,
        isJoined: true,
        userRank: 5,
        userPoints: 320,
        goal: _GroupGoal(
          title: 'Earn 9,000 XP as a group',
          current: 4200,
          target: 9000,
          endDate: monthEnd,
        ),
      ),
      const _Group(
        id: 'g3',
        name: 'Hydration Heroes',
        description: 'Eight glasses a day, every day. Small habit, big difference.',
        category: 'Health',
        iconKey: 'water',
        inviteCode: 'WATER8',
        memberCount: 9,
        isJoined: true,
        userRank: 1,
        userPoints: 410,
      ),
    ]);
    _discover.addAll(const [
      _Group(
        id: 'g4',
        name: 'Morning Runners',
        description: 'Early runs before the heat. Share your route, keep your streak.',
        category: 'Health',
        iconKey: 'run',
        inviteCode: 'GROWY1',
        memberCount: 1200,
        isJoined: false,
      ),
      _Group(
        id: 'g5',
        name: 'Exam Prep Circle',
        description:
            'Focused study sessions for midterms and finals. Quiet, steady, consistent.',
        category: 'Study',
        iconKey: 'book',
        inviteCode: 'EXAM50',
        memberCount: 850,
        isJoined: false,
      ),
      _Group(
        id: 'g6',
        name: 'Mindful Mornings',
        description:
            'A calm start: stretch, breathe and eat a healthy breakfast before the day begins.',
        category: 'Health',
        iconKey: 'mind',
        inviteCode: 'CALM30',
        memberCount: 430,
        isJoined: false,
      ),
      _Group(
        id: 'g7',
        name: 'Book Club Readers',
        description: 'Twenty pages a day adds up to a book a month.',
        category: 'Study',
        iconKey: 'book',
        inviteCode: 'READ20',
        memberCount: 610,
        isJoined: false,
      ),
    ]);
  }

  /// GET /groups/mine
  Future<List<_Group>> getMyGroups() async {
    await Future.delayed(_latency);
    return List.of(_mine);
  }

  /// GET /groups/discover
  Future<List<_Group>> getDiscoverGroups() async {
    await Future.delayed(_latency);
    return List.of(_discover);
  }

  /// POST /groups/{id}/join
  Future<_Group> joinGroup(String groupId) async {
    await Future.delayed(_latency);
    final index = _discover.indexWhere((g) => g.id == groupId);
    if (index == -1) throw StateError('Group $groupId is not joinable');
    final g = _discover.removeAt(index);
    final joined = g.copyWith(
      isJoined: true,
      memberCount: g.memberCount + 1,
      userRank: g.memberCount + 1,
      userPoints: 0,
    );
    _mine.add(joined);
    return joined;
  }

  /// POST /groups/join {room_code}
  Future<_Group> joinGroupByCode(String code) async {
    await Future.delayed(_latency);
    final clean = code.trim().toUpperCase();
    final match = _discover.where((g) => g.inviteCode == clean);
    if (match.isEmpty) throw const _GroupCodeNotFoundException();
    return joinGroup(match.first.id);
  }

  /// POST /groups/{id}/dismiss
  Future<void> dismissGroup(String groupId) async {
    final index = _discover.indexWhere((g) => g.id == groupId);
    if (index == -1) return;
    _dismissedIndex[groupId] = index;
    _dismissed[groupId] = _discover.removeAt(index);
  }

  Future<void> undoDismissGroup(String groupId) async {
    final g = _dismissed.remove(groupId);
    if (g == null) return;
    final index =
        (_dismissedIndex.remove(groupId) ?? 0).clamp(0, _discover.length).toInt();
    _discover.insert(index, g);
  }

  /// DELETE /groups/{id}/membership
  Future<void> leaveGroup(String groupId) async {
    await Future.delayed(_latency);
    final index = _mine.indexWhere((g) => g.id == groupId);
    if (index == -1) return;
    final g = _mine.removeAt(index);
    _discover.add(g.copyWith(
      isJoined: false,
      memberCount: g.memberCount - 1,
      userRank: 0,
      userPoints: 0,
    ));
  }

  /// GET /groups/{id}/leaderboard
  Future<List<_LeaderboardEntry>> getLeaderboard(String groupId) async {
    await Future.delayed(_latency);
    final group = _mine.firstWhere(
      (g) => g.id == groupId,
      orElse: () => throw StateError('Not a member of $groupId'),
    );
    const names = [
      'Sara', 'Lama', 'Ahmed', 'Noura', 'Omar', 'Reem', 'Faisal', 'Huda',
      'Khalid', 'Maha', 'Yousef', 'Dana', 'Ali', 'Joud', 'Hassan', 'Raghad',
      'Turki', 'Shahad', 'Majed', 'Ghada', 'Nawaf', 'Rana', 'Saad', 'Lulu',
      'Bader', 'Haya', 'Fahad', 'Asma', 'Waleed', 'Nouf', 'Ziyad', 'Afnan',
      'Mishari', 'Razan', 'Talal', 'Abeer', 'Sultan', 'Wejdan', 'Nasser',
    ];
    const step = 60;
    final others = (group.memberCount - 1).clamp(0, 39).toInt();
    _LeaderboardEntry me(int rank) => _LeaderboardEntry(
          rank: rank,
          userId: 'me',
          displayName: 'You',
          points: group.userPoints,
          isMe: true,
        );
    final entries = <_LeaderboardEntry>[];
    var rank = 1;
    var meAdded = false;
    for (var i = 0; i < others; i++) {
      if (!meAdded && rank == group.userRank) {
        entries.add(me(rank++));
        meAdded = true;
      }
      final points = group.userPoints + (group.userRank - rank) * step;
      entries.add(_LeaderboardEntry(
        rank: rank,
        userId: 'member_${groupId}_$i',
        displayName: names[i % names.length],
        points: points < 0 ? 0 : points,
        isMe: false,
      ));
      rank++;
    }
    if (!meAdded) entries.add(me(group.userRank));
    return entries;
  }
}

final _GroupsData _groupsData = _GroupsData();

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

const List<String> _kMonthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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

/// 850 → "850", 1200 → "1.2K", 15000 → "15K"
String _formatCompact(int value) {
  if (value < 1000) return value.toString();
  final thousands = value / 1000;
  final text = thousands >= 10
      ? thousands.round().toString()
      : thousands.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  return '${text}K';
}

/// "Oct 8"
String _formatShortDate(DateTime d) => '${_kMonthShort[d.month - 1]} ${d.day}';

/// "Sara Ahmed" → "SA", "Zad" → "Z"
String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}