import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/motion/growy_motion.dart';
import '../models/character_config.dart';
import '../utils/avatar_stage.dart';
import '../utils/avatar_svg.dart';

/// Shows the recoloured avatar for a gender + backend level (0–4).
///
/// `CharacterPreview(config: _config)` still works: gender defaults to girl
/// and level to 1.
class CharacterPreview extends StatefulWidget {
  final CharacterConfig config;
  final int level;
  final AvatarGender gender;

  const CharacterPreview({
    required this.config,
    this.level = 1,
    this.gender = AvatarGender.girl,
    super.key,
  });

  @override
  State<CharacterPreview> createState() => _CharacterPreviewState();
}

class _CharacterPreviewState extends State<CharacterPreview> {
  String? _rawSvg;
  String? _loadedPath;

  String get _assetPath => avatarAssetFor(widget.gender, widget.level);

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  @override
  void didUpdateWidget(covariant CharacterPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload only when the file changes (new stage or new gender),
    // not when just the colours change.
    if (_assetPath != _loadedPath) {
      _loadSvg();
    }
  }

  Future<void> _loadSvg() async {
    final path = _assetPath;
    final cached = cachedAvatarSvg(path);
    if (cached != null) {
      setState(() {
        _rawSvg = cached;
        _loadedPath = path;
      });
      return;
    }
    final raw = await loadAvatarSvg(path);
    if (!mounted) return;
    setState(() {
      _rawSvg = raw;
      _loadedPath = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_rawSvg == null) {
      return const AspectRatio(
        aspectRatio: kAvatarAspectRatio,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final recolored = recolorAvatarSvg(_rawSvg!, widget.config);

    return AspectRatio(
      aspectRatio: kAvatarAspectRatio,
      child: AnimatedSwitcher(
        // A quick fade when the gender or stage changes. Re-colouring
        // doesn't trigger it, because the key is the file path.
        duration: GrowyMotion.micro,
        child: SvgPicture.string(recolored, key: ValueKey(_loadedPath)),
      ),
    );
  }
}