class SkillDef {
  const SkillDef({
    required this.level,
    required this.name,
    required this.fishName,
    required this.cooldown,
    required this.effectDesc,
  });

  final int level;
  final String name;
  final String fishName;
  final double cooldown;
  final String effectDesc;

  static const List<SkillDef> all = [
    SkillDef(
      level: 1,
      name: '閃避衝刺',
      fishName: '小魚苗',
      cooldown: 8,
      effectDesc: '瞬間衝刺 3x 體型，穿越無敵',
    ),
    SkillDef(
      level: 2,
      name: '魚群呼喚',
      fishName: '熱帶魚',
      cooldown: 15,
      effectDesc: '召喚 5 隻小魚跟隨 8 秒，可吃',
    ),
    SkillDef(
      level: 3,
      name: '膨脹防禦',
      fishName: '河豚',
      cooldown: 20,
      effectDesc: '體型 3x 持續 2s，碰到自己的魚被彈開',
    ),
    SkillDef(
      level: 4,
      name: '血性狂咬',
      fishName: '鯊魚',
      cooldown: 12,
      effectDesc: '3s 內吃魚範圍 +50%，每吃一條 CD -0.5s',
    ),
    SkillDef(
      level: 5,
      name: '聲波震盪',
      fishName: '虎鯨',
      cooldown: 25,
      effectDesc: '同心圓震波，範圍內魚減速 70% 3s',
    ),
  ];

  static SkillDef? forLevel(int level) {
    if (level < 1 || level > all.length) return null;
    return all[level - 1];
  }

  static bool hasSkill(int level) => level >= 1 && level <= all.length;
}
