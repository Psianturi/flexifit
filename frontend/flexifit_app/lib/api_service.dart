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
  final bool? dealMade;
  final String? dealLabel;
  final double? empathyScore;
  final String? empathyRationale;
  final String? promptVersion;
  final bool? retryUsed;
  final double? initialEmpathyScore;

  const ChatResult({
    required this.response,
    this.dealMade,
    this.dealLabel,
    this.empathyScore,
    this.empathyRationale,
    this.promptVersion,
    this.retryUsed,
    this.initialEmpathyScore,
  });
}

class PersonaResult {
  final String archetypeTitle;
  final String description;
  final String avatarId;
  final int powerLevel;

  const PersonaResult({
    required this.archetypeTitle,
    required this.description,
    required this.avatarId,
    required this.powerLevel,
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
    String? language,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/chat');

      final payload = <String, dynamic>{
        'user_message': message,
        'current_goal': currentGoal,
        'chat_history': history,
      };
      final lang = (language ?? '').trim();
      if (lang.isNotEmpty) {
        payload['language'] = lang;
      }

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 28));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ChatResult(
          response: (data is Map ? data['response']?.toString() : null) ?? '',
          dealMade: data is Map ? (data['deal_made'] == true) : null,
          dealLabel: data is Map ? data['deal_label']?.toString() : null,
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
    String? language,
  }) async {
    final url = Uri.parse('$baseUrl/progress');

    final payload = <String, dynamic>{
      'user_message': 'progress_check',
      'current_goal': currentGoal,
      'chat_history': history,
    };
    final lang = (language ?? '').trim();
    if (lang.isNotEmpty) {
      payload['language'] = lang;
    }

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
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
    String? language,
  }) async {
    final url = Uri.parse('$baseUrl/progress/motivation');

    final payload = <String, dynamic>{
      'goal': goal,
      'completion_rate_7d': completionRate7d,
      'last7_days': last7Days
          .map((d) => {
                'date': d['date'],
                'done': d['done'] == true,
              })
          .toList(),
    };
    final lang = (language ?? '').trim();
    if (lang.isNotEmpty) {
      payload['language'] = lang;
    }

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
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

  static Future<PersonaResult> getPersona({
    required String goal,
    required int streak,
    required double completionRate7d,
    required List<Map<String, dynamic>> last7Days,
    required List<Map<String, dynamic>> history,
    String? language,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/persona');

      final payload = <String, dynamic>{
        'current_goal': goal,
        'completion_rate_7d': completionRate7d,
        'streak': streak,
        'last7_days': last7Days
            .map((d) => {
                  'date': d['date'],
                  'done': d['done'] == true,
                })
            .toList(),
        'chat_history': history
            .map((m) => {
                  'role': m['role'],
                  'text': m['text'],
                })
            .toList(),
      };
      final lang = (language ?? '').trim();
      if (lang.isNotEmpty) {
        payload['language'] = lang;
      }

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? decoded['data'] : null;

      final title = (data is Map ? data['archetype_title']?.toString() : null) ??
          'The Strategic Pengu';
      final description =
          (data is Map ? data['description']?.toString() : null) ??
            "You're great at shrinking the goal while still moving forward. Slow and steady — consistency wins.";
      final avatarId =
          (data is Map ? data['avatar_id']?.toString() : null) ?? 'PENGU';
      final power = data is Map && data['power_level'] is num
          ? (data['power_level'] as num).toInt()
          : 50;

      return PersonaResult(
        archetypeTitle: title.trim().isEmpty ? 'The Strategic Pengu' : title,
        description: description.trim().isEmpty
            ? "You're great at shrinking the goal while still moving forward. Slow and steady — consistency wins."
            : description,
        avatarId: avatarId,
        powerLevel: power.clamp(1, 100),
      );
    } catch (e) {
      debugPrint('ApiService.getPersona failed: $e');
      return const PersonaResult(
        archetypeTitle: 'The Strategic Pengu',
        description:
            "You're great at shrinking the goal while still moving forward. Slow and steady — consistency wins.",
        avatarId: 'PENGU',
        powerLevel: 50,
      );
    }
  }
}
