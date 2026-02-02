import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'progress_store.dart';
import 'notification_service.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => ProgressScreenState();
}

class ProgressScreenState extends State<ProgressScreen> {
  String? _goal;
  int _streak = 0;
  double _completionRate7d = 0;
  List<Map<String, dynamic>> _trend7d = const [];
  bool _doneToday = false;

  bool _syncing = false;
  String? _aiInsights;
  String? _weeklyMotivation;
  int? _microHabitsOffered;
  DateTime? _lastSyncedAt;

  bool _dailyNudgeEnabled = false;
  TimeOfDay? _dailyNudgeTime;

  PersonaResult? _cachedPersona;
  bool _personaLoading = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final goal = await ProgressStore.getGoal();
    final completions = await ProgressStore.getCompletions();

    final nudgeEnabled = await ProgressStore.getDailyNudgeEnabled();
    final nudgeTime = await ProgressStore.getDailyNudgeTime();

    final streak = ProgressStore.computeStreak(completions);
    final trend = ProgressStore.last7DaysTrend(completions);
    final rate = ProgressStore.completionRate7d(completions);
    final doneToday =
        completions[DateTime.now().toIso8601String().substring(0, 10)] ==
                true ||
            await ProgressStore.isDoneToday();

    if (!mounted) return;
    setState(() {
      _goal = goal;
      _streak = streak;
      _trend7d = trend;
      _completionRate7d = rate;
      _doneToday = doneToday;

      _dailyNudgeEnabled = nudgeEnabled;
      _dailyNudgeTime = nudgeTime == null
          ? null
          : TimeOfDay(hour: nudgeTime.hour, minute: nudgeTime.minute);
    });
  }

  List<String> _normalizedInsights(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return const [];

    if (text.startsWith('[') && text.endsWith(']')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          return decoded
              .whereType<dynamic>()
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {
        // Fall back to newline-based parsing.
      }
    }

    return text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) {
      final normalized = l.startsWith('- ') ? l.substring(2) : l;
      return normalized.startsWith('• ') ? normalized.substring(2) : normalized;
    }).toList(growable: false);
  }

  Future<void> _pickDailyNudgeTime() async {
    final initial = _dailyNudgeTime ?? const TimeOfDay(hour: 17, minute: 0);
    final selected = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (selected == null) return;

    await ProgressStore.setDailyNudgeTime(
      hour: selected.hour,
      minute: selected.minute,
    );

    if (!mounted) return;
    setState(() {
      _dailyNudgeTime = selected;
    });

    if (_dailyNudgeEnabled) {
      await NotificationService.instance.scheduleDailyNudge(
        time: selected,
        goal: _goal,
      );
    }
  }

  Future<void> _setDailyNudgeEnabled(bool enabled) async {
    await ProgressStore.setDailyNudgeEnabled(enabled);

    if (!mounted) return;
    setState(() {
      _dailyNudgeEnabled = enabled;
    });

    if (!enabled) {
      await NotificationService.instance.cancelDailyNudge();
      return;
    }

    final time = _dailyNudgeTime ?? const TimeOfDay(hour: 17, minute: 0);
    if (_dailyNudgeTime == null) {
      await ProgressStore.setDailyNudgeTime(
          hour: time.hour, minute: time.minute);
      if (!mounted) return;
      setState(() {
        _dailyNudgeTime = time;
      });
    }

    await NotificationService.instance.scheduleDailyNudge(
      time: time,
      goal: _goal,
    );
  }

  Future<void> _markDoneToday() async {
    await ProgressStore.markDoneToday();
    await reload();
  }

  Future<void> _undoDoneToday() async {
    await ProgressStore.markNotDoneToday();
    await reload();
  }

  Future<void> _syncWithAi() async {
    setState(() {
      _syncing = true;
    });

    try {
      final goal = _goal ?? 'Stay Healthy';

      final completions = await ProgressStore.getCompletions();
      final trend7d = ProgressStore.last7DaysTrend(completions);
      final rate7d = ProgressStore.completionRate7d(completions);

      final history = (await ProgressStore.getChatHistory())
          .map((m) => {
                'role': m['role'],
                'text': m['text'],
              })
          .toList();

      final result = await ApiService.getProgressInsights(
        currentGoal: goal,
        history: history,
      );

      WeeklyMotivationResult? motivationResult;
      try {
        motivationResult = await ApiService.getWeeklyMotivation(
          goal: goal,
          completionRate7d: rate7d,
          last7Days: trend7d,
        );
      } catch (e) {
        debugPrint('Weekly motivation failed: $e');
        motivationResult = null;
      }

      if (!mounted) return;
      setState(() {
        _aiInsights = result.insights;
        _weeklyMotivation = (motivationResult?.motivation ?? '').trim().isEmpty
            ? null
            : motivationResult!.motivation.trim();
        _microHabitsOffered = result.microHabitsOffered;
        _lastSyncedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiInsights = "Couldn't sync right now. Try again.";
        _weeklyMotivation = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  String _assetForAvatar(String avatarId) {
    switch (avatarId.trim().toUpperCase()) {
      case 'KUNG_FU_FOX':
        return 'assets/kungfu_fox.png';
      case 'LION':
        return 'assets/lion.png';
      case 'NINJA_TURTLE':
        return 'assets/ninja_turtle.png';
      case 'SPORTY_CAT':
        return 'assets/sporty_cat.png';
      case 'WORKOUT_WOLF':
        return 'assets/workout_wolf.png';
      case 'PENGU':
      default:
        return 'assets/pengu.png';
    }
  }

  Future<PersonaResult> _fetchPersona() async {
    final goal = _goal ?? 'Stay Healthy';
    final completions = await ProgressStore.getCompletions();
    final trend7d = ProgressStore.last7DaysTrend(completions);
    final rate7d = ProgressStore.completionRate7d(completions);
    final streak = ProgressStore.computeStreak(completions);

    final history = (await ProgressStore.getChatHistory())
        .map((m) => {
              'role': m['role'],
              'text': m['text'],
            })
        .toList();

    return ApiService.getPersona(
      goal: goal,
      streak: streak,
      completionRate7d: rate7d,
      last7Days: trend7d,
      history: history,
    );
  }

  Future<void> showPersonaDialog() async {
    if (_personaLoading) return;

    setState(() {
      _personaLoading = true;
    });

    final personaFuture = _fetchPersona().then((persona) {
      if (mounted) {
        setState(() {
          _cachedPersona = persona;
        });
      }
      return persona;
    });

    if (!mounted) return;
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'persona',
        barrierColor: Colors.black.withOpacity(0.75),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, _, __) {
          return FutureBuilder<PersonaResult>(
            future: personaFuture,
            builder: (context, snapshot) {
              final done = snapshot.connectionState == ConnectionState.done;
              final p = snapshot.data ?? _cachedPersona;

              if (!done || p == null) {
                return SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Material(
                        color: Colors.transparent,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.tealAccent.withOpacity(0.20),
                                        blurRadius: 28,
                                        spreadRadius: 2,
                                      ),
                                      BoxShadow(
                                        color: Colors.teal.withOpacity(0.18),
                                        blurRadius: 48,
                                        spreadRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              clipBehavior: Clip.antiAlias,
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'GENERATING…',
                                            style: TextStyle(
                                              letterSpacing: 1.2,
                                              color: Colors.teal.shade800,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Close',
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          icon: const Icon(Icons.close),
                                        )
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Center(
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0.0, end: 1.0),
                                        duration:
                                            const Duration(milliseconds: 900),
                                        curve: Curves.easeInOut,
                                        builder: (context, value, child) {
                                          return Transform.rotate(
                                            angle: value * 6.28318,
                                            child: child,
                                          );
                                        },
                                        child: Container(
                                          width: 120,
                                          height: 120,
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            border: Border.all(
                                                color: Colors.teal.shade100),
                                          ),
                                          child: Center(
                                            child: SizedBox(
                                              width: 34,
                                              height: 34,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                                color: Colors.teal.shade700,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Unlocking your Flexi Identity…',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey.shade900,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Analyzing your last 7 days + negotiation style.",
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(begin: 0.05, end: 0.92),
                                        duration:
                                            const Duration(milliseconds: 1400),
                                        curve: Curves.easeInOutCubic,
                                        builder: (context, v, _) {
                                          return LinearProgressIndicator(
                                            minHeight: 10,
                                            value: v,
                                            backgroundColor:
                                                Colors.grey.shade200,
                                            color: Colors.teal,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              final asset = _assetForAvatar(p.avatarId);
              final powerValue = (p.powerLevel / 100.0).clamp(0.0, 1.0);

              return SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Material(
                      color: Colors.transparent,
                      child: Stack(
                        children: [
                          // Glow
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.tealAccent.withOpacity(0.20),
                                      blurRadius: 28,
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: Colors.teal.withOpacity(0.18),
                                      blurRadius: 48,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Card
                          Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            clipBehavior: Clip.antiAlias,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'IDENTITY UNLOCKED',
                                          style: TextStyle(
                                            letterSpacing: 1.2,
                                            color: Colors.teal.shade800,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Close',
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(Icons.close),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Center(
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.92, end: 1.0),
                                      duration:
                                          const Duration(milliseconds: 520),
                                      curve: Curves.easeOutBack,
                                      builder: (context, scale, child) =>
                                          Transform.scale(
                                        scale: scale,
                                        child: child,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.teal.shade50,
                                          borderRadius:
                                              BorderRadius.circular(18),
                                          border: Border.all(
                                              color: Colors.teal.shade100),
                                        ),
                                        child: Image.asset(
                                          asset,
                                          width: 140,
                                          height: 140,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    p.archetypeTitle,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    p.description,
                                    style: TextStyle(
                                      color: Colors.grey.shade800,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      const Icon(Icons.bolt, size: 18),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Power Level',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const Spacer(),
                                      Text('${p.powerLevel}/100'),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0.0, end: powerValue),
                                      duration:
                                          const Duration(milliseconds: 700),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, value, _) {
                                        return LinearProgressIndicator(
                                          minHeight: 10,
                                          value: value,
                                          backgroundColor: Colors.grey.shade200,
                                          color: Colors.teal,
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            final text =
                                                '${p.archetypeTitle}\n${p.description}\nPower: ${p.powerLevel}/100';
                                            await Clipboard.setData(
                                              ClipboardData(text: text),
                                            );
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content:
                                                    Text('Copied to clipboard'),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.copy),
                                          label: const Text('Copy'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          icon: const Icon(Icons.check_circle),
                                          label: const Text('Nice!'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _personaLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalText = _goal ?? 'Not set';
    final insightsLines = _normalizedInsights(_aiInsights);

    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatCard(
            title: 'Main Goal',
            value: goalText,
            icon: Icons.flag,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Daily Nudge',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Switch(
                        value: _dailyNudgeEnabled,
                        onChanged: (v) => _setDailyNudgeEnabled(v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A gentle daily trigger to open the app and negotiate a tiny step.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dailyNudgeTime == null
                              ? 'Time: not set'
                              : 'Time: ${_dailyNudgeTime!.hour.toString().padLeft(2, '0')}:${_dailyNudgeTime!.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickDailyNudgeTime,
                        icon: const Icon(Icons.schedule),
                        label: const Text('Pick time'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _doneToday
                          ? "Today's done is marked ✅"
                          : "Haven't marked today yet",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!_doneToday)
                    ElevatedButton.icon(
                      onPressed: _markDoneToday,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Mark DONE'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _undoDoneToday,
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Streak',
                  value: '$_streak days',
                  icon: Icons.local_fire_department,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  title: 'Weekly Consistency',
                  value: '${_completionRate7d.toStringAsFixed(0)}%',
                  icon: Icons.show_chart,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TrendCard(trend: _trend7d),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'AI Insights',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _syncing ? null : _syncWithAi,
                        icon: _syncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync),
                        label: Text(_syncing ? 'Syncing' : 'Sync with AI'),
                      ),
                    ],
                  ),
                  if (_weeklyMotivation != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.shade100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.fitness_center,
                              color: Colors.teal.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _weeklyMotivation!,
                              style: TextStyle(
                                color: Colors.teal.shade900,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_lastSyncedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Last synced: ${_lastSyncedAt!.hour.toString().padLeft(2, '0')}:${_lastSyncedAt!.minute.toString().padLeft(2, '0')}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (_microHabitsOffered != null)
                    Text(
                        'Micro-habits offered (estimated): $_microHabitsOffered'),
                  if (_aiInsights != null && insightsLines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...insightsLines.map((l) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('• $l'),
                        )),
                  ] else
                    const Text(
                        'Tap “Sync with AI” to analyze your recent chat and get guidance.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text(value,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final List<Map<String, dynamic>> trend;

  const _TrendCard({required this.trend});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Last 7 days',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: trend.map((d) {
                final done = d['done'] == true;
                final date = (d['date'] as String?) ?? '';
                final label = date.length >= 5 ? date.substring(5) : date;

                return Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: done ? Colors.green : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(label, style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
