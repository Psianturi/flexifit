import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'goal_model.dart';

class ProgressStore {
  static const String goalKey = 'daily_goal';
  static const String completionsKey = 'completions_by_date';
  static const String chatHistoryKey = 'chat_history_v1';

  static const String goalHistoryKey = 'goal_history_v1';

  static const String dailyNudgeEnabledKey = 'daily_nudge_enabled_v1';
  static const String dailyNudgeHourKey = 'daily_nudge_hour_v1';
  static const String dailyNudgeMinuteKey = 'daily_nudge_minute_v1';

  static const String nightModeEnabledKey = 'night_mode_enabled_v1';

  static String _todayKey(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<bool> isDoneToday() async {
    final now = DateTime.now();
    final completions = await getCompletions();
    return completions[_todayKey(now)] == true;
  }

  static Future<String?> getGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(goalKey);
  }

  static Future<void> setGoal(String goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(goalKey, goal);
  }

  static Future<List<GoalModel>> getGoalHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(goalHistoryKey);

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final items = decoded
              .whereType<Map>()
              .map((e) => GoalModel.fromJson(Map<String, dynamic>.from(e)))
              .where((g) => g.title.trim().isNotEmpty)
              .toList(growable: false);

          // Newest-first is expected by UI.
          items.sort((a, b) => b.startDate.compareTo(a.startDate));
          return items;
        }
      } catch (_) {
        // Fall through to migration/empty.
      }
    }

    // Migration / seeding:
    // - If legacy daily_goal exists but history is missing, seed 1 active entry.
    final legacyGoal = prefs.getString(goalKey);
    if (legacyGoal != null && legacyGoal.trim().isNotEmpty) {
      final seeded = [
        GoalModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: legacyGoal.trim(),
          startDate: DateTime.now(),
          endDate: null,
          status: GoalStatus.active,
          finalStreak: 0,
        ),
      ];
      await setGoalHistory(seeded);
      return seeded;
    }

    return const [];
  }

  static Future<void> setGoalHistory(List<GoalModel> history) async {
    final prefs = await SharedPreferences.getInstance();

    final cleaned = history
        .where((g) => g.title.trim().isNotEmpty)
        .map((g) => g.copyWith(title: g.title.trim()))
        .toList(growable: false);

    // Newest-first.
    cleaned.sort((a, b) => b.startDate.compareTo(a.startDate));

    await prefs.setString(
      goalHistoryKey,
      jsonEncode(cleaned.map((g) => g.toJson()).toList(growable: false)),
    );
  }

  static Future<GoalModel?> getActiveGoal() async {
    final history = await getGoalHistory();
    try {
      return history.firstWhere((g) => g.status == GoalStatus.active);
    } catch (_) {
      return null;
    }
  }

  static Future<void> startNewGoal(
      {required String title, DateTime? now}) async {
    final newTitle = title.trim();
    if (newTitle.isEmpty) return;

    final when = now ?? DateTime.now();
    final history = await getGoalHistory();
    final active = await getActiveGoal();
    if (active != null && active.title.trim() == newTitle) {
      await setGoal(newTitle);
      return;
    }

    final updated = <GoalModel>[
      GoalModel(
        id: when.millisecondsSinceEpoch.toString(),
        title: newTitle,
        startDate: when,
        endDate: null,
        status: GoalStatus.active,
        finalStreak: 0,
      ),
      ...history.where((g) => g.status != GoalStatus.active),
    ];

    await setGoalHistory(updated);
    await setGoal(newTitle);
  }

  static Future<void> transitionGoal({
    required String newTitle,
    required String previousStatus,
    required int finalStreak,
    DateTime? now,
  }) async {
    final next = newTitle.trim();
    if (next.isEmpty) return;

    final when = now ?? DateTime.now();
    final history = await getGoalHistory();

    final normalizedStatus = GoalStatus.normalize(previousStatus);
    final archivedStatus = normalizedStatus == GoalStatus.completed
        ? GoalStatus.completed
        : GoalStatus.dropped;

    final updated = <GoalModel>[];

    bool archivedOne = false;
    for (final g in history) {
      if (!archivedOne && g.status == GoalStatus.active) {
        updated.add(
          g.copyWith(
            status: archivedStatus,
            endDate: when,
            finalStreak: finalStreak,
          ),
        );
        archivedOne = true;
        continue;
      }
      if (g.status == GoalStatus.active) {
        // Keep only one active.
        continue;
      }
      updated.add(g);
    }

    // Insert new active at top.
    updated.insert(
      0,
      GoalModel(
        id: when.millisecondsSinceEpoch.toString(),
        title: next,
        startDate: when,
        endDate: null,
        status: GoalStatus.active,
        finalStreak: 0,
      ),
    );

    await setGoalHistory(updated);
    await setGoal(next);
  }

  static Future<int> getCompletedGoalsCount() async {
    final history = await getGoalHistory();
    return history.where((g) => g.status == GoalStatus.completed).length;
  }

  static Future<void> generateFakeGoalHistoryForDemo() async {
    final now = DateTime.now();

    final active = GoalModel(
      id: now.millisecondsSinceEpoch.toString(),
      title: 'Build a 2-minute stretch habit',
      startDate: now.subtract(const Duration(days: 1)),
      endDate: null,
      status: GoalStatus.active,
      finalStreak: 0,
    );

    final completed1 = GoalModel(
      id: (now.millisecondsSinceEpoch - 1).toString(),
      title: 'Bangun Pagi',
      startDate: now.subtract(const Duration(days: 30)),
      endDate: now.subtract(const Duration(days: 18)),
      status: GoalStatus.completed,
      finalStreak: 12,
    );

    final dropped = GoalModel(
      id: (now.millisecondsSinceEpoch - 2).toString(),
      title: 'Baca Buku',
      startDate: now.subtract(const Duration(days: 17)),
      endDate: now.subtract(const Duration(days: 14)),
      status: GoalStatus.dropped,
      finalStreak: 2,
    );

    final completed2 = GoalModel(
      id: (now.millisecondsSinceEpoch - 3).toString(),
      title: 'No Sugar',
      startDate: now.subtract(const Duration(days: 13)),
      endDate: now.subtract(const Duration(days: 6)),
      status: GoalStatus.completed,
      finalStreak: 7,
    );

    // Newest-first.
    final history = [active, completed2, dropped, completed1];
    await setGoalHistory(history);
    await setGoal(active.title);
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
      final day =
          DateTime(base.year, base.month, base.day).subtract(Duration(days: i));
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

  static List<Map<String, dynamic>> last7DaysTrend(
      Map<String, bool> completions,
      {DateTime? now}) {
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

  static double completionRate7d(Map<String, bool> completions,
      {DateTime? now}) {
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
    final trimmed =
        items.length > 20 ? items.sublist(items.length - 20) : items;
    await prefs.setString(chatHistoryKey, jsonEncode(trimmed));
  }

  static Future<bool> getDailyNudgeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(dailyNudgeEnabledKey) ?? false;
  }

  static Future<void> setDailyNudgeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(dailyNudgeEnabledKey, enabled);
  }

  static Future<({int hour, int minute})?> getDailyNudgeTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(dailyNudgeHourKey);
    final minute = prefs.getInt(dailyNudgeMinuteKey);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23) return null;
    if (minute < 0 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }

  static Future<void> setDailyNudgeTime(
      {required int hour, required int minute}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(dailyNudgeHourKey, hour);
    await prefs.setInt(dailyNudgeMinuteKey, minute);
  }

  static Future<bool> getNightModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(nightModeEnabledKey) ?? false;
  }

  static Future<void> setNightModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(nightModeEnabledKey, enabled);
  }
}
