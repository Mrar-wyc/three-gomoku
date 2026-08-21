import 'package:flutter/material.dart';

import '../../state/room_controller.dart';
import 'room_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _name = TextEditingController(text: '玩家');
  int _aiCount = 0;
  String _difficulty = 'medium';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    final c = RoomController();
    final ok = await c.create(name, _aiCount, difficulty: _difficulty);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RoomScreen(controller: c)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败：${c.error ?? '未知错误'}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('创建房间')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '你的昵称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            const Text('AI 补位数量', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('无 AI')),
                ButtonSegment(value: 1, label: Text('1 个 AI')),
                ButtonSegment(value: 2, label: Text('2 个 AI')),
              ],
              selected: {_aiCount},
              onSelectionChanged: (s) => setState(() => _aiCount = s.first),
            ),
            if (_aiCount > 0) ...[
              const SizedBox(height: 16),
              const Text('AI 难度', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'easy', label: Text('简单')),
                  ButtonSegment(value: 'medium', label: Text('中等')),
                ],
                selected: {_difficulty},
                onSelectionChanged: (s) => setState(() => _difficulty = s.first),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              '房主为黑方；AI 依次顶替白方、红方。创建后得到 6 位房间号，发给朋友即可加入。',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(_busy ? '创建中…' : '创建房间'),
            ),
          ],
        ),
      ),
    );
  }
}
