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
import '../models/obstacle.dart';
import '../models/power_up.dart';
import '../models/seaweed_patch.dart';
import '../models/skill_def.dart' show SkillGroup;
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
  static const double _boostSpeedMult = 2.0;
  static const double _boostSizeDrain = 0.05;
  static const int _maxPowerUpsOnMap = 3;

  final Random _random = Random();
  final List<FishEntity> _fish = [];
  final List<SeaweedPatch> _seaweed = [];
  final List<PowerUp> _powerUps = [];
  final List<ActiveEffect> _activeEffects = [];
  final List<Obstacle> _obstacles = [];
  late final Ticker _ticker;

  ui.Image? _fishImage;
  ui.Image? _bgImage;
  ui.Image? _lv15Image;
  ui.Image? _lv16Image;
  ui.Image? _lv17Image;
  ui.Image? _lv18Image;

  Size _screen = Size.zero;
  Size _world = Size.zero;
  Offset _player = Offset.zero;
  Offset _heading = const Offset(1, 0);
  Offset _targetPosition = Offset.zero;
  Offset _camera = Offset.zero;
  Duration _lastTick = Duration.zero;
  int _fishCount = 40;

  Offset? _tapWorldPos;
  double _tapAlpha = 0.0;

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
  double _screenShake = 0; // screen shake intensity for combo break

  // ─── Floating damage/heal numbers ───
  final List<_FloatingNumber> _floatingNumbers = [];
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

  // ─── Boost (skill-like, fixed duration) ───
  bool _isBoosting = false;
  double _boostCooldown = 0;
  static const double _boostDuration = 3.0;
  static const double _boostCooldownTime = 6.0;
  double _playerSizeMultiplier = 1.0;
  double _boostTimer = 0; // remaining boost time
  double _hitInvincibility = 0; // invincibility after hit
  double _levelUpFlash = 0; // flash timer for level-up

  // ─── Power-ups ───
  double _powerUpSpawnTimer = 0;

  // ─── Skills (5 groups, independent cooldowns) ───
  final List<double> _skillCooldowns = [0, 0, 0, 0, 0];
  double _skillEffectTimer = 0;
  int _activeSkillGroup = -1; // which group's effect is currently active
  int _skillEatCount = 0;
  final List<FishEntity> _summonedFish = [];
  double _summonTimer = 0;
  double _sonicWaveRadius = 0;
  // ─── Berserk mode (Group 4) ───
  double _berserkSpeedMult = 1.0;
  double _berserkEatMult = 1.0;

  // ─── Obstacles ───
  double _hookTimer = 0;
  double _poisonTideTimer = 0;
  double _sharkTimer = 0;

  // ─── Poison trail ───
  final List<Offset> _poisonTrail = [];
  static const double _poisonTrailRadius = 60;

  int get _xpGoal => _level >= maxLevel ? 0 : (_level * _level * 3 + 30);
  // Later levels: fish count drops sharply after Lv12 to increase difficulty
  int get _effectiveFishCount {
    if (_level <= 12) {
      return (_fishCount * (1.0 - (_level - 1) * .04)).round();
    }
    // Lv13+ : aggressive reduction
    final base = 1.0 - 11 * .04; // .56 at Lv12
    final mult = (base - (_level - 12) * .10).clamp(.08, 1.0);
    return (_fishCount * mult).round().clamp(6, _fishCount);
  }
  int get _secondsSurvived => _runTime.floor();
  int get _maxHp => 60 + _level * 15;
  double get _cameraZoom {
    // More aggressive zoom-out at high levels.
    final basedOnLevel = (1.0 - (_level - 1) * .055).clamp(.18, 1.0);
    var zoom = basedOnLevel;
    // In landscape (wide screen), zoom out proportionally
    if (_screen.width > _screen.height) {
      zoom = (basedOnLevel * _screen.height / _screen.width).clamp(
        0.15,
        basedOnLevel,
      );
    }
    // Don't zoom out beyond the world — visible area must fit within world
    if (_world != Size.zero) {
      final minZoomX = _screen.width / _world.width;
      final minZoomY = _screen.height / _world.height;
      final minZoom = max(minZoomX, minZoomY);
      zoom = max(zoom, minZoom);
    }
    return zoom;
  }

  Size get _visibleWorldSize =>
      Size(_screen.width / _cameraZoom, _screen.height / _cameraZoom);

  bool get _isInvincible =>
      _activeEffects.any(
        (e) => e.type == PowerUpType.shield || e.type == PowerUpType.star,
      ) ||
      // Group 0 tier 0: dash through enemies
      (_skillEffectTimer > 0 && _activeSkillGroup == 0) ||
      // Group 4 tier 1+: berserk invincibility
      (_skillEffectTimer > 0 && _activeSkillGroup == 4 && _level >= 14);

  @override
  void initState() {
    super.initState();
    _fishCount = widget.fishCount;
    _loadAssets();
    _loadPrefs();
    _ticker = createTicker(_tick)..start();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    if (_gameOver || _isPaused) return false;
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _startBoosting();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyQ ||
          event.logicalKey == LogicalKeyboardKey.keyE) {
        _useSkill(0);
        return true;
      }
    }
    if (event is KeyUpEvent) {
      if (event.logicalKey == LogicalKeyboardKey.space) {
        _stopBoosting();
        return true;
      }
    }
    return false;
  }

  void _startBoosting() {
    if (_boostCooldown > 0 || _isBoosting) return;
    _isBoosting = true;
    _boostTimer = _boostDuration;
    HapticFeedback.mediumImpact();
  }

  void _stopBoosting() {
    _isBoosting = false;
    _boostCooldown = _boostCooldownTime;
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
    final lv15Data = await rootBundle.load(
      'assets/images/lv15_sperm_whale.png',
    );
    final lv16Data = await rootBundle.load(
      'assets/images/lv16_megamouth_shark.png',
    );
    final lv17Data = await rootBundle.load(
      'assets/images/lv17_dunkleosteus.png',
    );
    final lv18Data = await rootBundle.load('assets/images/lv18_mosasaurus.png');
    final fishCodec = await ui.instantiateImageCodec(
      fishData.buffer.asUint8List(),
    );
    final bgCodec = await ui.instantiateImageCodec(bgData.buffer.asUint8List());
    final lv15Codec = await ui.instantiateImageCodec(
      lv15Data.buffer.asUint8List(),
    );
    final lv16Codec = await ui.instantiateImageCodec(
      lv16Data.buffer.asUint8List(),
    );
    final lv17Codec = await ui.instantiateImageCodec(
      lv17Data.buffer.asUint8List(),
    );
    final lv18Codec = await ui.instantiateImageCodec(
      lv18Data.buffer.asUint8List(),
    );
    final fishFrame = await fishCodec.getNextFrame();
    final bgFrame = await bgCodec.getNextFrame();
    final lv15Frame = await lv15Codec.getNextFrame();
    final lv16Frame = await lv16Codec.getNextFrame();
    final lv17Frame = await lv17Codec.getNextFrame();
    final lv18Frame = await lv18Codec.getNextFrame();
    if (mounted) {
      setState(() {
        _fishImage = fishFrame.image;
        _bgImage = bgFrame.image;
        _lv15Image = lv15Frame.image;
        _lv16Image = lv16Frame.image;
        _lv17Image = lv17Frame.image;
        _lv18Image = lv18Frame.image;
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _reset(Size screenSize) {
    _screen = screenSize;
    _world = _worldSizeFor(screenSize);
    _level = 1;
    _player = Offset(_world.width / 2, _world.height / 2);
    _targetPosition = _player;
    _heading = const Offset(1, 0);
    _camera = _clampCamera(
      Offset(_player.dx - _screen.width / 2, _player.dy - _screen.height / 2),
    );
    _xp = 0;
    _hp = _maxHp;
    _score = 0;
    _combo = 0;
    _bestCombo = 0;
    _revengeKills = 0;
    _runTime = 0;
    _comboTimer = 0;
    _feedbackTimer = 0;
    _feedbackText = '';
    _spawnGraceTimer = 1.6;
    _biteTimer = 0;
    _gameOver = false;
    _savedRecord = false;
    _isChasing = false;
    _isPaused = false;
    _tapAlpha = 0;
    _tapWorldPos = null;

    _isBoosting = false;
    _boostCooldown = 0;
    _boostTimer = 0;
    _playerSizeMultiplier = 1.0;

    _powerUps.clear();
    _activeEffects.clear();
    _powerUpSpawnTimer = _random.nextDouble() * 5 + 15;

    _skillCooldowns.setAll(0, [0, 0, 0, 0, 0]);
    _skillEffectTimer = 0;
    _activeSkillGroup = -1;
    _skillEatCount = 0;
    _summonedFish.clear();
    _summonTimer = 0;
    _sonicWaveRadius = 0;

    _obstacles.clear();
    _hookTimer = 25 + _random.nextDouble() * 10;
    _poisonTideTimer = 15 + _random.nextDouble() * 15;
    _sharkTimer = 35 + _random.nextDouble() * 20;

    _poisonTrail.clear();

    _fish.clear();
    _seaweed
      ..clear()
      ..addAll(_generateSeaweed());
    final nearbyFishCount = min(_fishCount, max(3, _fishCount ~/ 8));
    for (var i = 0; i < _fishCount; i++) {
      _fish.add(_spawnFish(nearPlayer: i < nearbyFishCount));
    }

    // Spawn initial obstacles
    _spawnReefs();
    _spawnWhirlpools();
    _spawnCurrents();
  }

  Offset _clampCamera(Offset desired) {
    final visible = _visibleWorldSize;
    return Offset(
      desired.dx.clamp(0.0, max(0.0, _world.width - visible.width)),
      desired.dy.clamp(0.0, max(0.0, _world.height - visible.height)),
    );
  }

  Size _worldSizeFor(Size screenSize) {
    // Keep world aspect ratio roughly constant (~3:1) regardless of orientation.
    // In landscape the screen is wider, so we scale height up to compensate.
    final aspectRatio = screenSize.width / screenSize.height;
    final heightScale = (1.8 * aspectRatio / 0.5).clamp(1.8, 4.5);
    return Size(
      screenSize.width * worldWidthScale,
      screenSize.height * heightScale,
    );
  }

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
    final minLevel = max(1, _level - 4);
    final maxSpawnLevel = min(maxLevel, _level + 5);
    final bossAlive = _fish.any((fish) => fish.level >= 18);
    final roll = _random.nextDouble();

    // High levels: more predator bias
    final predatorBoost = max(0.0, (_level - 8) * .03); // 0→0.3 from Lv.8→18

    if (_level >= 13 && !bossAlive && roll > .985 - predatorBoost) {
      return 18;
    }
    if (_level >= 11 && roll > .965 - predatorBoost) {
      return min(maxSpawnLevel, 17);
    }
    if (_level >= 9 && roll > .94 - predatorBoost) {
      return min(maxSpawnLevel, 16);
    }
    // At high levels, fewer small fish
    final smallFishChance = .52 - predatorBoost;
    if (roll < smallFishChance) {
      return minLevel + _random.nextInt(_level - minLevel + 1);
    }
    if (roll < .88) {
      final closeMax = min(maxSpawnLevel, _level + 2);
      return _level + _random.nextInt(closeMax - _level + 1);
    }
    return minLevel + _random.nextInt(maxSpawnLevel - minLevel + 1);
  }

  // ─── Main loop ───

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
    _updateBoost(dt);
    _hitInvincibility = max(0, _hitInvincibility - dt);
    _levelUpFlash = max(0, _levelUpFlash - dt);
    _updateCamera(dt);
    _updateFish(dt);
    _resolveCollisions();
    _updateActiveEffects(dt);
    _updatePowerUps(dt);
    _updateObstacles(dt);
    _updateSkillCooldown(dt);
    _updatePoisonTrail(dt);
    _resolvePowerUpCollisions();
    _resolveObstacleCollisions();
    _updateTapIndicator(dt);

    _runTime += dt;
    _biteTimer = max(0, _biteTimer - dt);
    _comboTimer = max(0, _comboTimer - dt);
    if (_comboTimer == 0 && _combo > 2) {
      // Combo broken with impact
      _screenShake = 14;
      _spawnFloatingText('連擊中斷', const Color(0xffff5a6e), 1.6);
      _combo = 0;
      HapticFeedback.heavyImpact();
    } else if (_comboTimer == 0) {
      _combo = 0;
    }
    _feedbackTimer = max(0, _feedbackTimer - dt);
    // Update floating numbers
    for (var i = _floatingNumbers.length - 1; i >= 0; i--) {
      _floatingNumbers[i].update(dt);
      if (_floatingNumbers[i].isDead) _floatingNumbers.removeAt(i);
    }
    // Decay screen shake
    _screenShake = max(0, _screenShake - dt * 40);
    setState(() {});
  }

  // ─── Save ───

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

  // ─── Player movement ───

  void _updatePlayer(double dt) {
    if (_isChasing) {
      final toTarget = _targetPosition - _player;
      if (toTarget.distance > 3) {
        _heading = _normalize(toTarget);
      }
    }

    final speed = _playerSpeedForLevel(_level);
    final boostMult = _isBoosting ? _boostSpeedMult : 1.0;
    final berserkMult = _berserkSpeedMult;
    final effectSpeedMult =
        1.0 + (_activeEffects.any((e) => e.type == PowerUpType.boost) ? .6 : 0);
    _player +=
        _heading * speed * boostMult * berserkMult * effectSpeedMult * dt;

    final playerLength = _fishLength(_level);
    final xMargin = max(22.0, playerLength * .42);
    final yMargin = max(26.0, playerLength * .32);
    _player = Offset(
      _player.dx.clamp(xMargin, _world.width - xMargin),
      _player.dy.clamp(yMargin, _world.height - yMargin),
    );

    _spawnGraceTimer = max(0, _spawnGraceTimer - dt);

    // Poison trail
    if (_activeEffects.any((e) => e.type == PowerUpType.poison)) {
      _poisonTrail.add(_player);
      if (_poisonTrail.length > 80) {
        _poisonTrail.removeAt(0);
      }
    }
  }

  // ─── Boost ───

  void _updateBoost(double dt) {
    // Count down boost timer
    if (_isBoosting) {
      _boostTimer = max(0, _boostTimer - dt);
      if (_boostTimer <= 0) {
        _stopBoosting();
      }
    }
    // Count down boost cooldown
    _boostCooldown = max(0, _boostCooldown - dt);

    // Size multiplier recovery (only for inflate skill, not boost)
    if (!_isBoosting) {
      final clampMax = (_activeSkillGroup == 0 && _skillEffectTimer > 0)
          ? 3.0
          : 1.0;
      _playerSizeMultiplier = min(
        clampMax,
        _playerSizeMultiplier + _boostSizeDrain * .5 * dt,
      );
    }
  }

  // ─── Camera ───

  void _updateCamera(double dt) {
    final visible = _visibleWorldSize;
    final desired = Offset(
      _player.dx - visible.width / 2,
      _player.dy - visible.height / 2,
    );
    final target = _clampCamera(desired);
    _camera = Offset.lerp(_camera, target, min(1, dt * 3.5))!;
    // Screen shake offset (combo break, etc.)
    if (_screenShake > 0.3) {
      _camera += Offset(
        (sin(_runTime * 48 + 1.3) * _screenShake),
        (cos(_runTime * 56 + 2.1) * _screenShake * .7),
      );
    }
  }

  // ─── Tap indicator ───

  void _updateTapIndicator(double dt) {
    if (_tapAlpha > 0) {
      _tapAlpha = max(0, _tapAlpha - dt * 1.6);
    }
  }

  // ─── Fish AI ───

  void _updateFish(double dt) {
    const margin = 160.0;
    // Count active chasers this frame
    final activeChasers = _fish
        .where(
          (f) =>
              f.behaviorState == FishBehaviorState.chase ||
              f.behaviorState == FishBehaviorState.warn ||
              f.behaviorState == FishBehaviorState.attack ||
              f.biteProgress > 0,
        )
        .length;
    final playerHidden = _isInSeaweed(_player);
    final playerNoise = _isChasing ? 1.0 : .58;
    final allFish = [..._fish, ..._summonedFish];

    for (var i = 0; i < allFish.length; i++) {
      final fish = allFish[i];
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

      // Poison trail slow
      var slowMult = 1.0;
      for (final p in _poisonTrail) {
        if ((fish.position - p).distance < _poisonTrailRadius) {
          slowMult = .35;
          break;
        }
      }
      // Sonic wave slow
      if (_sonicWaveRadius > 0) {
        final dist = (fish.position - _player).distance;
        if (dist < _sonicWaveRadius && dist > _sonicWaveRadius * .3) {
          slowMult = min(slowMult, .3);
        }
      }
      // Vortex attraction
      if (_activeEffects.any((e) => e.type == PowerUpType.vortex)) {
        final dist = (fish.position - _player).distance;
        if (dist < 260 && dist > 30) {
          final pull = _normalize(_player - fish.position) * 180 * dt;
          fish.position += pull * slowMult;
        }
      }
      // Magnet attraction (only smaller fish)
      if (_activeEffects.any((e) => e.type == PowerUpType.magnet)) {
        final dist = (fish.position - _player).distance;
        if (dist < 280 && fish.level < _level && dist > 30) {
          final pull = _normalize(_player - fish.position) * 200 * dt;
          fish.position += pull * slowMult;
        }
      }
      // Group 2: Vortex pull (all fish)
      if (_activeSkillGroup == 2 && _skillEffectTimer > 0) {
        final tier = SkillGroup.byIndex(2)!.tierAt(_level);
        final pullRange = 220.0 + tier * 60;
        final dist = (fish.position - _player).distance;
        if (dist < pullRange && dist > 25) {
          final pull =
              _normalize(_player - fish.position) * (160 + tier * 40) * dt;
          fish.position += pull * slowMult;
          if (tier >= 1) {
            // Also slow pulled fish
            slowMult = min(slowMult, 0.3);
          }
        }
      }

      final wasStunned = fish.behaviorState == FishBehaviorState.stunned;
      if (fish.stunnedTimer > 0) {
        fish.behaviorState = FishBehaviorState.stunned;
        fish.velocity = Offset.lerp(
          fish.velocity,
          Offset.zero,
          min(1, dt * 3),
        )!;
        fish.position += fish.velocity * dt * slowMult;
        continue;
      }

      // Reset AI timers when coming out of stun so fish doesn't get stuck
      if (wasStunned) {
        fish.wanderTimer = 0;
        fish.chaseTimer = 0;
        fish.restTimer = 0;
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
          fish.level >= _level &&
          distance < chaseRange &&
          fish.restTimer <= 0 &&
          activeChasers < 3; // max 3 simultaneous chasers

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
          fish.restTimer = 3.0 + _random.nextDouble() * 4.0;
          fish.chaseTimer = 0; // don't chase again until rest+wander completes
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
          // After rest+wander, predators can chase again
          if (fish.predator && fish.chaseTimer <= 0 && fish.restTimer <= 0) {
            fish.chaseTimer = 1.0 + _random.nextDouble() * 2.0;
          }
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
      fish.position += fish.velocity * depthSpeed * slowMult * dt;

      if (fish.position.dx < -margin ||
          fish.position.dx > _world.width + margin ||
          fish.position.dy < -margin ||
          fish.position.dy > _world.height + margin) {
        if (i < _fish.length) {
          if (_fish.length > _effectiveFishCount) {
            _fish.removeAt(i);
          } else {
            _fish[i] = _spawnFish(awayFromPlayer: _player);
          }
        }
      }
    }

    // ─── Fish schooling: same-level fish cluster together ───
    _applySchooling(dt);
  }

  void _applySchooling(double dt) {
    if (_fish.length < 3) return;
    const schoolRadius = 260.0;
    const schoolForce = 18.0;

    for (var i = 0; i < _fish.length; i++) {
      final fish = _fish[i];
      // Only apply to wandering/resting fish, not chasing/fleeing
      final state = fish.behaviorState;
      if (state == FishBehaviorState.chase ||
          state == FishBehaviorState.flee ||
          state == FishBehaviorState.attack ||
          state == FishBehaviorState.stunned ||
          state == FishBehaviorState.hide) {
        continue;
      }

      var centerX = 0.0, centerY = 0.0, count = 0;

      // Sample approach: check a subset of same-level fish
      for (var j = 0; j < _fish.length; j++) {
        if (i == j) continue;
        final other = _fish[j];
        if (other.level != fish.level) continue;
        // Only cluster with similarly-behaving fish
        final otherState = other.behaviorState;
        if (otherState == FishBehaviorState.chase ||
            otherState == FishBehaviorState.flee ||
            otherState == FishBehaviorState.attack) {
          continue;
        }

        final dist = (fish.position - other.position).distance;
        if (dist < schoolRadius) {
          centerX += other.position.dx;
          centerY += other.position.dy;
          count++;
        }
      }

      if (count >= 1) {
        final center = Offset(centerX / count, centerY / count);
        final toCenter = center - fish.position;
        final dist = toCenter.distance;
        if (dist > 12) {
          // Gentle attraction toward school center; stronger when farther
          final strength = (dist / schoolRadius).clamp(0.1, 1.0) * schoolForce;
          fish.position += _normalize(toCenter) * strength * dt;
        }
      }
    }
  }

  // ─── Collisions ───

  void _resolveCollisions() {
    final playerRadius = _fishLength(_level) * .28 * _playerSizeMultiplier;
    final starActive = _activeEffects.any((e) => e.type == PowerUpType.star);
    final skillL3Active = _activeSkillGroup == 0 && _skillEffectTimer > 0;
    var eatRangeMultiplier = _berserkEatMult;
    if (_activeSkillGroup == 1 && _skillEffectTimer > 0) {
      final tier = SkillGroup.byIndex(1)!.tierAt(_level);
      eatRangeMultiplier = tier >= 2 ? 1.8 : 1.5;
    }

    for (var i = 0; i < _fish.length; i++) {
      final fish = _fish[i];
      final radius =
          _fishLength(fish.level, fish.sizeScale) *
          ui.lerpDouble(.22, .31, fish.depth)!;
      final dist = (_player - fish.position).distance;
      final eatRange = (playerRadius + radius) * eatRangeMultiplier;

      if (dist > playerRadius + radius && dist > eatRange) {
        continue;
      }

      final canTailBite = fish.level == _level + 1 && _isPlayerBitingTail(fish);

      if (fish.level <= _level || canTailBite || starActive) {
        final spec = FishSpecs.byLevel(fish.level);
        final revengeBonus =
            !starActive &&
            (canTailBite ||
                fish.behaviorState == FishBehaviorState.chase ||
                fish.behaviorState == FishBehaviorState.attack);
        _combo = _comboTimer > 0 ? _combo + 1 : 1;
        _bestCombo = max(_bestCombo, _combo);
        _comboTimer = 2.4;
        final comboBonus = _combo >= 3 ? (_combo - 2) * 20 : 0;
        final doubleMult =
            _activeEffects.any((e) => e.type == PowerUpType.doubleScore)
            ? 2
            : 1;
        _score +=
            (spec.score + comboBonus + (revengeBonus ? spec.score : 0)) *
            doubleMult;
        _xp += spec.xp + (revengeBonus ? spec.xp ~/ 2 : 0);
        final hpRestore = 5 + spec.damage ~/ 3;
        _hp = min(_maxHp, _hp + hpRestore); // small HP restore
        if (_hp < _maxHp && hpRestore > 0) {
          _spawnFloatingText('+$hpRestore', const Color(0xff3ee6d4), 0.9);
        }
        if (_combo >= 5) {
          HapticFeedback.heavyImpact();
        } else if (_combo >= 3) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.lightImpact();
        }
        if (revengeBonus) {
          _revengeKills += 1;
        }

        _biteTimer = .24;
        if (_fish.length > _effectiveFishCount) {
          _fish.removeAt(i);
        } else {
          _fish[i] = _spawnFish(awayFromPlayer: _player);
        }
        while (_level < maxLevel && _xp >= _xpGoal) {
          _xp -= _xpGoal;
          _level += 1;
          _levelUpFlash = .5;
          HapticFeedback.heavyImpact();
        }

        // Blood rage: CD reduction per eat (Group 1)
        if (_activeSkillGroup == 1 && _skillEffectTimer > 0) {
          final tier = SkillGroup.byIndex(1)!.tierAt(_level);
          final reduction = tier >= 2 ? 0.8 : 0.5;
          _skillCooldowns[1] = max(0, _skillCooldowns[1] - reduction);
          _skillEatCount++;
        }
      } else if (_spawnGraceTimer <= 0) {
        if (_isInvincible) {
          // Shield: knock back attacker
          if (_activeEffects.any((e) => e.type == PowerUpType.shield)) {
            final away = _normalize(fish.position - _player);
            fish.position += away * 140;
            fish.velocity = away * _cruiseSpeedForFish(fish) * 1.5;
            fish.stunnedTimer = .6;
          }
          continue;
        }
        if (skillL3Active) {
          final away = _normalize(fish.position - _player);
          fish.position += away * 180;
          fish.velocity = away * _cruiseSpeedForFish(fish) * 2;
          fish.stunnedTimer = .8;
          continue;
        }
        final isAttacking =
            fish.behaviorState == FishBehaviorState.attack ||
            fish.biteProgress > 0;
        if (!isAttacking) {
          if (fish.restTimer > 0) {
            // Fish is resting after previous bite, push player away
            _player -= _heading * 18;
            continue;
          }
          // Direct body collision: fish bites immediately, rest afterwards
          fish.biteProgress = .42;
          fish.behaviorState = FishBehaviorState.attack;
        }
        final spec = FishSpecs.byLevel(fish.level);
        final hidingReduction = _isInSeaweed(_player) ? .55 : 1.0;
        final damage = (spec.damage * hidingReduction).round();

        // Invincibility frames after hit
        if (_hitInvincibility > 0) {
          // Still knock back but no damage
          _player -= _heading * 20;
          continue;
        }
        _hitInvincibility = 1.5;

        _hp = max(0, _hp - damage);
        _spawnFloatingText('-$damage', const Color(0xffff5a6e), 1.2);
        HapticFeedback.heavyImpact();
        fish.biteProgress = 0;
        fish.restTimer = max(fish.restTimer, 1.1);
        fish.behaviorState = FishBehaviorState.rest;
        _player -= _heading * 40; // stronger knockback
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
          HapticFeedback.heavyImpact();
        }
      }
    }

    // ─── Fish vs fish collisions ───
    _resolveFishFishCollisions();

    // Collision with summoned fish (skill L2)
    for (var i = 0; i < _summonedFish.length; i++) {
      final fish = _summonedFish[i];
      final radius =
          _fishLength(fish.level, fish.sizeScale) *
          ui.lerpDouble(.22, .31, fish.depth)!;
      if ((_player - fish.position).distance > playerRadius + radius) continue;
      final spec = FishSpecs.byLevel(fish.level);
      _combo = _comboTimer > 0 ? _combo + 1 : 1;
      _bestCombo = max(_bestCombo, _combo);
      _comboTimer = 2.4;
      final comboBonus = _combo >= 3 ? (_combo - 2) * 20 : 0;
      final doubleMult =
          _activeEffects.any((e) => e.type == PowerUpType.doubleScore) ? 2 : 1;
      _score += (spec.score + comboBonus) * doubleMult;
      _xp += spec.xp;
      _biteTimer = .24;
      _summonedFish.removeAt(i);
      i--;
      while (_level < maxLevel && _xp >= _xpGoal) {
        _xp -= _xpGoal;
        _level += 1;
        _levelUpFlash = .5;
        HapticFeedback.heavyImpact();
      }
    }
  }

  void _resolveFishFishCollisions() {
    for (var a = 0; a < _fish.length; a++) {
      final fishA = _fish[a];
      if (fishA.level < 2) continue;
      final radiusA =
          _fishLength(fishA.level, fishA.sizeScale) *
          ui.lerpDouble(.22, .31, fishA.depth)!;

      for (var b = a + 1; b < _fish.length; b++) {
        final fishB = _fish[b];
        final levelDiff = (fishA.level - fishB.level).abs();
        if (levelDiff < 2) continue;

        final radiusB =
            _fishLength(fishB.level, fishB.sizeScale) *
            ui.lerpDouble(.22, .31, fishB.depth)!;
        final dist = (fishA.position - fishB.position).distance;
        if (dist > radiusA + radiusB) continue;

        final bigger = fishA.level > fishB.level ? fishA : fishB;
        final smaller = fishA.level > fishB.level ? fishB : fishA;
        final smallerIdx = fishA.level > fishB.level ? b : a;
        if (smaller.level < 2) continue;
        if (bigger.restTimer > 0) continue;

        // Smaller fish gets eaten — reduce count at high levels
        if (_fish.length > _effectiveFishCount) {
          _fish.removeAt(smallerIdx);
        } else {
          _fish[smallerIdx] = _spawnFish(awayFromPlayer: smaller.position);
        }
        bigger.restTimer = max(bigger.restTimer, .6);
        bigger.behaviorState = FishBehaviorState.rest;
        // Break inner loop since fish array was modified
        break;
      }
    }
  }

  void _showFeedback(String text) {
    _feedbackText = text;
    _feedbackTimer = text.isEmpty ? 0 : 1.2;
  }

  void _spawnFloatingText(String text, Color color, [double lifetime = 1.0]) {
    // Convert player world position to screen position
    final screenPos = (_player - _camera) * _cameraZoom;
    _floatingNumbers.add(_FloatingNumber(
      position: screenPos,
      text: text,
      color: color,
      lifetime: lifetime,
    ));
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

  double _playerSpeedForLevel(int level) =>
      _baseSpeedForLevel(level) + max(4, 22 - level);

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

  // ─── Power-ups ───

  void _updatePowerUps(double dt) {
    _powerUpSpawnTimer -= dt;
    if (_powerUpSpawnTimer <= 0 && _powerUps.length < _maxPowerUpsOnMap) {
      _spawnPowerUp();
      _powerUpSpawnTimer = 15 + _random.nextDouble() * 10;
    }

    for (var i = _powerUps.length - 1; i >= 0; i--) {
      _powerUps[i].timer += dt;
      if (_powerUps[i].timer >= _powerUps[i].lifetime) {
        _powerUps.removeAt(i);
      }
    }
  }

  void _spawnPowerUp() {
    final types = PowerUpType.values;
    final weights = [22, 20, 12, 10, 6, 5, 3]; // rarity weights
    var total = 0;
    for (final w in weights) {
      total += w;
    }
    var roll = _random.nextInt(total);
    var idx = 0;
    for (var i = 0; i < weights.length; i++) {
      roll -= weights[i];
      if (roll < 0) {
        idx = i;
        break;
      }
    }

    final margin = 100.0;
    final pos = Offset(
      margin + _random.nextDouble() * max(1, _world.width - margin * 2),
      margin + _random.nextDouble() * max(1, _world.height - margin * 2),
    );
    _powerUps.add(PowerUp(type: types[idx], position: pos));
  }

  void _resolvePowerUpCollisions() {
    for (var i = _powerUps.length - 1; i >= 0; i--) {
      final pu = _powerUps[i];
      if ((_player - pu.position).distance <
          pu.radius + _fishLength(_level) * .35) {
        _applyPowerUpEffect(pu.type);
        _powerUps.removeAt(i);
      }
    }
  }

  void _applyPowerUpEffect(PowerUpType type) {
    double duration;
    switch (type) {
      case PowerUpType.boost:
        duration = 5;
        break;
      case PowerUpType.magnet:
        duration = 8;
        break;
      case PowerUpType.shield:
        duration = 6;
        break;
      case PowerUpType.poison:
        duration = 3;
        break;
      case PowerUpType.doubleScore:
        duration = 10;
        break;
      case PowerUpType.vortex:
        duration = 3;
        break;
      case PowerUpType.star:
        duration = 5;
        break;
    }
    // Remove existing effect of same type
    _activeEffects.removeWhere((e) => e.type == type);
    _activeEffects.add(ActiveEffect(type: type, remaining: duration));
    HapticFeedback.mediumImpact();
  }

  String puLabel(PowerUpType type) {
    switch (type) {
      case PowerUpType.boost:
        return '⚡ 衝刺';
      case PowerUpType.magnet:
        return '🧲 磁鐵';
      case PowerUpType.shield:
        return '🛡 護盾';
      case PowerUpType.poison:
        return '💀 毒霧';
      case PowerUpType.doubleScore:
        return '✨ 雙倍';
      case PowerUpType.vortex:
        return '🌪 漩渦';
      case PowerUpType.star:
        return '💎 無敵星';
    }
  }

  void _updateActiveEffects(double dt) {
    for (var i = _activeEffects.length - 1; i >= 0; i--) {
      _activeEffects[i].remaining -= dt;
      if (_activeEffects[i].remaining <= 0) {
        if (_activeEffects[i].type == PowerUpType.poison) {
          _poisonTrail.clear();
        }
        _activeEffects.removeAt(i);
      }
    }
  }

  void _updatePoisonTrail(double dt) {
    if (!_activeEffects.any((e) => e.type == PowerUpType.poison)) {
      if (_poisonTrail.isNotEmpty) {
        _poisonTrail.removeAt(0);
      }
    }
    // Fade old trail points
    if (_poisonTrail.length > 60) {
      _poisonTrail.removeRange(0, _poisonTrail.length - 60);
    }
  }

  // ─── Skills ───

  void _updateSkillCooldown(double dt) {
    for (var i = 0; i < _skillCooldowns.length; i++) {
      _skillCooldowns[i] = max(0, _skillCooldowns[i] - dt);
    }
    _skillEffectTimer = max(0, _skillEffectTimer - dt);
    _summonTimer = max(0, _summonTimer - dt);

    // Sonic wave (Group 1 tier 1): expand 0.3s, then sustain at max radius
    if (_activeSkillGroup == 1 && _skillEffectTimer > 0 && _level >= 5) {
      final elapsed = 3.0 - _skillEffectTimer;
      _sonicWaveRadius = (40 + (elapsed / .3) * 240).clamp(40.0, 280.0);
    } else {
      _sonicWaveRadius = 0;
    }

    // Summon despawn (Group 0 tier 1)
    if (_summonTimer <= 0 && _summonedFish.isNotEmpty) {
      _summonedFish.clear();
    }

    // Inflate cleanup (Group 0 tier 2)
    if (_activeSkillGroup == 0 &&
        _skillEffectTimer <= 0 &&
        _playerSizeMultiplier > 1.0) {
      _playerSizeMultiplier = 1.0;
    }

    // Berserk cleanup (Group 4)
    if (_activeSkillGroup == 4 && _skillEffectTimer <= 0) {
      _berserkSpeedMult = 1.0;
      _berserkEatMult = 1.0;
    }
  }

  void _useSkill(int groupIndex) {
    if (groupIndex < 0 || groupIndex >= 5) return;
    if (_skillCooldowns[groupIndex] > 0) return;
    final group = SkillGroup.byIndex(groupIndex);
    if (group == null || !group.isUnlocked(_level)) return;

    _skillCooldowns[groupIndex] = group.cooldown;
    _activeSkillGroup = groupIndex;
    final tier = group.tierAt(_level);

    HapticFeedback.heavyImpact();

    switch (groupIndex) {
      case 0: // 閃避衝刺 (Lv.1-3)
        _skillEffectTimer = .3;
        _player += _heading * _fishLength(_level) * 3;
        if (tier >= 1 && _level >= 2) {
          // Summon small fish
          _summonTimer = 8;
          _summonedFish.clear();
          for (var i = 0; i < 3; i++) {
            final angle = _random.nextDouble() * pi * 2;
            final dist = 60 + _random.nextDouble() * 40;
            final pos = _player + Offset(cos(angle), sin(angle)) * dist;
            _summonedFish.add(
              FishEntity(
                position: pos,
                velocity: _heading * 60,
                level: max(1, _level - 2),
                depth: _random.nextDouble(),
                sizeScale: .85 + _random.nextDouble() * .1,
                speedScale: .9,
                predator: false,
                chaseTimer: 0,
                restTimer: 99,
                wanderTimer: 99,
                behaviorState: FishBehaviorState.wander,
              ),
            );
          }
        }
        if (tier >= 2) {
          // Inflate
          _skillEffectTimer = 2;
          _playerSizeMultiplier = 3.0;
        }
        break;

      case 1: // 血性狂咬 (Lv.4-6)
        _skillEffectTimer = 3;
        _skillEatCount = 0;
        if (tier >= 1) {
          // Sonic wave
          _sonicWaveRadius = 40;
        }
        break;

      case 2: // 渦流吸引 (Lv.7-9)
        _skillEffectTimer = 3 + tier * 0.5; // 3, 3.5, 4s
        break;

      case 3: // 深淵怒吼 (Lv.10-12)
        _skillEffectTimer = 0.3; // brief cast
        _showFeedback('💥 ${group.tierNames[tier]}');
        // Apply stun to all fish
        final allFish = [..._fish, ..._summonedFish];
        for (final f in allFish) {
          f.stunnedTimer = 1.5 + tier * 0.5; // 1.5, 2.0, 2.5s
          if (tier >= 1 && tier < 2) {
            // Push fish away
            final away = _normalize(f.position - _player);
            f.position += away * 200;
          }
        }
        if (tier >= 2) {
          // Kill fish 2+ levels below directly
          _fish.removeWhere((f) => f.level <= _level - 2);
          _summonedFish.removeWhere((f) => f.level <= _level - 2);
          // Respawn to maintain count
          while (_fish.length < _effectiveFishCount) {
            _fish.add(_spawnFish(awayFromPlayer: _player));
          }
        }
        break;

      case 4: // 狂暴獵殺 (Lv.13-18)
        _skillEffectTimer = tier >= 4 ? 3 : 4;
        if (tier >= 5) {
          _berserkSpeedMult = 3.0;
          _berserkEatMult = 3.0;
        } else if (tier >= 4) {
          _berserkSpeedMult = 3.0;
          _berserkEatMult = 3.0;
        } else if (tier >= 3) {
          _berserkSpeedMult = 2.5;
          _berserkEatMult = 2.5;
        } else if (tier >= 2) {
          _berserkSpeedMult = 2.0;
          _berserkEatMult = 2.0;
        } else if (tier >= 1) {
          _berserkSpeedMult = 1.5;
          _berserkEatMult = 1.5;
        } else {
          _berserkSpeedMult = 1.5;
          _berserkEatMult = 1.5;
        }
        // Tier 5: also kill small fish
        if (tier >= 5) {
          _fish.removeWhere((f) => f.level <= _level - 2);
          _summonedFish.removeWhere((f) => f.level <= _level - 2);
          while (_fish.length < _effectiveFishCount) {
            _fish.add(_spawnFish(awayFromPlayer: _player));
          }
        }
        break;
    }
  }

  // ─── Obstacles ───

  void _updateObstacles(double dt) {
    // Later levels: obstacles spawn more frequently
    final obstacleMult = 1.0 - (_level - 1) * .035; // 1.0→0.4 at Lv.18
    _hookTimer -= dt;
    if (_hookTimer <= 0) {
      _spawnHook();
      _hookTimer = (25 + _random.nextDouble() * 10) * obstacleMult;
    }

    _poisonTideTimer -= dt;
    if (_poisonTideTimer <= 0) {
      _spawnPoisonTide();
      _poisonTideTimer = (18 + _random.nextDouble() * 15) * obstacleMult;
    }

    _sharkTimer -= dt;
    if (_sharkTimer <= 0) {
      _spawnAiShark();
      _sharkTimer = (35 + _random.nextDouble() * 25) * obstacleMult;
    }

    for (var i = _obstacles.length - 1; i >= 0; i--) {
      final obs = _obstacles[i];
      obs.timer += dt;

      if (obs.type == ObstacleType.hook) {
        if (obs.timer > obs.lifetime) {
          _obstacles.removeAt(i);
        }
      } else if (obs.type == ObstacleType.aiShark) {
        final toPlayer = _player - obs.position;
        obs.velocity =
            _normalize(toPlayer) * _playerSpeedForLevel(_level) * 1.0;
        obs.position += obs.velocity * dt;
        if (obs.timer > 15) _obstacles.removeAt(i);
      } else if (obs.type == ObstacleType.poisonTide) {
        if (obs.timer > obs.lifetime) _obstacles.removeAt(i);
      } else if (obs.type == ObstacleType.whirlpool) {
        for (final fish in [..._fish, ..._summonedFish]) {
          final dist = (fish.position - obs.position).distance;
          if (dist < obs.radius && dist > 10) {
            final tangent = Offset(
              -(fish.position.dy - obs.position.dy),
              fish.position.dx - obs.position.dx,
            );
            fish.position +=
                _normalize(tangent) * 60 * dt +
                _normalize(obs.position - fish.position) * 40 * dt;
          }
        }
      }
    }
  }

  void _spawnHook() {
    final margin = 100.0;
    _obstacles.add(
      Obstacle(
        type: ObstacleType.hook,
        position: Offset(
          margin + _random.nextDouble() * max(1, _world.width - margin * 2),
          -30,
        ),
        lifetime: 5,
        width: 40,
        height: 80,
      ),
    );
  }

  void _spawnPoisonTide() {
    final margin = 120.0;
    _obstacles.add(
      Obstacle(
        type: ObstacleType.poisonTide,
        position: Offset(
          margin + _random.nextDouble() * max(1, _world.width - margin * 2),
          margin + _random.nextDouble() * max(1, _world.height - margin * 2),
        ),
        lifetime: 15,
        radius: 70 + _random.nextDouble() * 60,
      ),
    );
  }

  void _spawnAiShark() {
    final side = _random.nextInt(4);
    Offset pos;
    if (side == 0) {
      pos = Offset(-60, _random.nextDouble() * _world.height);
    } else if (side == 1) {
      pos = Offset(_world.width + 60, _random.nextDouble() * _world.height);
    } else if (side == 2) {
      pos = Offset(_random.nextDouble() * _world.width, -60);
    } else {
      pos = Offset(_random.nextDouble() * _world.width, _world.height + 60);
    }
    _obstacles.add(
      Obstacle(
        type: ObstacleType.aiShark,
        position: pos,
        radius: 70,
        lifetime: 15,
      ),
    );
  }

  void _spawnReefs() {
    final margin = 160.0;
    for (var i = 0; i < 6; i++) {
      _obstacles.add(
        Obstacle(
          type: ObstacleType.reef,
          position: Offset(
            margin + _random.nextDouble() * max(1, _world.width - margin * 2),
            _world.height * (.3 + _random.nextDouble() * .6),
          ),
          radius: 50 + _random.nextDouble() * 60,
        ),
      );
    }
  }

  void _spawnWhirlpools() {
    final margin = 200.0;
    for (var i = 0; i < 1; i++) {
      _obstacles.add(
        Obstacle(
          type: ObstacleType.whirlpool,
          position: Offset(
            margin + _random.nextDouble() * max(1, _world.width - margin * 2),
            _world.height * (.25 + _random.nextDouble() * .6),
          ),
          radius: 90 + _random.nextDouble() * 70,
        ),
      );
    }
  }

  void _spawnCurrents() {
    // Fewer currents at higher levels — big fish shouldn't be pushed around
    int count;
    if (_level <= 5) {
      count = 4;
    } else if (_level <= 10) {
      count = 3;
    } else if (_level <= 14) {
      count = 2;
    } else if (_level <= 16) {
      count = 1;
    } else {
      return; // Lv17+: no currents
    }
    final margin = 200.0;
    for (var i = 0; i < count; i++) {
      _obstacles.add(
        Obstacle(
          type: ObstacleType.current,
          position: Offset(
            margin + _random.nextDouble() * max(1, _world.width - margin * 2),
            _world.height * (.25 + _random.nextDouble() * .6),
          ),
          radius: 60,
          width: 220 + _random.nextDouble() * 180,
          height: 40,
          angle: _random.nextDouble() * pi * 2,
        ),
      );
    }
  }

  void _resolveObstacleCollisions() {
    if (_isInvincible || _spawnGraceTimer > 0) return;

    for (var i = _obstacles.length - 1; i >= 0; i--) {
      final obs = _obstacles[i];
      final dist = (_player - obs.position).distance;
      final playerR = _fishLength(_level) * .28;

      if (obs.type == ObstacleType.hook) {
        if (dist < obs.width * .8 + playerR) {
          _hp = max(0, _hp - 30);
          _spawnFloatingText('-30', const Color(0xffff5a6e), 1.2);
          HapticFeedback.mediumImpact();
          _player -= _heading * 35;
          _obstacles.removeAt(i);
          if (_hp <= 0) _gameOver = true;
        }
      } else if (obs.type == ObstacleType.aiShark) {
        if (dist < obs.radius * .6 + playerR) {
          final sharkDamage = (_maxHp * 0.75).round(); // reduce to ~1/4 HP
          _hp = max(1, _hp - sharkDamage);
          _spawnFloatingText('-$sharkDamage', const Color(0xffff5a6e), 1.0);
          HapticFeedback.heavyImpact();
          _player -= _heading * 50;
          _obstacles.removeAt(i); // shark disappears after hit
        }
      } else if (obs.type == ObstacleType.poisonTide) {
        if (dist < obs.radius + playerR) {
          _hp = max(0, _hp - (5 * (1 / 20)).round());
          if (_hp <= 0) _gameOver = true;
        }
      } else if (obs.type == ObstacleType.whirlpool) {
        if (dist < obs.radius * .4) {
          _player = Offset(
            _random.nextDouble() * (_world.width - 200) + 100,
            _random.nextDouble() * (_world.height - 200) + 100,
          );
        }
      } else if (obs.type == ObstacleType.reef) {
        if (dist < obs.radius * .7 + playerR) {
          final away = _normalize(_player - obs.position);
          _player += away * 50;
          // Stun: freeze briefly
          _isChasing = false;
        }
      } else if (obs.type == ObstacleType.current) {
        if (dist < obs.width * .5) {
          final dir = Offset(cos(obs.angle), sin(obs.angle));
          _player += dir * 180 * (1 / 60);
        }
      }
    }
  }

  // ─── Screen to world ───

  Offset _screenToWorld(Offset screenPos) {
    return _camera + screenPos / _cameraZoom;
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _gameOver,
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) => KeyEventResult.ignored,
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
                                  lv15Image: _lv15Image,
                                  lv16Image: _lv16Image,
                                  lv17Image: _lv17Image,
                                  lv18Image: _lv18Image,
                                  fish: [..._fish, ..._summonedFish],
                                  player: _player,
                                  playerLevel: _level,
                                  playerHeading: _heading,
                                  playerHidden: _isInSeaweed(_player),
                                  playerBite: sin(
                                    (1 - (_biteTimer / .24).clamp(0.0, 1.0)) *
                                        pi,
                                  ),
                                  seaweed: _seaweed,
                                  fishLength: _fishLength,
                                  camera: _camera,
                                  zoom: _cameraZoom,
                                  world: _world,
                                  screen: _screen,
                                  powerUps: _powerUps,
                                  obstacles: _obstacles,
                                  activeEffects: _activeEffects,
                                  isBoosting: _isBoosting,
                                  isBerserk:
                                      _activeSkillGroup == 4 &&
                                      _skillEffectTimer > 0,
                                  levelUpFlash: _levelUpFlash,
                                  poisonTrail: _poisonTrail,
                                  playerSizeMultiplier: _playerSizeMultiplier,
                                  sonicWaveRadius: _sonicWaveRadius,
                                  isInvincible: _isInvincible,
                                  skillL3Active:
                                      _activeSkillGroup == 0 &&
                                      _skillEffectTimer > 0,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_tapAlpha > 0 && _tapWorldPos != null)
                  CustomPaint(
                    painter: TapIndicatorPainter(
                      worldPos: _tapWorldPos!,
                      camera: _camera,
                      zoom: _cameraZoom,
                      alpha: _tapAlpha,
                    ),
                  ),
                if (_floatingNumbers.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _FloatingNumbersPainter(
                          numbers: _floatingNumbers,
                        ),
                      ),
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
                if (_useJoystick &&
                    _joystickOrigin != null &&
                    _joystickCurrent != null)
                  CustomPaint(
                    painter: _JoystickPainter(
                      origin: _joystickOrigin!,
                      current: _joystickCurrent!,
                    ),
                  ),
                // HUD
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Hud(
                          level: _level,
                          hp: _hp,
                          maxHp: _maxHp,
                          xp: _xp,
                          xpGoal: _xpGoal,
                          boostSize: _playerSizeMultiplier,
                        ),
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _MenuButton(onTap: _openPauseMenu),
                            const Spacer(),
                            // Active power-up indicators
                            if (_activeEffects.isNotEmpty)
                              _ActiveEffectsBar(effects: _activeEffects),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Spacer(),
                            // Skill + Boost buttons (scrollable if overflow)
                            Flexible(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true, // right-aligned
                                child: Row(
                                  children: [
                                    for (var i = 0; i < 5; i++)
                                      if (SkillGroup.byIndex(
                                        i,
                                      )!.isUnlocked(_level))
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: _SkillButton(
                                            group: SkillGroup.byIndex(i)!,
                                            cooldown: _skillCooldowns[i],
                                            active:
                                                _activeSkillGroup == i &&
                                                _skillEffectTimer > 0,
                                            onTap: () => _useSkill(i),
                                          ),
                                        ),
                                    const SizedBox(width: 4),
                                    _BoostButton(
                                      isBoosting: _isBoosting,
                                      cooldown: _boostCooldown,
                                      cooldownMax: _boostCooldownTime,
                                      onTap: () => _startBoosting(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: _ScoreBadge(score: _score)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
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
// World background painter
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
// Tap indicator
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

    final radius = 16 + (1 - alpha) * 14;
    canvas.drawCircle(screenPos, radius, paint);

    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: alpha * .7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screenPos, 4, innerPaint);
  }

  @override
  bool shouldRepaint(covariant TapIndicatorPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════
// HUD
// ═══════════════════════════════════════════════════

class _Hud extends StatelessWidget {
  const _Hud({
    required this.level,
    required this.hp,
    required this.maxHp,
    required this.xp,
    required this.xpGoal,
    required this.boostSize,
  });

  final int level;
  final int hp;
  final int maxHp;
  final int xp;
  final int xpGoal;
  final double boostSize;

  @override
  Widget build(BuildContext context) {
    final xpValue = xpGoal == 0 ? 1.0 : (xp / xpGoal).clamp(0.0, 1.0);
    final sizePercent = (boostSize * 100).round();
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
                if (boostSize < .98) ...[
                  const SizedBox(width: 8),
                  Text(
                    '體 $sizePercent%',
                    style: TextStyle(
                      color: boostSize < .3
                          ? const Color(0xffff3157)
                          : const Color(0xfff0c040),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: _Bar(
                    value: hp / maxHp,
                    color: const Color(0xffff3157),
                  ),
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

// ═══════════════════════════════════════════════════
// Boost button (bottom-right)
// ═══════════════════════════════════════════════════

class _BoostButton extends StatelessWidget {
  const _BoostButton({
    required this.isBoosting,
    required this.cooldown,
    required this.cooldownMax,
    required this.onTap,
  });

  final bool isBoosting;
  final double cooldown;
  final double cooldownMax;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ready = cooldown <= 0 && !isBoosting;
    final progress = ready
        ? 1.0
        : 1.0 - ((isBoosting ? 0 : cooldown) / cooldownMax).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (ready) onTap();
      },
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isBoosting
                      ? const Color(0xff00bcd4)
                      : ready
                      ? const Color(0xfff0c040)
                      : Colors.white.withValues(alpha: .25),
                ),
              ),
            ),
            Text(
              '🚀',
              style: TextStyle(
                fontSize: 16,
                color: ready ? Colors.white : Colors.white38,
              ),
            ),
            if (!ready && !isBoosting)
              Positioned(
                bottom: 4,
                child: Text(
                  '${cooldown.ceil()}s',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Skill button (bottom-right)
// ═══════════════════════════════════════════════════

class _SkillButton extends StatelessWidget {
  const _SkillButton({
    required this.group,
    required this.cooldown,
    required this.active,
    required this.onTap,
  });

  final SkillGroup group;
  final double cooldown;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ready = cooldown <= 0;
    final progress = ready
        ? 1.0
        : 1.0 - (cooldown / group.cooldown).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (ready) onTap();
      },
      child: SizedBox(
        width: 56,
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  active
                      ? const Color(0xff00e676)
                      : ready
                      ? const Color(0xfff0c040)
                      : Colors.white.withValues(alpha: .25),
                ),
              ),
            ),
            Text(
              group.icon,
              style: TextStyle(
                color: ready ? Colors.white : Colors.white38,
                fontSize: 16,
              ),
            ),
            if (!ready)
              Positioned(
                bottom: 4,
                child: Text(
                  '${cooldown.ceil()}s',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Active effects bar
// ═══════════════════════════════════════════════════

class _ActiveEffectsBar extends StatelessWidget {
  const _ActiveEffectsBar({required this.effects});
  final List<ActiveEffect> effects;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: effects.map((e) {
        String icon;
        Color color;
        switch (e.type) {
          case PowerUpType.boost:
            icon = '⚡';
            color = const Color(0xff00bcd4);
            break;
          case PowerUpType.magnet:
            icon = '🧲';
            color = const Color(0xff9c27b0);
            break;
          case PowerUpType.shield:
            icon = '🛡';
            color = const Color(0xff2196f3);
            break;
          case PowerUpType.poison:
            icon = '💀';
            color = const Color(0xff4caf50);
            break;
          case PowerUpType.doubleScore:
            icon = '✨';
            color = const Color(0xffffc107);
            break;
          case PowerUpType.vortex:
            icon = '🌪';
            color = const Color(0xff607d8b);
            break;
          case PowerUpType.star:
            icon = '💎';
            color = const Color(0xffff4081);
            break;
        }
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              Text(
                '${e.remaining.ceil()}s',
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }).toList(),
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
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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

// ═══════════════════════════════════════════════════
// Floating damage/heal numbers
// ═══════════════════════════════════════════════════

class _FloatingNumber {
  _FloatingNumber({
    required this.position,
    required this.text,
    required this.color,
    required this.lifetime,
  }) : maxLifetime = lifetime;

  Offset position;
  final String text;
  final Color color;
  double lifetime;
  final double maxLifetime;
  double get alpha => (lifetime / (lifetime + 0.35)).clamp(0.0, 1.0);
  bool get isDead => lifetime <= 0;

  void update(double dt) {
    lifetime -= dt;
    position = Offset(position.dx, position.dy - 44 * dt);
  }
}

class _FloatingNumbersPainter extends CustomPainter {
  _FloatingNumbersPainter({required this.numbers});

  final List<_FloatingNumber> numbers;

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in numbers) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: n.text,
          style: TextStyle(
            color: n.color.withValues(alpha: n.alpha),
            fontSize: 22,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 4,
                offset: const Offset(1, 2),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Slight horizontal wobble
      final wobble = sin(n.maxLifetime - n.lifetime * 6) * 8;
      textPainter.paint(
        canvas,
        Offset(n.position.dx - textPainter.width / 2 + wobble,
               n.position.dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FloatingNumbersPainter oldDelegate) => true;
}
