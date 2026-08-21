import 'package:flutter/foundation.dart';

import '../core/ai.dart';
import '../core/game_logic.dart';

class LocalPlayer {
  final int slot;
  final String name;
  final bool isAi;
  const LocalPlayer(this.slot, this.name, this.isAi);
}

/// 本地三人对局（热座 + 可选 AI），用于离线验证规则与 AI。
class LocalGameController extends ChangeNotifier {
  List<int> board = GameLogic.newBoard();
  List<LocalPlayer> players = const [];
  int turn = 0;
  int? winner; // 座位号
  bool draw = false;
  bool aiThinking = false;
  int? lastIndex;
  int _aiCount = 0;

  void start(int aiCount) {
    _aiCount = aiCount;
    board = GameLogic.newBoard();
    players = [
      const LocalPlayer(0, '黑方', false),
      LocalPlayer(1, aiCount >= 1 ? 'AI' : '白方', aiCount >= 1),
      LocalPlayer(2, aiCount == 2 ? 'AI' : '红方', aiCount == 2),
    ];
    turn = 0;
    winner = null;
    draw = false;
    aiThinking = false;
    notifyListeners();
    _maybeAi();
  }

  void restart() => start(_aiCount);

  bool get isFinished => winner != null || draw;

  bool get canPlace =>
      !isFinished && !aiThinking && !players[turn].isAi;

  void placeAt(int row, int col) {
    if (!canPlace) return;
    final idx = GameLogic.indexOf(row, col);
    if (board[idx] != GameLogic.empty) return;
    _apply(turn, idx);
  }

  void _apply(int slot, int idx) {
    final next = List<int>.of(board);
    next[idx] = slot + 1;
    board = next;
    lastIndex = idx;

    final w = GameLogic.winnerAfterMove(board, GameLogic.rowOf(idx), GameLogic.colOf(idx));
    if (w != null) {
      winner = w;
    } else if (GameLogic.isFull(board)) {
      draw = true;
    } else {
      turn = (slot + 1) % 3;
    }
    notifyListeners();
    _maybeAi();
  }

  void _maybeAi() {
    if (isFinished || !players[turn].isAi) return;
    aiThinking = true;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 350), () {
      if (isFinished || !players[turn].isAi) {
        aiThinking = false;
        notifyListeners();
        return;
      }
      final idx = GomokuAI.bestMove(board, turn + 1);
      aiThinking = false;
      _apply(turn, idx);
    });
  }
}
