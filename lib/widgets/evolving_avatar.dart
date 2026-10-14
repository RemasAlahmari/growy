import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_svg/flutter_svg.dart';

import '../core/motion/growy_motion.dart';
import '../models/character_config.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_stage.dart';
import '../utils/avatar_svg.dart';
import 'character_preview.dart';

/// The avatar evolving from one stage into the next (from the Evolution Lab).
///
/// To avoid lag, both characters are drawn ONCE into images (colour + white
/// silhouette) before the animation starts. During the animation only these
/// ready images are moved, so the SVGs are never redrawn per frame.
///
/// Plays by itself as soon as it appears, then calls [onFinished].
/// With "Remove animations" turned on, it skips straight to [onFinished].
class EvolvingAvatar extends StatefulWidget {
  const EvolvingAvatar({
    super.key,
    required this.config,
    required this.gender,
    required this.fromLevel,
    required this.toLevel,
    required this.onFinished,
    this.width = 178,
  });

  final CharacterConfig config;
  final AvatarGender gender;

  /// Backend levels (0–4). The character stages come from avatar_stage.dart.
  final int fromLevel;
  final int toLevel;

  final VoidCallback onFinished;

  /// Width the avatar is shown at on screen (used for the image resolution).
  final double width;

  @override
  State<EvolvingAvatar> createState() => _EvolvingAvatarState();
}

// Feet on the ground (y = 800 of the 820 frame), as an Alignment:
// the squash and stretch always happens from the feet.
const Alignment _feetAnchor = Alignment(0, 800 / 820 * 2 - 1);

// Rough centre of the body (chest height), as a fraction of the frame.
const Offset _bodyCentre = Offset(0.5, 0.48);

// Timeline: fractions of the whole animation (0..1). Change these to tune it.
const double _chargeStart = 0.12; // squash ends, glow + silhouette begin
const double _chargeEnd = 0.38; // silhouette fully white
const double _swap = 0.42; // old character is replaced by the new one
const double _revealStart = 0.47; // colour starts coming back
const double _revealEnd = 0.68; // new character fully coloured
const int _particleCount = 36;

/// 0 before [a], 1 after [b], straight line in between.
double _seg(double t, double a, double b) =>
    b <= a ? (t >= b ? 1.0 : 0.0) : ((t - a) / (b - a)).clamp(0.0, 1.0);

