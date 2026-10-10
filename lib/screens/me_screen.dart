// Growy — Me page (profile, stats, personal info, appearance, Edit Profile, log out).
// Self-contained: every helper below is private to this file.
// Open it with: MeScreen()
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/motion/motion.dart';
import '../models/character_config.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'avatar_customizer_screen.dart';
import 'login_screen.dart';

/// Me tab: identity, progress, personal info and account options.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  _UserProfile? _user;

  /// The avatar look. TODO: load and save it the same way your Home screen does.
  CharacterConfig _avatarConfig = CharacterConfig.defaultConfig();
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await _meData.getMe();
      if (mounted) {
        setState(() {
          _user = user;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _openCustomizer() async {
    final result = await Navigator.of(context).push<CharacterConfig>(
      MaterialPageRoute(
        builder: (_) => AvatarCustomizerScreen(initialConfig: _avatarConfig),
      ),
    );
    if (result != null && mounted) setState(() => _avatarConfig = result);
  }

  Future<void> _openEditProfile(_UserProfile user) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _EditProfileScreen(user: user)),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated')));
    }
    _load(); // the photo can change on Edit Profile even without saving
  }

  Future<void> _changePhoto() async {
    final user = _user;
    if (user == null) return;
    final updated = await _pickProfilePhoto(context, user);
    if (updated != null && mounted) setState(() => _user = updated);
  }

  Future<void> _chooseAppearance() async {
    final mode = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: _GrowyColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_GrowyRadius.card),
        ),
      ),
      builder: (context) => _AppearanceSheet(current: themeController.value),
    );
    if (mode != null) await themeController.setMode(mode);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _GrowyColors.background,
        surfaceTintColor: _GrowyColors.background,
        title: Text('Log out?', style: _GrowyText.sectionTitle),
        content: Text(
          'You can log back in any time with your email and password.',
          style: _GrowyText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: _GrowyText.body.copyWith(
                color: _GrowyColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Log out',
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
    await _AccountService.signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
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
                      Expanded(
                        child: Text('Me', style: _GrowyText.screenTitle),
                      ),
                    ],
                  ),
                  const SizedBox(height: _GrowySpacing.lg),
                  if (user == null && _failed)
                    _LoadError(onRetry: _load)
                  else if (user == null)
                    Padding(
                      padding: EdgeInsets.all(_GrowySpacing.xxl),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _GrowyColors.primary,
                        ),
                      ),
                    )
                  else ...[
                    GrowyFadeIn(
                      child: _ProfileHeader(
                        user: user,
                        onPhotoTap: _changePhoto,
                      ),
                    ),
                    const SizedBox(height: _GrowySpacing.xl),
                    const _SectionHeader(title: 'Your stats'),
                    _StatsGrid(user: user),
                    const SizedBox(height: _GrowySpacing.xl),
                    const _SectionHeader(title: 'Personal information'),
                    _GrowyCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _GrowySpacing.lg,
                        vertical: _GrowySpacing.xs,
                      ),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.alternate_email_rounded,
                            label: 'Username',
                            value: '@${user.username}',
                          ),
                          Divider(height: 1, color: _GrowyColors.cardBorder),
                          _InfoRow(
                            icon: Icons.mail_outline_rounded,
                            label: 'Email',
                            value: user.email,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: _GrowySpacing.lg),
                    GrowyPressEffect(
                      child: _GrowyButton.secondary(
                        label: 'Edit Profile',
                        icon: Icons.edit_outlined,
                        onPressed: () => _openEditProfile(user),
                      ),
                    ),
                    const SizedBox(height: _GrowySpacing.xl),
                    const _SectionHeader(title: 'Account'),
                    _GrowyCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _GrowySpacing.lg,
                        vertical: _GrowySpacing.xs,
                      ),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.face_retouching_natural_outlined,
                            label: 'Customize avatar',
                            showChevron: true,
                            onTap: _openCustomizer,
                          ),
                          Divider(height: 1, color: _GrowyColors.cardBorder),
                          ValueListenableBuilder<ThemeMode>(
                            valueListenable: themeController,
                            builder: (context, mode, _) => _InfoRow(
                              icon: GrowyPalette.isDark
                                  ? Icons.dark_mode_outlined
                                  : Icons.light_mode_outlined,
                              label: 'Appearance',
                              value: _AppearanceSheet.labelFor(mode),
                              showChevron: true,
                              onTap: _chooseAppearance,
                            ),
                          ),
                          Divider(height: 1, color: _GrowyColors.cardBorder),
                          _InfoRow(
                            icon: Icons.logout_rounded,
                            label: 'Log out',
                            iconColor: _GrowyColors.error,
                            labelColor: _GrowyColors.error,
                            onTap: _confirmLogout,
                          ),
                        ],
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

