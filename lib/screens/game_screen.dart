import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fish_entity.dart';
import '../models/fish_spec.dart';
import '../models/game_map.dart';
import '../models/game_record.dart';
import '../models/seaweed_patch.dart';
import '../painters/fish_game_painter.dart';
import '../services/storage_service.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.fishCount,
    this.gameMap,
    this.debugStartAtGameOver = false,
  });

  final int fishCount;
  final GameMap? gameMap;
  final bool debugStartAtGameOver;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  static const int maxLevel = FishSpecs.maxLevel;
  static const double worldWidthScale = 12.0;
  static const double worldHeightScale = 1.8;

  final Random _random = Random();
  final List<FishEntity> _fish = [];
  final List<SeaweedPatch> _seaweed = [];
  late final Ticker _ticker;

  // 圖片資源
  ui.Image? _fishImage;
  ui.Image? _bgImage;

  // 座標系統
  Size _screen = Size.zero;
  Size _world = Size.zero;
  Offset _player = Offset.zero;
  Offset _heading = const Offset(1, 0);
  Offset _targetPosition = Offset.zero;
  Offset _camera = Offset.zero;
  Duration _lastTick = Duration.zero;
  int _fishCount = 40;

  // 點擊指示器
  Offset? _tapWorldPos;
  double _tapAlpha = 0.0;

  // 遊戲狀態
  int _level = 1;
  int _xp = 0;
  int _hp = 100;
  int _score = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _revengeKills = 0;
  int _bestSavedScore = 0;
  double _runTime = 0;
  double _comboTimer = 0;
  double _feedbackTimer = 0;
  double _hurtCooldown = 0;
  double _spawnGraceTimer = 0;
  double _biteTimer = 0;
  bool _gameOver = false;
  bool _debugGameOverApplied = false;
  bool _savedRecord = false;
  bool _isChasing = false;
  bool _isPaused = false;
  bool _useJoystick = false;
  Offset? _joystickOrigin;
  Offset? _joystickCurrent;
  String _feedbackText = '';

  int get _xpGoal => _level >= maxLevel ? 0 : 28 + (_level * 16);
  int get _secondsSurvived => _runTime.floor();
  double get _cameraZoom => (1.0 - (_level - 1) * .022).clamp(.62, 1.0);
  Size get _visibleWorldSize =>
      Size(_screen.width / _cameraZoom, _screen.height / _cameraZoom);

  @override
  void initState() {
    super.initState();
    _fishCount = widget.fishCount;
    _loadAssets();
    _loadPrefs();
    _ticker = createTicker(_tick)..start();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final records = await StorageService.getRecords();
    if (mounted) {
      setState(() {
        _useJoystick = prefs.getBool('use_joystick') ?? false;
        _bestSavedScore = records.isEmpty ? 0 : records.first.score;
      });
    }
  }

  Future<void> _loadAssets() async {
    final fishData = await rootBundle.load('assets/images/fish_levels.png');
    final bgData = await rootBundle.load(
      (widget.gameMap ?? GameMaps.all.first).assetPath,
    );

    final fishCodec = await ui.instantiateImageCodec(
      fishData.buffer.asUint8List(),
    );
    final bgCodec = await ui.instantiateImageCodec(bgData.buffer.asUint8List());

    final fishFrame = await fishCodec.getNextFrame();
    final bgFrame = await bgCodec.getNextFrame();

    if (mounted) {
      setState(() {
        _fishImage = fishFrame.image;
        _bgImage = bgFrame.image;
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // ─── 重置 ───

  void _reset(Size screenSize) {
    _screen = screenSize;
    _world = _worldSizeFor(screenSize);

    // 玩家在世界正中央
    _level = 1;
    _player = Offset(_world.width / 2, _world.height / 2);
    _targetPosition = _player;
    _heading = const Offset(1, 0);
    _camera = _clampCamera(
      Offset(_player.dx - _screen.width / 2, _player.dy - _screen.height / 2),
    );
    _xp = 0;
    _hp = 100;
    _score = 0;
    _combo = 0;
    _bestCombo = 0;
    _revengeKills = 0;
    _runTime = 0;
    _comboTimer = 0;
    _feedbackTimer = 0;
    _feedbackText = '';
    _hurtCooldown = 0;
    _spawnGraceTimer = 1.6;
    _biteTimer = 0;
    _gameOver = false;
    _savedRecord = false;
    _isChasing = false;
    _isPaused = false;
    _tapAlpha = 0;
    _tapWorldPos = null;
    _fish.clear();
    _seaweed
      ..clear()
      ..addAll(_generateSeaweed());
    final nearbyFishCount = min(_fishCount, max(3, _fishCount ~/ 8));
    for (var i = 0; i < _fishCount; i++) {
      _fish.add(_spawnFish(nearPlayer: i < nearbyFishCount));
    }
  }

  // ─── 攝影機 ───

  Offset _clampCamera(Offset desired) {
    final visible = _visibleWorldSize;
    return Offset(
      desired.dx.clamp(0.0, max(0.0, _world.width - visible.width)),
      desired.dy.clamp(0.0, max(0.0, _world.height - visible.height)),
    );
  }

  Size _worldSizeFor(Size screenSize) {
    return Size(
      screenSize.width * worldWidthScale,
      screenSize.height * worldHeightScale,
    );
  }

  // ─── 生成魚 ───

  List<SeaweedPatch> _generateSeaweed() {
    final patches = <SeaweedPatch>[];
    final count = max(10, (_world.width / _screen.width * 2.2).round());
    for (var i = 0; i < count; i++) {
      patches.add(
        SeaweedPatch(
          center: Offset(
            140 + _random.nextDouble() * max(1, _world.width - 280),
            _world.height * (.35 + _random.nextDouble() * .55),
          ),
          width: 110 + _random.nextDouble() * 90,
          height: 180 + _random.nextDouble() * 170,
          swaySeed: _random.nextDouble() * pi * 2,
        ),
      );
    }
    return patches;
  }

  bool _isInSeaweed(Offset position) {
    for (final patch in _seaweed) {
      if (patch.contains(position)) return true;
    }
    return false;
  }

  SeaweedPatch? _nearestSeaweed(Offset position, {double maxDistance = 520}) {
    SeaweedPatch? nearest;
    var best = maxDistance;
    for (final patch in _seaweed) {
      final distance = (patch.center - position).distance;
      if (distance < best) {
        best = distance;
        nearest = patch;
      }
    }
    return nearest;
  }

  FishEntity _spawnFish({Offset? awayFromPlayer, bool nearPlayer = false}) {
    final level = _randomSpawnLevel();
    final spec = FishSpecs.byLevel(level);
    final margin = 80.0;
    Offset position;

    if (nearPlayer) {
      position = _randomNearPlayerPosition();
    } else if (awayFromPlayer == null) {
      position = Offset(
        margin + _random.nextDouble() * max(1, _world.width - margin * 2),
        margin + _random.nextDouble() * max(1, _world.height - margin * 2),
      );
    } else {
      final side = _random.nextInt(4);
      if (side == 0) {
        position = Offset(-margin, _random.nextDouble() * _world.height);
      } else if (side == 1) {
        position = Offset(
          _world.width + margin,
          _random.nextDouble() * _world.height,
        );
      } else if (side == 2) {
        position = Offset(_random.nextDouble() * _world.width, -margin);
      } else {
        position = Offset(
          _random.nextDouble() * _world.width,
          _world.height + margin,
        );
      }
    }

    final angle = _random.nextDouble() * pi * 2;
    final speed = _randomSpeedForLevel(level);
    return FishEntity(
      position: position,
      velocity: Offset(cos(angle), sin(angle)) * speed,
      level: level,
      depth: _random.nextDouble(),
      sizeScale: _randomSizeScaleForLevel(level),
      speedScale: speed / _baseSpeedForLevel(level),
      predator:
          level >= 5 &&
          level > _level &&
          _random.nextDouble() < spec.chaseChance,
      chaseTimer: .6 + _random.nextDouble() * 2,
      restTimer: _random.nextDouble() * 3,
      wanderTimer: .5 + _random.nextDouble() * 2,
    );
  }

  Offset _randomNearPlayerPosition() {
    final angle = _random.nextDouble() * pi * 2;
    final minDistance = max(180.0, _screen.shortestSide * .45);
    final maxDistance = max(minDistance + 1, _screen.longestSide * .9);
    final distance =
        minDistance + _random.nextDouble() * (maxDistance - minDistance);
    final raw = _player + Offset(cos(angle), sin(angle)) * distance;
    return Offset(
      raw.dx.clamp(80.0, _world.width - 80.0),
      raw.dy.clamp(80.0, _world.height - 80.0),
    );
  }

  int _randomSpawnLevel() {
    final minLevel = max(1, _level - 5);
    final maxSpawnLevel = min(maxLevel, _level + 5);
    final bossAlive = _fish.any((fish) => fish.level >= 18);
    final roll = _random.nextDouble();
    if (_level >= 13 && !bossAlive && roll > .985) {
      return 18;
    }
    if (_level >= 11 && roll > .965) {
      return min(maxSpawnLevel, 17);
    }
    if (_level >= 9 && roll > .94) {
      return min(maxSpawnLevel, 16);
    }
    if (roll < .52) {
      return minLevel + _random.nextInt(_level - minLevel + 1);
    }
    if (roll < .88) {
      final closeMax = min(maxSpawnLevel, _level + 2);
      return _level + _random.nextInt(closeMax - _level + 1);
    }
    return minLevel + _random.nextInt(maxSpawnLevel - minLevel + 1);
  }

  // ─── 主迴圈 ───

  void _tick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = min((elapsed - _lastTick).inMicroseconds / 1000000, 1 / 20);
    _lastTick = elapsed;

    if (_screen == Size.zero || _gameOver || _isPaused) {
      if (_gameOver && !_savedRecord) {
        _saveGameRecord();
      }
      return;
    }

    _updatePlayer(dt);
    _updateCamera(dt);
    _updateFish(dt);
    _resolveCollisions();
    _updateTapIndicator(dt);
    _runTime += dt;
    _biteTimer = max(0, _biteTimer - dt);
    _comboTimer = max(0, _comboTimer - dt);
    if (_comboTimer == 0) {
      _combo = 0;
    }
    _feedbackTimer = max(0, _feedbackTimer - dt);
    setState(() {});
  }

  // ─── 存檔 ───

  Future<void> _saveGameRecord() async {
    _savedRecord = true;
    await StorageService.saveRecord(
      GameRecord(
        score: _score,
        level: _level,
        timestamp: DateTime.now(),
        survivalSeconds: _secondsSurvived,
        revengeKills: _revengeKills,
        bestCombo: _bestCombo,
      ),
    );
  }

  // ─── 玩家移動 ───

  void _updatePlayer(double dt) {
    // 按住跟隨模式：持續朝目標移動
    if (_isChasing) {
      final toTarget = _targetPosition - _player;
      if (toTarget.distance > 3) {
        _heading = _normalize(toTarget);
      }
    }

    final speed = _playerSpeedForLevel(_level);
    _player += _heading * speed * dt;

    // 世界邊界夾制
    final playerLength = _fishLength(_level);
    final xMargin = max(22.0, playerLength * .42);
    final yMargin = max(26.0, playerLength * .32);
    _player = Offset(
      _player.dx.clamp(xMargin, _world.width - xMargin),
      _player.dy.clamp(yMargin, _world.height - yMargin),
    );

    _hurtCooldown = max(0, _hurtCooldown - dt);
    _spawnGraceTimer = max(0, _spawnGraceTimer - dt);
  }

  // ─── 攝影機跟隨 ───

  void _updateCamera(double dt) {
    final visible = _visibleWorldSize;
    final desired = Offset(
      _player.dx - visible.width / 2,
      _player.dy - visible.height / 2,
    );
    final target = _clampCamera(desired);
    _camera = Offset.lerp(_camera, target, min(1, dt * 3.5))!;
  }

  // ─── 點擊指示器 ───

  void _updateTapIndicator(double dt) {
    if (_tapAlpha > 0) {
      _tapAlpha = max(0, _tapAlpha - dt * 1.6);
    }
  }

  // ─── 魚 AI ───

  void _updateFish(double dt) {
    const margin = 160.0;
    final playerHidden = _isInSeaweed(_player);
    final playerNoise = _isChasing ? 1.0 : .58;
    for (var i = 0; i < _fish.length; i++) {
      final fish = _fish[i];
      fish.wanderTimer -= dt;
      fish.chaseTimer -= dt;
      fish.restTimer -= dt;
      fish.attackWindup = max(0, fish.attackWindup - dt);
      fish.attackCooldown = max(0, fish.attackCooldown - dt);
      fish.biteProgress = max(0, fish.biteProgress - dt * 3.8);
      fish.hiddenTimer = _isInSeaweed(fish.position)
          ? min(1.0, fish.hiddenTimer + dt * 1.8)
          : max(0.0, fish.hiddenTimer - dt * 1.4);
      fish.stunnedTimer = max(0, fish.stunnedTimer - dt);

      if (fish.stunnedTimer > 0) {
        fish.behaviorState = FishBehaviorState.stunned;
        fish.velocity = Offset.lerp(
          fish.velocity,
          Offset.zero,
          min(1, dt * 3),
        )!;
        fish.position += fish.velocity * dt;
        continue;
      }

      var desired = fish.velocity;
      final toPlayer = _player - fish.position;
      final distance = toPlayer.distance;
      final hiddenModifier = playerHidden ? (.38 + playerNoise * .24) : 1.0;
      final chaseRange = (180 + fish.level * 18) * hiddenModifier;
      final attackRange = _fishLength(fish.level, fish.sizeScale) * .38;

      if (fish.attackWindup > 0) {
        fish.behaviorState = FishBehaviorState.warn;
        desired = _normalize(toPlayer) * _cruiseSpeedForFish(fish) * .45;
      } else if (fish.biteProgress > 0) {
        fish.behaviorState = FishBehaviorState.attack;
        desired = _normalize(toPlayer) * _chaseSpeedForFish(fish) * .9;
      }

      final canChase =
          fish.predator &&
          fish.level > _level &&
          distance < chaseRange &&
          fish.restTimer <= 0;

      if (canChase &&
          distance < attackRange &&
          fish.attackCooldown <= 0 &&
          fish.attackWindup <= 0 &&
          fish.biteProgress <= 0) {
        fish.behaviorState = FishBehaviorState.warn;
        fish.attackWindup = fish.level >= 18 ? .65 : .36;
        fish.attackCooldown = fish.level >= 16 ? 1.2 : .85;
      } else if (canChase && fish.chaseTimer > 0 && fish.attackWindup <= 0) {
        fish.behaviorState = FishBehaviorState.chase;
        desired = _normalize(toPlayer) * _chaseSpeedForFish(fish);
      } else {
        if (fish.chaseTimer <= 0) {
          fish.behaviorState = FishBehaviorState.rest;
          fish.restTimer = 1.4 + _random.nextDouble() * 2.8;
          fish.chaseTimer = 1.2 + _random.nextDouble() * 2.4;
        }
        if (fish.wanderTimer <= 0) {
          fish.behaviorState = fish.restTimer > 0
              ? FishBehaviorState.rest
              : FishBehaviorState.wander;
          final angle =
              atan2(fish.velocity.dy, fish.velocity.dx) +
              (_random.nextDouble() - .5) * 1.6;
          desired = Offset(cos(angle), sin(angle)) * _cruiseSpeedForFish(fish);
          fish.wanderTimer = .6 + _random.nextDouble() * 2.1;
        }
      }

      if (fish.level < _level && distance < 120) {
        fish.behaviorState = FishBehaviorState.flee;
        final safePatch = _nearestSeaweed(fish.position);
        if (safePatch != null && _random.nextDouble() < .72) {
          fish.behaviorState = FishBehaviorState.hide;
          desired =
              _normalize(safePatch.center - fish.position) *
              _escapeSpeedForFish(fish);
        } else {
          desired =
              _normalize(fish.position - _player) * _escapeSpeedForFish(fish);
        }
      }

      if (fish.attackWindup == 0 &&
          fish.behaviorState == FishBehaviorState.warn) {
        fish.biteProgress = .42;
        fish.behaviorState = FishBehaviorState.attack;
      }

      final turnRate = FishSpecs.byLevel(fish.level).turnRate;
      fish.velocity = Offset.lerp(
        fish.velocity,
        desired,
        min(1, dt * turnRate),
      )!;
      final depthSpeed = ui.lerpDouble(.72, 1.16, fish.depth)!;
      fish.position += fish.velocity * depthSpeed * dt;

      // 超出世界邊界 → 重生
      if (fish.position.dx < -margin ||
          fish.position.dx > _world.width + margin ||
          fish.position.dy < -margin ||
          fish.position.dy > _world.height + margin) {
        _fish[i] = _spawnFish(awayFromPlayer: _player);
      }
    }
  }

  // ─── 碰撞 ───

  void _resolveCollisions() {
    final playerRadius = _fishLength(_level) * .28;
    for (var i = 0; i < _fish.length; i++) {
      final fish = _fish[i];
      final radius =
          _fishLength(fish.level, fish.sizeScale) *
          ui.lerpDouble(.22, .31, fish.depth)!;
      if ((_player - fish.position).distance > playerRadius + radius) {
        continue;
      }

      final canTailBite = fish.level == _level + 1 && _isPlayerBitingTail(fish);
      if (fish.level <= _level || canTailBite) {
        final spec = FishSpecs.byLevel(fish.level);
        final revengeBonus =
            canTailBite ||
            fish.behaviorState == FishBehaviorState.chase ||
            fish.behaviorState == FishBehaviorState.attack;
        _combo = _comboTimer > 0 ? _combo + 1 : 1;
        _bestCombo = max(_bestCombo, _combo);
        _comboTimer = 2.4;
        final comboBonus = _combo >= 3 ? (_combo - 2) * 20 : 0;
        _score += spec.score + comboBonus + (revengeBonus ? spec.score : 0);
        _xp += spec.xp + (revengeBonus ? spec.xp ~/ 2 : 0);
        if (revengeBonus) {
          _revengeKills += 1;
          _showFeedback('反殺 +${spec.score}');
        } else if (_combo >= 3) {
          _showFeedback('連吃 $_combo');
        }
        _biteTimer = .24;
        _fish[i] = _spawnFish(awayFromPlayer: _player);
        while (_level < maxLevel && _xp >= _xpGoal) {
          _xp -= _xpGoal;
          _level += 1;
          _showFeedback('升級 Lv.$_level');
        }
      } else if (_hurtCooldown <= 0 && _spawnGraceTimer <= 0) {
        final isAttacking =
            fish.behaviorState == FishBehaviorState.attack ||
            fish.biteProgress > 0;
        if (!isAttacking) {
          fish.behaviorState = FishBehaviorState.warn;
          fish.attackWindup = max(fish.attackWindup, .28);
          continue;
        }
        final spec = FishSpecs.byLevel(fish.level);
        final hidingReduction = _isInSeaweed(_player) ? .55 : 1.0;
        final damage = (spec.damage * hidingReduction).round();
        _hp = max(0, _hp - damage);
        _hurtCooldown = .75;
        fish.biteProgress = 0;
        fish.restTimer = max(fish.restTimer, 1.1);
        fish.behaviorState = FishBehaviorState.rest;
        _player -= _heading * 28;
        // 碰撞反彈後重新夾制邊界
        final playerLength = _fishLength(_level);
        _player = Offset(
          _player.dx.clamp(
            max(22.0, playerLength * .42),
            _world.width - max(22.0, playerLength * .42),
          ),
          _player.dy.clamp(
            max(26.0, playerLength * .32),
            _world.height - max(26.0, playerLength * .32),
          ),
        );
        if (_hp <= 0) {
          _gameOver = true;
          _showFeedback('');
        }
      }
    }
  }

  void _showFeedback(String text) {
    _feedbackText = text;
    _feedbackTimer = text.isEmpty ? 0 : 1.2;
  }

  bool _isPlayerBitingTail(FishEntity fish) {
    final fishDir = _normalize(fish.velocity);
    final fishLength = _fishLength(fish.level, fish.sizeScale);
    final tailCenter = fish.position - fishDir * (fishLength * .42);
    final tailRadius = max(24.0, fishLength * .18);
    final playerApproachingTail =
        _heading.dx * fishDir.dx + _heading.dy * fishDir.dy > .15;
    return (_player - tailCenter).distance < tailRadius &&
        playerApproachingTail;
  }

  double _fishLength(int level, [double sizeScale = 1]) =>
      FishSpecs.byLevel(level).length * sizeScale;

  double _randomSizeScaleForLevel(int level) =>
      .97 + _random.nextDouble() * .06;

  double _baseSpeedForLevel(int level) => FishSpecs.byLevel(level).speed;

  double _randomSpeedForLevel(int level) {
    final minSpeed = _baseSpeedForLevel(level);
    final maxSpeed = minSpeed + 10 + max(0, level - 4) * 2.5;
    return minSpeed + _random.nextDouble() * (maxSpeed - minSpeed);
  }

  double _playerSpeedForLevel(int level) => _baseSpeedForLevel(level) + 18;

  double _cruiseSpeedForFish(FishEntity fish) =>
      _baseSpeedForLevel(fish.level) * fish.speedScale;

  double _chaseSpeedForFish(FishEntity fish) =>
      _cruiseSpeedForFish(fish) * 1.28;

  double _escapeSpeedForFish(FishEntity fish) =>
      _cruiseSpeedForFish(fish) * 1.12;

  Offset _normalize(Offset value) {
    final length = value.distance;
    if (length < .001) return const Offset(1, 0);
    return value / length;
  }

  // ─── 螢幕座標 → 世界座標 ───

  Offset _screenToWorld(Offset screenPos) {
    return _camera + screenPos / _cameraZoom;
  }

  // ─── 建構 UI ───

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _gameOver,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size.width > 0 && size.height > 0 && _screen == Size.zero) {
            if (widget.debugStartAtGameOver && !_debugGameOverApplied) {
              _debugGameOverApplied = true;
              _screen = size;
              _world = _worldSizeFor(size);
              _player = Offset(_world.width / 2, _world.height / 2);
              _level = 1;
              _score = 0;
              _hp = 0;
              _gameOver = true;
            } else if (_fishImage != null && _bgImage != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _reset(size));
              });
            }
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              // 遊戲世界層（含攝影機平移）
              if (_screen != Size.zero && _bgImage != null)
                Positioned.fill(
                  child: ClipRect(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      child: Stack(
                        children: [
                          CustomPaint(
                            painter: WorldBackgroundPainter(
                              bgImage: _bgImage!,
                              world: _world,
                              camera: _camera,
                              zoom: _cameraZoom,
                              screen: _screen,
                            ),
                          ),
                          if (_fishImage != null)
                            CustomPaint(
                              painter: FishGamePainter(
                                fishImage: _fishImage!,
                                fish: _fish,
                                player: _player,
                                playerLevel: _level,
                                playerHeading: _heading,
                                hurt: _hurtCooldown > 0,
                                playerHidden: _isInSeaweed(_player),
                                playerBite: sin(
                                  (1 - (_biteTimer / .24).clamp(0.0, 1.0)) * pi,
                                ),
                                seaweed: _seaweed,
                                fishLength: _fishLength,
                                camera: _camera,
                                zoom: _cameraZoom,
                                world: _world,
                                screen: _screen,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              // 點擊指示器（螢幕空間）
              if (_tapAlpha > 0 && _tapWorldPos != null)
                CustomPaint(
                  painter: TapIndicatorPainter(
                    worldPos: _tapWorldPos!,
                    camera: _camera,
                    zoom: _cameraZoom,
                    alpha: _tapAlpha,
                  ),
                ),
              if (_feedbackTimer > 0 && _feedbackText.isNotEmpty)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 92),
                      child: _FeedbackBadge(text: _feedbackText),
                    ),
                  ),
                ),
              // 搖桿指示器
              if (_useJoystick &&
                  _joystickOrigin != null &&
                  _joystickCurrent != null)
                CustomPaint(
                  painter: _JoystickPainter(
                    origin: _joystickOrigin!,
                    current: _joystickCurrent!,
                  ),
                ),
              // HUD（固定在螢幕上）
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Hud(level: _level, hp: _hp, xp: _xp, xpGoal: _xpGoal),
                      const Spacer(),
                      // 底部列：左邊選單按鈕 + 右邊分數
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _MenuButton(onTap: _openPauseMenu),
                          const Spacer(),
                          Flexible(child: _ScoreBadge(score: _score)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Game Over
              if (_gameOver)
                _GameOverOverlay(
                  score: _score,
                  level: _level,
                  xp: _xp,
                  xpGoal: _xpGoal,
                  survivalSeconds: _secondsSurvived,
                  revengeKills: _revengeKills,
                  bestCombo: _bestCombo,
                  bestScore: _bestSavedScore,
                  onRestart: () => setState(() => _reset(_screen)),
                  onHome: () => Navigator.of(context).pop(),
                ),
              // 暫停選單
              if (_isPaused)
                _PauseOverlay(
                  useJoystick: _useJoystick,
                  onToggleJoystick: () {
                    setState(() => _useJoystick = !_useJoystick);
                    SharedPreferences.getInstance().then(
                      (p) => p.setBool('use_joystick', _useJoystick),
                    );
                  },
                  onResume: () => setState(() => _isPaused = false),
                  onRestart: () {
                    setState(() {
                      _isPaused = false;
                      _reset(_screen);
                    });
                  },
                  onHome: () => Navigator.of(context).pop(),
                ),
            ],
          );
        },
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    if (_useJoystick) {
      _joystickOrigin = details.localPosition;
      _joystickCurrent = details.localPosition;
      _updateJoystickInput();
    } else {
      _isChasing = true;
      _updateTarget(details.localPosition);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_useJoystick) {
      _joystickCurrent = details.localPosition;
      _updateJoystickInput();
    } else {
      _updateTarget(details.localPosition);
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_useJoystick) {
      _joystickOrigin = null;
      _joystickCurrent = null;
      _tapAlpha = 0;
    }
    _isChasing = false;
  }

  void _updateJoystickInput() {
    if (_joystickOrigin == null || _joystickCurrent == null) return;
    final delta = _joystickCurrent! - _joystickOrigin!;
    if (delta.distance < 8) {
      _isChasing = false;
      return;
    }
    _isChasing = true;
    // Set target far away in the direction of the joystick
    final dir = _normalize(delta);
    _targetPosition = _player + dir * 1000;
    _tapWorldPos = _player + dir * 100;
    _tapAlpha = 0.5;
  }

  void _updateTarget(Offset localPosition) {
    final worldPos = _screenToWorld(localPosition);
    _targetPosition = worldPos;
    _tapWorldPos = worldPos;
    _tapAlpha = 1.0;
  }

  void _openPauseMenu() {
    setState(() => _isPaused = true);
  }
}

