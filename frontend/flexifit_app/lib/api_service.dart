import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'app_config.dart';

class ProgressInsights {
  final String insights;
  final int? microHabitsOffered;

  const ProgressInsights({
    required this.insights,
    required this.microHabitsOffered,
  });
}

class WeeklyMotivationResult {
  final String motivation;

  const WeeklyMotivationResult({required this.motivation});
}

class ChatResult {
  final String response;
  final double? empathyScore;
  final String? empathyRationale;
  final String? promptVersion;
  final bool? retryUsed;
  final double? initialEmpathyScore;

  const ChatResult({
    required this.response,
    this.empathyScore,
    this.empathyRationale,
    this.promptVersion,
    this.retryUsed,
    this.initialEmpathyScore,
  });
}

class ApiService {
  static String get baseUrl {
    return AppConfig.apiBaseUrl;
  }

  static Future<ChatResult> sendMessage({
    required String message,
    required String currentGoal,
    required List<Map<String, String>> history,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/chat');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_message': message,
              'current_goal': currentGoal,
              'chat_history': history,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ChatResult(
          response: (data is Map ? data['response']?.toString() : null) ?? '',
          empathyScore: data is Map && data['empathy_score'] is num
              ? (data['empathy_score'] as num).toDouble()
              : null,
          empathyRationale:
              data is Map ? data['empathy_rationale']?.toString() : null,
          promptVersion: data is Map ? data['prompt_version']?.toString() : null,
          retryUsed: data is Map ? (data['retry_used'] == true) : null,
          initialEmpathyScore: data is Map && data['initial_empathy_score'] is num
              ? (data['initial_empathy_score'] as num).toDouble()
              : null,
        );
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ApiService.sendMessage failed: $e');
      debugPrint('ApiService baseUrl: $baseUrl');

      if (e is TimeoutException) {
        return const ChatResult(
          response:
              "I'm having trouble reaching the server (it may be waking up). Please try again in a moment.",
        );
      }

      // Demo safety fallbacks with DEAL_MADE integration
      if (message.toLowerCase().contains('tired') ||
          message.toLowerCase().contains('exhausted')) {
        return const ChatResult(
          response:
              "[DEAL_MADE] I understand you're tired. Let's lock in: just put on your workout clothes. That's a tiny win! 💪",
        );
      } else if (message.toLowerCase().contains('busy') ||
          message.toLowerCase().contains('time')) {
        return const ChatResult(
          response:
              "[DEAL_MADE] Busy days happen! Let's commit to: 2 minutes of your goal. Micro-habits build neural pathways! 🧠",
        );
      } else if (message.toLowerCase().contains('ready') ||
          message.toLowerCase().contains('action')) {
        return const ChatResult(
          response:
              "[DEAL_MADE] Love the energy! Let's lock in: your full goal today! Consistency beats intensity! 🔥",
        );
      }
      return const ChatResult(
        response:
            "Connection issue, but here's what I know: tiny habits beat big goals. What's the smallest step you can take? 🤖",
      );
    }
  }

  static Future<bool> checkConnection() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<ProgressInsights> getProgressInsights({
    required String currentGoal,
    required List<Map<String, dynamic>> history,
  }) async {
    final url = Uri.parse('$baseUrl/progress');

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'user_message': 'progress_check',
            'current_goal': currentGoal,
            'chat_history': history,
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final data = decoded is Map ? decoded['data'] : null;

    final insights = (data is Map ? (data['insights']?.toString()) : null) ??
        'No insights yet.';
    final microHabitsOffered =
        data is Map && data['micro_habits_offered'] is num
            ? (data['micro_habits_offered'] as num).toInt()
            : null;

    return ProgressInsights(
      insights: insights,
      microHabitsOffered: microHabitsOffered,
    );
  }

  static Future<WeeklyMotivationResult> getWeeklyMotivation({
    required String goal,
    required double completionRate7d,
    required List<Map<String, dynamic>> last7Days,
  }) async {
    final url = Uri.parse('$baseUrl/progress/motivation');

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'goal': goal,
            'completion_rate_7d': completionRate7d,
            'last7_days': last7Days
                .map((d) => {
                      'date': d['date'],
                      'done': d['done'] == true,
                    })
                .toList(),
          }),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Server error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final data = decoded is Map ? decoded['data'] : null;
    final motivation =
        (data is Map ? data['motivation']?.toString() : null) ?? '';

    return WeeklyMotivationResult(motivation: motivation);
  }
}
