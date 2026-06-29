class GameRecord {
  final int score;
  final int level;
  final DateTime timestamp;
  final int survivalSeconds;
  final int revengeKills;
  final int bestCombo;

  GameRecord({
    required this.score,
    required this.level,
    required this.timestamp,
    this.survivalSeconds = 0,
    this.revengeKills = 0,
    this.bestCombo = 0,
  });

  Map<String, dynamic> toJson() => {
    'score': score,
    'level': level,
    'timestamp': timestamp.toIso8601String(),
    'survivalSeconds': survivalSeconds,
    'revengeKills': revengeKills,
    'bestCombo': bestCombo,
  };

  factory GameRecord.fromJson(Map<String, dynamic> json) => GameRecord(
    score: json['score'] as int,
    level: json['level'] as int,
    timestamp: DateTime.parse(json['timestamp'] as String),
    survivalSeconds: json['survivalSeconds'] as int? ?? 0,
    revengeKills: json['revengeKills'] as int? ?? 0,
    bestCombo: json['bestCombo'] as int? ?? 0,
  );

  String get displayDate {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return '剛剛';
    if (diff.inHours < 1) return '${diff.inMinutes} 分鐘前';
    if (diff.inDays < 1) return '${diff.inHours} 小時前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${timestamp.month}/${timestamp.day}';
  }
}
