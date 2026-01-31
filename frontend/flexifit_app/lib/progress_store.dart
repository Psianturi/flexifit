import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ProgressStore {
  static const String goalKey = 'daily_goal';
  static const String completionsKey = 'completions_by_date';
  static const String chatHistoryKey = 'chat_history_v1';

  static String _todayKey(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<String?> getGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(goalKey);
  }

  static Future<void> setGoal(String goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(goalKey, goal);
  }

  static Future<Map<String, bool>> getCompletions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(completionsKey);
    if (raw == null || raw.isEmpty) return {};

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};

    return decoded.map<String, bool>((key, value) {
      return MapEntry(key.toString(), value == true);
    });
  }

  static Future<void> _setCompletions(Map<String, bool> completions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(completionsKey, jsonEncode(completions));
  }

  static Future<void> markDoneToday() async {
    final now = DateTime.now();
    final completions = await getCompletions();
    completions[_todayKey(now)] = true;
    await _setCompletions(completions);
  }

  static Future<void> markNotDoneToday() async {
    final now = DateTime.now();
    final completions = await getCompletions();
    completions[_todayKey(now)] = false;
    await _setCompletions(completions);
  }

  static int computeStreak(Map<String, bool> completions, {DateTime? now}) {
    final base = now ?? DateTime.now();
    int streak = 0;

    for (int i = 0; i < 3650; i++) {
      final day = DateTime(base.year, base.month, base.day).subtract(Duration(days: i));
      final key = _todayKey(day);
      final done = completions[key] == true;
      if (done) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }

  static List<Map<String, dynamic>> last7DaysTrend(Map<String, bool> completions, {DateTime? now}) {
    final base = now ?? DateTime.now();
    final start = DateTime(base.year, base.month, base.day);

    return List.generate(7, (index) {
      final day = start.subtract(Duration(days: 6 - index));
      final key = _todayKey(day);
      return {
        'date': key,
        'done': completions[key] == true,
      };
    });
  }

  static double completionRate7d(Map<String, bool> completions, {DateTime? now}) {
    final trend = last7DaysTrend(completions, now: now);
    final doneCount = trend.where((d) => d['done'] == true).length;
    return (doneCount / 7.0) * 100.0;
  }

  static Future<List<Map<String, dynamic>>> getChatHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(chatHistoryKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];

    return decoded.whereType<Map>().map((m) {
      return {
        'role': m['role']?.toString() ?? 'user',
        'text': m['text']?.toString() ?? '',
        'createdAt': m['createdAt']?.toString(),
      };
    }).toList();
  }

  static Future<void> setChatHistory(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = items.length > 20 ? items.sublist(items.length - 20) : items;
    await prefs.setString(chatHistoryKey, jsonEncode(trimmed));
  }
}
