import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'growy_motion.dart';

/// `enter`: fades its child in while it rises 16 px. Plays once, the first
/// time the widget appears; rebuilds do not replay it.
///
/// ```dart
/// GrowyFadeIn(child: ProfileHeader(...))
/// ```
class GrowyFadeIn extends StatelessWidget {
  const GrowyFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = GrowyMotion.enter,
    this.offset = GrowyMotion.enterOffset,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// How far (px) the child rises. Use 0 for a plain fade.
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (GrowyMotion.reduced(context)) {
      return child.animate().fadeIn(duration: GrowyMotion.reducedFade);
    }
    var effects = child
        .animate(delay: delay)
        .fadeIn(duration: duration, curve: GrowyMotion.enterCurve);
    if (offset != 0) {
      effects = effects.moveY(
        begin: offset,
        end: 0,
        duration: duration,
        curve: GrowyMotion.enterCurve,
      );
    }
    return effects;
  }
}
