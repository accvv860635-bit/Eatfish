import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/fish_entity.dart';
import '../models/fish_spec.dart';
import '../models/seaweed_patch.dart';

class FishGamePainter extends CustomPainter {
  FishGamePainter({
    required this.fishImage,
    required this.fish,
    required this.player,
    required this.playerLevel,
    required this.playerHeading,
    required this.hurt,
    required this.playerHidden,
    required this.playerBite,
    required this.seaweed,
    required this.fishLength,
    required this.camera,
    required this.zoom,
    required this.world,
    required this.screen,
  });

  final ui.Image fishImage;
  final List<FishEntity> fish;
  final Offset player;
  final int playerLevel;
  final Offset playerHeading;
  final bool hurt;
  final bool playerHidden;
  final double playerBite;
  final List<SeaweedPatch> seaweed;
  final double Function(int level) fishLength;
  final Offset camera;
  final double zoom;
  final Size world;
  final Size screen;

  @override
  void paint(Canvas canvas, Size size) {
    // 攝影機平移 → 世界座標轉螢幕座標
    canvas.save();
    canvas.scale(zoom);
    canvas.translate(-camera.dx, -camera.dy);

    _drawSeaweed(canvas, front: false);

    final ordered = [...fish]..sort((a, b) => a.depth.compareTo(b.depth));
    for (final entity in ordered) {
      // 只繪製在可見範圍內的魚（含緩衝）
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

    if (hurt) {
      canvas.drawCircle(
        player,
        fishLength(playerLevel) * .48,
        Paint()
          ..color = const Color(0xffff355d).withValues(alpha: .26)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    _drawFish(
      canvas,
      player,
      playerHeading,
      fishLength(playerLevel) * 1.16,
      playerHidden ? 0 : 1,
      const Color(0xffffffff),
      playerLevel,
      false,
      isPlayer: true,
      bite: playerBite,
    );

    _drawSeaweed(canvas, front: true);

    canvas.restore();
  }

  bool _isInView(Offset worldPos) {
    const buffer = 160.0;
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
