import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_record.dart';

class StorageService {
  static const _recordsKey = 'leaderboard_records';
  static const _fishCountKey = 'fish_count';
  static const _selectedMapKey = 'selected_map';
  static const int minFishCount = 30;
  static const int maxFishCount = 150;
  static const int defaultFishCount = 40;
  static const String defaultMapId = 'sunken_reef';

  static Future<List<GameRecord>> getRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recordsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => GameRecord.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRecord(GameRecord record) async {
    final records = await getRecords();
    records.add(record);
    records.sort((a, b) => b.score.compareTo(a.score));
    final top = records.take(20).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recordsKey, jsonEncode(top));
  }

  static Future<int> getFishCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_fishCountKey) ?? defaultFishCount)
        .clamp(minFishCount, maxFishCount)
        .toInt();
  }

  static Future<void> setFishCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _fishCountKey,
      count.clamp(minFishCount, maxFishCount).toInt(),
    );
  }

  static Future<String> getSelectedMapId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedMapKey) ?? defaultMapId;
  }

  static Future<void> setSelectedMapId(String mapId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedMapKey, mapId);
  }
}
