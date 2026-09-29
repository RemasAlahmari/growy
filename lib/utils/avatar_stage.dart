/// There are 4 levels each level has it's own stage of the avatar from 1-5
///  Levels above the highest number here just keep showing that highest
/// stage instead of crashing on a missing asset file.

const List<int> kAvailableAvatarStages = [1];
String avatarAssetForLevel(int level) {
  final targetStage = level.clamp(1, 4);
  final availableStage = kAvailableAvatarStages
      .where((s) => s <= targetStage)
      .fold<int>(1, (best, s) => s > best ? s : best);
  return 'assets/character/character_lvl$availableStage.svg';
}