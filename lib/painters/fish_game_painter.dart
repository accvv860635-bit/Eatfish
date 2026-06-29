import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/fish_entity.dart';
import '../models/fish_spec.dart';
import '../models/obstacle.dart';
import '../models/power_up.dart';
import '../models/seaweed_patch.dart';

class FishGamePainter extends CustomPainter {
  FishGamePainter({
    required this.fishImage,
    required this.fish,
    required this.player,
    required this.playerLevel,
    required this.playerHeading,
    required this.playerHidden,
    required this.playerBite,
    required this.seaweed,
    required this.fishLength,
    required this.camera,
    required this.zoom,
    required this.world,
    required this.screen,
    this.powerUps = const [],
    this.obstacles = const [],
    this.activeEffects = const [],
    this.isBoosting = false,
    this.poisonTrail = const [],
    this.playerSizeMultiplier = 1.0,
    this.sonicWaveRadius = 0,
    this.isInvincible = false,
    this.skillL3Active = false,
  });

  final ui.Image fishImage;
  final List<FishEntity> fish;
  final Offset player;
  final int playerLevel;
  final Offset playerHeading;
  final bool playerHidden;
  final double playerBite;
  final List<SeaweedPatch> seaweed;
  final double Function(int level) fishLength;
  final Offset camera;
  final double zoom;
  final Size world;
  final Size screen;
  final List<PowerUp> powerUps;
  final List<Obstacle> obstacles;
  final List<ActiveEffect> activeEffects;
  final bool isBoosting;
  final List<Offset> poisonTrail;
  final double playerSizeMultiplier;
  final double sonicWaveRadius;
  final bool isInvincible;
  final bool skillL3Active;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(zoom);
    canvas.translate(-camera.dx, -camera.dy);

    _drawSeaweed(canvas, front: false);

    // Draw obstacles (behind fish)
    for (final obs in obstacles) {
      if (!_isInView(obs.position)) continue;
      _drawObstacle(canvas, obs);
    }

    // Draw poison trail
    if (poisonTrail.isNotEmpty) {
      _drawPoisonTrail(canvas);
    }

    // Draw power-ups
    for (final pu in powerUps) {
      if (!_isInView(pu.position)) continue;
      _drawPowerUp(canvas, pu);
    }

    // Draw sonic wave
    if (sonicWaveRadius > 0) {
      _drawSonicWave(canvas);
    }

    final ordered = [...fish]..sort((a, b) => a.depth.compareTo(b.depth));
    for (final entity in ordered) {
      if (!_isInView(entity.position)) continue;

      final scale = ui.lerpDouble(.94, 1.04, entity.depth)!;
      final hiddenFade = ui.lerpDouble(1, 0, entity.hiddenTimer)!;
      final opacity = ui.lerpDouble(.36, .9, entity.depth)! * hiddenFade;
      if (opacity <= .02) continue;
      final tint = entity.level > playerLevel
          ? const Color(0xffe8f4ff)
          : const Color(0xffa8d8ef);
      _drawFish(
        canvas,
        entity.position,
        entity.velocity,
        fishLength(entity.level) * entity.sizeScale * scale,
        opacity,
        tint,
        entity.level,
        entity.predator && entity.level > playerLevel,
        behaviorState: entity.behaviorState,
        bite: entity.biteProgress,
      );
    }

