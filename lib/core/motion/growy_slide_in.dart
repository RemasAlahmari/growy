import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'growy_motion.dart';

/// `stagger`: one item of a list that fades and slides in a little after the
/// item before it. Give each item its position with [index].
///
/// Only the first 6 items are staggered; later ones arrive with the 6th, so
/// a long list never takes more than about 0.7 s to settle.
///
/// ```dart
/// for (var i = 0; i < groups.length; i++)
///   GrowySlideIn(index: i, child: GroupCard(groups[i]))
/// ```
class GrowySlideIn extends StatelessWidget {
  const GrowySlideIn({
    super.key,
    required this.index,
    required this.child,
    this.axis = Axis.vertical,
    this.baseDelay = Duration.zero,
  });

  final int index;
  final Widget child;

  /// Vertical lists rise up; horizontal strips slide in from the right.
  final Axis axis;

  /// Extra wait before the first item, e.g. to let a header land first.
  final Duration baseDelay;

  @override
  Widget build(BuildContext context) {
    if (GrowyMotion.reduced(context)) {
      return child.animate().fadeIn(duration: GrowyMotion.reducedFade);
    }
    final delay = baseDelay + GrowyMotion.staggerDelay(index);
    final faded = child
        .animate(delay: delay)
        .fadeIn(duration: GrowyMotion.stagger, curve: GrowyMotion.enterCurve);
    return axis == Axis.vertical
        ? faded.moveY(
            begin: GrowyMotion.enterOffset,
            end: 0,
            duration: GrowyMotion.stagger,
            curve: GrowyMotion.enterCurve,
          )
        : faded.moveX(
            begin: 24,
            end: 0,
            duration: GrowyMotion.stagger,
            curve: GrowyMotion.enterCurve,
          );
  }
}
