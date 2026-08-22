import 'package:flutter/material.dart';

import '../../services/stats_service.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Stats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await StatsService.load();
    if (!mounted) return;
    setState(() => _stats = s);
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清零战绩？'),
        content: const Text('本机记录的联机对局数、胜负与连胜将被清空，不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清零')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await StatsService.reset();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats ?? const Stats();
    return Scaffold(
      appBar: AppBar(title: const Text('我的战绩'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _row('对局数', '${s.games}'),
                    _row('胜 / 负 / 和', '${s.wins} / ${s.losses} / ${s.draws}'),
                    _row('胜率', s.games == 0 ? '—' : '${(s.winRate * 100).toStringAsFixed(1)}%'),
                    _row('当前连胜', s.winStreak > 0 ? '${s.winStreak} 连胜' : '—'),
                    _row('当前连负', s.lossStreak > 0 ? '${s.lossStreak} 连负' : '—'),
                  ],
                ),
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('清零战绩'),
              onPressed: _reset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15, color: Colors.black87)),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
