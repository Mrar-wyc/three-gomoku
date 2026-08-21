import 'package:flutter/material.dart';

import '../../state/room_controller.dart';
import 'room_screen.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController(text: '玩家');
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim().toUpperCase();
    final name = _name.text.trim();
    if (code.isEmpty || name.isEmpty) return;
    setState(() => _busy = true);
    final c = RoomController();
    final ok = await c.join(code, name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RoomScreen(controller: c)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加入失败：${c.error ?? '未知错误'}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入房间')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '房间号',
                hintText: '6 位字母 / 数字',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '你的昵称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _join,
              child: Text(_busy ? '加入中…' : '加入房间'),
            ),
          ],
        ),
      ),
    );
  }
}
