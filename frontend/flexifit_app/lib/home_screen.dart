import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'chat_screen.dart';
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
      backgroundColor: kIsWeb ? Colors.grey.shade100 : null,
      appBar: appBar,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // For web on wide screens, constrain content width for readability.
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
                  child: Material(
                    elevation: 2,
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
          );
        },
      ),
    );
  }
}
