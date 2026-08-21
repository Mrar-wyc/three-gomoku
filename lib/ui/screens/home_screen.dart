import 'package:flutter/material.dart';

import '../../services/room_prefs.dart';
import '../../state/local_game_controller.dart';
import '../../state/room_controller.dart';
import 'create_room_screen.dart';
import 'join_room_screen.dart';
import 'local_game_screen.dart';
import 'room_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _savedCode;
  String? _savedName;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final (code, name) = await RoomPrefs.load();
    if (!mounted) return;
    setState(() {
      _savedCode = code;
      _savedName = name;
    });
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _loadPrefs();
  }

  Future<void> _startLocal() async {
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
    if (aiCount == null || !mounted) return;

    String difficulty = 'medium';
    if (aiCount > 0) {
      difficulty = await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('选择 AI 难度'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, 'easy'),
                  child: const Text('简单（只进攻）'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, 'medium'),
                  child: const Text('中等（攻守兼顾）'),
                ),
              ],
            ),
          ) ??
          'medium';
      if (!mounted) return;
    }

    final c = LocalGameController()..start(aiCount, difficulty: difficulty);
    await _push(LocalGameScreen(controller: c));
  }

  Future<void> _rejoin() async {
    final code = _savedCode;
    if (code == null) return;
    final c = RoomController();
    final ok = await c.join(code, _savedName ?? '玩家');
    if (!mounted) return;
    if (ok) {
      await _push(RoomScreen(controller: c));
    } else {
      setState(() {
        _savedCode = null;
        _savedName = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回到房间失败：${c.error ?? '未知错误'}')),
      );
    }
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
              if (_savedCode != null) ...[
                SizedBox(
                  width: 260,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.replay),
                    label: Text('回到房间 $_savedCode'),
                    onPressed: _rejoin,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: 260,
                child: FilledButton.icon(
                  icon: const Icon(Icons.groups),
                  label: const Text('本地三人对局'),
                  onPressed: _startLocal,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 260,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('创建房间'),
                  onPressed: () => _push(const CreateRoomScreen()),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 260,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.login),
                  label: const Text('加入房间'),
                  onPressed: () => _push(const JoinRoomScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
