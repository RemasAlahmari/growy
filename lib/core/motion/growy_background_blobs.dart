import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'growy_motion.dart';

/// Where the soft circles sit on a page.
enum GrowyBlobPreset {
  /// Bottom of the screen (Login, Sign Up). The original Growy look.
  auth,

  /// Top corners (Welcome / splash).
  top,

  /// Small, top-right, so they never sit under the habit list (Home).
  home,

  /// Two circles at half strength (Groups, Me, Habits).
  quiet,
}

/// `ambient`: Growy's calm living background. The two soft circles drift and
/// breathe slowly, each on its own cycle (10 s and 8 s), so they never move
/// in sync.
///
/// Put it first in a Stack, behind everything:
/// ```dart
/// Stack(children: [
///   const Positioned.fill(child: GrowyBackgroundBlobs(preset: GrowyBlobPreset.auth)),
///   ...content,
/// ])
/// ```
///
/// It never takes taps, is invisible to screen readers, pauses automatically
/// when its page is covered, and stays still when animations are turned off.
class GrowyBackgroundBlobs extends StatefulWidget {
  const GrowyBackgroundBlobs({super.key, this.preset = GrowyBlobPreset.auth});

  final GrowyBlobPreset preset;

  @override
  State<GrowyBackgroundBlobs> createState() => _GrowyBackgroundBlobsState();
}

class _GrowyBackgroundBlobsState extends State<GrowyBackgroundBlobs>
    with TickerProviderStateMixin {
  static const _cycles = [
    Duration(seconds: 10),
    Duration(seconds: 8),
  ];

  late final List<AnimationController> _controllers = [
    for (var i = 0; i < _cycles.length; i++)
      AnimationController(vsync: this, duration: _cycles[i])
        // Start each circle at a different point of its cycle.
        ..value = const [0.0, 0.5][i],
  ];
  late final List<Animation<double>> _curves = [
    for (final c in _controllers)
      CurvedAnimation(parent: c, curve: GrowyMotion.ambientCurve),
  ];
  late final Listenable _repaint = Listenable.merge(_controllers);
  bool? _running;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = !GrowyMotion.reduced(context);
    if (run == _running) return;
    _running = run;
    for (final c in _controllers) {
      if (run) {
        c.repeat(reverse: true);
      } else {
        c.stop();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _curves) {
      (c as CurvedAnimation).dispose();
    }
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _BlobPainter(
              blobs: _blobsFor(widget.preset),
              progress: _curves,
              repaint: _repaint,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  /// Same circles, sizes and positions as the original static design
  /// (auth_widgets.dart bottomCircles / Welcome), now drifting slowly.
  /// Each circle is placed by its centre, measured in px from a screen corner.
  static List<_Blob> _blobsFor(GrowyBlobPreset preset) {
    final dark = GrowyPalette.isDark;
    final green = GrowyPalette.primary;
    final peach = GrowyPalette.secondary;
    final a = dark ? 0.14 : 0.20; // the original circles used 20%

    switch (preset) {
      case GrowyBlobPreset.auth:
        // Was: green 420 at left -200 / bottom -110, pink 420 at right -150 / bottom -150.
        return [
          _Blob(green, a, Alignment.bottomLeft, const Offset(10, -100), 420, 57, 28, 0.07),
          _Blob(peach, a, Alignment.bottomRight, const Offset(-60, -60), 420, -48, 22, 0.08),
        ];
      case GrowyBlobPreset.top:
        // Was: pink 340 at left -140 / top -150, green 340 at right -120 / top -150.
        return [
          _Blob(peach, a, Alignment.topLeft, const Offset(30, 20), 340, 48, 22, 0.08),
          _Blob(green, a, Alignment.topRight, const Offset(-50, 20), 340, -57, 28, 0.07),
        ];
      case GrowyBlobPreset.home:
        // Smaller, top-right, away from the habit list.
        return [
          _Blob(green, a * 0.7, Alignment.topRight, const Offset(-10, 10), 260, -44, 22, 0.07),
          _Blob(peach, a * 0.7, Alignment.topRight, const Offset(-150, -30), 200, 38, 19, 0.08),
        ];
      case GrowyBlobPreset.quiet:
        // Same as auth, at half strength, for content-heavy pages.
        return [
          _Blob(green, a * 0.5, Alignment.bottomLeft, const Offset(10, -100), 420, 57, 28, 0.07),
          _Blob(peach, a * 0.5, Alignment.bottomRight, const Offset(-60, -60), 420, -48, 22, 0.08),
        ];
    }
  }
}

class _Blob {
  const _Blob(
    this.color,
    this.opacity,
    this.corner,
    this.offset,
    this.size,
    this.driftX,
    this.driftY,
    this.scaleRange,
  );

  final Color color;
  final double opacity;

  /// Screen corner the circle is measured from.
  final Alignment corner;

  /// Circle centre, in px from [corner].
  final Offset offset;

  /// Diameter in px.
  final double size;

  /// Total drift in px across one cycle.
  final double driftX;
  final double driftY;

  /// Extra scale at the far end of the cycle (0.05 = 1.00 → 1.05).
  final double scaleRange;
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({
    required this.blobs,
    required this.progress,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<_Blob> blobs;
  final List<Animation<double>> progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < blobs.length; i++) {
      final b = blobs[i];
      final t = progress[i % progress.length].value; // 0 → 1 → 0, eased
      final wave = t * 2 - 1; // -1 → 1
      final corner = b.corner.alongSize(size);
      final center = corner +
          b.offset +
          Offset(b.driftX * wave / 2, b.driftY * wave / 2);
      final radius = b.size / 2 * (1 + b.scaleRange * t);
      // Solid like the original circles, with a slightly soft rim.
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            b.color.withValues(alpha: b.opacity),
            b.color.withValues(alpha: b.opacity),
            b.color.withValues(alpha: b.opacity * 0.6),
          ],
          stops: const [0.0, 0.9, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.blobs.length != blobs.length ||
      old.blobs.first.color != blobs.first.color ||
      old.blobs.first.opacity != blobs.first.opacity;
}
