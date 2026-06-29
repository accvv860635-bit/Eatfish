import 'dart:ui';

enum PowerUpType {
  boost,
  magnet,
  shield,
  poison,
  doubleScore,
  vortex,
  star,
}

class PowerUp {
  PowerUp({
    required this.type,
    required this.position,
    this.lifetime = 60,
    this.timer = 0,
  });

  PowerUpType type;
  Offset position;
  double lifetime;
  double timer;

  String get label {
    switch (type) {
      case PowerUpType.boost:
        return '⚡';
      case PowerUpType.magnet:
        return '🧲';
      case PowerUpType.shield:
        return '🛡';
      case PowerUpType.poison:
        return '💀';
      case PowerUpType.doubleScore:
        return '✨';
      case PowerUpType.vortex:
        return '🌪';
      case PowerUpType.star:
        return '💎';
    }
  }

  double get radius => 22;
}

class ActiveEffect {
  ActiveEffect({
    required this.type,
    required this.remaining,
  });

  PowerUpType type;
  double remaining;
}
