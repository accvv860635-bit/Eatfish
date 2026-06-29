import 'package:flutter/material.dart';

import '../models/game_map.dart';
import '../services/storage_service.dart';
import 'game_screen.dart';
import 'leaderboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  double _fishCount = 40;
  GameMap _selectedMap = GameMaps.all.first;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFishCount();
  }

  Future<void> _loadFishCount() async {
    final count = await StorageService.getFishCount();
    final mapId = await StorageService.getSelectedMapId();
    if (mounted) {
      setState(() {
        _fishCount = count.toDouble();
        _selectedMap = GameMaps.byId(mapId);
        _loading = false;
      });
    }
  }

  Future<void> _saveFishCount() async {
    await StorageService.setFishCount(_fishCount.round());
  }

  Future<void> _selectMap(GameMap map) async {
    setState(() => _selectedMap = map);
    await StorageService.setSelectedMapId(map.id);
  }

  void _startGame() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GameScreen(fishCount: _fishCount.round(), gameMap: _selectedMap),
      ),
    );
  }

  void _openLeaderboard() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff0a2a3f), Color(0xff061821), Color(0xff020d14)],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 34),
                      // 標題
                      const Text(
                        '大魚吃小魚',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '🐟 海洋生存遊戲',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xff7bb8d4),
                        ),
                      ),
                      const SizedBox(height: 26),
                      // 按鈕區
                      _GlassCard(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 魚群數量滑桿
                            const Text(
                              '場上魚群數量',
                              style: TextStyle(
                                color: Color(0xff8abfd4),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  '30',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 4,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 10,
                                      ),
                                      activeTrackColor: const Color(0xff3ee6d4),
                                      inactiveTrackColor: Colors.white
                                          .withValues(alpha: .12),
                                      thumbColor: const Color(0xff3ee6d4),
                                      overlayColor: const Color(
                                        0xff3ee6d4,
                                      ).withValues(alpha: .18),
                                    ),
                                    child: Slider(
                                      value: _fishCount,
                                      min: StorageService.minFishCount
                                          .toDouble(),
                                      max: StorageService.maxFishCount
                                          .toDouble(),
                                      divisions: 24,
                                      onChanged: (value) {
                                        setState(() => _fishCount = value);
                                        _saveFishCount();
                                      },
                                    ),
                                  ),
                                ),
                                const Text(
                                  '150',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${_fishCount.round()} 隻',
                              style: const TextStyle(
                                color: Color(0xff3ee6d4),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '選擇地圖',
                                  style: TextStyle(
                                    color: Color(0xff8abfd4),
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _selectedMap.style,
                                  style: const TextStyle(
                                    color: Color(0xff3ee6d4),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 112,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: GameMaps.all.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final map = GameMaps.all[index];
                                  return _MapChoiceCard(
                                    map: map,
                                    selected: map.id == _selectedMap.id,
                                    onTap: () => _selectMap(map),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 開始遊戲按鈕
                      SizedBox(
                        width: 220,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _startGame,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff18c7bb),
                            foregroundColor: const Color(0xff031417),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                            textStyle: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: const Text('開始遊戲'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 排行榜按鈕
                      SizedBox(
                        width: 220,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _openLeaderboard,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xff8abfd4),
                            side: const BorderSide(color: Color(0xff2a5a6e)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('排行榜'),
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _MapChoiceCard extends StatelessWidget {
  const _MapChoiceCard({
    required this.map,
    required this.selected,
    required this.onTap,
  });

  final GameMap map;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 132,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xff3ee6d4) : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(map.assetPath, fit: BoxFit.cover),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: .68),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    map.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    map.style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xffb8eef7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
      ),
      child: child,
    );
  }
}
