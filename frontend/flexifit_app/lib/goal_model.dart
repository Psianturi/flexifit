class GoalStatus {
  static const String active = 'active';
  static const String completed = 'completed';
  static const String dropped = 'dropped';

  static const Set<String> values = {active, completed, dropped};

  static String normalize(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    return values.contains(v) ? v : active;
  }
}

class GoalModel {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime? endDate;
  final String status;
  final int finalStreak;

  const GoalModel({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.finalStreak,
  });

  bool get isActive => status == GoalStatus.active;

  GoalModel copyWith({
    String? id,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    int? finalStreak,
  }) {
    return GoalModel(
      id: id ?? this.id,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      finalStreak: finalStreak ?? this.finalStreak,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'status': status,
      'finalStreak': finalStreak,
    };
  }

  static GoalModel fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final title = json['title']?.toString().trim();
    final startRaw = json['startDate']?.toString();
    final endRaw = json['endDate']?.toString();

    final start =
        startRaw == null ? null : DateTime.tryParse(startRaw)?.toLocal();
    final end = endRaw == null ? null : DateTime.tryParse(endRaw)?.toLocal();

    final status = GoalStatus.normalize(json['status']?.toString());

    final streakRaw = json['finalStreak'];
    int streak = 0;
    if (streakRaw is int) {
      streak = streakRaw;
    } else if (streakRaw is num) {
      streak = streakRaw.toInt();
    } else {
      streak = int.tryParse(streakRaw?.toString() ?? '') ?? 0;
    }

    return GoalModel(
      id: (id == null || id.isEmpty)
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : id,
      title: title ?? '',
      startDate: start ?? DateTime.now(),
      endDate: end,
      status: status,
      finalStreak: streak,
    );
  }
}
