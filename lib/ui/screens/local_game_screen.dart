import 'package:flutter/material.dart';

import '../../core/game_logic.dart';
import '../../state/local_game_controller.dart';
import '../widgets/board_widget.dart';
import '../widgets/player_bar.dart';

class LocalGameScreen extends StatefulWidget {
  final LocalGameController controller;

  const LocalGameScreen({super.key, required this.controller});

  @override
  State<LocalGameScreen> createState() => _LocalGameScreenState();
}

class _LocalGameScreenState extends State<LocalGameScreen> {
  LocalGameController get c => widget.controller;
  bool _prevFinished = false;

  String _resultText() {
    if (c.winner != null) {
      final name = c.players[c.winner!].name;
      return GameLogic.isFull(c.board) ? '满盘判胜 · $name（最长连子）' : '$name 获胜！';
    }
    if (c.draw) {
      return GameLogic.isFull(c.board) ? '满盘和棋（并列最长）' : '和棋！';
    }
    return '';
  }

  void _checkResult() {
    final finished = c.isFinished;
    if (finished && !_prevFinished) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showResult());
    }
    _prevFinished = finished;
  }

  Future<void> _showResult() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_resultText()),
        content: const Text('本局结束'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              c.restart();
            },
            child: const Text('再来一局'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        _checkResult();
        return Scaffold(
          appBar: AppBar(
            title: const Text('本地三人对局'),
            actions: [
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: '悔棋',
                onPressed: c.canUndo ? c.undo : null,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '重新开局',
                onPressed: c.restart,
              ),
            ],
          ),
          body: Column(
            children: [
              PlayerBar(players: _info()),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: BoardWidget(
                    board: c.board,
                    lastIndex: c.lastIndex,
                    onTap: c.placeAt,
                    enabled: c.canPlace,
                  ),
                ),
              ),
              _status(),
            ],
          ),
        );
      },
    );
  }

  List<PlayerInfo> _info() {
    return c.players
        .map((p) => PlayerInfo(
              name: p.name,
              stone: p.slot + 1,
              isTurn: c.turn == p.slot,
              statusLabel: p.isAi ? 'AI' : '真人',
            ))
        .toList();
  }

  Widget _status() {
    final String text;
    if (c.isFinished) {
      text = _resultText();
    } else {
      final cur = c.players[c.turn];
      text = cur.isAi ? 'AI 思考中…' : '轮到 ${cur.name} 落子';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (c.isFinished)
            FilledButton.tonal(
              onPressed: c.restart,
              child: const Text('再来一局'),
            ),
        ],
      ),
    );
  }
}
