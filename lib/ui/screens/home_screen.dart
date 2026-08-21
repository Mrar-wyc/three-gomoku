import 'package:flutter/material.dart';

import '../../state/local_game_controller.dart';
import 'create_room_screen.dart';
import 'join_room_screen.dart';
import 'local_game_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _startLocal(BuildContext context) async {
    final aiCount = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择 AI 数量'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('0 个 AI（三人真人轮流下）'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('1 个 AI（红方由 AI 顶替）'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('2 个 AI（你一人对战两个 AI）'),
          ),
        ],
      ),
    );
    if (aiCount == null || !context.mounted) return;
    final c = LocalGameController()..start(aiCount);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LocalGameScreen(controller: c)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('三人五子棋'), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '19 × 19 · 先连成五子者胜',
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 260,
                child: FilledButton.icon(
                  icon: const Icon(Icons.groups),
                  label: const Text('本地三人对局'),
                  onPressed: () => _startLocal(context),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 260,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('创建房间'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 260,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.login),
                  label: const Text('加入房间'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JoinRoomScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
