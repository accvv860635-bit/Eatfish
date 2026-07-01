/// 技能組定義 — 5 組技能，每組對應多個等級
/// 技能槽索引 0-4 = 等級範圍 [1-3], [4-6], [7-9], [10-12], [13-18]
class SkillGroup {
  const SkillGroup({
    required this.index,
    required this.name,
    required this.icon,
    required this.cooldown,
    required this.levelRange,
    required this.tierNames,
    required this.tierDescs,
  });

  /// 0-based group index
  final int index;
  final String name;
  final String icon;
  final double cooldown;
  /// [minLevel, maxLevel] inclusive
  final List<int> levelRange;
  /// Tier names for each sub-level within this group
  final List<String> tierNames;
  final List<String> tierDescs;

  int get minLevel => levelRange[0];
  int get maxLevel => levelRange[1];

  /// Which tier (0-based) the player has within this group at [playerLevel]
  int tierAt(int playerLevel) {
    if (playerLevel < minLevel) return -1;
    return (playerLevel - minLevel).clamp(0, tierNames.length - 1);
  }

  /// Whether this skill group is unlocked at [playerLevel]
  bool isUnlocked(int playerLevel) => playerLevel >= minLevel;

  static const List<SkillGroup> all = [
    SkillGroup(
      index: 0,
      name: '閃避衝刺',
      icon: '⚡',
      cooldown: 8,
      levelRange: [1, 3],
      tierNames: ['衝刺', '衝刺+召喚', '衝刺+膨脹'],
      tierDescs: ['向前衝刺 3x 體長', '衝刺 + 召喚 3 隻小魚', '衝刺 + 體型 3x 2s'],
    ),
    SkillGroup(
      index: 1,
      name: '血性狂咬',
      icon: '🦈',
      cooldown: 10,
      levelRange: [4, 6],
      tierNames: ['狂咬', '狂咬+聲波', '狂咬強化'],
      tierDescs: ['吃魚範圍+50% 3s', '狂咬+聲波震盪緩速', '吃魚範圍+80% CD減更多'],
    ),
    SkillGroup(
      index: 2,
      name: '渦流吸引',
      icon: '🌪',
      cooldown: 14,
      levelRange: [7, 9],
      tierNames: ['吸引', '吸引+緩速', '吸引擴大'],
      tierDescs: ['拉近周圍魚群 3s', '被拉魚減速 70%', '範圍加大 + 拉力更強'],
    ),
    SkillGroup(
      index: 3,
      name: '深淵怒吼',
      icon: '💥',
      cooldown: 18,
      levelRange: [10, 12],
      tierNames: ['震懾', '震懾+擊退', '擊殺'],
      tierDescs: ['全屏魚暈眩 1.5s', '暈眩+擊退 200px', '低 2 等魚直接擊殺'],
    ),
    SkillGroup(
      index: 4,
      name: '狂暴獵殺',
      icon: '🔥',
      cooldown: 20,
      levelRange: [13, 18],
      tierNames: ['狂暴', '狂暴+無敵', '極限狂暴', '超極限', '終極', '神級'],
      tierDescs: [
        '速1.5x 吃魚1.5x 4s',
        '期間無敵',
        '速2x 吃魚2x 4s',
        '速2.5x 吃魚2.5x 4s',
        '速3x 吃魚3x 3s',
        '速3x 吃魚3x + 全屏擊殺 4s',
      ],
    ),
  ];

  /// Get a specific group by its index (0-4)
  static SkillGroup? byIndex(int index) {
    if (index < 0 || index >= all.length) return null;
    return all[index];
  }
}
