/// There are 5 levels (0–4, decided by the backend). Each level has its own
/// avatar stage, 1–5:  Level 0 → stage 1 · Level 1 → stage 2 · … · Level 4 → stage 5.
/// Asset files are named character_lvl1.svg … character_lvl5.svg.
///
/// Add a stage number to [kAvailableAvatarStages] once its SVG exists.
/// Until then, a level shows the highest stage that does exist, instead of
/// crashing on a missing asset file.

const List<int> kAvailableAvatarStages = [1];

String avatarAssetForLevel(int level) {
  final targetStage = level.clamp(0, 4) + 1;
  final availableStage = kAvailableAvatarStages
      .where((s) => s <= targetStage)
      .fold<int>(1, (best, s) => s > best ? s : best);
  return 'assets/character/character_lvl$availableStage.svg';
}