class _ProfileHeader extends StatelessWidget {
  final _UserProfile user;
  final VoidCallback onPhotoTap;

  const _ProfileHeader({required this.user, required this.onPhotoTap});

  @override
  Widget build(BuildContext context) {
    return _GrowyCard(
      padding: const EdgeInsets.all(_GrowySpacing.xl),
      child: Column(
        children: [
          _ProfilePhoto(user: user, showEditBadge: true, onTap: onPhotoTap),
          const SizedBox(height: _GrowySpacing.md),
          Text(
            user.displayName,
            textAlign: TextAlign.center,
            style: _GrowyText.bigNumber,
          ),
          Text('@${user.username}', style: _GrowyText.caption),
          const SizedBox(height: _GrowySpacing.lg),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: _GrowySpacing.sm,
            runSpacing: _GrowySpacing.sm,
            children: [
              _GrowyPill(
                text: user.isMaxLevel ? 'Max level' : 'Level ${user.level}',
                icon: Icons.star_rounded,
              ),
              GrowyCountUp(
                value: user.totalXp,
                builder: (xp) => _GrowyPill(
                  text: '${_formatNumber(xp)} XP',
                  icon: Icons.bolt_rounded,
                ),
              ),
              _GrowyPill(
                text: '${user.currentStreak}-day streak',
                icon: Icons.local_fire_department_rounded,
                background: _GrowyColors.secondaryTint,
                foreground: _GrowyColors.secondaryDeep,
              ),
            ],
          ),
          if (!user.isMaxLevel && user.xpForNextLevel != null) ...[
            const SizedBox(height: _GrowySpacing.lg),
            _ProgressBarRow(
              value: user.xpIntoLevel / user.xpForNextLevel!,
              leftText:
                  '${_formatNumber(user.xpIntoLevel)} / ${_formatNumber(user.xpForNextLevel!)} XP',
              rightText: 'Level ${user.level + 1}',
            ),
          ],
        ],
      ),
    );
  }
}

/// Two rows of two tiles. Rows (not a GridView) so tile height never breaks on small phones.
class _StatsGrid extends StatelessWidget {
  final _UserProfile user;
  const _StatsGrid({required this.user});

