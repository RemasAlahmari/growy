import 'package:flutter/material.dart';

class CharacterConfig {
  final Color skinColor;
  final Color hairColor;
  final Color shirtColor;
  final Color pantsColor;
  final Color shoesColor;

  const CharacterConfig({
    required this.skinColor,
    required this.hairColor,
    required this.shirtColor,
    required this.pantsColor,
    required this.shoesColor,
  });

  factory CharacterConfig.defaultConfig() => const CharacterConfig(
    skinColor: Color(0xFFF5D0B0),
    hairColor: Color(0xFF8B5E3C),
    shirtColor: Color(0xFFFF8FA3),
    pantsColor: Color(0xFF3A506B),
    shoesColor: Color(0xFFFFFFFF),
  );

  /// Hand-picked shading colours for the 4 skin presets in the customizer.
  static const Map<int, Color> _skinShadePresets = {
    0xFFF5D0B0: Color(0xFFED9D63),
    0xFFD9A066: Color(0xFFC27A3E),
    0xFF8D5524: Color(0xFF6B3D16),
    0xFF5C3A21: Color(0xFF3E2412),
  };

  /// Colour for the skin shade lines (#990099 in the SVGs).
  /// Not chosen by the user and not saved to the backend: it is always
  /// worked out from [skinColor]. Presets use the hand-picked shade; any
  /// other skin colour is darkened to 78% of its lightness.
  Color get skinShadeColor {
    final preset = _skinShadePresets[skinColor.toARGB32()];
    if (preset != null) return preset;
    final hsl = HSLColor.fromColor(skinColor);
    return hsl
        .withLightness((hsl.lightness * 0.78).clamp(0.0, 1.0))
        .toColor();
  }

  CharacterConfig copyWith({
    Color? skinColor,
    Color? hairColor,
    Color? shirtColor,
    Color? pantsColor,
    Color? shoesColor,
  }) {
    return CharacterConfig(
      skinColor: skinColor ?? this.skinColor,
      hairColor: hairColor ?? this.hairColor,
      shirtColor: shirtColor ?? this.shirtColor,
      pantsColor: pantsColor ?? this.pantsColor,
      shoesColor: shoesColor ?? this.shoesColor,
    );
  }

  Map<String, dynamic> toJson() => {
    'skin': skinColor.value,
    'hair': hairColor.value,
    'shirt': shirtColor.value,
    'pants': pantsColor.value,
    'shoes': shoesColor.value,
  };

  factory CharacterConfig.fromJson(Map<String, dynamic> json) {
    return CharacterConfig(
      skinColor: Color(json['skin']),
      hairColor: Color(json['hair']),
      shirtColor: Color(json['shirt']),
      pantsColor: Color(json['pants']),
      shoesColor: Color(json['shoes']),
    );
  }
}