import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'progress_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
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

    return Scaffold(
      appBar: AppBar(
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
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ChatScreen(
            key: _chatKey,
            embedded: true,
            onProgressChanged: () => _progressKey.currentState?.reload(),
          ),
          ProgressScreen(key: _progressKey),
        ],
      ),
    );
  }
}