// ═══════════════════════════════════════════════════
// 世界背景繪製器
// ═══════════════════════════════════════════════════

class WorldBackgroundPainter extends CustomPainter {
  WorldBackgroundPainter({
    required this.bgImage,
    required this.world,
    required this.camera,
    required this.zoom,
    required this.screen,
  });

  final ui.Image bgImage;
  final Size world;
  final Offset camera;
  final double zoom;
  final Size screen;

  @override
  void paint(Canvas canvas, Size size) {
    final srcRect = Rect.fromLTWH(
      0,
      0,
      bgImage.width.toDouble(),
      bgImage.height.toDouble(),
    );
    canvas.save();
    canvas.scale(zoom);
    canvas.translate(-camera.dx, -camera.dy);

    final drawRect = Rect.fromLTWH(0, 0, world.width, world.height);
    final fitted = applyBoxFit(BoxFit.cover, srcRect.size, drawRect.size);
    final inputSubrect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & srcRect.size,
    );
    final outputSubrect = Alignment.center.inscribe(
      fitted.destination,
      drawRect,
    );
    canvas.drawImageRect(
      bgImage,
      inputSubrect,
      outputSubrect,
      Paint()..filterQuality = FilterQuality.high,
    );

    // 暗角漸層（覆蓋世界）
    final gradientPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(.05, -.22),
        radius: 1.2,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: .10),
          Colors.black.withValues(alpha: .24),
        ],
        stops: const [.2, .72, 1],
      ).createShader(Rect.fromLTWH(0, 0, world.width, world.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, world.width, world.height),
      gradientPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WorldBackgroundPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════
// 點擊指示器
// ═══════════════════════════════════════════════════

class TapIndicatorPainter extends CustomPainter {
  TapIndicatorPainter({
    required this.worldPos,
    required this.camera,
    required this.zoom,
    required this.alpha,
  });

  final Offset worldPos;
  final Offset camera;
  final double zoom;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final screenPos = (worldPos - camera) * zoom;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: alpha * .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // 外圈（隨 alpha 縮放）
    final radius = 16 + (1 - alpha) * 14;
    canvas.drawCircle(screenPos, radius, paint);

    // 內圈
    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: alpha * .7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPos, 4, innerPaint);
  }

  @override
  bool shouldRepaint(covariant TapIndicatorPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════
// HUD 元件
// ═══════════════════════════════════════════════════

class _Hud extends StatelessWidget {
  const _Hud({
    required this.level,
    required this.hp,
    required this.xp,
    required this.xpGoal,
  });

  final int level;
  final int hp;
  final int xp;
  final int xpGoal;

  @override
  Widget build(BuildContext context) {
    final xpValue = xpGoal == 0 ? 1.0 : (xp / xpGoal).clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff061821).withValues(alpha: .62),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Lv.$level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Bar(value: hp / 100, color: const Color(0xffff3157)),
                ),
                const SizedBox(width: 8),
                Text(
                  '$hp',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            _Bar(value: xpValue, color: const Color(0xff3ee6d4), height: 8),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color, this.height = 10});
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        minHeight: height,
        value: value,
        backgroundColor: Colors.white.withValues(alpha: .15),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xff061821).withValues(alpha: .62),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          'Score $score',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FeedbackBadge extends StatelessWidget {
  const _FeedbackBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff061821).withValues(alpha: .76),
        border: Border.all(color: const Color(0xff3ee6d4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xffd8fff8),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({
    required this.score,
    required this.level,
    required this.xp,
    required this.xpGoal,
    required this.survivalSeconds,
    required this.revengeKills,
    required this.bestCombo,
    required this.bestScore,
    required this.onRestart,
    required this.onHome,
  });

  final int score;
  final int level;
  final int xp;
  final int xpGoal;
  final int survivalSeconds;
  final int revengeKills;
  final int bestCombo;
  final int bestScore;
  final VoidCallback onRestart;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final timeText = _formatTime(survivalSeconds);
    final nextLevelText = xpGoal == 0
        ? '已達最高等級'
        : '差 ${max(0, xpGoal - xp)} XP 升到 Lv.${level + 1}';
    final recordText = bestScore <= 0
        ? '第一筆成績'
        : score > bestScore
        ? '新紀錄 +${score - bestScore}'
        : '差 ${bestScore - score + 1} 分破紀錄';
    return ColoredBox(
      color: Colors.black.withValues(alpha: .62),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xff071923).withValues(alpha: .92),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: .14)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Game Over',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    recordText,
                    style: const TextStyle(
                      color: Color(0xffb8eef7),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _ResultTile(label: '分數', value: '$score'),
                      _ResultTile(label: '最高等級', value: 'Lv.$level'),
                      _ResultTile(label: '存活', value: timeText),
                      _ResultTile(label: '反殺', value: '$revengeKills'),
                      _ResultTile(label: '連吃', value: '$bestCombo'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        nextLevelText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xff3ee6d4),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: onHome,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xff8abfd4),
                          side: const BorderSide(color: Color(0xff2a5a6e)),
                        ),
                        child: const Text('回首頁'),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: onRestart,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xff18c7bb),
                          foregroundColor: const Color(0xff031417),
                        ),
                        child: const Text('再來一局'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    if (minutes == 0) return '${rest}s';
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff031417).withValues(alpha: .72),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: Color(0xff8abfd4), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xff061821).withValues(alpha: .62),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.menu, color: Colors.white70, size: 24),
      ),
    );
  }
}

