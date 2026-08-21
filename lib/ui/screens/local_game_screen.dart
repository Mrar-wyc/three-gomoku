import 'package:flutter/material.dart';

import '../../state/local_game_controller.dart';
import '../widgets/board_widget.dart';
import '../widgets/player_bar.dart';

class LocalGameScreen extends StatelessWidget {
  final LocalGameController controller;

  const LocalGameScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地三人对局'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新开局',
            onPressed: controller.restart,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final info = controller.players
              .map((p) => PlayerInfo(
                    name: p.name,
                    stone: p.slot + 1,
                    isTurn: controller.turn == p.slot,
                    statusLabel: p.isAi ? 'AI' : '真人',
                  ))
              .toList();
          return Column(
            children: [
              PlayerBar(players: info),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: BoardWidget(
                    board: controller.board,
                    lastIndex: controller.lastIndex,
                    onTap: controller.placeAt,
                    enabled: controller.canPlace,
                  ),
                ),
              ),
              _status(controller),
            ],
          );
        },
      ),
    );
  }

  Widget _status(LocalGameController c) {
    String text;
    if (c.winner != null) {
      text = '${c.players[c.winner!].name} 获胜！';
    } else if (c.draw) {
      text = '和棋！';
    } else {
      final cur = c.players[c.turn];
      text = cur.isAi ? 'AI 思考中…' : '轮到 ${cur.name} 落子';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (c.isFinished)
            FilledButton.tonal(
              onPressed: controller.restart,
              child: const Text('再来一局'),
            ),
        ],
      ),
    );
  }
}
