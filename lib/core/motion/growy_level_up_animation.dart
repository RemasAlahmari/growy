import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import 'growy_motion.dart';

/// `levelUp`: the one full celebration in Growy. Shows a card with a soft
/// glow, the new level rolling in, and one small burst of leaf confetti.
/// Also used for streak milestones (pass a [title] and [message]).
///
/// ```dart
/// await showGrowyLevelUp(context, level: 3);
/// ```
Future<void> showGrowyLevelUp(
  BuildContext context, {
  required int level,
  String? title,
  String? message,
  Widget? avatar,
}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: GrowyMotion.enter,
    pageBuilder: (context, _, _) => GrowyLevelUpAnimation(
      level: level,
      title: title ?? 'Level up!',
      message: message ?? "You're now Level $level. Your avatar evolved!",
      avatar: avatar,
    ),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: GrowyMotion.enterCurve,
      ),
      child: child,
    ),
  );
}

class GrowyLevelUpAnimation extends StatefulWidget {
  const GrowyLevelUpAnimation({
    super.key,
    required this.level,
    required this.title,
    required this.message,
    this.avatar,
  });

  final int level;
  final String title;
  final String message;

  /// Optional avatar to glow behind (e.g. CharacterPreview). Defaults to a star.
  final Widget? avatar;

  @override
  State<GrowyLevelUpAnimation> createState() => _GrowyLevelUpAnimationState();
}

class _GrowyLevelUpAnimationState extends State<GrowyLevelUpAnimation> {
  final ConfettiController _confetti = ConfettiController(
    duration: const Duration(milliseconds: 400),
  );

  @override
  void initState() {
    super.initState();
    // Fire the burst 400 ms in, as the level number lands.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted || GrowyMotion.reduced(context)) return;
      _confetti.play();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  /// A small leaf shape for the confetti.
  static Path _leaf(Size size) {
    final w = size.width, h = size.height;
    return Path()
      ..moveTo(w / 2, 0)
      ..quadraticBezierTo(w, h * 0.35, w / 2, h)
      ..quadraticBezierTo(0, h * 0.35, w / 2, 0)
      ..close();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = GrowyMotion.reduced(context);
    final green = GrowyPalette.primary;

    Widget glow = Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [green.withValues(alpha: 0.35), green.withValues(alpha: 0)],
        ),
      ),
    );
    Widget art =
        widget.avatar ??
        Icon(Icons.auto_awesome_rounded, color: green, size: 56);
    Widget levelText = Text(
      'Level ${widget.level}',
      style: GoogleFonts.fraunces(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: green,
      ),
    );

    if (!reduced) {
      glow = glow
          .animate(delay: 200.ms)
          .fadeIn(duration: 400.ms)
          .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1))
          .then(delay: 600.ms)
          .fadeOut(duration: 600.ms);
      art = art
          .animate(delay: 200.ms)
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.06, 1.06),
            duration: 300.ms,
            curve: Curves.easeOut,
          )
          .then()
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1 / 1.06, 1 / 1.06),
            duration: 300.ms,
          );
      levelText = levelText
          .animate(delay: 400.ms)
          .fadeIn(duration: 200.ms)
          .scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1.2, 1.2),
            duration: 250.ms,
            curve: GrowyMotion.popCurve,
          )
          .then()
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1 / 1.2, 1 / 1.2),
            duration: 200.ms,
          );
    }

    final card = Material(
      color: GrowyPalette.surfaceRaised,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 140,
              child: Stack(alignment: Alignment.center, children: [glow, art]),
            ),
            Text(
              widget.title,
              style: GoogleFonts.fraunces(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: GrowyPalette.textMain,
              ),
            ),
            const SizedBox(height: 4),
            levelText,
            const SizedBox(height: 8),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: GrowyPalette.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Nice!',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: green,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return SafeArea(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: reduced
                  ? card
                  : card
                        .animate()
                        .fadeIn(duration: 250.ms)
                        .scale(
                          begin: const Offset(0.94, 0.94),
                          end: const Offset(1, 1),
                          duration: 300.ms,
                          curve: GrowyMotion.enterCurve,
                        ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.directional,
              blastDirection: math.pi / 2, // straight down
              emissionFrequency: 0.15,
              numberOfParticles: 8, // about 25 leaves in total
              maxBlastForce: 14,
              minBlastForce: 6,
              gravity: 0.25,
              shouldLoop: false,
              minimumSize: const Size(8, 12),
              maximumSize: const Size(12, 18),
              colors: [
                green,
                Color.lerp(green, Colors.white, 0.5)!,
                GrowyPalette.secondary,
              ],
              createParticlePath: _leaf,
            ),
          ),
        ],
      ),
    );
  }
}
