import 'package:flutter/material.dart';

import '../../core/constants.dart';

class PlayerInfo {
  final String name;
  final int stone; // 1..3
  final bool isTurn;
  final String statusLabel;
  final Duration? remaining; // 当前回合人座的倒计时

  const PlayerInfo({
    required this.name,
    required this.stone,
    this.isTurn = false,
    this.statusLabel = '',
    this.remaining,
  });
}

class PlayerBar extends StatelessWidget {
  final List<PlayerInfo> players;

  const PlayerBar({super.key, required this.players});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [for (final p in players) Expanded(child: _chip(p))],
      ),
    );
  }

  Widget _chip(PlayerInfo p) {
    final active = p.isTurn;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFFF3E0) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? Colors.orange : Colors.black12,
          width: active ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: GomokuPalette.stone[p.stone],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black38),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  p.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          if (p.statusLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              p.statusLabel,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
          if (p.isTurn && p.remaining != null) ...[
            const SizedBox(height: 2),
            Text(
              '⏱ ${_fmt(p.remaining!)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: p.remaining!.inSeconds <= 10
                    ? Colors.red
                    : Colors.black54,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds < 0 ? 0 : d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
