import 'package:flutter/material.dart';

import '../../services/room_prefs.dart';
import '../../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _name = TextEditingController();
  late bool _sound = SettingsService.sound;
  late bool _haptic = SettingsService.haptic;

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final (_, name) = await RoomPrefs.load();
    if (!mounted) return;
    _name.text = name ?? '玩家';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await RoomPrefs.saveName(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('昵称已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('落子音效'),
            subtitle: const Text('落子时播放提示音'),
            value: _sound,
            onChanged: (v) {
              setState(() => _sound = v);
              SettingsService.setSound(v);
            },
          ),
          SwitchListTile(
            title: const Text('震动反馈'),
            subtitle: const Text('落子时轻微震动'),
            value: _haptic,
            onChanged: (v) {
              setState(() => _haptic = v);
              SettingsService.setHaptic(v);
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '我的昵称',
                helperText: '创建/加入房间时使用',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: _saveName,
                child: const Text('保存昵称'),
              ),
            ),
          ),
          const Divider(),
          const ListTile(
            title: Text('关于'),
            subtitle: Text('三人五子棋 · 三人轮流落子，先连成五子者胜'),
          ),
        ],
      ),
    );
  }
}
