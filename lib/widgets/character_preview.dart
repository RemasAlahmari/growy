import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/character_config.dart';

class CharacterPreview extends StatefulWidget {
  final CharacterConfig config;

  const CharacterPreview({required this.config, super.key});

  @override
  State<CharacterPreview> createState() => _CharacterPreviewState();
}

class _CharacterPreviewState extends State<CharacterPreview> {
  String? _rawSvg;

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  Future<void> _loadSvg() async {
    final raw = await rootBundle.loadString('assets/character/character_lvl1.svg');
    setState(() => _rawSvg = raw);
  }

  String _hex(Color c) =>
      '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    if (_rawSvg == null) {
      return const AspectRatio(
        aspectRatio: 400 / 800,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final recolored = _rawSvg!
        .replaceAll('#FF00FF', _hex(widget.config.skinColor))
        .replaceAll('#00FF00', _hex(widget.config.hairColor))
        .replaceAll('#00FFFF', _hex(widget.config.shirtColor))
        .replaceAll('#FFFF00', _hex(widget.config.pantsColor))
        .replaceAll('#FF6600', _hex(widget.config.shoesColor));

    return AspectRatio(
      aspectRatio: 400 / 800,
      child: SvgPicture.string(recolored),
    );
  }
}