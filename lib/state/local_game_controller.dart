import 'package:flutter/foundation.dart';

import '../core/ai.dart';
import '../core/feedback.dart';
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
  final List<(List<int>, int)> _undoStack = []; // (落子前棋盘, 落子前回合)
  int _aiCount = 0;
  String _difficulty = 'medium';

  void start(int aiCount, {String difficulty = 'medium'}) {
    _aiCount = aiCount;
    _difficulty = difficulty;
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
    lastIndex = null;
    _undoStack.clear();
    notifyListeners();
    _maybeAi();
  }

  void restart() => start(_aiCount, difficulty: _difficulty);

  /// 可悔棋：对局未结束、AI 未思考、且最后一步是真人落下。
  bool get canUndo {
    if (isFinished || aiThinking || _undoStack.isEmpty) return false;
    final prevTurn = _undoStack.last.$2;
    return prevTurn >= 0 && prevTurn < players.length && !players[prevTurn].isAi;
  }

  /// 悔一步：恢复落子前棋盘与回合。
  void undo() {
    if (!canUndo) return;
    final (b, t) = _undoStack.removeLast();
    board = b;
    turn = t;
    winner = null;
    draw = false;
    lastIndex = null;
    notifyListeners();
  }

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
    _undoStack.add((List<int>.of(board), turn));
    final next = List<int>.of(board);
    next[idx] = slot + 1;
    board = next;
    lastIndex = idx;
    MoveFeedback.play();

    final w = GameLogic.winnerAfterMove(board, GameLogic.rowOf(idx), GameLogic.colOf(idx));
    if (w != null) {
      winner = w;
    } else if (GameLogic.isFull(board)) {
      final w = GameLogic.winnerByLongestLine(board);
      if (w != null) {
        winner = w;
      } else {
        draw = true;
      }
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
      final idx = GomokuAI.bestMove(board, turn + 1, difficulty: _difficulty);
      aiThinking = false;
      _apply(turn, idx);
    });
  }
}
