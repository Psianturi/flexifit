import 'package:flutter/material.dart';

import 'api_service.dart';
import 'progress_store.dart';

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
  int? _microHabitsOffered;
  DateTime? _lastSyncedAt;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final goal = await ProgressStore.getGoal();
    final completions = await ProgressStore.getCompletions();

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
    });
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

      if (!mounted) return;
      setState(() {
        _aiInsights = result.insights;
        _microHabitsOffered = result.microHabitsOffered;
        _lastSyncedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _aiInsights = "Couldn't sync right now. Try again.";
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _syncing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final goalText = _goal ?? 'Not set';
    final insightsLines = (_aiInsights ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) {
      final normalized = l.startsWith('- ') ? l.substring(2) : l;
      return normalized.startsWith('• ') ? normalized.substring(2) : normalized;
    }).toList();

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
                  title: '7-day Rate',
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
