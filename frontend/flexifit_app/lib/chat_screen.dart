import 'package:flutter/material.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';
import 'package:confetti/confetti.dart';
import 'api_service.dart';
import 'progress_store.dart';

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

class ChatScreenState extends State<ChatScreen> {
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

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;

  late final ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 900),
    );
    _loadGoal();
    _loadProgress();
    _loadChatHistory();
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

    loaded.sort((a, b) => a.createdAt!.compareTo(b.createdAt!));

    if (!mounted) return;
    setState(() {
      _messages = loaded.reversed.toList(); // newest-first for DashChat
    });
  }

  Future<void> _loadGoal() async {
    final goal = await ProgressStore.getGoal();
    setState(() {
      _userGoal = goal;
    });

    if (_userGoal == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => showGoalDialog());
    } else {
      _addBotMessage(
          "Hello! Your goal today: $_userGoal. How are you feeling? 😊");
    }
  }

  void sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

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
                partialResults: true,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Voice input',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isListening
                        ? 'Listening… speak now.'
                        : 'Tap the mic, then tap Send.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.teal.shade200),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.teal.shade50,
                    ),
                    child: Text(
                      recognized.isEmpty ? '(no speech yet)' : recognized,
                      style: const TextStyle(fontSize: 16),
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
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveGoal(String goal) async {
    await ProgressStore.setGoal(goal);
    setState(() {
      _userGoal = goal;
    });
    _addBotMessage(
        "Great! Your goal: \"$goal\". Tell me, how are you feeling right now?");
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
    final items = chronological.map((m) {
      return {
        'role': m.user.id == '1' ? 'user' : 'model',
        'text': m.text,
        'createdAt': m.createdAt?.toIso8601String(),
      };
    }).toList();

    await ProgressStore.setChatHistory(items);
  }

  Future<void> _onSend(ChatMessage message) async {
    setState(() {
      _messages.insert(0, message);
      _isLoading = true;
    });

    await _persistChatHistory();

    _startLoadingAnimation();

    final chronological = _messages.reversed.toList();
    final last10 = chronological.length > 10
        ? chronological.sublist(chronological.length - 10)
        : chronological;

    final historyPayload = last10.map((m) {
      return {
        'role': m.user.id == '1' ? 'user' : 'model',
        'text': m.text,
      };
    }).toList();

    String responseText = await ApiService.sendMessage(
      message: message.text,
      currentGoal: _userGoal ?? "Stay Healthy",
      history: historyPayload,
    );

    _stopLoadingAnimation();
    setState(() {
      _isLoading = false;
    });

    // Check for DEAL_MADE tag
    if (responseText.contains('[DEAL_MADE]')) {
      String cleanResponse = responseText.replaceAll('[DEAL_MADE]', '').trim();
      _playConfetti();
      _extractAndShowDeal(cleanResponse);
      _addBotMessage(cleanResponse);
    } else {
      _addBotMessage(responseText);
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

  void _extractAndShowDeal(String response) {
    setState(() {
      _showActionButtons = true;
      // Extract habit from response (simple parsing)
      if (response.toLowerCase().contains('walk')) {
        _currentAgreedHabit = "Complete today's walk";
      } else if (response.toLowerCase().contains('workout')) {
        _currentAgreedHabit = "Complete today's workout";
      } else if (response.toLowerCase().contains('read')) {
        _currentAgreedHabit = "Complete today's reading";
      } else {
        _currentAgreedHabit = "Complete today's activity";
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

    _playConfetti();

    // Add celebration message
    _addBotMessage(
        "🎉 Amazing! Streak updated: $_streakCount days! You're building unstoppable momentum! 🔥");
  }

  void _stopLoadingAnimation() {
    _loadingTimer?.cancel();
    _loadingText = "FlexiFit is thinking...";
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
  Widget build(BuildContext context) {
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
        Expanded(
          child: Column(
            children: [
              // Quick Reply Buttons for Demo
              Container(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _buildQuickReply("I'm really tired today 😴"),
                    _buildQuickReply("Super busy, no time!"),
                    _buildQuickReply("Ready for action! Let's go! 🔥"),
                  ],
                ),
              ),
              Expanded(
                child: DashChat(
                  currentUser: _currentUser,
                  onSend: _onSend,
                  messages: _messages,
                  typingUsers: _isLoading ? [_aiUser] : [],
                  inputOptions: InputOptions(
                    inputDecoration: const InputDecoration(
                      hintText: "I'm tired... / Ready to go! / How do I start?",
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    inputTextStyle: const TextStyle(fontSize: 16),
                  ),
                  messageOptions: MessageOptions(
                    showTime: true,
                    messageDecorationBuilder:
                        (message, previousMessage, nextMessage) {
                      return BoxDecoration(
                        color: message.user.id == '1'
                            ? Colors.teal.shade100
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      );
                    },
                  ),
                ),
              ),
              // Micro-Contract Action Button
              if (_showActionButtons)
                Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.handshake, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentAgreedHabit,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check_circle),
                        label: const Text("DONE!"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _markAsDone,
                      ),
                    ],
                  ),
                ),
              // Loading indicator with smart text
              if (_isLoading)
                Container(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _loadingText,
                        style: TextStyle(
                          color: Colors.teal.shade600,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final withConfetti = Stack(
      children: [
        content,
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
        title: const Text("FlexiFit Agent"),
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
