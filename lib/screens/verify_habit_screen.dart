import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../services/verification_service.dart';
import '../models/habit_summary.dart';

import '../core/motion/motion.dart';
import '../theme/app_theme.dart';

Color get _secondaryText => GrowyPalette.textSecondary;
Color get _errorColor => GrowyPalette.error;

/// Opened from a habit card on Home. The user takes a live photo with the
/// camera (gallery uploads are not allowed),
/// the backend checks it with CLIP, and the result is shown here.
/// Home reloads its data when this screen closes.
class VerifyHabitScreen extends StatefulWidget {
  const VerifyHabitScreen({super.key, required this.habit});

  final HabitSummary habit;

  @override
  State<VerifyHabitScreen> createState() => _VerifyHabitScreenState();
}

class _VerifyHabitScreenState extends State<VerifyHabitScreen> {
  final ImagePicker _picker = ImagePicker();
  final VerificationService _service = VerificationService();

  XFile? _photo;
  Uint8List? _photoBytes; // for the preview (works on Android and web)
  bool _isSubmitting = false;
  VerificationResult? _result;
  String? _error;

  /// True once today's attempts for this habit are used up (no more tries).
  bool _outOfAttempts = false;

  bool get _isVerified => _result?.isVerified ?? false;

  /// Nothing more to do on this screen: verified, or out of attempts.
  bool get _isDone => _isVerified || _outOfAttempts;

  /// Camera only: the photo must be taken now, never picked from the gallery.
  Future<void> _takePhoto() async {
    try {
      // Resize before upload: CLIP only looks at a small image anyway,
      // and smaller files upload much faster.
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (photo == null) return; // user cancelled

      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _photoBytes = bytes;
        _result = null;
        _error = null;
      });
    } catch (e) {
      debugPrint('Image pick failed: $e');
      if (!mounted) return;
      setState(
        () => _error =
            'Could not open the camera. Check that Growy is allowed to use it.',
      );
    }
  }

  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await _service.submitPhoto(
        habitId: widget.habit.id,
        photo: photo,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        // The last rejected attempt: no more tries today.
        if (!result.isVerified && result.attemptsRemaining == 0) {
          _outOfAttempts = true;
        }
      });
      if (result.leveledUp && result.currentLevel != null) {
        await _showLevelUp(result.currentLevel!);
      }
    } on VerificationException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _outOfAttempts = e.outOfAttempts;
      });
    } catch (e) {
      debugPrint('Verification failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// The one full celebration: glow, level number, leaf confetti.
  Future<void> _showLevelUp(int level) =>
      showGrowyLevelUp(context, level: level);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textDark),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              widget.habit.name,
              style: GoogleFonts.fraunces(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Verify with a photo to earn ${widget.habit.xpValue} XP',
              style: GoogleFonts.poppins(fontSize: 13, color: _secondaryText),
            ),
            const SizedBox(height: 20),
            _InstructionCard(label: widget.habit.category),
            const SizedBox(height: 20),
            _PhotoPreview(
              bytes: _photoBytes,
              isChecking: _isSubmitting,
              result: _result,
            ),
            const SizedBox(height: 16),
            if (!_isDone)
              _SourceButton(
                icon: _photo == null
                    ? Icons.photo_camera_outlined
                    : Icons.refresh_rounded,
                label: _photo == null ? 'Take Photo' : 'Retake',
                onPressed: _isSubmitting ? null : _takePhoto,
              ),
            if (_result != null) ...[
              const SizedBox(height: 20),
              GrowyFadeIn(
                key: ValueKey(_result),
                offset: 8,
                child: _ResultBanner(result: _result!),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 13, color: _errorColor),
              ),
            ],
            const SizedBox(height: 24),
            _PrimaryButton(
              label: _isDone
                  ? 'Back to Home'
                  : (_isSubmitting ? 'Checking your photo...' : 'Verify Photo'),
              isLoading: _isSubmitting,
              onPressed: _isDone
                  ? () => Navigator.pop(context)
                  : (_photo == null || _isSubmitting ? null : _submit),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.label});

  final String label; // the habit's CLIP label, e.g. "a person reading a book"

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Take a clear photo showing:',
            style: GoogleFonts.poppins(fontSize: 13, color: _secondaryText),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Good light and the main subject in the middle work best.',
            style: GoogleFonts.poppins(fontSize: 12, color: _secondaryText),
          ),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.bytes,
    this.isChecking = false,
    this.result,
  });

  final Uint8List? bytes;

  /// While the AI is checking, a soft shimmer sweeps across the photo.
  final bool isChecking;

  /// After checking, a green (verified) or amber (try again) ring draws in.
  final VerificationResult? result;

  @override
  Widget build(BuildContext context) {
    final reduced = GrowyMotion.reduced(context);
    final passed = result?.isVerified;
    final ringColor = passed == null
        ? Colors.transparent
        : (passed ? AppColors.primary : GrowyPalette.warning);

    Widget photo = bytes == null
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_camera_outlined,
                size: 40,
                color: _secondaryText,
              ),
              const SizedBox(height: 8),
              Text(
                'Take a photo to verify your habit',
                style: GoogleFonts.poppins(fontSize: 13, color: _secondaryText),
              ),
            ],
          )
        : Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true);

    // A new photo shrinks in slightly from a full-bleed "snap".
    if (bytes != null && !reduced) {
      photo = photo
          .animate(key: ValueKey(bytes.hashCode))
          .fadeIn(duration: 200.ms)
          .scale(
            begin: const Offset(1.04, 1.04),
            end: const Offset(1, 1),
            duration: 300.ms,
            curve: GrowyMotion.enterCurve,
          );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: GrowyMotion.enterCurve,
        padding: EdgeInsets.all(passed == null ? 0 : 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ringColor, width: passed == null ? 0 : 3),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: GrowyPalette.surfaceMuted,
            child: Stack(
              fit: StackFit.expand,
              children: [
                photo,
                // A soft band of light sweeps across while the AI checks.
                if (isChecking && bytes != null && !reduced)
                  IgnorePointer(
                    child:
                        DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.35),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                  stops: const [0.3, 0.5, 0.7],
                                ),
                              ),
                            )
                            .animate(
                              onPlay: (controller) => controller.repeat(),
                            )
                            .slideX(begin: -1, end: 1, duration: 1400.ms),
                  ),
                if (isChecking)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: GrowyPalette.cameraScrim,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _CheckingLabel(),
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

