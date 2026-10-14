import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/character_config.dart';

/// Loading and recolouring of the avatar SVGs, shared by CharacterPreview
/// and EvolvingAvatar so both always look exactly the same.

// Raw (uncoloured) SVG text per asset path, so each file is read only once.
final Map<String, String> _rawSvgCache = {};

/// The raw SVG if it was already loaded, otherwise null.
String? cachedAvatarSvg(String path) => _rawSvgCache[path];

/// Loads the raw SVG text of an avatar file (from the cache when possible).
Future<String> loadAvatarSvg(String path) async {
  final cached = _rawSvgCache[path];
  if (cached != null) return cached;
  final raw = await rootBundle.loadString(path);
  _rawSvgCache[path] = raw;
  return raw;
}

/// Replaces the placeholder colours with the user's colours.
///
/// #FF00FF skin · #990099 skin shade · #00FF00 hair · #00FFFF shirt ·
/// #FFFF00 pants · #FF6600 shoes
String recolorAvatarSvg(String rawSvg, CharacterConfig config) {
  var svg = rawSvg;
  svg = _replaceColor(svg, '#FF00FF', config.skinColor);
  svg = _replaceColor(svg, '#990099', config.skinShadeColor);
  svg = _replaceColor(svg, '#00FF00', config.hairColor);
  svg = _replaceColor(svg, '#00FFFF', config.shirtColor);
  svg = _replaceColor(svg, '#FFFF00', config.pantsColor);
  svg = _replaceColor(svg, '#FF6600', config.shoesColor);
  return svg;
}

// padLeft keeps the hex correct even for colours with a low alpha value.
String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// Case-insensitive find/replace, because export tools sometimes write
/// hex colours in lowercase.
String _replaceColor(String svg, String placeholder, Color color) {
  return svg.replaceAll(
    RegExp(RegExp.escape(placeholder), caseSensitive: false),
    _hex(color),
  );
}