import 'package:flutter/material.dart';

import 'app_config.dart';
import 'goal_model.dart';
import 'progress_store.dart';

class JourneyHistoryScreen extends StatefulWidget {
  const JourneyHistoryScreen({super.key});

  @override
  State<JourneyHistoryScreen> createState() => _JourneyHistoryScreenState();
}

class _JourneyHistoryScreenState extends State<JourneyHistoryScreen> {
  bool _loading = true;
  String _filter = 'all';
  List<GoalModel> _history = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
    });

    final history = await ProgressStore.getGoalHistory();

    if (!mounted) return;
    setState(() {
      _history = history;
      _loading = false;
    });
  }

  List<GoalModel> get _filtered {
    final items = _history;

    if (_filter == 'completed') {
      return items
          .where((g) => g.status == GoalStatus.completed)
          .toList(growable: false);
    }

    if (_filter == 'dropped') {
      return items
          .where((g) => g.status == GoalStatus.dropped)
          .toList(growable: false);
    }

    return items;
  }

  Color _statusColor(String status) {
    switch (status) {
      case GoalStatus.completed:
        return Colors.green;
      case GoalStatus.dropped:
        return Colors.red;
      case GoalStatus.active:
      default:
        return Colors.amber.shade700;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case GoalStatus.completed:
        return Icons.check_circle;
      case GoalStatus.dropped:
        return Icons.cancel;
      case GoalStatus.active:
      default:
        return Icons.play_circle_fill;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case GoalStatus.completed:
        return 'Conquered';
      case GoalStatus.dropped:
        return 'Dropped';
      case GoalStatus.active:
      default:
        return 'Active';
    }
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _confirmGenerateFakeHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate sample journey?'),
        content: const Text(
          'This will overwrite your saved goal timeline on this device.\n\nUse only for demo/screenshots.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await ProgressStore.generateFakeGoalHistoryForDemo();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final canGenerateFake = AppConfig.showDebugEvals;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: canGenerateFake ? _confirmGenerateFakeHistory : null,
          child: const Text('Your Journey'),
        ),
        actions: [
          if (canGenerateFake)
            IconButton(
              tooltip: 'Generate sample journey',
              icon: const Icon(Icons.auto_awesome),
              onPressed: _confirmGenerateFakeHistory,
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _filter == 'all',
                        onSelected: (_) => setState(() => _filter = 'all'),
                      ),
                      ChoiceChip(
                        label: const Text('Completed'),
                        selected: _filter == 'completed',
                        onSelected: (_) =>
                            setState(() => _filter = 'completed'),
                      ),
                      ChoiceChip(
                        label: const Text('Failed'),
                        selected: _filter == 'dropped',
                        onSelected: (_) => setState(() => _filter = 'dropped'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No goals yet. Set your first goal in Chat, then come back here to see your timeline.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final g = _filtered[index];
                            final color = _statusColor(g.status);

                            final isFirst = index == 0;
                            final isLast = index == _filtered.length - 1;

                            final subtitle = g.endDate == null
                                ? 'Started ${_formatDate(g.startDate)}'
                                : '${_formatDate(g.startDate)} → ${_formatDate(g.endDate!)}';

                            final streakText = g.isActive
                                ? null
                                : 'Final streak: ${g.finalStreak} days';

                            return _TimelineRow(
                              color: color,
                              isFirst: isFirst,
                              isLast: isLast,
                              child: Card(
                                elevation: g.isActive ? 3 : 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: g.isActive
                                      ? BorderSide(
                                          color: Colors.amber.shade200,
                                          width: 1.2,
                                        )
                                      : BorderSide(
                                          color: Colors.grey.shade200,
                                          width: 1,
                                        ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            _statusIcon(g.status),
                                            color: color,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              g.title.isEmpty
                                                  ? '(Untitled goal)'
                                                  : g.title,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color:
                                                  color.withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              _statusLabel(g.status),
                                              style: TextStyle(
                                                color: color,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        subtitle,
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      if (streakText != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          streakText,
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final Widget child;
  final Color color;
  final bool isFirst;
  final bool isLast;

  const _TimelineRow({
    required this.child,
    required this.color,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 26,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: 2,
                  color: isFirst ? Colors.transparent : Colors.grey.shade300,
                ),
              ),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast ? Colors.transparent : Colors.grey.shade300,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.only(bottom: 8), child: child)),
      ],
    );
  }
}
