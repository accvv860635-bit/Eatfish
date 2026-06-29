import 'dart:ui';

enum ObstacleType {
  hook,
  whirlpool,
  aiShark,
  poisonTide,
  reef,
  current,
}

class Obstacle {
  Obstacle({
    required this.type,
    required this.position,
    this.radius = 60,
    this.lifetime = 5,
    this.timer = 0,
    this.angle = 0,
    this.width = 120,
    this.height = 120,
    this.targetOffset = Offset.zero,
  });

  ObstacleType type;
  Offset position;
  double radius;
  double lifetime;
  double timer;
  double angle;
  double width;
  double height;
  Offset targetOffset;
  Offset velocity = Offset.zero;

  bool get blocksMovement =>
      type == ObstacleType.reef || type == ObstacleType.current;
}
