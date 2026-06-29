import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_record.dart';
import '../services/storage_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<GameRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await StorageService.getRecords();
    if (mounted) {
      setState(() {
        _records = records;
        _loading = false;
      });
    }
  }

  Future<void> _clearRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff0a2a3f),
        title: const Text('清除紀錄',
            style: TextStyle(color: Colors.white)),
        content: const Text('確定要清除所有排行榜紀錄嗎？',
            style: TextStyle(color: Color(0xff8abfd4))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除',
                style: TextStyle(color: Color(0xffff3157))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('leaderboard_records');
      _loadRecords();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff061821),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('排行榜',
            style: TextStyle(
                fontWeight: FontWeight.w800, color: Colors.white)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        actions: _records.isNotEmpty
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.white38, size: 20),
                  onPressed: _clearRecords,
                  tooltip: '清除紀錄',
                ),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('🐟',
                          style: TextStyle(fontSize: 48)),
                      SizedBox(height: 16),
                      Text('還沒有遊戲紀錄',
                          style: TextStyle(
                              color: Color(0xff5a7d8e),
                              fontSize: 16)),
                      SizedBox(height: 4),
                      Text('快去玩一局吧！',
                          style: TextStyle(
                              color: Color(0xff3a5d6e),
                              fontSize: 14)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  itemCount: _records.length,
                  itemBuilder: (context, index) {
                    final record = _records[index];
                    final rank = index + 1;
                    final isTop3 = rank <= 3;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isTop3
                            ? const Color(0xff0f3040)
                            : Colors.white.withValues(alpha: .04),
                        borderRadius: BorderRadius.circular(12),
                        border: isTop3
                            ? Border.all(
                                color: _rankColor(rank)
                                    .withValues(alpha: .3))
                            : null,
                      ),
                      child: Row(
                        children: [
                          // 排名
                          SizedBox(
                            width: 36,
                            child: Text(
                              '#$rank',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isTop3
                                    ? _rankColor(rank)
                                    : const Color(0xff5a7d8e),
                              ),
                            ),
                          ),
                          // 獎牌
                          if (isTop3)
                            Text(
                              _rankEmoji(rank),
                              style: const TextStyle(fontSize: 20),
                            ),
                          const SizedBox(width: 8),
                          // 分數 & 等級
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Score ${record.score}',
                                  style: TextStyle(
                                    color: isTop3
                                        ? Colors.white
                                        : const Color(0xffb8d8e8),
                                    fontSize: 16,
                                    fontWeight: isTop3
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Lv.${record.level}',
                                  style: const TextStyle(
                                    color: Color(0xff5a7d8e),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 時間
                          Text(
                            record.displayDate,
                            style: const TextStyle(
                              color: Color(0xff4a6d7e),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xffffd700);
      case 2:
        return const Color(0xffc0c0c0);
      case 3:
        return const Color(0xffcd7f32);
      default:
        return const Color(0xff5a7d8e);
    }
  }

  String _rankEmoji(int rank) {
    switch (rank) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '';
    }
  }
}