    // Player shield glow
    if (activeEffects.any((e) => e.type == PowerUpType.shield)) {
      canvas.drawCircle(
        player,
        fishLength(playerLevel) * .7,
        Paint()
          ..color = const Color(0xff2196f3).withValues(alpha: .2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }

    // Player star glow
    if (activeEffects.any((e) => e.type == PowerUpType.star)) {
      canvas.drawCircle(
        player,
        fishLength(playerLevel) * .7,
        Paint()
          ..color = const Color(0xffffd700).withValues(alpha: .3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }

    // Player invincible glow
    if (isInvincible) {
      canvas.drawCircle(
        player,
        fishLength(playerLevel) * .65,
        Paint()
          ..color = const Color(0xffffff00).withValues(alpha: .25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    // Boost trail
    if (isBoosting) {
      final trailPaint = Paint()
        ..color = const Color(0xff00e5ff).withValues(alpha: .35);
      final trailStart = player - playerHeading * fishLength(playerLevel) * .5;
      canvas.drawCircle(trailStart, fishLength(playerLevel) * .18, trailPaint);
      canvas.drawCircle(
        trailStart - playerHeading * fishLength(playerLevel) * .25,
        fishLength(playerLevel) * .12,
        trailPaint..color = const Color(0xff00e5ff).withValues(alpha: .18),
      );
    }

    _drawFish(
      canvas,
      player,
      playerHeading,
      fishLength(playerLevel) * 1.16 * playerSizeMultiplier,
      playerHidden ? .25 : 1,
      const Color(0xffffffff),
      playerLevel,
      false,
      isPlayer: true,
      bite: playerBite,
      isInvincible: isInvincible,
      isShielded: activeEffects.any((e) => e.type == PowerUpType.shield),
      isStar: activeEffects.any((e) => e.type == PowerUpType.star),
    );

    // Skill L3 inflate ring
    if (skillL3Active) {
      canvas.drawCircle(
        player,
        fishLength(playerLevel) * 1.8,
        Paint()
          ..color = const Color(0xffff9800).withValues(alpha: .3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    _drawSeaweed(canvas, front: true);

    canvas.restore();
  }

  bool _isInView(Offset worldPos) {
    const buffer = 200.0;
    final visibleWidth = screen.width / zoom;
    final visibleHeight = screen.height / zoom;
    return worldPos.dx > camera.dx - buffer &&
        worldPos.dx < camera.dx + visibleWidth + buffer &&
        worldPos.dy > camera.dy - buffer &&
        worldPos.dy < camera.dy + visibleHeight + buffer;
  }

  void _drawFish(
    Canvas canvas,
    Offset center,
    Offset direction,
    double length,
    double opacity,
    Color tint,
    int level,
    bool predator, {
    bool isPlayer = false,
    double bite = 0,
    FishBehaviorState behaviorState = FishBehaviorState.wander,
    bool isInvincible = false,
    bool isShielded = false,
    bool isStar = false,
  }) {
    final angle = atan2(direction.dy, direction.dx);
    final height = length * .44;
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: length,
      height: height,
    );
    final paint = Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.mode(
        tint.withValues(alpha: isPlayer ? .08 : .2),
        BlendMode.srcATop,
      );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawShadow(
      Path()..addOval(rect.inflate(-length * .18)),
      Colors.black.withValues(alpha: .55),
      isPlayer ? 8 : 4,
      false,
    );

    // Star/invincible player tint
    if (isPlayer && isStar) {
      final starPaint = Paint()
        ..color = const Color(0xffffd700).withValues(alpha: .35);
      canvas.drawRect(rect, starPaint);
    } else if (isPlayer && isShielded) {
      final shieldPaint = Paint()
        ..color = const Color(0xff448aff).withValues(alpha: .25);
      canvas.drawRect(rect, shieldPaint);
    }

    if (level >= 15) {
      _drawMonsterFish(canvas, rect, level, opacity, bite);
    } else {
      canvas.drawImageRect(
        fishImage,
        _sourceRectForLevel(level),
        _imageRectForLevel(rect, level),
        paint..color = Colors.white.withValues(alpha: opacity),
      );
    }
    if (bite > 0.02) {
      _drawBiteFlash(canvas, rect, length, bite, opacity);
    }
    canvas.restore();

    if (opacity > .02 && behaviorState == FishBehaviorState.warn) {
      _drawWarning(canvas, center, height, opacity);
    }

    if (opacity <= .02) return;
    final badgePaint = Paint()
      ..color = (predator ? const Color(0xffff3b4f) : const Color(0xffd6f7ff))
          .withValues(alpha: isPlayer ? .96 : .72);
    canvas.drawCircle(
      center + Offset(0, -height * .66),
      isPlayer ? 13 : 9,
      badgePaint,
    );
    _drawCenteredText(
      canvas,
      '$level',
      center + Offset(0, -height * .66),
      isPlayer ? 14 : 10,
      predator ? Colors.white : const Color(0xff05212c),
      FontWeight.w800,
    );
  }

  Rect _sourceRectForLevel(int level) {
    return _levelSourceRects[level.clamp(1, _levelSourceRects.length) - 1];
  }

  Rect _imageRectForLevel(Rect bodyRect, int level) {
    final source = _sourceRectForLevel(level);
    final sourceAspect = source.height / source.width;
    return Rect.fromCenter(
      center: bodyRect.center,
      width: bodyRect.width,
      height: bodyRect.width * sourceAspect,
    );
  }

  static final List<Rect> _levelSourceRects = [
    Rect.fromLTWH(72.0, 197.0, 186.0, 49.0),
    Rect.fromLTWH(359.0, 166.0, 198.0, 108.0),
    Rect.fromLTWH(652.0, 178.0, 200.0, 103.0),
    Rect.fromLTWH(947.0, 164.0, 214.0, 108.0),
    Rect.fromLTWH(1271.0, 155.0, 179.0, 131.0),
    Rect.fromLTWH(30.0, 454.0, 250.0, 74.0),
    Rect.fromLTWH(332.0, 422.0, 228.0, 131.0),
    Rect.fromLTWH(614.0, 427.0, 269.0, 128.0),
    Rect.fromLTWH(926.0, 441.0, 294.0, 105.0),
    Rect.fromLTWH(1228.0, 453.0, 286.0, 79.0),
    Rect.fromLTWH(8.0, 720.0, 292.0, 130.0),
    Rect.fromLTWH(316.0, 710.0, 298.0, 142.0),
    Rect.fromLTWH(614.0, 704.0, 307.0, 151.0),
    Rect.fromLTWH(921.0, 719.0, 307.0, 132.0),
    Rect.fromLTWH(1228.0, 725.0, 306.0, 128.0),
  ];

  void _drawMonsterFish(
    Canvas canvas,
    Rect rect,
    int level,
    double opacity,
    double bite,
  ) {
    final spec = FishSpecs.byLevel(level);
    final bodyColor = switch (level) {
      15 => const Color(0xff2d3540),
      16 => const Color(0xff172531),
      17 => const Color(0xff3b4650),
      _ => const Color(0xff18202b),
    };
    final bellyColor = switch (level) {
      15 => const Color(0xff8c9499),
      16 => const Color(0xff647f91),
      17 => const Color(0xff879196),
      _ => const Color(0xff556579),
    };
    final mouthOpen = bite.clamp(0.0, 1.0);
    final bodyPaint = Paint()
      ..isAntiAlias = true
      ..color = bodyColor.withValues(alpha: opacity);
    final bellyPaint = Paint()
      ..isAntiAlias = true
      ..color = bellyColor.withValues(alpha: opacity * .72);

    final bodyPath = Path()
      ..moveTo(rect.left + rect.width * .08, 0)
      ..cubicTo(
        rect.left + rect.width * .22,
        rect.top + rect.height * .05,
        rect.left + rect.width * .64,
        rect.top - rect.height * .04,
        rect.right - rect.width * .08,
        -rect.height * .05,
      )
      ..cubicTo(
        rect.right + rect.width * .06,
        -rect.height * .02,
        rect.right + rect.width * .04,
        rect.height * .2,
        rect.right - rect.width * .04,
        rect.height * .26,
      )
      ..cubicTo(
        rect.left + rect.width * .62,
        rect.bottom + rect.height * .05,
        rect.left + rect.width * .26,
        rect.bottom - rect.height * .04,
        rect.left + rect.width * .08,
        0,
      )
      ..close();
    canvas.drawPath(bodyPath, bodyPaint);

    final bellyPath = Path()
      ..moveTo(rect.left + rect.width * .2, rect.height * .14)
      ..cubicTo(
        rect.left + rect.width * .42,
        rect.height * .34,
        rect.left + rect.width * .72,
        rect.height * .36,
        rect.right - rect.width * .11,
        rect.height * .18,
      )
      ..cubicTo(
        rect.left + rect.width * .68,
        rect.height * .56,
        rect.left + rect.width * .34,
        rect.height * .5,
        rect.left + rect.width * .2,
        rect.height * .14,
      )
      ..close();
    canvas.drawPath(bellyPath, bellyPaint);

    final tail = Path()
      ..moveTo(rect.left + rect.width * .04, 0)
      ..lineTo(rect.left - rect.width * .18, -rect.height * .48)
      ..lineTo(rect.left - rect.width * .1, 0)
      ..lineTo(rect.left - rect.width * .18, rect.height * .48)
      ..close();
    canvas.drawPath(tail, bodyPaint);

    final finPaint = Paint()
      ..isAntiAlias = true
      ..color = bodyColor.withValues(alpha: opacity * .9);
    if (level != 15) {
      canvas.drawPath(
        Path()
          ..moveTo(rect.left + rect.width * .45, rect.top + rect.height * .08)
          ..lineTo(rect.left + rect.width * .25, rect.top - rect.height * .34)
          ..lineTo(rect.left + rect.width * .62, rect.top + rect.height * .2)
          ..close(),
        finPaint,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(rect.left + rect.width * .42, rect.height * .22)
        ..lineTo(rect.left + rect.width * .24, rect.height * .62)
        ..lineTo(rect.left + rect.width * .58, rect.height * .33)
        ..close(),
      finPaint,
    );

    final mouthX = rect.right - rect.width * .03;
    final mouthGap = level == 15
        ? rect.height * (.08 + .1 * mouthOpen)
        : rect.height * (.18 + .32 * mouthOpen);
    final jawPaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xff06080b).withValues(alpha: opacity * .9);
    if (level == 15) {
      canvas.drawArc(
        Rect.fromLTWH(
          rect.right - rect.width * .22,
          -mouthGap,
          rect.width * .18,
          mouthGap * 2,
        ),
        -pi / 3,
        pi * .66,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(2, rect.height * .035)
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xff0b0d10).withValues(alpha: opacity * .7),
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(mouthX, -mouthGap)
          ..lineTo(rect.right - rect.width * .25, -rect.height * .16)
          ..lineTo(rect.right - rect.width * .12, 0)
          ..lineTo(mouthX, mouthGap)
          ..close(),
        jawPaint,
      );
      final teethPaint = Paint()
        ..isAntiAlias = true
        ..color = Colors.white.withValues(alpha: opacity * .82);
      for (var i = 0; i < 5; i++) {
        final tx = rect.right - rect.width * (.08 + i * .035);
        canvas.drawPath(
          Path()
            ..moveTo(tx, -mouthGap * .72)
            ..lineTo(tx - rect.width * .012, -mouthGap * .25)
            ..lineTo(tx + rect.width * .014, -mouthGap * .25)
            ..close(),
          teethPaint,
        );
      }
    }

    if (level >= 16) {
      final gillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.3, rect.height * .018)
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xff05090c).withValues(alpha: opacity * .32);
      for (var i = 0; i < 4; i++) {
        final x = rect.right - rect.width * (.31 + i * .025);
        canvas.drawLine(
          Offset(x, -rect.height * .18),
          Offset(x - rect.width * .025, rect.height * .16),
          gillPaint,
        );
      }
    } else {
      final spotsPaint = Paint()
        ..isAntiAlias = true
        ..color = Colors.white.withValues(alpha: opacity * .12);
      for (var i = 0; i < 9; i++) {
        canvas.drawCircle(
          Offset(
            rect.left + rect.width * (.22 + i * .06),
            -rect.height * (.18 + (i % 3) * .035),
          ),
          max(1.8, rect.height * .025),
          spotsPaint,
        );
      }
    }

    final eyePaint = Paint()
      ..isAntiAlias = true
      ..color = (spec.boss ? const Color(0xffff465a) : const Color(0xffffd75c))
          .withValues(alpha: opacity);
    canvas.drawCircle(
      Offset(rect.right - rect.width * .22, -rect.height * .17),
      max(2.4, rect.height * .045),
      eyePaint,
    );
  }

  void _drawBiteFlash(
    Canvas canvas,
    Rect rect,
    double length,
    double bite,
    double opacity,
  ) {
    final mouth = Offset(rect.right - length * .05, 0);
    final flashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(2, length * .025)
      ..color = const Color(0xffffeff2).withValues(alpha: opacity * bite * .72);
    canvas.drawArc(
      Rect.fromCircle(center: mouth, radius: length * (.18 + .08 * bite)),
      -pi / 2,
      pi,
      false,
      flashPaint,
    );
  }

  void _drawWarning(
    Canvas canvas,
    Offset center,
    double height,
    double opacity,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xffff4058).withValues(alpha: opacity * .85);
    canvas.drawCircle(center, height * 1.15, paint);
  }

  // ─── Power-up rendering ───

  void _drawPowerUp(Canvas canvas, PowerUp pu) {
    final pulse = sin(pu.timer * 3) * .25 + .75;
    Color glowColor;
    switch (pu.type) {
      case PowerUpType.boost:
        glowColor = const Color(0xff00bcd4);
        break;
      case PowerUpType.magnet:
        glowColor = const Color(0xff9c27b0);
        break;
      case PowerUpType.shield:
        glowColor = const Color(0xff2196f3);
        break;
      case PowerUpType.poison:
        glowColor = const Color(0xff4caf50);
        break;
      case PowerUpType.doubleScore:
        glowColor = const Color(0xffffc107);
        break;
      case PowerUpType.vortex:
        glowColor = const Color(0xff607d8b);
        break;
      case PowerUpType.star:
        glowColor = const Color(0xffff4081);
        break;
    }

    // Outer glow
    canvas.drawCircle(
      pu.position,
      pu.radius * (1.2 + pulse * .3),
      Paint()
        ..color = glowColor.withValues(alpha: .2 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Orb body
    canvas.drawCircle(
      pu.position,
      pu.radius * pulse,
      Paint()
        ..color = glowColor.withValues(alpha: .7)
        ..style = PaintingStyle.fill,
    );

    // Inner highlight
    canvas.drawCircle(
      pu.position,
      pu.radius * .5 * pulse,
      Paint()..color = Colors.white.withValues(alpha: .6),
    );

    // Label
    _drawCenteredText(
      canvas,
      pu.label,
      pu.position,
      15,
      Colors.white,
      FontWeight.w900,
    );
  }

  // ─── Obstacle rendering ───

  void _drawObstacle(Canvas canvas, Obstacle obs) {
    switch (obs.type) {
      case ObstacleType.hook:
        _drawHook(canvas, obs);
        break;
      case ObstacleType.whirlpool:
        _drawWhirlpool(canvas, obs);
        break;
      case ObstacleType.aiShark:
        _drawAiShark(canvas, obs);
        break;
      case ObstacleType.poisonTide:
        _drawPoisonTideObs(canvas, obs);
        break;
      case ObstacleType.reef:
        _drawReef(canvas, obs);
        break;
      case ObstacleType.current:
        _drawCurrent(canvas, obs);
        break;
    }
  }

  void _drawHook(Canvas canvas, Obstacle obs) {
    final dropY = obs.position.dy + obs.timer * 180;
    if (dropY > world.height * .9) return;

    final hookPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xff8899aa);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xff556677).withValues(alpha: .7);

    // Line from top
    canvas.drawLine(
      Offset(obs.position.dx, 0),
      Offset(obs.position.dx, dropY),
      linePaint,
    );

    // Hook shape
    final path = Path()
      ..moveTo(obs.position.dx - obs.width * .3, dropY - obs.height * .5)
      ..cubicTo(
        obs.position.dx - obs.width * .2,
        dropY + obs.height * .2,
        obs.position.dx + obs.width * .2,
        dropY + obs.height * .3,
        obs.position.dx + obs.width * .1,
        dropY - obs.height * .2,
      );
    canvas.drawPath(path, hookPaint);

    // Warning glow
    canvas.drawCircle(
      Offset(obs.position.dx, dropY),
      30,
      Paint()
        ..color = const Color(0xffff4444).withValues(alpha: .15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  void _drawWhirlpool(Canvas canvas, Obstacle obs) {
    final anim = sin(obs.timer * 2) * .5 + .5;
    final center = obs.position;

    for (var i = 0; i < 3; i++) {
      final r = obs.radius * (.5 + .15 * i) * (.8 + anim * .2);
      canvas.drawCircle(
        center + Offset(sin(obs.timer + i) * 8, cos(obs.timer + i) * 8),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xff4488aa).withValues(
            alpha: .4 - i * .1,
          ),
      );
    }
    canvas.drawCircle(
      center,
      12,
      Paint()..color = const Color(0xff1a3344).withValues(alpha: .6),
    );
  }

  void _drawAiShark(Canvas canvas, Obstacle obs) {
    final direction = obs.velocity.distance > .1
        ? obs.velocity / obs.velocity.distance
        : const Offset(1, 0);
    final angle = atan2(direction.dy, direction.dx);

    canvas.save();
    canvas.translate(obs.position.dx, obs.position.dy);
    canvas.rotate(angle);

    // Shark body
    final bodyPaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xffcc3333).withValues(alpha: .8);
    final body = Path()
      ..moveTo(-50, -18)
      ..cubicTo(-20, -28, 30, -26, 55, -6)
      ..cubicTo(65, 0, 65, 0, 55, 6)
      ..cubicTo(30, 26, -20, 28, -50, 18)
      ..close();
    canvas.drawPath(body, bodyPaint);

    // Dorsal fin
    final finPaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xff881111).withValues(alpha: .85);
    canvas.drawPath(
      Path()
        ..moveTo(-10, -20)
        ..lineTo(5, -42)
        ..lineTo(18, -20)
        ..close(),
      finPaint,
    );

    // Eye
    canvas.drawCircle(const Offset(38, -8), 4, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(39, -8),
      2,
      Paint()..color = Colors.black,
    );

    // Warning label
    _drawCenteredText(
      canvas,
      '🦈',
      Offset(0, -32),
      18,
      Colors.white,
      FontWeight.w900,
    );

    canvas.restore();
  }

  void _drawPoisonTideObs(Canvas canvas, Obstacle obs) {
    final paint = Paint()
      ..color = const Color(0xff4caf50).withValues(alpha: .25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(obs.position, obs.radius, paint);

    // Inner bubbles
    final innerPaint = Paint()
      ..color = const Color(0xff66bb6a).withValues(alpha: .15);
    for (var i = 0; i < 6; i++) {
      final a = i * pi / 3 + obs.timer;
      canvas.drawCircle(
        obs.position + Offset(cos(a), sin(a)) * obs.radius * .5,
        obs.radius * .18,
        innerPaint,
      );
    }

    _drawCenteredText(
      canvas,
      '☠',
      obs.position,
      16,
      const Color(0xff4caf50),
      FontWeight.w900,
    );
  }

  void _drawReef(Canvas canvas, Obstacle obs) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xff5d4037).withValues(alpha: .75);
    final path = Path();
    final sides = 7;
    for (var i = 0; i < sides; i++) {
      final a = i * 2 * pi / sides - pi / 2;
      final r = obs.radius * (.7 + .3 * ((i * 37) % 100) / 100);
      final x = obs.position.dx + cos(a) * r;
      final y = obs.position.dy + sin(a) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);

    final shadowPaint = Paint()
      ..isAntiAlias = true
      ..color = const Color(0xff3e2723).withValues(alpha: .4);
    canvas.drawPath(path, shadowPaint..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  void _drawCurrent(Canvas canvas, Obstacle obs) {
    final dir = Offset(cos(obs.angle), sin(obs.angle));
    final perp = Offset(-dir.dy, dir.dx);

    // Direction arrows
    final arrowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xff4488cc).withValues(alpha: .5);
    for (var i = -2; i <= 2; i++) {
      final base = obs.position + perp * (i * obs.width * .18);
      canvas.drawLine(
        base - dir * obs.width * .4,
        base + dir * obs.width * .4,
        arrowPaint,
      );
      // Arrowhead
      final tip = base + dir * obs.width * .45;
      canvas.drawLine(
        tip,
        tip - dir * 18 + perp * 10,
        arrowPaint,
      );
      canvas.drawLine(
        tip,
        tip - dir * 18 - perp * 10,
        arrowPaint,
      );
    }
  }

  // ─── Effects rendering ───

  void _drawPoisonTrail(Canvas canvas) {
    for (var i = 0; i < poisonTrail.length; i++) {
      final alpha = .08 + (i / poisonTrail.length) * .15;
      final radius = 15 + (i / poisonTrail.length) * 25;
      canvas.drawCircle(
        poisonTrail[i],
        radius,
        Paint()
          ..color = const Color(0xff4caf50).withValues(alpha: alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  void _drawSonicWave(Canvas canvas) {
    for (var i = 0; i < 2; i++) {
      final r = sonicWaveRadius - i * 40;
      if (r < 0) continue;
      canvas.drawCircle(
        player,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 - i * .5
          ..color = const Color(0xff4488ff)
              .withValues(alpha: max(0, .5 - i * .2)),
      );
    }
  }

  // ─── Seaweed ───

  void _drawSeaweed(Canvas canvas, {required bool front}) {
    for (final patch in seaweed) {
      if (!_isInView(patch.center)) continue;
      final alpha = front ? .9 : .34;
      final baseY = patch.center.dy + patch.height * .5;
      final rootPaint = Paint()
        ..isAntiAlias = true
        ..color = const Color(0xff06261f).withValues(alpha: alpha * .55);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(patch.center.dx, baseY + 5),
          width: patch.width * .85,
          height: 24,
        ),
        rootPaint,
      );

      final strandCount = max(8, (patch.width / 13).round());
      for (var i = 0; i < strandCount; i++) {
        final t = strandCount == 1 ? 0.0 : i / (strandCount - 1);
        final x = patch.center.dx - patch.width * .42 + patch.width * .84 * t;
        final height = patch.height * (.62 + .38 * ((i * 37) % 100) / 100);
        final sway = sin(patch.swaySeed + i * .9) * patch.width * .1;
        final bladeWidth = front ? 10.0 + (i % 4) * 2.0 : 5.0 + (i % 3);
        final path = Path()
          ..moveTo(x, baseY)
          ..cubicTo(
            x + sway,
            baseY - height * .35,
            x - sway,
            baseY - height * .7,
            x + sway * .45,
            baseY - height,
          );
        final fillPath = Path()
          ..moveTo(x - bladeWidth * .38, baseY)
          ..cubicTo(
            x + sway - bladeWidth,
            baseY - height * .34,
            x - sway - bladeWidth * .4,
            baseY - height * .72,
            x + sway * .45,
            baseY - height,
          )
          ..cubicTo(
            x - sway + bladeWidth * .4,
            baseY - height * .72,
            x + sway + bladeWidth,
            baseY - height * .34,
            x + bladeWidth * .38,
            baseY,
          )
          ..close();
        final paint = Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.fill
          ..color = Color.lerp(
            const Color(0xff073b32),
            const Color(0xff2ea671),
            t,
          )!.withValues(alpha: alpha);
        canvas.drawPath(fillPath, paint);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = max(1.2, bladeWidth * .16)
            ..color = const Color(0xff8de0a4).withValues(alpha: alpha * .24),
        );
      }
    }
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    Color color,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant FishGamePainter oldDelegate) => true;
}
