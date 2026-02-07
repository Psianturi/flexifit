import 'package:flutter/material.dart';

import 'goal_model.dart';
import 'progress_store.dart';

class JourneyHistoryScreen extends StatefulWidget {
  const JourneyHistoryScreen({super.key});

  @override
  State<JourneyHistoryScreen> createState() => _JourneyHistoryScreenState();
}

class _JourneyHistoryScreenState extends State<JourneyHistoryScreen> {
  static const String _logoAssetPath = 'assets/logo/flexifit-logo.png';
  bool _loading = true;
  String _filter = 'all';
  List<GoalModel> _history = const [];
  String? _currentGoal;

  void _setFilter(String next) {
    if (_filter == next) return;
    setState(() {
      _filter = next;
    });

    _reload();
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
    });

    final goal = await ProgressStore.getGoal();
    final history = await ProgressStore.getGoalHistory();

    if (!mounted) return;
    setState(() {
      _history = history;
      _currentGoal = goal?.trim();
      _loading = false;
    });
  }

  Future<void> _archiveActiveGoal(String status) async {
    final label = status == GoalStatus.completed ? 'Conquered' : 'Dropped';

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark goal as $label?'),
        content: const Text(
          'This will archive your current goal and clear it from Chat/Progress until you set a new one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await ProgressStore.archiveActiveGoal(status: status);
    await _reload();
  }

  List<GoalModel> get _displayList {
    final items = _filtered;
    if (_filter != 'all') return items;

    final current = (_currentGoal ?? '').trim();
    if (current.isEmpty) return items;

    final hasMatchingActive = items.any((g) =>
        g.status == GoalStatus.active &&
        g.title.trim().toLowerCase() == current.toLowerCase());
    if (hasMatchingActive) return items;

    return [
      GoalModel(
        id: 'legacy_active',
        title: current,
        startDate: DateTime.now(),
        endDate: null,
        status: GoalStatus.active,
        finalStreak: 0,
      ),
      ...items,
    ];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _LogoMark(assetPath: _logoAssetPath, size: 34),
            const SizedBox(width: 10),
            const Text('Your Journey'),
          ],
        ),
        actions: [
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
                if ((_currentGoal ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade100),
                      ),
                      child: Text(
                        'Current goal: ${_currentGoal!}',
                        style: TextStyle(
                          color: Colors.teal.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _filter == 'all',
                        onSelected: (_) => _setFilter('all'),
                      ),
                      ChoiceChip(
                        label: const Text('Completed'),
                        selected: _filter == 'completed',
                        onSelected: (_) => _setFilter('completed'),
                      ),
                      ChoiceChip(
                        label: const Text('Failed'),
                        selected: _filter == 'dropped',
                        onSelected: (_) => _setFilter('dropped'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _displayList.isEmpty
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
                          itemCount: _displayList.length,
                          itemBuilder: (context, index) {
                            final g = _displayList[index];
                            final color = _statusColor(g.status);

                            final isFirst = index == 0;
                            final isLast = index == _displayList.length - 1;

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
                                          if (g.isActive) ...[
                                            const SizedBox(width: 6),
                                            PopupMenuButton<String>(
                                              tooltip: 'Goal actions',
                                              onSelected: (value) {
                                                if (value == GoalStatus.completed) {
                                                  _archiveActiveGoal(GoalStatus.completed);
                                                } else if (value == GoalStatus.dropped) {
                                                  _archiveActiveGoal(GoalStatus.dropped);
                                                }
                                              },
                                              itemBuilder: (context) => const [
                                                PopupMenuItem(
                                                  value: GoalStatus.completed,
                                                  child: Text('Mark as completed'),
                                                ),
                                                PopupMenuItem(
                                                  value: GoalStatus.dropped,
                                                  child: Text('Mark as failed'),
                                                ),
                                              ],
                                              icon: const Icon(Icons.more_vert),
                                            ),
                                          ],
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

class _LogoMark extends StatelessWidget {
  final String assetPath;
  final double size;

  const _LogoMark({
    required this.assetPath,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Transform.scale(
        scale: 1.12,
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.fitness_center,
              color: theme.colorScheme.primary,
              size: size * 0.70,
            );
          },
        ),
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
    return IntrinsicHeight(
      child: Row(
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
              padding: const EdgeInsets.only(bottom: 8),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
