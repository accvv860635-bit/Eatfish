import 'dart:ui';

enum FishBehaviorState {
  wander,
  flee,
  hide,
  warn,
  chase,
  attack,
  rest,
  stunned,
}

class FishEntity {
  FishEntity({
    required this.position,
    required this.velocity,
    required this.level,
    required this.depth,
    required this.sizeScale,
    required this.speedScale,
    required this.predator,
    required this.chaseTimer,
    required this.restTimer,
    required this.wanderTimer,
    this.behaviorState = FishBehaviorState.wander,
    this.attackWindup = 0,
    this.attackCooldown = 0,
    this.biteProgress = 0,
    this.hiddenTimer = 0,
    this.stunnedTimer = 0,
  });

  Offset position;
  Offset velocity;
  int level;
  double depth;
  double sizeScale;
  double speedScale;
  bool predator;
  double chaseTimer;
  double restTimer;
  double wanderTimer;
  FishBehaviorState behaviorState;
  double attackWindup;
  double attackCooldown;
  double biteProgress;
  double hiddenTimer;
  double stunnedTimer;
}
