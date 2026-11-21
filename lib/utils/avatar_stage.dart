/// Which avatar SVG to show for a gender + backend level.
///
/// The backend has 4 levels (1–4, see home_screen.dart: 0 / 500 / 1500 /
/// 3000 XP). There are 4 character stages per gender, so the stage is the
/// same as the level. The character changes at 500, 1500 and 3000 XP.
///
///   Level 1 → stage 1 · Level 2 → stage 2
///   Level 3 → stage 3 · Level 4 → stage 4
///
/// Files: assets/character/girl_character_lvl1.svg … girl_character_lvl4.svg
///        assets/character/boy_character_lvl1.svg  … boy_character_lvl4.svg
/// All are 520 × 820, feet at y = 800, body centre at x = 260.

enum AvatarGender { girl, boy }

/// Size of every avatar SVG frame.
const double kAvatarFrameWidth = 520;
const double kAvatarFrameHeight = 820;
const double kAvatarAspectRatio = kAvatarFrameWidth / kAvatarFrameHeight;

/// Character stage (1–4) for a backend level (1–4): the same number.
/// Out-of-range levels are clamped (e.g. an old 0 shows stage 1).
int avatarStageForLevel(int level) => level.clamp(1, 4);

/// Asset path for a gender + backend level,
/// e.g. (girl, 2) → 'assets/character/girl_character_lvl2.svg'.
String avatarAssetFor(AvatarGender gender, int level) =>
    'assets/character/${gender.name}_character_lvl${avatarStageForLevel(level)}.svg';