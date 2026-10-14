import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/character_config.dart';
import '../services/avatar_gender_store.dart';
import '../services/avatar_service.dart';
import '../theme/app_theme.dart';
import '../utils/avatar_stage.dart';
import '../widgets/character_preview.dart';
import 'home_screen.dart';

class AvatarCustomizerScreen extends StatefulWidget {
  // The avatar the user currently has, so the customizer opens showing it
  // instead of always starting from the default look.
  final CharacterConfig? initialConfig;

  final bool isFirstSetup;

  // Boy or girl the customizer opens with (girl if not given).
  final AvatarGender? initialGender;

  // The user's backend level (0–4), so the preview shows the right stage.
  final int level;

  const AvatarCustomizerScreen({
    super.key,
    this.initialConfig,
    this.isFirstSetup = false,
    this.initialGender,
    this.level = 0,
  });

  @override
  State<AvatarCustomizerScreen> createState() => _AvatarCustomizerScreenState();
}

class _AvatarCustomizerScreenState extends State<AvatarCustomizerScreen> {
  late CharacterConfig _config;
  late AvatarGender _gender;
  String _activeCategory = 'skin';
  final AvatarService _avatarService = AvatarService();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig ?? CharacterConfig.defaultConfig();
    _gender = widget.initialGender ?? AvatarGender.girl;
  }

  final Map<String, List<Color>> _categoryColors = {
    'skin': [
      const Color(0xFFF5D0B0),
      const Color(0xFFD9A066),
      const Color(0xFF8D5524),
      const Color(0xFF5C3A21),
    ],
    'hair': [
      const Color(0xFF3B2417),
      const Color(0xFF8B5E3C),
      const Color(0xFFE8B923),
      const Color(0xFF2D2D2D),
    ],
    'shirt': [
      const Color(0xFFFF8FA3),
      const Color(0xFF6EC6FF),
      const Color(0xFF8DE28C),
      const Color(0xFFFFD166),
    ],
    'pants': [
      const Color(0xFF2E2E2E),
      const Color(0xFF3A506B),
      const Color(0xFF5C4033),
      const Color(0xFF7CB79E),
    ],
    'shoes': [
      const Color(0xFFFFFFFF),
      const Color(0xFFFF6B6B),
      const Color(0xFF4D4D4D),
      const Color(0xFF6EC6FF),
    ],
  };

  // Skin and Hair use Material icons; Shirt, Pants and Shoes use the small
  // SVG icons at the bottom of this file (Material has no clothing icons).
  final List<Map<String, dynamic>> _categories = const [
    {'key': 'skin', 'label': 'Skin', 'icon': Icons.face},
    {'key': 'hair', 'label': 'Hair', 'icon': Icons.content_cut},
    {'key': 'shirt', 'label': 'Shirt', 'svg': _shirtIcon},
    {'key': 'pants', 'label': 'Pants', 'svg': _pantsIcon},
    {'key': 'shoes', 'label': 'Shoes', 'svg': _shoeIcon},
  ];

  void _selectColor(Color color) {
    setState(() {
      switch (_activeCategory) {
        case 'skin':
          _config = _config.copyWith(skinColor: color);
          break;
        case 'hair':
          _config = _config.copyWith(hairColor: color);
          break;
        case 'shirt':
          _config = _config.copyWith(shirtColor: color);
          break;
        case 'pants':
          _config = _config.copyWith(pantsColor: color);
          break;
        case 'shoes':
          _config = _config.copyWith(shoesColor: color);
          break;
      }
    });
  }

  Color get _currentSelection {
    switch (_activeCategory) {
      case 'skin':
        return _config.skinColor;
      case 'hair':
        return _config.hairColor;
      case 'shirt':
        return _config.shirtColor;
      case 'pants':
        return _config.pantsColor;
      case 'shoes':
        return _config.shoesColor;
      default:
        return Colors.transparent;
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      // PUT /users/me/avatar with _config.toJson() (skin, hair, shirt, pants, shoes)
      await _avatarService.saveMyAvatar(_config);
      // Boy/girl is remembered on this phone (the backend can't store it yet).
      await AvatarGenderStore.save(_gender);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Avatar saved!')));
      if (widget.isFirstSetup) {
        // Sign Up -> Avatar -> Home: replace the whole stack so the back
        // button can't return to Sign Up or Login.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(config: _config)),
              (route) => false,
        );
      } else {
        // Opened from Home: close and send the new look back.
        Navigator.pop(context, _config);
      }
    } catch (e) {
      debugPrint('Avatar save failed: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save avatar. Please try again.'),
        ),
      );
    }
  }

  // The icon of a category tab: an SVG for clothes, a Material icon otherwise.
  Widget _categoryIcon(Map<String, dynamic> cat, Color color) {
    final svg = cat['svg'] as String?;
    if (svg != null) {
      return SvgPicture.string(
        svg,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }
    return Icon(cat['icon'] as IconData, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final colors = _categoryColors[_activeCategory]!;

    return PopScope(
      // After Sign Up, don't let the back button return to the Sign Up form.
      canPop: !widget.isFirstSetup,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          automaticallyImplyLeading: !widget.isFirstSetup,
          title: Text(
            'Make It Yours!',
            style: TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.bold,
            ),
          ),
          iconTheme: IconThemeData(color: AppColors.textDark),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Character preview: full width, takes all the space above
              // the controls, so the character is as big as possible.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(154, 211, 211, 209),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    child: Center(
                      child: CharacterPreview(
                        config: _config,
                        gender: _gender,
                        level: widget.level,
                      ),
                    ),
                  ),
                ),
              ),

              // ---- Controls, grouped together above the Save button ----

              // Girl / Boy switch
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AvatarGender>(
                    segments: const [
                      ButtonSegment(
                        value: AvatarGender.girl,
                        label: Text('Girl'),
                        icon: Icon(Icons.female_rounded),
                      ),
                      ButtonSegment(
                        value: AvatarGender.boy,
                        label: Text('Boy'),
                        icon: Icon(Icons.male_rounded),
                      ),
                    ],
                    selected: {_gender},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        setState(() => _gender = selection.first),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.primary,
                      selectedForegroundColor: Colors.white,
                      foregroundColor: AppColors.textDark,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Category tabs: all 5 fit the screen width (no sideways scroll)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (var i = 0; i < _categories.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _buildCategoryTab(_categories[i]),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Colour circles for the selected category
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final color in colors)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _buildSwatch(color),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Save button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.primary.withOpacity(
                        0.6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                        : const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTab(Map<String, dynamic> cat) {
    final isActive = _activeCategory == cat['key'];
    final foreground = isActive ? Colors.white : AppColors.textDark;

    return GestureDetector(
      onTap: () => setState(() => _activeCategory = cat['key']),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? AppColors.primary : GrowyPalette.hairline,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _categoryIcon(cat, foreground),
            const SizedBox(height: 4),
            Text(
              cat['label'],
              style: TextStyle(
                fontSize: 12,
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwatch(Color color) {
    final isSelected = _currentSelection.value == color.value;

    return GestureDetector(
      onTap: () => _selectColor(color),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.primary : GrowyPalette.hairline,
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.4),
              blurRadius: 8,
            ),
          ]
              : null,
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white)
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small clothing icons (24 × 24). Drawn in one colour; the tab recolours them
// (white when selected, dark otherwise), just like the Material icons.
// ---------------------------------------------------------------------------

/// T-shirt.
const String _shirtIcon =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path fill="#000" d="M8.5 3L4 5.2L1.5 9.5L4.5 11.3L6 10V21H18V10'
    'L19.5 11.3L22.5 9.5L20 5.2L15.5 3C14.9 4.6 13.6 5.6 12 5.6'
    'C10.4 5.6 9.1 4.6 8.5 3Z"/>'
    '</svg>';

/// Pants: waistband + two legs.
const String _pantsIcon =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path fill="#000" d="M6 2H18V4.2H6Z"/>'
    '<path fill="#000" d="M6 5.2H18L19.5 22H14.2L12 10L9.8 22H4.5Z"/>'
    '</svg>';

/// Sneaker (side view) with its sole.
const String _shoeIcon =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">'
    '<path fill="#000" d="M2 12.5C2 11.4 2.9 10.5 4 10.5H8.2L10.4 12.6'
    'C12 14 13.8 14.6 16 14.9L19.4 15.4C21 15.6 22 16.7 22 18V18.2H2Z"/>'
    '<path fill="#000" d="M2 19.4H22V21H2Z"/>'
    '</svg>';