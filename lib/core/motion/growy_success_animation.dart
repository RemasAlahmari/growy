import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../theme/app_theme.dart';
import 'growy_motion.dart';

/// `success`: a green check that pops in, with an optional "+30 XP" that
/// rises 12 px and fades. Plays once, about 0.7 s. No confetti: this is the
/// everyday reward.
///
/// ```dart
/// GrowySuccessAnimation(xp: 30)
/// ```
class GrowySuccessAnimation extends StatefulWidget {
  const GrowySuccessAnimation({
    super.key,
    this.xp,
    this.size = 56,
    this.color,
    this.haptic = true,
  });

  /// XP to float above the check. Leave null to show the check only.
  final int? xp;
  final double size;

  /// Defaults to Growy green.
  final Color? color;
  final bool haptic;

  @override
  State<GrowySuccessAnimation> createState() => _GrowySuccessAnimationState();
}

class _GrowySuccessAnimationState extends State<GrowySuccessAnimation> {
  @override
  void initState() {
    super.initState();
    if (widget.haptic) HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? GrowyPalette.primary;
    final reduced = GrowyMotion.reduced(context);

    Widget check = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(
        Icons.check_rounded,
        color: Colors.white,
        size: widget.size * 0.6,
      ),
    );
    if (!reduced) {
      check = check
          .animate()
          .scale(
            begin: const Offset(0.4, 0.4),
            end: const Offset(1, 1),
            duration: 300.ms,
            curve: GrowyMotion.popCurve,
          )
          .fadeIn(duration: 150.ms);
    }

    final xp = widget.xp;
    if (xp == null) return check;

    Widget label = Text(
      '+$xp XP',
      style: TextStyle(
        fontSize: widget.size * 0.3,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
    if (!reduced) {
      label = label
          .animate(delay: 150.ms)
          .fadeIn(duration: 150.ms)
          .moveY(begin: 0, end: -12, duration: 500.ms, curve: Curves.easeOut)
          .then(delay: 150.ms)
          .fadeOut(duration: 200.ms);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: widget.size * 0.45, child: label),
        check,
      ],
    );
  }
}

/// `count`: rolls a number from its old value to its new one (600 ms).
/// The first time it appears it counts up from [from].
///
/// ```dart
/// GrowyCountUp(value: totalXp, builder: (v) => Text('$v XP'))
/// ```
class GrowyCountUp extends StatelessWidget {
  const GrowyCountUp({
    super.key,
    required this.value,
    required this.builder,
    this.from = 0,
  });

  final int value;
  final int from;
  final Widget Function(int value) builder;

  @override
  Widget build(BuildContext context) {
    if (GrowyMotion.reduced(context)) return builder(value);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from.toDouble(), end: value.toDouble()),
      duration: GrowyMotion.count,
      curve: GrowyMotion.enterCurve,
      builder: (context, v, _) => builder(v.round()),
    );
  }
}
