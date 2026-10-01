import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/character_config.dart';
import '../utils/avatar_stage.dart';

/// whenever the level — and therefore the underlying SVG — changes.

/// `CharacterPreview(config: _config)` in the customizer keep compiling

class CharacterPreview extends StatefulWidget {
  final CharacterConfig config;
  final int level;

  const CharacterPreview({required this.config, this.level = 1, super.key});

  @override
  State<CharacterPreview> createState() => _CharacterPreviewState();
}

class _CharacterPreviewState extends State<CharacterPreview> {
  // Raw (uncolored) SVG text, cached per asset path so multiple
  // CharacterPreview instances (Home, Customizer, ...) don't each re-read
  // the same file from disk.
  static final Map<String, String> _rawSvgCache = {};
  String? _rawSvg;
  String? _loadedPath;
 
  @override
  void initState() {
    super.initState();
    _loadSvg();
  }
 
  @override
  void didUpdateWidget(covariant CharacterPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (avatarAssetForLevel(widget.level) != _loadedPath) {
      _loadSvg();
    }
  }
 
  Future<void> _loadSvg() async {
    final path = avatarAssetForLevel(widget.level);
    final cached = _rawSvgCache[path];
    if (cached != null) {
      setState(() {
        _rawSvg = cached;
        _loadedPath = path;
      });
      return;
    }
    final raw = await rootBundle.loadString(path);
    _rawSvgCache[path] = raw;
    if (!mounted) return;
    setState(() {
      _rawSvg = raw;
      _loadedPath = path;
    });
  }
 
  String _hex(Color c) =>
      '#${c.value.toRadixString(16).substring(2).toUpperCase()}';
 
  /// Case-insensitive find/replace — export tools (Figma, Illustrator,
  /// Inkscape, etc.) often flatten hex colors to lowercase when you re-save
  /// an SVG, which silently broke the old case-sensitive replaceAll.
  String _replaceColor(String svg, String placeholder, Color color) {
    return svg.replaceAll(
      RegExp(RegExp.escape(placeholder), caseSensitive: false),
      _hex(color),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    if (_rawSvg == null) {
      return const AspectRatio(
        aspectRatio: 400 / 800,
        child: Center(child: CircularProgressIndicator()),
      );
    }
 
    var recolored = _rawSvg!;
    recolored = _replaceColor(recolored, '#FF00FF', widget.config.skinColor);
    recolored = _replaceColor(recolored, '#00FF00', widget.config.hairColor);
    recolored = _replaceColor(recolored, '#00FFFF', widget.config.shirtColor);
    recolored = _replaceColor(recolored, '#FFFF00', widget.config.pantsColor);
    recolored = _replaceColor(recolored, '#FF6600', widget.config.shoesColor);
 
    return AspectRatio(
      aspectRatio: 400 / 800,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        // Keyed by stage, not by color, so re-coloring never re-triggers
        // the evolve animation — only an actual level/stage change does.
        child: SvgPicture.string(recolored, key: ValueKey(_loadedPath)),
      ),
    );
  }
}