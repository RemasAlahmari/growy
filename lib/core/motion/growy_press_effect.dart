import 'package:flutter/material.dart';

import 'growy_motion.dart';

/// `press`: shrinks its child to 97% while a finger is down and springs back
/// on release. It only listens to the touch, so the child's own InkWell or
/// button still handles the tap.
///
/// ```dart
/// GrowyPressEffect(child: GrowyPrimaryButton(...))
/// ```
class GrowyPressEffect extends StatefulWidget {
  const GrowyPressEffect({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.97,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<GrowyPressEffect> createState() => _GrowyPressEffectState();
}

class _GrowyPressEffectState extends State<GrowyPressEffect> {
  bool _down = false;

  void _set(bool down) {
    if (!widget.enabled || _down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (GrowyMotion.reduced(context)) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: _down ? GrowyMotion.pressDown : GrowyMotion.pressUp,
        curve: GrowyMotion.pressCurve,
        child: widget.child,
      ),
    );
  }
}