  @override
  Widget build(BuildContext context) {
    Widget tile(int index, Widget child) => Expanded(
      child: GrowySlideIn(index: index, child: child),
    );
    return Column(
      children: [
        Row(
          children: [
            tile(
              0,
              GrowyCountUp(
                value: user.habitsCompleted,
                builder: (v) => _StatTile(
                  icon: Icons.check_circle_outline_rounded,
                  value: _formatNumber(v),
                  label: 'Habits completed',
                ),
              ),
            ),
            const SizedBox(width: _GrowySpacing.md),
            tile(
              1,
              GrowyCountUp(
                value: user.longestStreak,
                builder: (v) => _StatTile(
                  icon: Icons.local_fire_department_rounded,
                  iconColor: _GrowyColors.secondaryDeep,
                  iconBackground: _GrowyColors.secondaryTint,
                  value: '$v days',
                  label: 'Longest streak',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: _GrowySpacing.md),
        Row(
          children: [
            tile(
              2,
              GrowyCountUp(
                value: user.groupsJoined,
                builder: (v) => _StatTile(
                  icon: Icons.groups_outlined,
                  value: _formatNumber(v),
                  label: 'Groups joined',
                ),
              ),
            ),
            const SizedBox(width: _GrowySpacing.md),
            tile(
              3,
              GrowyCountUp(
                value: user.photosVerified,
                builder: (v) => _StatTile(
                  icon: Icons.photo_camera_outlined,
                  iconColor: _GrowyColors.secondaryDeep,
                  iconBackground: _GrowyColors.secondaryTint,
                  value: _formatNumber(v),
                  label: 'Photos verified',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Edit the profile photo, display name, username and email.
/// The photo comes from the phone's album (the avatar is customized
/// separately). Password changes go through a Firebase reset email.
/// Pops with `true` after a successful save.
class _EditProfileScreen extends StatefulWidget {
  final _UserProfile user;

  const _EditProfileScreen({super.key, required this.user});

  @override
  State<_EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<_EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _email;

  /// The photo shown at the top. Photo changes save immediately.
  late _UserProfile _photoUser = widget.user;

  bool _saving = false;
  String? _usernameError;

  static final RegExp _usernamePattern = RegExp(r'^[a-zA-Z0-9_]{3,20}$');
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _displayName = TextEditingController(text: u.displayName);
    _username = TextEditingController(text: u.username);
    _email = TextEditingController(text: u.email);
    for (final c in [_displayName, _username, _email]) {
      c.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [_displayName, _username, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _emailChanged =>
      _email.text.trim().toLowerCase() != widget.user.email.toLowerCase();

  bool get _isDirty =>
      _displayName.text.trim() != widget.user.displayName ||
      _username.text.trim().toLowerCase() != widget.user.username ||
      _emailChanged;

  // ----------------------------------------------------------- actions

  Future<void> _changePhoto() async {
    final updated = await _pickProfilePhoto(context, _photoUser);
    if (updated != null && mounted) setState(() => _photoUser = updated);
  }

  Future<void> _save() async {
    setState(() => _usernameError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      if (_emailChanged) {
        final password = await _askCurrentPassword();
        if (password == null || password.isEmpty)
          return; // finally resets _saving
        await _AccountService.changeEmail(
          newEmail: _email.text.trim(),
          currentPassword: password,
        );
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Check your new inbox to confirm the email change.'),
          ),
        );
      }

      await _meData.updateMe(
        displayName: _displayName.text.trim(),
        username: _username.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on _UsernameTakenException {
      if (!mounted) return;
      setState(() => _usernameError = 'That username is taken');
      _formKey.currentState?.validate();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_AccountService.messageFor(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askCurrentPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _GrowyColors.background,
        surfaceTintColor: _GrowyColors.background,
        title: Text('Confirm it\'s you', style: _GrowyText.sectionTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your current password to change your email.',
              style: _GrowyText.body,
            ),
            const SizedBox(height: _GrowySpacing.md),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              style: _GrowyText.body,
              decoration: _inputDecoration(hint: 'Current password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: _GrowyText.body.copyWith(
                color: _GrowyColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(
              'Continue',
              style: _GrowyText.body.copyWith(
                color: _GrowyColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _changePassword() async {
    final email = widget.user.email;
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _GrowyColors.background,
        surfaceTintColor: _GrowyColors.background,
        title: Text('Change password', style: _GrowyText.sectionTitle),
        content: Text(
          "We'll email a link to $email so you can set a new password.",
          style: _GrowyText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: _GrowyText.body.copyWith(
                color: _GrowyColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Send link',
              style: _GrowyText.body.copyWith(
                color: _GrowyColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (send != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _AccountService.sendPasswordReset(email);
      messenger.showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(_AccountService.messageFor(e))),
      );
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _GrowyColors.background,
        surfaceTintColor: _GrowyColors.background,
        title: Text('Discard changes?', style: _GrowyText.sectionTitle),
        content: Text(
          'Your edits to your profile will be lost.',
          style: _GrowyText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Keep editing',
              style: _GrowyText.body.copyWith(
                color: _GrowyColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Discard',
              style: _GrowyText.body.copyWith(
                color: _GrowyColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop(false);
      },
      child: Scaffold(
        backgroundColor: _GrowyColors.background,
        appBar: AppBar(
          backgroundColor: _GrowyColors.background,
          surfaceTintColor: _GrowyColors.background,
          foregroundColor: _GrowyColors.textMain,
          elevation: 0,
          title: Text('Edit profile', style: _GrowyText.sectionTitle),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              _GrowySpacing.screen,
              _GrowySpacing.sm,
              _GrowySpacing.screen,
              _GrowySpacing.xxl,
            ),
            children: [
              Center(
                child: _ProfilePhoto(
                  user: _photoUser,
                  size: 80,
                  onTap: _changePhoto,
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: _changePhoto,
                  style: TextButton.styleFrom(
                    foregroundColor: _GrowyColors.primary,
                  ),
                  child: Text(
                    _photoUser.hasPhoto ? 'Change photo' : 'Add photo',
                    style: _GrowyText.body.copyWith(
                      color: _GrowyColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: _GrowySpacing.lg),
              _LabeledField(
                label: 'Display name',
                controller: _displayName,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.length < 2) return 'Enter at least 2 characters';
                  if (text.length > 30) return 'Keep it under 30 characters';
                  return null;
                },
              ),
              _LabeledField(
                label: 'Username',
                controller: _username,
                prefixText: '@',
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (_usernameError != null) return _usernameError;
                  final text = v?.trim() ?? '';
                  if (!_usernamePattern.hasMatch(text)) {
                    return '3–20 letters, numbers or underscores';
                  }
                  return null;
                },
              ),
              _LabeledField(
                label: 'Email',
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                helperText: _emailChanged
                    ? "You'll confirm this with your password and a link sent to the new address."
                    : null,
                validator: (v) => _emailPattern.hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Enter a valid email',
              ),
              const SizedBox(height: _GrowySpacing.sm),
              _GrowyCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: _GrowySpacing.lg,
                  vertical: _GrowySpacing.xs,
                ),
                child: _InfoRow(
                  icon: Icons.lock_outline_rounded,
                  label: 'Change password',
                  showChevron: true,
                  onTap: _changePassword,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              _GrowySpacing.screen,
              _GrowySpacing.md,
              _GrowySpacing.screen,
              _GrowySpacing.lg + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: _GrowyButton(
              label: 'Save Changes',
              isLoading: _saving,
              onPressed: _isDirty ? _save : null,
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration({
  String? hint,
  String? prefixText,
  String? helperText,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_GrowyRadius.input),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: _GrowyText.body.copyWith(color: _GrowyColors.textSecondary),
    prefixText: prefixText,
    prefixStyle: _GrowyText.body.copyWith(color: _GrowyColors.textSecondary),
    helperText: helperText,
    helperMaxLines: 2,
    helperStyle: _GrowyText.caption,
    errorStyle: _GrowyText.caption.copyWith(color: _GrowyColors.error),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: _GrowySpacing.lg,
      vertical: 16,
    ),
    enabledBorder: border(_GrowyColors.inputBorder),
    focusedBorder: border(_GrowyColors.primary, 1.5),
    errorBorder: border(_GrowyColors.error),
    focusedErrorBorder: border(_GrowyColors.error, 1.5),
  );
}

/// Growy input: label above the field, 12px radius, green border on focus.
class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? prefixText;
  final String? helperText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final FormFieldValidator<String>? validator;

  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.prefixText,
    this.helperText,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _GrowySpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: _GrowyText.caption.copyWith(
              color: _GrowyColors.textMain,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            textCapitalization: textCapitalization,
            validator: validator,
            style: _GrowyText.body,
            cursorColor: _GrowyColors.primary,
            decoration: _inputDecoration(
              hint: hint,
              prefixText: prefixText,
              helperText: helperText,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------- profile photo

/// Lets the user pick a profile photo from their album (or remove it),
/// uploads it, and returns the updated profile. Returns null if cancelled.
Future<_UserProfile?> _pickProfilePhoto(
  BuildContext context,
  _UserProfile user,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: _GrowyColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(_GrowyRadius.card),
      ),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _GrowySpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: _GrowyColors.primary,
              ),
              title: Text('Choose from album', style: _GrowyText.body),
              onTap: () => Navigator.of(context).pop('album'),
            ),
            if (user.hasPhoto)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: _GrowyColors.error,
                ),
                title: Text(
                  'Remove photo',
                  style: _GrowyText.body.copyWith(color: _GrowyColors.error),
                ),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null) return null;

  try {
    if (choice == 'remove') {
      final updated = await _meData.removePhoto();
      messenger.showSnackBar(const SnackBar(content: Text('Photo removed')));
      return updated;
    }
    // Gallery only. Resized so uploads stay small and fast.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return null; // user closed the album
    final bytes = await picked.readAsBytes();
    final updated = await _meData.uploadPhoto(picked, bytes);
    messenger.showSnackBar(
      const SnackBar(content: Text('Profile photo updated')),
    );
    return updated;
  } catch (e) {
    debugPrint('Profile photo failed: $e');
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't update your photo. Check that Growy can access your photos.",
        ),
      ),
    );
    return null;
  }
}

/// Round profile photo from the user's album. Shows their initials until a
/// photo is added. The avatar character is separate (Customize avatar).
class _ProfilePhoto extends StatelessWidget {
  final _UserProfile user;
  final double size;
  final bool showEditBadge;
  final VoidCallback? onTap;

  const _ProfilePhoto({
    required this.user,
    this.size = 96,
    this.showEditBadge = false,
    this.onTap,
  });

  Widget _initials() => Center(
    child: Text(
      _initialsOf(user.displayName),
      style: _GrowyText.bigNumber.copyWith(
        fontSize: size * 0.34,
        color: _GrowyColors.primary,
      ),
    ),
  );

  Widget _image() {
    final bytes = user.photoBytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
    }
    final url = user.photoUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _initials(),
      );
    }
    return _initials();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: user.hasPhoto
          ? 'Profile photo. Tap to change'
          : 'Add a profile photo',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: _GrowyColors.primaryTint,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                // Cross-fades smoothly when the photo changes.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: KeyedSubtree(
                    key: ValueKey(user.photoKey),
                    child: SizedBox.expand(child: _image()),
                  ),
                ),
              ),
              if (showEditBadge)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: size * 0.3,
                    height: size * 0.3,
                    decoration: BoxDecoration(
                      color: _GrowyColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _GrowyColors.background,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
                      size: size * 0.15,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet: System / Light / Dark. Pops with the chosen [ThemeMode].
class _AppearanceSheet extends StatelessWidget {
  final ThemeMode current;
  const _AppearanceSheet({required this.current});

  static String labelFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'Same as phone';
    }
  }

  static IconData _iconFor(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _GrowySpacing.sm,
          _GrowySpacing.xl,
          _GrowySpacing.sm,
          _GrowySpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _GrowySpacing.lg),
              child: Text('Appearance', style: _GrowyText.sectionTitle),
            ),
            const SizedBox(height: _GrowySpacing.sm),
            for (final mode in const [
              ThemeMode.system,
              ThemeMode.light,
              ThemeMode.dark,
            ])
              ListTile(
                leading: Icon(_iconFor(mode), color: _GrowyColors.primary),
                title: Text(labelFor(mode), style: _GrowyText.body),
                trailing: mode == current
                    ? Icon(Icons.check_rounded, color: _GrowyColors.primary)
                    : null,
                selected: mode == current,
                onTap: () => Navigator.of(context).pop(mode),
              ),
          ],
        ),
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
              if (rightText != null)
                Text(rightText!, style: _GrowyText.caption),
            ],
          ),
        ],
      ],
    );
  }
}

/// Icon + label + value row, optionally tappable with a chevron.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final Color? labelColor;
  Color get _labelColor => labelColor ?? _GrowyColors.textMain;
  final Color? iconColor;
  Color get _iconColor => iconColor ?? _GrowyColors.primary;
  final VoidCallback? onTap;
  final bool showChevron;

  const _InfoRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.labelColor,
    this.iconColor,
    this.onTap,
    this.showChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(_GrowyRadius.input),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: _GrowySpacing.sm),
          child: Row(
            children: [
              Icon(icon, size: 22, color: _iconColor),
              const SizedBox(width: _GrowySpacing.md),
              Expanded(
                child: value == null
                    ? Text(
                        label,
                        style: _GrowyText.body.copyWith(color: _labelColor),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: _GrowyText.caption),
                          const SizedBox(height: 2),
                          Text(
                            value!,
                            style: _GrowyText.body.copyWith(
                              color: valueColor ?? _GrowyColors.textMain,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
              ),
              if (showChevron)
                Icon(
                  Icons.chevron_right_rounded,
                  color: _GrowyColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
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
                            style: _GrowyText.button.copyWith(
                              color: foreground,
                            ),
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

/// Everything the Me page and Edit Profile need about the signed-in user.
/// The backend computes every number (XP, level, streaks); the app only shows them.
class _UserProfile {
  final String id;
  final String displayName;
  final String username;
  final String email;

  /// Profile photo from the user's album, stored by the backend.
  final String? photoUrl;

  /// The just-picked photo, shown right away while/after it uploads.
  final Uint8List? photoBytes;

  final int totalXp;
  final int level;

  /// XP earned inside the current level (e.g. 950 of the 1,500 needed).
  final int xpIntoLevel;

  /// XP needed to go from this level to the next. Null at max level.
  final int? xpForNextLevel;

  final int currentStreak;
  final int longestStreak;
  final int habitsCompleted;
  final int groupsJoined;
  final int photosVerified;

  const _UserProfile({
    required this.id,
    required this.displayName,
    required this.username,
    required this.email,
    this.photoUrl,
    this.photoBytes,
    required this.totalXp,
    required this.level,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
    required this.currentStreak,
    required this.longestStreak,
    required this.habitsCompleted,
    required this.groupsJoined,
    required this.photosVerified,
  });

  bool get isMaxLevel => xpForNextLevel == null;

  bool get hasPhoto =>
      photoBytes != null || (photoUrl != null && photoUrl!.isNotEmpty);

  /// Changes whenever the photo changes (drives the cross-fade).
  Object get photoKey => photoBytes ?? photoUrl ?? 'none';

  _UserProfile copyWith({
    String? displayName,
    String? username,
    String? email,
    String? photoUrl,
    Uint8List? photoBytes,
    bool clearPhoto = false,
    int? totalXp,
    int? level,
    int? xpIntoLevel,
    int? xpForNextLevel,
    bool clearXpForNextLevel = false,
    int? currentStreak,
    int? longestStreak,
    int? habitsCompleted,
    int? groupsJoined,
    int? photosVerified,
  }) {
    return _UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      email: email ?? this.email,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      photoBytes: clearPhoto ? null : (photoBytes ?? this.photoBytes),
      totalXp: totalXp ?? this.totalXp,
      level: level ?? this.level,
      xpIntoLevel: xpIntoLevel ?? this.xpIntoLevel,
      xpForNextLevel: clearXpForNextLevel
          ? null
          : (xpForNextLevel ?? this.xpForNextLevel),
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      habitsCompleted: habitsCompleted ?? this.habitsCompleted,
      groupsJoined: groupsJoined ?? this.groupsJoined,
      photosVerified: photosVerified ?? this.photosVerified,
    );
  }

  /// Field names follow the backend's snake_case. Adjust if Student A names them differently.
  factory _UserProfile.fromJson(Map<String, dynamic> json) {
    return _UserProfile(
      id: json['id'].toString(),
      displayName: (json['display_name'] ?? json['username'] ?? '') as String,
      username: (json['username'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      photoUrl: json['profile_image_url'] as String?,
      totalXp: (json['total_points'] ?? 0) as int,
      level: (json['current_level'] ?? 0) as int,
      xpIntoLevel: (json['xp_into_level'] ?? 0) as int,
      xpForNextLevel: json['xp_for_next_level'] as int?,
      currentStreak: (json['streak_days'] ?? 0) as int,
      longestStreak: (json['longest_streak'] ?? 0) as int,
      habitsCompleted: (json['habits_completed'] ?? 0) as int,
      groupsJoined: (json['groups_joined'] ?? 0) as int,
      photosVerified: (json['photos_verified'] ?? 0) as int,
    );
  }
}

/// Account actions that Firebase owns (password, email, sign-out).
/// The Growy backend never sees passwords.
class _AccountService {
  _AccountService._();

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static String? get currentEmail => _auth.currentUser?.email;

  /// Emails the user a link to set a new password.
  static Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  /// Firebase requires the current password before changing the email.
  /// The change only applies after the user clicks the link sent to [newEmail].
  static Future<void> changeEmail({
    required String newEmail,
    required String currentPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.verifyBeforeUpdateEmail(newEmail.trim());
  }

  static Future<void> signOut() => _auth.signOut();

  /// User-friendly message for a Firebase error.
  static String messageFor(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'wrong-password':
        case 'invalid-credential':
          return 'Your current password is incorrect.';
        case 'invalid-email':
          return 'That email address is not valid.';
        case 'email-already-in-use':
          return 'That email is already used by another account.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'network-request-failed':
          return 'No connection. Check your internet and try again.';
        case 'no-current-user':
          return 'Please log in again to change your email.';
        case 'requires-recent-login':
          return 'Please log out and log in again, then retry.';
      }
      return error.message ?? 'Something went wrong. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}

/// Growy's level thresholds (same as the backend):
/// 0–99 → 0, 100–499 → 1, 500–1499 → 2, 1500–2999 → 3, 3000+ → 4 (max).
///
/// The backend's `current_level` is the source of truth. These helpers only
/// work out the progress bar ("950 / 1,500 XP") and the sample data.
const List<int> _kLevelFloors = [0, 100, 500, 1500, 3000];

int get _kMaxLevel => _kLevelFloors.length - 1; // 4

int _levelForXp(int totalXp) {
  var level = 0;
  for (var i = 0; i < _kLevelFloors.length; i++) {
    if (totalXp >= _kLevelFloors[i]) level = i;
  }
  return level;
}

/// XP at which [level] starts.
int _levelFloorXp(int level) => _kLevelFloors[level.clamp(0, _kMaxLevel)];

/// XP needed to go from [level] to the next one, or null at max level.
int? _xpNeededAfterLevel(int level) {
  if (level >= _kMaxLevel) return null;
  return _kLevelFloors[level + 1] - _kLevelFloors[level];
}

// ───────────────────────────────────────────────────────────── sample data
// Sample profile so the page works before the backend is ready.
// TODO(backend): getMe → GET /users/me, updateMe → PUT /users/me (409 = username taken),
// uploadPhoto → POST /users/me/photo (multipart, returns profile_image_url),
// removePhoto → DELETE /users/me/photo.

class _UsernameTakenException implements Exception {
  const _UsernameTakenException();
}

class _MeData {
  static const Set<String> _taken = {'sara', 'admin', 'growy'};
  late _UserProfile _user;

  _MeData() {
    const totalXp = 2450;
    final level = _levelForXp(totalXp);
    final next = _xpNeededAfterLevel(level);
    _user = _UserProfile(
      id: 'me',
      displayName: 'Zad',
      username: 'zad',
      email: _AccountService.currentEmail ?? 'zad@growy.app',
      totalXp: totalXp,
      level: level,
      xpIntoLevel: totalXp - _levelFloorXp(level),
      xpForNextLevel: next,
      currentStreak: 15,
      longestStreak: 21,
      habitsCompleted: 86,
      groupsJoined: 3,
      photosVerified: 86,
    );
  }

  Future<_UserProfile> getMe() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _user;
  }

  Future<_UserProfile> updateMe({
    required String displayName,
    required String username,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final clean = username.trim().toLowerCase();
    if (clean != _user.username && _taken.contains(clean)) {
      throw const _UsernameTakenException();
    }
    _user = _user.copyWith(displayName: displayName.trim(), username: clean);
    return _user;
  }

  /// Sample version keeps the picked bytes in memory. With the backend,
  /// upload `photo` and use the returned `profile_image_url` (keep the
  /// bytes too, so the new photo shows instantly without a download).
  Future<_UserProfile> uploadPhoto(XFile photo, Uint8List bytes) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _user = _user.copyWith(photoBytes: bytes);
    return _user;
  }

  Future<_UserProfile> removePhoto() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _user = _user.copyWith(clearPhoto: true);
    return _user;
  }
}

final _MeData _meData = _MeData();

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

/// "Sara Ahmed" → "SA", "Zad" → "Z"
String _initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}
