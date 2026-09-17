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