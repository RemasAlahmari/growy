import 'package:flutter/material.dart';
import '../models/character_config.dart';
import '../theme/app_theme.dart';
import '../widgets/character_preview.dart';

class AvatarCustomizerScreen extends StatefulWidget {
  const AvatarCustomizerScreen({super.key});

  @override
  State<AvatarCustomizerScreen> createState() => _AvatarCustomizerScreenState();
}

class _AvatarCustomizerScreenState extends State<AvatarCustomizerScreen> {
  CharacterConfig _config = CharacterConfig.defaultConfig();
  String _activeCategory = 'skin';

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

  final List<Map<String, dynamic>> _categories = const [
    {'key': 'skin', 'label': 'Skin', 'icon': Icons.face},
    {'key': 'hair', 'label': 'Hair', 'icon': Icons.content_cut},
    {'key': 'shirt', 'label': 'Shirt', 'icon': Icons.checkroom},
    {'key': 'pants', 'label': 'Pants', 'icon': Icons.dry_cleaning},
    {'key': 'shoes', 'label': 'Shoes', 'icon': Icons.hiking},
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

  void _handleSave() {
    // TODO: send _config.toJson() to your FastAPI backend
    // e.g. PUT /avatars/{id}/customization
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Avatar saved!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Customize Growy',
          style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Character preview
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 2),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: CharacterPreview(config: _config),
                ),
              ),
            ),

            // Category tabs
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isActive = _activeCategory == cat['key'];
                  return GestureDetector(
                    onTap: () => setState(() => _activeCategory = cat['key']),
                    child: Container(
                      width: 72,
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive ? AppColors.primary : Colors.black12,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            cat['icon'],
                            color: isActive ? Colors.white : AppColors.textDark,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cat['label'],
                            style: TextStyle(
                              fontSize: 12,
                              color: isActive ? Colors.white : AppColors.textDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Color swatch grid
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                  ),
                  itemCount: _categoryColors[_activeCategory]!.length,
                  itemBuilder: (context, index) {
                    final color = _categoryColors[_activeCategory]![index];
                    final isSelected = _currentSelection.value == color.value;
                    return GestureDetector(
                      onTap: () => _selectColor(color),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? AppColors.primary : Colors.black12,
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
                  },
                ),
              ),
            ),

            // Save button
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _handleSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
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
    );
  }
}