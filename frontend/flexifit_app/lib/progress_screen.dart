import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'progress_store.dart';
import 'notification_service.dart';
import 'theme_controller.dart';

Color _cOpacity(Color color, double opacity) {
  final o = opacity.clamp(0.0, 1.0).toDouble();
  return color.withValues(alpha: o);
}

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

  bool _nightModeEnabled = false;

  PersonaResult? _cachedPersona;
  bool _personaLoading = false;

  static const Set<String> _idStopwords = {
    'yang',
    'untuk',
    'dan',
    'dari',
    'dengan',
    'kamu',
    'anda',
    'ayo',
    'hari',
    'ini',
    'jangan',
    'bisa',
    'saja',
    'lebih',
    'mulai',
    'waktu',
    'ambil',
    'buku',
    'baca',
    'satu',
    'halaman',
    'tetap',
    'semangat',
    'karena',
    'kalau',
    'banget',
  };

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

    final nightModeEnabled = await ProgressStore.getNightModeEnabled();

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

      _nightModeEnabled = nightModeEnabled;
    });
  }

  Future<void> _setNightModeEnabled(bool enabled) async {
    await ThemeController.instance.setNightModeEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _nightModeEnabled = enabled;
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
        // Might be a Python-style list string: ['a', 'b'] (single quotes).
        final items = RegExp(r'''["']([^"']+)["']''')
            .allMatches(text)
            .map((m) => (m.group(1) ?? '').trim())
            .where((s) => s.isNotEmpty)
            .toList(growable: false);
        if (items.length >= 2) {
          return items;
        }
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

  String _inferLanguageForAi(List<Map<String, dynamic>> history) {
    // Prefer the language implied by recent USER messages to avoid device-locale
    // causing mixed-language AI output when the user chats in English.
    final recentUserText = history
        .where((m) => (m['role']?.toString().toLowerCase() ?? '') == 'user')
        .map((m) => m['text']?.toString() ?? '')
        .where((t) => t.trim().isNotEmpty)
        .toList(growable: false)
        .reversed
        .take(6)
        .join(' ')
        .toLowerCase();

    if (recentUserText.isNotEmpty) {
      final cleaned = recentUserText.replaceAll(RegExp(r'[^a-z\s]'), ' ');
      final tokens = cleaned
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList(growable: false);

      var hits = 0;
      for (final t in tokens) {
        if (_idStopwords.contains(t)) {
          hits++;
          if (hits >= 2) break;
        }
      }

      if (hits >= 2) return 'id';
      // If the device is Indonesian but the chat looks non-Indonesian, default to English.
      final device = Localizations.localeOf(context).languageCode.toLowerCase();
      if (device == 'id') return 'en';
      return device;
    }

    return Localizations.localeOf(context).languageCode.toLowerCase();
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

      final language = _inferLanguageForAi(history);

      final result = await ApiService.getProgressInsights(
        currentGoal: goal,
        history: history,
        language: language,
      );

      WeeklyMotivationResult? motivationResult;
      try {
        motivationResult = await ApiService.getWeeklyMotivation(
          goal: goal,
          completionRate7d: rate7d,
          last7Days: trend7d,
          language: language,
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

    final language = _inferLanguageForAi(history);

    return ApiService.getPersona(
      goal: goal,
      streak: streak,
      completionRate7d: rate7d,
      last7Days: trend7d,
      history: history,
      language: language,
    );
  }

  Future<void> showPersonaDialog() async {
    if (_personaLoading) return;

    setState(() {
      _personaLoading = true;
    });

    final completedGoals = await ProgressStore.getCompletedGoalsCount();
    final isLegendary = completedGoals >= 3;

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
        barrierColor: _cOpacity(Colors.black, 0.75),
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
                                            _cOpacity(Colors.tealAccent, 0.20),
                                        blurRadius: 28,
                                        spreadRadius: 2,
                                      ),
                                      BoxShadow(
                                        color: _cOpacity(Colors.teal, 0.18),
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
              final title = isLegendary
                  ? 'Legendary ${p.archetypeTitle}'
                  : p.archetypeTitle;

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
                                      color: _cOpacity(Colors.tealAccent, 0.20),
                                      blurRadius: 28,
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: _cOpacity(Colors.teal, 0.18),
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
                                      child: ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(18),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            border: Border.all(
                                              color: isLegendary
                                                  ? Colors.amber.shade400
                                                  : Colors.teal.shade100,
                                              width: isLegendary ? 2 : 1,
                                            ),
                                          ),
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Image.asset(
                                                asset,
                                                width: 140,
                                                height: 140,
                                                fit: BoxFit.contain,
                                              ),
                                              Positioned.fill(
                                                child: _SoftShimmer(
                                                  intensity: isLegendary
                                                      ? 0.22
                                                      : 0.14,
                                                  period: const Duration(
                                                    milliseconds: 2600,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          18),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    title,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 820;
        final maxWidth = isWide ? 920.0 : double.infinity;

        final background = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).scaffoldBackgroundColor,
                _cOpacity(Theme.of(context).colorScheme.primary, 0.06),
              ],
            ),
          ),
        );

        final dailyNudgeCard = _GlassCard(
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
        );

        final appearanceCard = _GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Appearance',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Switch(
                      value: _nightModeEnabled,
                      onChanged: (v) => _setNightModeEnabled(v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _nightModeEnabled ? 'Dark mode is ON.' : 'Dark mode is OFF.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        );

        final doneTodayCard = _GlassCard(
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
        );

        final aiInsightsCard = _GlassCard(
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _syncing ? null : _syncWithAi,
                      icon: _syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(_syncing ? 'Syncing' : 'Sync'),
                    ),
                  ],
                ),
                if (_weeklyMotivation != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _cOpacity(
                          Theme.of(context).colorScheme.primary, 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _cOpacity(
                            Theme.of(context).colorScheme.primary, 0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.fitness_center,
                          color: Theme.of(context).colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _weeklyMotivation!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
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
                    style: TextStyle(
                      fontSize: 12,
                      color: _cOpacity(
                          Theme.of(context).colorScheme.onSurface, 0.65),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (_microHabitsOffered != null)
                  Text(
                      'Micro-habits offered (estimated): $_microHabitsOffered'),
                if (_aiInsights != null && insightsLines.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...insightsLines.map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: _cOpacity(
                                Theme.of(context).colorScheme.primary, 0.85),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(l)),
                        ],
                      ),
                    ),
                  ),
                ] else
                  const Text(
                    'Tap “Sync” to analyze your recent chat and get guidance.',
                  ),
              ],
            ),
          ),
        );

        Widget body;
        if (!isWide) {
          body = ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _StatCard(
                title: 'Main Goal',
                value: goalText,
                icon: Icons.flag,
                emphasized: true,
              ),
              const SizedBox(height: 12),
              dailyNudgeCard,
              const SizedBox(height: 12),
              appearanceCard,
              const SizedBox(height: 12),
              doneTodayCard,
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
                    child: _WeeklyConsistencyCard(
                      percent: _completionRate7d,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _TrendCard(trend: _trend7d),
              const SizedBox(height: 12),
              aiInsightsCard,
            ],
          );
        } else {
          final effectiveW = math.min(constraints.maxWidth, maxWidth);
          final spacing = 16.0;
          final col = (effectiveW - spacing) / 2;

          body = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: col,
                  child: _StatCard(
                    title: 'Current Goal',
                    value: goalText,
                    icon: Icons.flag,
                    emphasized: true,
                  ),
                ),
                SizedBox(width: col, child: doneTodayCard),
                SizedBox(
                  width: col,
                  child: _StatCard(
                    title: 'Streak',
                    value: '$_streak days',
                    icon: Icons.local_fire_department,
                  ),
                ),
                SizedBox(
                  width: col,
                  child: _WeeklyConsistencyCard(
                    percent: _completionRate7d,
                  ),
                ),
                SizedBox(width: effectiveW, child: _TrendCard(trend: _trend7d)),
                SizedBox(width: effectiveW, child: aiInsightsCard),
                SizedBox(width: col, child: dailyNudgeCard),
                SizedBox(width: col, child: appearanceCard),
              ],
            ),
          );
        }

        return Stack(
          children: [
            background,
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: RefreshIndicator(
                  onRefresh: reload,
                  child: body,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final bool emphasized;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;

    return _GlassCard(
      tint: emphasized ? _cOpacity(accent, 0.07) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    _cOpacity(accent, 0.18),
                    _cOpacity(accent, 0.08),
                  ],
                ),
                border: Border.all(color: _cOpacity(accent, 0.18)),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: _cOpacity(scheme.onSurface, 0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: emphasized ? 16.5 : 15.5,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyConsistencyCard extends StatelessWidget {
  final double percent;

  const _WeeklyConsistencyCard({required this.percent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final normalized = (percent / 100.0).clamp(0.0, 1.0);

    return _GlassCard(
      tint: _cOpacity(accent, 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [
                    _cOpacity(accent, 0.18),
                    _cOpacity(accent, 0.08),
                  ],
                ),
                border: Border.all(color: _cOpacity(accent, 0.18)),
              ),
              child: Icon(Icons.show_chart, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weekly Consistency',
                    style: TextStyle(
                      color: _cOpacity(scheme.onSurface, 0.65),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${percent.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: normalized),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: value,
                        strokeWidth: 5,
                        backgroundColor: _cOpacity(accent, 0.14),
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                      Text(
                        '${(value * 100).round()}%',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _cOpacity(scheme.onSurface, 0.72),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  final List<Map<String, dynamic>> trend;

  const _TrendCard({required this.trend});

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  String _signature = '';

  String _computeSignature(List<Map<String, dynamic>> trend) {
    return trend
        .map((d) => '${d['date']}:${d['done'] == true ? 1 : 0}')
        .join('|');
  }

  @override
  void initState() {
    super.initState();
    _signature = _computeSignature(widget.trend);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant _TrendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _computeSignature(widget.trend);
    if (next != _signature) {
      _signature = next;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last 7 days',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: widget.trend.asMap().entries.map((entry) {
                final i = entry.key;
                final d = entry.value;
                final done = d['done'] == true;
                final date = (d['date'] as String?) ?? '';
                final label = date.length >= 5 ? date.substring(5) : date;

                final start = (i * 0.07).clamp(0.0, 0.6);
                final end = (start + 0.45).clamp(0.0, 1.0);
                final anim = CurvedAnimation(
                  parent: _controller,
                  curve: Interval(start, end, curve: Curves.easeOutCubic),
                );

                return Expanded(
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: anim,
                        builder: (context, _) {
                          final v = anim.value;
                          return Opacity(
                            opacity: v,
                            child: Transform.scale(
                              alignment: Alignment.bottomCenter,
                              scaleX: 1,
                              scaleY: (v).clamp(0.01, 1.0),
                              child: Container(
                                height: 22,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                decoration: BoxDecoration(
                                  gradient: done
                                      ? LinearGradient(
                                          colors: [
                                            Colors.green.shade400,
                                            Colors.teal.shade400,
                                          ],
                                        )
                                      : null,
                                  color: done
                                      ? null
                                      : _cOpacity(scheme.onSurface, 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color: _cOpacity(scheme.onSurface, 0.65),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftShimmer extends StatefulWidget {
  final double intensity;
  final Duration period;
  final BorderRadius borderRadius;

  const _SoftShimmer({
    required this.intensity,
    required this.period,
    required this.borderRadius,
  });

  @override
  State<_SoftShimmer> createState() => _SoftShimmerState();
}

class _SoftShimmerState extends State<_SoftShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final dx = (t * 2.2 - 1.1) * w;
                return Opacity(
                  opacity: widget.intensity,
                  child: Transform.translate(
                    offset: Offset(dx, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: const Alignment(-1, -0.2),
                          end: const Alignment(1, 0.2),
                          colors: [
                            Colors.transparent,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color? tint;

  const _GlassCard({required this.child, this.tint});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = tint ?? _cOpacity(scheme.surface, 0.88);

    return Container(
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _cOpacity(scheme.primary, 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: _cOpacity(Colors.black, 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: child,
    );
  }
}
