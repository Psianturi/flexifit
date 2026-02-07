import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';
import 'dart:math' as math;
import 'package:confetti/confetti.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'goal_model.dart';
import 'progress_store.dart';
import 'app_config.dart';

class ChatScreen extends StatefulWidget {
  final bool embedded;
  final VoidCallback? onProgressChanged;

  const ChatScreen({
    super.key,
    this.embedded = false,
    this.onProgressChanged,
  });

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen>
    with AutomaticKeepAliveClientMixin<ChatScreen> {
  final ChatUser _currentUser = ChatUser(id: '1', firstName: 'Me');
  final ChatUser _aiUser = ChatUser(
    id: '2',
    firstName: 'FlexiFit',
    profileImage: 'https://cdn-icons-png.flaticon.com/512/4712/4712035.png',
  );

  List<ChatMessage> _messages = [];
  String? _userGoal;
  bool _isLoading = false;
  String _loadingText = "FlexiFit is thinking...";
  Timer? _loadingTimer;
  bool _showActionButtons = false;
  String _currentAgreedHabit = "";
  int _streakCount = 0;

  double? _lastEmpathyScore;
  String? _lastEmpathyRationale;
  bool? _lastRetryUsed;
  double? _lastInitialEmpathyScore;
  String? _lastPromptVersion;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  String? _speechLocaleId;

  late final ConfettiController _confettiController;

  bool _bootstrapped = false;

  static const String _typingSentinel = '__FLEXIFIT_TYPING__';
  static const String _logoAssetPath = 'assets/logo/flexifit-logo.png';

  static const int _dealMinRecentUserMessages = 3;

  double? _tryParseNumberToken(String token) {
    final normalized = token.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    final direct = double.tryParse(normalized.replaceAll(',', '.'));
    if (direct != null) return direct;

    const wordToNum = {
      'a': 1,
      'an': 1,
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'satu': 1,
      'dua': 2,
      'tiga': 3,
      'empat': 4,
      'lima': 5,
      'enam': 6,
      'tujuh': 7,
      'delapan': 8,
      'sembilan': 9,
      'sepuluh': 10,
    };
    final mapped = wordToNum[normalized];
    if (mapped == null) return null;
    return mapped.toDouble();
  }

  String? _normalizeUnit(String raw) {
    final u = raw.trim().toLowerCase();
    if (u.isEmpty) return null;

    if (u == 'km' || u == 'kms' || u == 'kilometer' || u == 'kilometers') {
      return 'km';
    }
    if (u == 'page' || u == 'pages' || u == 'halaman') {
      return 'pages';
    }
    if (u == 'min' || u == 'mins' || u == 'minute' || u == 'minutes') {
      return 'minutes';
    }
    if (u == 'hour' || u == 'hours' || u == 'jam') {
      return 'hours';
    }
    if (u == 'step' || u == 'steps') {
      return 'steps';
    }
    return null;
  }

  /// Normalize time units to minutes for fair comparison.
  ({double value, String unit}) _toComparableUnit(double value, String unit) {
    if (unit == 'hours') return (value: value * 60, unit: 'minutes');
    return (value: value, unit: unit);
  }

  ({double value, String unit})? _extractQuantityUnit(String text) {
    final t = text.toLowerCase();

    // Prefer explicit numeric quantities.
    final numeric = RegExp(
            r'\b(\d+(?:[\.,]\d+)?)\s*(km|kms|kilometer|kilometers|page|pages|halaman|min|mins|minute|minutes|hour|hours|jam|step|steps)\b')
        .firstMatch(t);
    if (numeric != null) {
      final value = _tryParseNumberToken(numeric.group(1) ?? '');
      final unit = _normalizeUnit(numeric.group(2) ?? '');
      if (value != null && unit != null && value > 0) {
        return _toComparableUnit(value, unit);
      }
    }

    // Fallback: number words right before a unit (e.g., 'two pages').
    final word = RegExp(
            r'\b(a|an|one|two|three|four|five|six|seven|eight|nine|ten|satu|dua|tiga|empat|lima|enam|tujuh|delapan|sembilan|sepuluh)\s*(km|kms|kilometer|kilometers|page|pages|halaman|min|mins|minute|minutes|hour|hours|jam|step|steps)\b')
        .firstMatch(t);
    if (word != null) {
      final value = _tryParseNumberToken(word.group(1) ?? '');
      final unit = _normalizeUnit(word.group(2) ?? '');
      if (value != null && unit != null && value > 0) {
        return _toComparableUnit(value, unit);
      }
    }

    return null;
  }

  String? _inferGoalDomain(String text) {
    final t = text.toLowerCase();
    if (RegExp(r'\b(read|reading|book|baca|halaman|page|pages)\b')
        .hasMatch(t)) {
      return 'read';
    }
    if (RegExp(
            r'\b(run|running|jog|jogging|lari|walk|walking|jalan|steps|step|km|kilometer)\b')
        .hasMatch(t)) {
      return 'move';
    }
    if (RegExp(
            r'\b(workout|exercise|push\s*up|pushup|sit\s*up|situp|gym|angkat)\b')
        .hasMatch(t)) {
      return 'workout';
    }
    if (RegExp(r'\b(sleep|sleeping|tidur|nap|rest|istirahat)\b').hasMatch(t)) {
      return 'sleep';
    }
    if (RegExp(r'\b(meditat|meditasi|yoga|stretch|peregangan)\b').hasMatch(t)) {
      return 'wellness';
    }
    return null;
  }

  bool _sameDomainOrUnknown(String goal, String dealLabel) {
    final domain = _inferGoalDomain(goal);
    if (domain == null) return true;

    final t = dealLabel.toLowerCase();
    switch (domain) {
      case 'read':
        return RegExp(r'\b(read|reading|baca|halaman|page|pages|book)\b')
            .hasMatch(t);
      case 'move':
        return RegExp(
                r'\b(run|running|jog|jogging|lari|walk|walking|jalan|steps|step|km|kilometer)\b')
            .hasMatch(t);
      case 'workout':
        return RegExp(
                r'\b(workout|exercise|push\s*up|pushup|sit\s*up|situp|gym|angkat)\b')
            .hasMatch(t);
      case 'sleep':
        return RegExp(
                r'\b(sleep|sleeping|tidur|nap|rest|istirahat|lay\s*down|close.*eyes|berbaring|tutup.*mata)\b')
            .hasMatch(t);
      case 'wellness':
        return RegExp(
                r'\b(meditat|meditasi|yoga|stretch|peregangan|relax|rileks)\b')
            .hasMatch(t);
    }
    return true;
  }

  bool _shouldShowDealBanner({
    required String goal,
    required String dealLabel,
    required int recentUserMsgCount,
  }) {
    final label = dealLabel.trim();
    if (label.isEmpty) return false;
    if (recentUserMsgCount < _dealMinRecentUserMessages) return false;

    if (!_sameDomainOrUnknown(goal, label)) return false;

    final goalMeasure = _extractQuantityUnit(goal);
    final dealMeasure = _extractQuantityUnit(label);

    // If the goal is quantified, require the deal to also be quantified.
    if (goalMeasure != null && dealMeasure == null) return false;

    // If both are quantified, require same unit and at least 50%.
    if (goalMeasure != null && dealMeasure != null) {
      if (goalMeasure.unit != dealMeasure.unit) return false;
      final ratio = dealMeasure.value / goalMeasure.value;
      if (ratio < 0.50) return false;
    }

    return true;
  }

  bool _looksLikeGoalCompletionClaim(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return false;

    // Avoid triggering on partial progress.
    const partialHints = [
      'almost',
      'nearly',
      'half',
      'partly',
      'some',
      'a bit',
      'setengah',
      'baru',
      'masih',
      'belum',
      'hampir',
      'dikit',
      'sedikit',
    ];
    if (partialHints.any(t.contains)) return false;

    const strongCompletion = [
      'completed',
      'i completed',
      'i have completed',
      'finished',
      'i finished',
      "i've finished",
      'done',
      'i am done',
      "i'm done",
      'sudah selesai',
      'udah selesai',
      'selesai',
      'tuntas',
      'berhasil',
    ];
    final hasCompletionVerb = strongCompletion.any(t.contains);
    if (!hasCompletionVerb) return false;

    // Require some context that implies full completion (today/goal/hari ini or a quantified unit).
    final hasContext =
        t.contains('today') || t.contains('hari ini') || t.contains('goal');
    final hasUnits = RegExp(
            r'\b\d+\s*(km|kms|kilometer|steps|step|push\s*up|pushup|reps|rep|times|x|minutes|min|pages|page)\b')
        .hasMatch(t);

    return hasContext || hasUnits;
  }

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 900),
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    await _loadChatHistory();
    await _loadGoal();
    await _loadProgress();
  }

  Future<void> ensureChatLoaded() async {
    if (_messages.isNotEmpty) return;
    await _loadChatHistory();
    await _loadGoal();
    await _loadProgress();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _loadingTimer?.cancel();
    super.dispose();
  }

  void _playConfetti() {
    // Avoid overlapping animations.
    _confettiController.stop();
    _confettiController.play();
  }

  Future<void> _loadProgress() async {
    final completions = await ProgressStore.getCompletions();
    final streak = ProgressStore.computeStreak(completions);

    if (!mounted) return;
    setState(() {
      _streakCount = streak;
    });

    // Keep legacy value in sync for any older code paths.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('streak_count', streak);
  }

  Future<void> _loadChatHistory() async {
    final items = await ProgressStore.getChatHistory();
    if (items.isEmpty) return;

    final loaded = <ChatMessage>[];
    for (final item in items) {
      final role = (item['role']?.toString() ?? 'user');
      final text = (item['text']?.toString() ?? '');
      if (text.trim().isEmpty) continue;

      final createdAtRaw = item['createdAt']?.toString();
      final createdAt = createdAtRaw != null
          ? DateTime.tryParse(createdAtRaw) ?? DateTime.now()
          : DateTime.now();

      loaded.add(
        ChatMessage(
          user: role == 'model' ? _aiUser : _currentUser,
          createdAt: createdAt,
          text: text,
        ),
      );
    }

    loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (!mounted) return;
    setState(() {
      _messages = loaded.reversed.toList();
    });
  }

  Future<void> _loadGoal() async {
    final goal = await ProgressStore.getGoal();
    setState(() {
      _userGoal = goal;
    });

    if (_userGoal == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showGoalDialog());
      return;
    }

    // Only add the greeting if this is a fresh conversation.
    if (_messages.isEmpty) {
      _addBotMessage(
          "Hello! Your goal today: $_userGoal. How are you feeling? 😊");
    }
  }

  void sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final goal = (_userGoal ?? '').trim();
    if (goal.isEmpty) {
      showGoalDialog();
      return;
    }

    final message = ChatMessage(
      user: _currentUser,
      createdAt: DateTime.now(),
      text: trimmed,
    );

    _onSend(message);
  }

  Future<void> confirmAndClearConversation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content:
            const Text('This will remove your chat history on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await _clearConversation();
  }

  Future<void> _clearConversation() async {
    _stopLoadingAnimation();
    if (!mounted) return;

    setState(() {
      _messages = [];
      _isLoading = false;
      _showActionButtons = false;
      _currentAgreedHabit = '';
    });

    await ProgressStore.setChatHistory([]);

    if (!mounted) return;
    final goal = _userGoal;
    if (goal != null && goal.trim().isNotEmpty) {
      _addBotMessage("Hello! Your goal today: $goal. How are you feeling? 😊");
    }
  }

  Future<void> showVoiceSheet() async {
    if (!_speechReady) {
      _speechReady = await _speech.initialize();

      if (_speechReady) {
        try {
          final locales = await _speech.locales();
          if (locales.any((l) => l.localeId == 'en_US')) {
            _speechLocaleId = 'en_US';
          } else if (locales.any((l) => l.localeId == 'id_ID')) {
            _speechLocaleId = 'id_ID';
          } else if (locales.isNotEmpty) {
            _speechLocaleId = locales.first.localeId;
          }
        } catch (_) {
          // If locale discovery fails, fall back to platform default.
          _speechLocaleId = null;
        }
      }
    }

    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Speech recognition not available on this device.')),
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        bool isListening = false;
        String recognized = '';

        Future<void> stop() async {
          await _speech.stop();
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> toggle() async {
              if (isListening) {
                await stop();
                setModalState(() => isListening = false);
                return;
              }

              setModalState(() => isListening = true);
              await _speech.listen(
                localeId: _speechLocaleId,
                listenOptions: stt.SpeechListenOptions(
                  partialResults: true,
                ),
                onResult: (result) {
                  setModalState(() {
                    recognized = result.recognizedWords;
                  });
                },
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 8,
              ),
              child: Builder(builder: (context) {
                final scheme = Theme.of(context).colorScheme;
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice input',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isListening
                          ? 'Listening… speak now.'
                          : 'Tap the mic, then tap Send.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? scheme.primary.withValues(alpha: 0.4)
                              : Colors.teal.shade200,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: isDark
                            ? scheme.surfaceContainerHighest
                            : Colors.teal.shade50,
                      ),
                      child: Text(
                        recognized.isEmpty ? '(no speech yet)' : recognized,
                        style: TextStyle(fontSize: 16, color: scheme.onSurface),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: toggle,
                          icon: Icon(isListening ? Icons.stop : Icons.mic),
                          tooltip: isListening ? 'Stop' : 'Start',
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            await stop();
                            if (!context.mounted) return;
                            Navigator.pop(context);
                          },
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: recognized.trim().isEmpty
                              ? null
                              : () async {
                                  await stop();
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  sendText(recognized);
                                },
                          child: const Text('Send'),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            );
          },
        );
      },
    );
  }

  Future<void> _saveGoal(String goal) async {
    final newGoal = goal.trim();
    if (newGoal.isEmpty) return;

    final current = (_userGoal ?? '').trim();
    if (current.isEmpty) {
      await ProgressStore.startNewGoal(title: newGoal);
      setState(() {
        _userGoal = newGoal;
      });
      _addBotMessage(
          "Great! Your goal: \"$newGoal\". Tell me, how are you feeling right now?");
      return;
    }

    if (current.toLowerCase() == newGoal.toLowerCase()) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    await _confirmArchiveAndSetNewGoal(previousGoal: current, newGoal: newGoal);
  }

  Future<void> _confirmArchiveAndSetNewGoal({
    required String previousGoal,
    required String newGoal,
  }) async {
    final status = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Before we switch goals…'),
        content: Text(
          'How would you mark your previous goal?\n\n"$previousGoal"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, GoalStatus.dropped),
            child: const Text('Dropped / Archive'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, GoalStatus.completed),
            child: const Text('Conquered!'),
          ),
        ],
      ),
    );

    if (status == null) return;

    final completions = await ProgressStore.getCompletions();
    final finalStreak = ProgressStore.computeStreak(completions);

    await ProgressStore.transitionGoal(
      newTitle: newGoal,
      previousStatus: status,
      finalStreak: finalStreak,
    );

    if (!mounted) return;
    setState(() {
      _userGoal = newGoal;
    });

    _addBotMessage(
        "New journey started! Your goal: \"$newGoal\". How are you feeling today?");
  }

  void _addBotMessage(String text) {
    setState(() {
      _messages.insert(
          0,
          ChatMessage(
            user: _aiUser,
            createdAt: DateTime.now(),
            text: text,
          ));
    });

    _persistChatHistory();
  }

  Future<void> _persistChatHistory() async {
    final chronological = _messages.reversed.toList();
    final items = chronological
        .map((m) {
          if (m.user.id == _aiUser.id && m.text == _typingSentinel) {
            return null;
          }
          return {
            'role': m.user.id == '1' ? 'user' : 'model',
            'text': m.text,
            'createdAt': m.createdAt.toIso8601String(),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    await ProgressStore.setChatHistory(items);
  }

  bool _hasTypingIndicator() {
    return _messages.any(
      (m) => m.user.id == _aiUser.id && m.text == _typingSentinel,
    );
  }

  void _showTypingIndicator() {
    if (_hasTypingIndicator()) return;
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          user: _aiUser,
          createdAt: DateTime.now(),
          text: _typingSentinel,
        ),
      );
    });
  }

  void _hideTypingIndicator() {
    if (!_hasTypingIndicator()) return;
    setState(() {
      _messages.removeWhere(
        (m) => m.user.id == _aiUser.id && m.text == _typingSentinel,
      );
    });
  }

  Future<void> _onSend(ChatMessage message) async {
    setState(() {
      _messages.insert(0, message);
      _isLoading = true;

      _showActionButtons = false;
      _currentAgreedHabit = '';
    });

    _startLoadingAnimation();

    await _persistChatHistory();

    try {
      if (_looksLikeGoalCompletionClaim(message.text)) {
        final alreadyDone = await ProgressStore.isDoneToday();
        if (!alreadyDone && mounted) {
          setState(() {
            _showActionButtons = true;
            _currentAgreedHabit = "today's goal";
          });
        }
      }
    } catch (_) {}

    _showTypingIndicator();

    final chronological = _messages.reversed.toList();
    final last10 = chronological.length > 10
        ? chronological.sublist(chronological.length - 10)
        : chronological;

    // Find the latest "New journey started!" bot message to scope counting.
    // Only user messages AFTER that point count toward the deal gate.
    int journeyStart = 0;
    for (int i = last10.length - 1; i >= 0; i--) {
      final m = last10[i];
      if (m.user.id != _currentUser.id &&
          m.text.toLowerCase().contains('new journey started')) {
        journeyStart = i + 1;
        break;
      }
    }
    final sinceJourney = last10.sublist(journeyStart);

    final recentUserMsgCount = sinceJourney
        .where((m) => m.user.id == _currentUser.id && m.text != _typingSentinel)
        .length;

    final historyPayload = last10.map((m) {
      return {
        'role': m.user.id == '1' ? 'user' : 'model',
        'text': m.text,
      };
    }).toList();

    final result = await ApiService.sendMessage(
      message: message.text,
      currentGoal: _userGoal ?? "Stay Healthy",
      history: historyPayload,
    );

    _lastEmpathyScore = result.empathyScore;
    _lastEmpathyRationale = result.empathyRationale;
    _lastRetryUsed = result.retryUsed;
    _lastInitialEmpathyScore = result.initialEmpathyScore;
    _lastPromptVersion = result.promptVersion;

    final responseText = result.response;

    final dealMade =
        (result.dealMade == true) || responseText.contains('[DEAL_MADE]');
    final dealLabel = (result.dealLabel ?? '').trim();

    final visibleResponse = responseText.replaceAll('[DEAL_MADE]', '').trim();
    final showDealBanner = dealMade &&
        _shouldShowDealBanner(
          goal: _userGoal ?? '',
          dealLabel: dealLabel,
          recentUserMsgCount: recentUserMsgCount,
        );

    _stopLoadingAnimation();
    _hideTypingIndicator();
    setState(() {
      _isLoading = false;
    });

    // Confetti + marking DONE happens when the user accepts.
    if (showDealBanner) {
      _extractAndShowDeal(
        visibleResponse,
        dealLabelOverride: dealLabel.isNotEmpty ? dealLabel : null,
      );
      _addBotMessage(visibleResponse);
    } else {
      _addBotMessage(visibleResponse);
    }
  }

  void _startLoadingAnimation() {
    final loadingMessages = [
      "Analyzing emotional state...",
      "Calculating micro-habit options...",
      "Applying BJ Fogg methodology...",
      "Negotiating optimal plan..."
    ];

    int index = 0;
    _loadingTimer = Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!_isLoading) {
        timer.cancel();
        return;
      }
      setState(() {
        _loadingText = loadingMessages[index % loadingMessages.length];
      });
      index++;
    });
  }

  void _extractAndShowDeal(String response, {String? dealLabelOverride}) {
    setState(() {
      _showActionButtons = true;

      final override = (dealLabelOverride ?? '').trim();
      if (override.isNotEmpty) {
        _currentAgreedHabit = override;
      } else {
        if (response.toLowerCase().contains('walk')) {
          _currentAgreedHabit = "today's walk";
        } else if (response.toLowerCase().contains('workout')) {
          _currentAgreedHabit = "today's workout";
        } else if (response.toLowerCase().contains('read')) {
          _currentAgreedHabit = "today's reading";
        } else {
          _currentAgreedHabit = "today's micro-habit";
        }
      }
    });
  }

  Future<void> _markAsDone() async {
    setState(() {
      _showActionButtons = false;
    });

    await ProgressStore.markDoneToday();
    await _loadProgress();
    widget.onProgressChanged?.call();

    HapticFeedback.mediumImpact();

    _playConfetti();

    // Add celebration message
    _addBotMessage(
        "🎉 Deal accepted — marked DONE for today. Streak: $_streakCount days. Keep it going! 🔥");
  }

  void _stopLoadingAnimation() {
    _loadingTimer?.cancel();
    _loadingText = "FlexiFit is thinking...";
  }

  Widget _typingDots(Color color) {
    return _TypingDots(color: color);
  }

  Widget _buildQuickReply(String text) {
    return ElevatedButton(
      onPressed: () {
        final message = ChatMessage(
          user: _currentUser,
          createdAt: DateTime.now(),
          text: text,
        );
        _onSend(message);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal.shade50,
        foregroundColor: Colors.teal.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  void showGoalDialog() {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Let's Set Your Main Goal!"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("What is the ONE healthy habit you want to build?"),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "e.g., Run 5km, Drink 2L water, Read 20 pages",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context);
                _saveGoal(controller.text);
              }
            },
            child: const Text("Start Journey!"),
          )
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final showDebug = AppConfig.showDebugEvals;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final showQuickReplies = !keyboardOpen && _messages.length <= 1;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTabletWide = screenWidth >= 760;
    final maxContentWidth = isTabletWide ? 860.0 : double.infinity;
    final maxBubbleWidth = math.min(screenWidth * 0.68, 520.0);

    final isCompactWidth = screenWidth < 420;

    final debugHasData = showDebug &&
        (_lastEmpathyScore != null || _lastEmpathyRationale != null);

    double reservedBottom = 0;
    if (_isLoading) reservedBottom += 40;
    if (_showActionButtons) reservedBottom += isCompactWidth ? 124 : 84;
    if (debugHasData) reservedBottom += 78;

    final content = Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12.0),
          color: Colors.teal.shade50,
          child: Text(
            "🎯 Today's Goal: ${_userGoal ?? 'Not set yet'} 🔥 $_streakCount",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.teal.shade900,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            'FlexiFit is an AI coach, not medical advice. For health concerns, consult a professional.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              if (_messages.length <= 1 && !_isLoading)
                IgnorePointer(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.teal.withValues(alpha: 0.18),
                                    Colors.cyan.withValues(alpha: 0.10),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.teal.withValues(alpha: 0.20),
                                ),
                              ),
                              child: Icon(
                                Icons.smart_toy_outlined,
                                size: 54,
                                color: Colors.teal.shade700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              "I'm ready to negotiate a tiny win.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.grey.shade900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "How's your energy right now — tired, busy, or ready to go?",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                height: 1.25,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Column(
                children: [
                  if (showQuickReplies)
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildQuickReply("I'm really tired today 😴"),
                            const SizedBox(width: 8),
                            _buildQuickReply("Super busy, no time!"),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: reservedBottom),
                      child: DashChat(
                        currentUser: _currentUser,
                        onSend: _onSend,
                        messages: _messages,
                        typingUsers: const [],
                        inputOptions: InputOptions(
                          inputDecoration: InputDecoration(
                            hintText:
                                "I'm tired… / Ready to go! / Where do I start?",
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surface
                                .withValues(alpha: 0.85),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(
                                color: Colors.teal.withValues(alpha: 0.25),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(
                                color: Colors.teal.withValues(alpha: 0.18),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(
                                color: Colors.teal.withValues(alpha: 0.35),
                                width: 1.4,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          inputTextStyle: const TextStyle(fontSize: 16),
                        ),
                        messageOptions: MessageOptions(
                          showOtherUsersName: false,
                          showTime: true,
                          maxWidth: maxBubbleWidth,
                          avatarBuilder: (user, _, __) {
                            if (user.id == _aiUser.id) {
                              return CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    Colors.teal.withValues(alpha: 0.12),
                                child: Icon(
                                  Icons.smart_toy_outlined,
                                  size: 18,
                                  color: Colors.teal.shade700,
                                ),
                              );
                            }

                            return const SizedBox(width: 0, height: 0);
                          },
                          messageDecorationBuilder:
                              (message, previousMessage, nextMessage) {
                            final isMe = message.user.id == _currentUser.id;

                            final radius = BorderRadius.only(
                              topLeft: Radius.circular(isMe ? 18 : 6),
                              topRight: Radius.circular(isMe ? 18 : 18),
                              bottomLeft: Radius.circular(isMe ? 18 : 18),
                              bottomRight: Radius.circular(isMe ? 6 : 18),
                            );

                            if (isMe) {
                              return BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.teal.shade400,
                                    Colors.cyan.shade400,
                                  ],
                                ),
                                borderRadius: radius,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.teal.withValues(alpha: 0.18),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  )
                                ],
                              );
                            }

                            return BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: 0.86),
                              borderRadius: radius,
                              border: Border.all(
                                color: Colors.teal.withValues(alpha: 0.10),
                              ),
                            );
                          },
                          messageTextBuilder:
                              (message, previousMessage, nextMessage) {
                            final isMe = message.user.id == _currentUser.id;

                            if (!isMe && message.text == _typingSentinel) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: _typingDots(
                                  Colors.teal.withValues(alpha: 0.55),
                                ),
                              );
                            }

                            return Text(
                              message.text,
                              style: TextStyle(
                                fontSize: 15.5,
                                height: 1.25,
                                color: isMe
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (debugHasData)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.teal.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.smart_toy_outlined,
                                    size: 18,
                                    color: Colors.teal.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Empathy ${_lastEmpathyScore != null ? "${_lastEmpathyScore!.toStringAsFixed(1)}/5" : "—"}"
                                      "${_lastInitialEmpathyScore != null ? " (initial ${_lastInitialEmpathyScore!.toStringAsFixed(0)}/5)" : ""}"
                                      "${_lastRetryUsed == true ? " • retry used" : ""}"
                                      "${_lastPromptVersion != null ? " • ${_lastPromptVersion!}" : ""}",
                                      style: TextStyle(
                                        color: Colors.teal.shade800,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if ((_lastEmpathyRationale ?? '')
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _lastEmpathyRationale!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.teal.shade900
                                        .withValues(alpha: 0.75),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (_showActionButtons)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: (isDark ? Colors.white : Colors.white)
                                    .withValues(alpha: isDark ? 0.04 : 0.30),
                                blurRadius: 10,
                                offset: const Offset(-4, -4),
                              ),
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: isDark ? 0.40 : 0.08),
                                blurRadius: 10,
                                offset: const Offset(4, 4),
                              ),
                            ],
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isNarrow = constraints.maxWidth < 360;
                              final habitLabel =
                                  _currentAgreedHabit.trim().isEmpty
                                      ? "today's micro-habit"
                                      : _currentAgreedHabit;
                              final message =
                                  "Ready to lock in $habitLabel? Tap Accept Deal to mark DONE today.";

                              void dismiss() {
                                setState(() {
                                  _showActionButtons = false;
                                });
                              }

                              if (!isNarrow) {
                                return Row(
                                  children: [
                                    Icon(Icons.handshake,
                                        size: 18, color: Colors.green.shade700),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        message,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        tooltip: 'Dismiss',
                                        onPressed: dismiss,
                                        iconSize: 18,
                                        icon: Icon(Icons.close,
                                            color: Colors.green.shade700),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.check_circle,
                                          size: 16),
                                      label: const Text("Accept Deal",
                                          style: TextStyle(fontSize: 12)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: _markAsDone,
                                    ),
                                  ],
                                );
                              }

                              // ── Narrow / mobile layout ──
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.handshake,
                                          size: 16,
                                          color: Colors.green.shade700),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Deal ready',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                            color: Colors.green.shade800,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 26,
                                        height: 26,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          tooltip: 'Dismiss',
                                          onPressed: dismiss,
                                          iconSize: 16,
                                          icon: Icon(Icons.close,
                                              color: Colors.green.shade700),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    message,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11.5,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.check_circle,
                                          size: 16),
                                      label: const Text("Accept Deal",
                                          style: TextStyle(fontSize: 12.5)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6),
                                        minimumSize:
                                            const Size(double.infinity, 34),
                                      ),
                                      onPressed: _markAsDone,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      if (_isLoading)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.teal.shade100),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _loadingText,
                                  style: TextStyle(
                                    color: Colors.teal.shade700,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final withConfetti = Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).scaffoldBackgroundColor,
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
              ],
            ),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: content,
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: IgnorePointer(
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.06,
              numberOfParticles: 18,
              maxBlastForce: 22,
              minBlastForce: 10,
              gravity: 0.25,
              colors: const [
                Color(0xFF00BFA5),
                Color(0xFF1DE9B6),
                Color(0xFFFFD54F),
                Color(0xFFFF8A65),
                Color(0xFF81C784),
              ],
              createParticlePath: (size) {
                // Simple diamond particle.
                final path = Path();
                path.moveTo(size.width / 2, 0);
                path.lineTo(size.width, size.height / 2);
                path.lineTo(size.width / 2, size.height);
                path.lineTo(0, size.height / 2);
                path.close();
                return path;
              },
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return withConfetti;
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            _LogoMark(assetPath: _logoAssetPath, size: 35),
            const SizedBox(width: 10),
            const Text("FlexiFit"),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(28),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'AI coach only — not medical advice.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: showGoalDialog,
            tooltip: "Change Goal",
          )
        ],
      ),
      body: withConfetti,
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

class _TypingDots extends StatefulWidget {
  final Color color;

  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;

        Widget dot(int i) {
          final phase = i * 0.9;
          final y = (math.sin(t + phase) + 1) / 2; // 0..1
          final scale = 0.75 + (0.25 * y);
          final opacity = 0.45 + (0.45 * y);

          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, -2.5 * y),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot(0),
            const SizedBox(width: 5),
            dot(1),
            const SizedBox(width: 5),
            dot(2),
          ],
        );
      },
    );
  }
}