class _PauseOverlay extends StatelessWidget {
  const _PauseOverlay({
    required this.onResume,
    required this.onRestart,
    required this.onHome,
    required this.useJoystick,
    required this.onToggleJoystick,
  });

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onHome;
  final bool useJoystick;
  final VoidCallback onToggleJoystick;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ColoredBox(
          color: Colors.black.withValues(alpha: .55),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: min(360.0, constraints.maxWidth - 48),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xff071923).withValues(alpha: .94),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .14),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .35),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                '暫停',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .05),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: .08),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.gamepad,
                                      color: Color(0xff8abfd4),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '操控模式',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            useJoystick ? '搖桿模式' : '按鈕模式',
                                            style: const TextStyle(
                                              color: Color(0xff8abfd4),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: useJoystick,
                                      onChanged: (_) => onToggleJoystick(),
                                      activeTrackColor: const Color(0xff3ee6d4),
                                      activeThumbColor: Colors.white,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              FilledButton(
                                onPressed: onResume,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xff18c7bb),
                                  foregroundColor: const Color(0xff031417),
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                child: const Text('繼續遊戲'),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: onRestart,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xff8abfd4),
                                  side: const BorderSide(
                                    color: Color(0xff2a5a6e),
                                  ),
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                child: const Text('再來一局'),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: onHome,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xffff5a6e),
                                  side: const BorderSide(
                                    color: Color(0xff5a2a2e),
                                  ),
                                  minimumSize: const Size.fromHeight(44),
                                ),
                                child: const Text('回首頁'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({required this.origin, required this.current});

  final Offset origin;
  final Offset current;

  @override
  void paint(Canvas canvas, Size size) {
    final delta = current - origin;
    final distance = min(58.0, delta.distance);
    final direction = delta.distance < .001
        ? Offset.zero
        : delta / delta.distance;
    final knob = origin + direction * distance;

    final basePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: .2);
    final linePaint = Paint()
      ..isAntiAlias = true
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xff79f3ff).withValues(alpha: .34);
    final knobPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: .34);

    canvas.drawCircle(origin, 58, basePaint);
    canvas.drawLine(origin, knob, linePaint);
    canvas.drawCircle(knob, 13, knobPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.origin != origin || oldDelegate.current != current;
  }
}