/// "Checking your photo..." that turns into "Still checking..." after 8 s,
/// so a slow server never looks frozen.
class _CheckingLabel extends StatefulWidget {
  @override
  State<_CheckingLabel> createState() => _CheckingLabelState();
}

class _CheckingLabelState extends State<_CheckingLabel> {
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: GrowyMotion.micro,
      child: Text(
        _slow ? 'Still checking...' : 'Checking your photo...',
        key: ValueKey(_slow),
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.primary),
        label: Text(
          label,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final VerificationResult result;

  static String _attemptsText(int? left) {
    if (left == null) return 'Try a clearer photo that shows the habit.';
    if (left <= 0)
      return 'No attempts left for this habit today. Try again tomorrow.';
    return 'Try a clearer photo. $left ${left == 1 ? 'attempt' : 'attempts'} left today.';
  }

  @override
  Widget build(BuildContext context) {
    final passed = result.isVerified;
    // Amber, not red: a photo the AI couldn't read is not the user's fault.
    final color = passed ? AppColors.primary : GrowyPalette.warning;
    final confidence = result.confidence;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          passed
              ? GrowySuccessAnimation(size: 28, color: color)
              : Icon(Icons.info_outline_rounded, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passed
                      ? 'Verified! +${result.pointsEarned} XP'
                      : "Couldn't verify this photo yet",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  passed
                      ? (result.leveledUp && result.currentLevel != null
                            ? "Level up! You're now Level ${result.currentLevel}."
                            : 'Nice work, your avatar is growing.')
                      : _attemptsText(result.attemptsRemaining),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: _secondaryText,
                  ),
                ),
                // Helpful while tuning CLIP labels and thresholds;
                // remove before the final demo if you prefer.
                if (result.predictedLabel != null && confidence != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Detected: ${result.predictedLabel} '
                    '(${(confidence * 100).toStringAsFixed(0)}%)',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: _secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.fraunces(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
