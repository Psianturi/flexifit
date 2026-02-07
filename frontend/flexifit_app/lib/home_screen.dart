import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'chat_screen.dart';
import 'journey_history_screen.dart';
import 'progress_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const double _webMaxWidth = 720.0;

  late final TabController _tabController;

  final _chatKey = GlobalKey<ChatScreenState>();
  final _progressKey = GlobalKey<ProgressScreenState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _progressKey.currentState?.reload();
      }

      if (_tabController.index == 0 && !_tabController.indexIsChanging) {
        _chatKey.currentState?.ensureChatLoaded();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isChatTab = _tabController.index == 0;
    final isWideWeb = kIsWeb && MediaQuery.of(context).size.width >= 900;

    Widget content = TabBarView(
      controller: _tabController,
      children: [
        ChatScreen(
          key: _chatKey,
          embedded: true,
          onProgressChanged: () => _progressKey.currentState?.reload(),
        ),
        ProgressScreen(key: _progressKey),
      ],
    );

    PreferredSizeWidget appBar;
    if (!isWideWeb) {
      appBar = AppBar(
        title: Text(isChatTab ? 'FlexiFit Chat' : 'FlexiFit Progress'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
            Tab(icon: Icon(Icons.insights), text: 'Progress'),
          ],
        ),
        actions: [
          if (isChatTab)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Change Goal',
              onPressed: () => _chatKey.currentState?.showGoalDialog(),
            ),
          if (isChatTab)
            IconButton(
              icon: const Icon(Icons.mic),
              tooltip: 'Voice input',
              onPressed: () => _chatKey.currentState?.showVoiceSheet(),
            ),
          if (isChatTab)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete conversation',
              onPressed: () =>
                  _chatKey.currentState?.confirmAndClearConversation(),
            ),
          if (!isChatTab)
            IconButton(
              icon: const Icon(Icons.badge_outlined),
              tooltip: 'See your Flexi Identity',
              onPressed: () => _progressKey.currentState?.showPersonaDialog(),
            ),
          if (!isChatTab)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Journey history',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const JourneyHistoryScreen(),
                ),
              ),
            ),
        ],
      );
    } else {
      appBar = AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _webMaxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child:
                        Text(isChatTab ? 'FlexiFit Chat' : 'FlexiFit Progress'),
                  ),
                  if (isChatTab)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Change Goal',
                      onPressed: () => _chatKey.currentState?.showGoalDialog(),
                    ),
                  if (isChatTab)
                    IconButton(
                      icon: const Icon(Icons.mic),
                      tooltip: 'Voice input',
                      onPressed: () => _chatKey.currentState?.showVoiceSheet(),
                    ),
                  if (isChatTab)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete conversation',
                      onPressed: () =>
                          _chatKey.currentState?.confirmAndClearConversation(),
                    ),
                  if (!isChatTab)
                    IconButton(
                      icon: const Icon(Icons.badge_outlined),
                      tooltip: 'See your Flexi Identity',
                      onPressed: () =>
                          _progressKey.currentState?.showPersonaDialog(),
                    ),
                  if (!isChatTab)
                    IconButton(
                      icon: const Icon(Icons.history),
                      tooltip: 'Journey history',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const JourneyHistoryScreen(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight - 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _webMaxWidth),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chat'),
                    Tab(icon: Icon(Icons.insights), text: 'Progress'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Stack(
        children: [
          if (kIsWeb) const _WebBackdrop(),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!kIsWeb || constraints.maxWidth < 900) {
                  return content;
                }

                final height = constraints.maxHeight;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _webMaxWidth),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: SizedBox(
                        height: height - 32,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.white)
                                    .withValues(
                                  alpha: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? 0.04
                                      : 0.35,
                                ),
                                blurRadius: 22,
                                offset: const Offset(-8, -8),
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? 0.50
                                      : 0.12,
                                ),
                                blurRadius: 22,
                                offset: const Offset(8, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            elevation: 0,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                size: Size(_webMaxWidth, height - 32),
                              ),
                              child: content,
                            ),
                          ),
                        ),
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

class _WebBackdrop extends StatelessWidget {
  const _WebBackdrop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 900;

    final base = isDark ? const Color(0xFF0F1112) : const Color(0xFFF4FAF9);
    final accentA = isDark
        ? Colors.teal.withValues(alpha: 0.12)
        : Colors.teal.withValues(alpha: 0.16);
    final accentB = isDark
        ? Colors.cyan.withValues(alpha: 0.10)
        : Colors.cyan.withValues(alpha: 0.12);

    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base,
              (isDark ? const Color(0xFF12181A) : const Color(0xFFEAF7F4))
                  .withValues(alpha: 0.92),
              (isDark ? const Color(0xFF0B0F10) : const Color(0xFFF7FBFF))
                  .withValues(alpha: 0.96),
            ],
          ),
        ),
        child: IgnorePointer(
          child: Stack(
            children: [
              if (isWide)
                Align(
                  alignment: const Alignment(-1.0, -0.9),
                  child: _BackdropBlob(color: accentA, size: 620),
                ),
              Align(
                alignment: const Alignment(1.0, -0.8),
                child: _BackdropBlob(color: accentB, size: 540),
              ),
              Align(
                alignment: const Alignment(0.1, 1.0),
                child: _BackdropBlob(
                  color:
                      Colors.tealAccent.withValues(alpha: isDark ? 0.08 : 0.10),
                  size: 700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackdropBlob extends StatelessWidget {
  const _BackdropBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}