class _EvolvingAvatarState extends State<EvolvingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: GrowyMotion.evolve,
  );

  ui.Image? _fromColour, _fromWhite, _toColour, _toWhite;
  bool _started = false;
  bool _hapticDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (GrowyMotion.reduced(context)) {
      // "Remove animations" is on: no evolution, just finish.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFinished();
      });
      return;
    }
    _prepareAndPlay(MediaQuery.devicePixelRatioOf(context));
  }

  Future<void> _prepareAndPlay(double pixelRatio) async {
    final widthPx = (widget.width * pixelRatio).ceil();
    try {
      // 1. Recolour both SVGs with the user's colours.
      final fromSvg = recolorAvatarSvg(
        await loadAvatarSvg(avatarAssetFor(widget.gender, widget.fromLevel)),
        widget.config,
      );
      final toSvg = recolorAvatarSvg(
        await loadAvatarSvg(avatarAssetFor(widget.gender, widget.toLevel)),
        widget.config,
      );

      // 2. Draw each one into an image ONCE (this is what removes the lag).
      final fromColour = await _rasterize(fromSvg, widthPx);
      final toColour = await _rasterize(toSvg, widthPx);
      final fromWhite = await _whiteCopy(fromColour);
      final toWhite = await _whiteCopy(toColour);

      if (!mounted) {
        fromColour.dispose();
        toColour.dispose();
        fromWhite.dispose();
        toWhite.dispose();
        return;
      }
      setState(() {
        _fromColour = fromColour;
        _toColour = toColour;
        _fromWhite = fromWhite;
        _toWhite = toWhite;
      });

      // 3. Play.
      _controller.addListener(_onTick);
      await _controller.forward().orCancel;
      if (mounted) widget.onFinished();
    } catch (e) {
      // If anything goes wrong, skip the animation instead of getting stuck.
      debugPrint('Evolution animation skipped: $e');
      if (mounted) widget.onFinished();
    }
  }

  /// Draws an SVG string into an image that is [widthPx] pixels wide.
  Future<ui.Image> _rasterize(String svg, int widthPx) async {
    final info = await vg.loadPicture(SvgStringLoader(svg), null);
    final scale = widthPx / info.size.width;
    final heightPx = (info.size.height * scale).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawPicture(info.picture);
    final picture = recorder.endRecording();
    final image = await picture.toImage(widthPx, heightPx);

    picture.dispose();
    info.picture.dispose();
    return image;
  }

  /// A white silhouette of [source] (same shape, every pixel white).
  Future<ui.Image> _whiteCopy(ui.Image source) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(
      source,
      Offset.zero,
      Paint()
        ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(source.width, source.height);
    picture.dispose();
    return image;
  }

  // A light buzz at the moment the character changes.
  void _onTick() {
    if (!_hapticDone && _controller.value >= _swap) {
      _hapticDone = true;
      HapticFeedback.lightImpact();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _fromColour?.dispose();
    _toColour?.dispose();
    _fromWhite?.dispose();
    _toWhite?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fromColour = _fromColour;
    final toColour = _toColour;
    final fromWhite = _fromWhite;
    final toWhite = _toWhite;

    // While the images are being prepared (a split second), show the old
    // character standing still, so nothing flickers.
    if (fromColour == null ||
        toColour == null ||
        fromWhite == null ||
        toWhite == null) {
      return CharacterPreview(
        config: widget.config,
        gender: widget.gender,
        level: widget.fromLevel,
      );
    }

    final glowColor = GrowyPalette.primary;

    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: kAvatarAspectRatio,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final showNew = t >= _swap;

            // How white the character is (0 = normal colours, 1 = silhouette).
            final whiteAmount = t < _revealStart
                ? Curves.easeIn.transform(_seg(t, _chargeStart, _chargeEnd))
                : 1 - Curves.easeOut.transform(_seg(t, _revealStart, _revealEnd));

            // Squash and stretch, always from the feet.
            double sx = 1, sy = 1;
            if (t < _chargeStart) {
              // Anticipation: a small squash down.
              final k = math.sin(_seg(t, 0, _chargeStart) * math.pi / 2);
              sx = 1 + 0.04 * k;
              sy = 1 - 0.06 * k;
            } else if (t < _swap) {
              // Charge: slowly stretch up and tremble.
              final k = _seg(t, _chargeStart, _swap);
              final tremble = math.sin(t * 220) * 0.006 * k;
              sx = 1.04 - 0.07 * k + tremble;
              sy = 0.94 + 0.12 * k - tremble;
            } else {
              // Pop, then settle with a soft bounce.
              final k = _seg(t, _swap, 1);
              final bounce = math.exp(-5 * k) * math.cos(k * math.pi * 5);
              sx = 1 - 0.05 * bounce;
              sy = 1 + 0.08 * bounce;
            }

            // Glow behind the character.
            final glow = t < _swap
                ? Curves.easeIn.transform(_seg(t, _chargeStart, _swap))
                : 1 - Curves.easeOut.transform(_seg(t, _swap, _revealEnd));

            // Short white flash at the moment of the swap.
            final flash = t < _swap
                ? _seg(t, _swap - 0.05, _swap)
                : 1 - _seg(t, _swap, _swap + 0.10);

            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                // 1. Glow
                if (glow > 0)
                  CustomPaint(
                    painter: _GlowPainter(
                      amount: glow,
                      flash: flash,
                      color: glowColor,
                    ),
                  ),
                // 2. Particles behind the character
                CustomPaint(
                  painter: _ParticlePainter(t: t, color: glowColor),
                ),
                // 3. The character (ready-made images only)
                Transform(
                  alignment: _feetAnchor,
                  transform: Matrix4.diagonal3Values(sx, sy, 1),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RawImage(
                        image: showNew ? toColour : fromColour,
                        fit: BoxFit.contain,
                      ),
                      if (whiteAmount > 0)
                        Opacity(
                          opacity: whiteAmount.clamp(0.0, 1.0),
                          child: RawImage(
                            image: showNew ? toWhite : fromWhite,
                            fit: BoxFit.contain,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.amount, required this.flash, required this.color});

  final double amount; // 0..1
  final double flash; // 0..1
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre =
    Offset(size.width * _bodyCentre.dx, size.height * _bodyCentre.dy);
    final radius = size.height * (0.35 + 0.25 * amount + 0.25 * flash);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(color, Colors.white, 0.5 + 0.5 * flash)!.withValues(
            alpha: (0.75 * amount + 0.25 * flash).clamp(0.0, 1.0),
          ),
          color.withValues(alpha: 0.35 * amount),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawCircle(centre, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) =>
      old.amount != amount || old.flash != flash || old.color != color;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre =
    Offset(size.width * _bodyCentre.dx, size.height * _bodyCentre.dy);
    final maxR = size.height * 0.62;
    final rnd = math.Random(7); // fixed seed = same pattern every time
    final paint = Paint();

    for (var i = 0; i < _particleCount; i++) {
      final angle = rnd.nextDouble() * math.pi * 2;
      final speed = 0.6 + rnd.nextDouble() * 0.4;
      final delay = rnd.nextDouble() * 0.25;
      final dotSize = size.width * (0.008 + rnd.nextDouble() * 0.012);
      final isWhite = rnd.nextBool();
      final dir = Offset(math.cos(angle), math.sin(angle));

      // Phase 1: particles fly IN to the body while it charges.
      final inK = _seg(
        t,
        _chargeStart + delay * (_swap - _chargeStart),
        _swap,
      );
      if (inK > 0 && t < _swap) {
        final r = maxR * speed * (1 - Curves.easeIn.transform(inK));
        paint.color = (isWhite ? Colors.white : color)
            .withValues(alpha: (inK * 1.5).clamp(0.0, 1.0));
        canvas.drawCircle(centre + dir * r, dotSize, paint);
      }

      // Phase 2: particles burst OUT after the swap.
      final outK = _seg(t, _swap, _swap + 0.32 + delay * 0.4);
      if (t >= _swap && outK < 1) {
        final r = maxR * speed * Curves.easeOutCubic.transform(outK);
        paint.color = (isWhite ? Colors.white : color)
            .withValues(alpha: (1 - outK).clamp(0.0, 1.0));
        canvas.drawCircle(
          centre + dir * r,
          dotSize * (1.4 - 0.6 * outK),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => old.t != t;
}