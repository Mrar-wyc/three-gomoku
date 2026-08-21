import 'game_logic.dart';

/// 五子棋 AI：启发式评分 + 攻守加权。
/// 三人局关键差异：同时评估两个对手的威胁，防守分取二者最大值。
/// 难度：
/// - easy   = 只进攻（除立即取胜/封堵外不防守）
/// - medium = 攻守兼顾（默认）
/// - hard   = 1.5 层搜索：对 top-K 候选评估「我方评分 − 两个对手最强回应评分」
class GomokuAI {
  static const int _win = 1000000;
  static const int _attackWeight = 10;
  static const int _defenseWeightMedium = 9;
  static const int _defenseWeightEasy = 0;
  static const int _hardTopK = 12;

  /// 返回最佳落点索引；stone 取值 1..3。
  static int bestMove(List<int> board, int stone, {String difficulty = 'medium'}) {
    if (difficulty == 'hard') return _hardMove(board, stone);

    final candidates = _candidates(board);
    if (candidates.isEmpty) {
      return GameLogic.indexOf(GameLogic.size ~/ 2, GameLogic.size ~/ 2);
    }

    final defenseWeight = difficulty == 'easy' ? _defenseWeightEasy : _defenseWeightMedium;
    final opps = [1, 2, 3].where((s) => s != stone).toList();
    int bestIdx = candidates.first;
    int bestScore = -1;

    for (final idx in candidates) {
      final row = GameLogic.rowOf(idx);
      final col = GameLogic.colOf(idx);
      final my = _scoreAt(board, row, col, stone);

      // 自己能立即连五，直接取胜（两档难度都执行）。
      if (my >= _win) return idx;

      int maxOpp = 0;
      for (final o in opps) {
        final s = _scoreAt(board, row, col, o);
        if (s > maxOpp) maxOpp = s;
      }

      // 对手下一步能连五，必须封堵（两档难度都执行）。
      final int total;
      if (maxOpp >= _win) {
        total = _win + my;
      } else {
        total = my * _attackWeight + maxOpp * defenseWeight;
      }

      if (total > bestScore) {
        bestScore = total;
        bestIdx = idx;
      }
    }
    return bestIdx;
  }

  /// 困难：对 top-K 候选做一步前瞻。
  /// 每个候选：落子后计算两个对手各自的最强回应，取最坏回应；
  /// 评估值 = 我方该步攻击分 − 对手最强回应分 × 防守权重。
  static int _hardMove(List<int> board, int stone) {
    final candidates = _candidates(board);
    if (candidates.isEmpty) {
      return GameLogic.indexOf(GameLogic.size ~/ 2, GameLogic.size ~/ 2);
    }
    final opps = [1, 2, 3].where((s) => s != stone).toList();

    // 立即取胜 / 立即封堵（与 medium 同规则）
    final scored = <(int, int)>[];
    int? blockIdx;
    for (final idx in candidates) {
      final r = GameLogic.rowOf(idx);
      final c = GameLogic.colOf(idx);
      final my = _scoreAt(board, r, c, stone);
      if (my >= _win) return idx;
      int maxOpp = 0;
      for (final o in opps) {
        final s = _scoreAt(board, r, c, o);
        if (s > maxOpp) maxOpp = s;
      }
      if (maxOpp >= _win) blockIdx ??= idx;
      scored.add((idx, my * _attackWeight + maxOpp * _defenseWeightMedium));
    }
    if (blockIdx != null) return blockIdx;

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final top = scored.take(_hardTopK).toList();

    int bestIdx = top.first.$1;
    int bestEval = -1000000000;

    for (final entry in top) {
      final idx = entry.$1;
      final r = GameLogic.rowOf(idx);
      final c = GameLogic.colOf(idx);
      board[idx] = stone;

      int worstReply = 0;
      for (final o in opps) {
        final oCands = _candidates(board);
        int bestO = 0;
        for (final oi in oCands) {
          final or = GameLogic.rowOf(oi);
          final oc = GameLogic.colOf(oi);
          final s = _scoreAt(board, or, oc, o);
          if (s >= _win) {
            bestO = _win;
            break;
          }
          if (s > bestO) bestO = s;
        }
        if (bestO > worstReply) worstReply = bestO;
      }

      board[idx] = GameLogic.empty;
      final my = _scoreAt(board, r, c, stone);
      final eval = my * _attackWeight - worstReply * _defenseWeightMedium;
      if (eval > bestEval) {
        bestEval = eval;
        bestIdx = idx;
      }
    }
    return bestIdx;
  }

  /// 评估 stone 在 (row, col) 落子后的棋形得分（不修改原棋盘）。
  static int _scoreAt(List<int> board, int row, int col, int stone) {
    final idx = GameLogic.indexOf(row, col);
    if (board[idx] != GameLogic.empty) return -1;
    board[idx] = stone;

    int total = 0;
    const dirs = [
      [0, 1], [1, 0], [1, 1], [1, -1],
    ];
    for (final d in dirs) {
      int count = 1;
      int open = 0;
      for (final sign in const [1, -1]) {
        int r = row + d[0] * sign;
        int c = col + d[1] * sign;
        while (GameLogic.inBounds(r, c) &&
            board[GameLogic.indexOf(r, c)] == stone) {
          count++;
          r += d[0] * sign;
          c += d[1] * sign;
        }
        if (GameLogic.inBounds(r, c) &&
            board[GameLogic.indexOf(r, c)] == GameLogic.empty) {
          open++;
        }
      }
      total += _shapeScore(count, open);
    }

    board[idx] = GameLogic.empty;
    return total;
  }

  static int _shapeScore(int count, int open) {
    if (count >= 5) return _win;
    if (open == 0) return 0; // 两头被封，死棋
    switch (count) {
      case 4:
        return open == 2 ? 100000 : 50000; // 活四 / 冲四
      case 3:
        return open == 2 ? 5000 : 500; // 活三 / 眠三
      case 2:
        return open == 2 ? 200 : 30; // 活二 / 眠二
      case 1:
        return 10;
      default:
        return 0;
    }
  }

  /// 只在已有棋子附近 2 格内生成候选点，缩小搜索范围。
  static List<int> _candidates(List<int> board) {
    final set = <int>{};
    bool any = false;
    for (int r = 0; r < GameLogic.size; r++) {
      for (int c = 0; c < GameLogic.size; c++) {
        if (board[GameLogic.indexOf(r, c)] != GameLogic.empty) {
          any = true;
          for (int dr = -2; dr <= 2; dr++) {
            for (int dc = -2; dc <= 2; dc++) {
              final nr = r + dr;
              final nc = c + dc;
              if (GameLogic.inBounds(nr, nc) &&
                  board[GameLogic.indexOf(nr, nc)] == GameLogic.empty) {
                set.add(GameLogic.indexOf(nr, nc));
              }
            }
          }
        }
      }
    }
    if (!any) {
      return [GameLogic.indexOf(GameLogic.size ~/ 2, GameLogic.size ~/ 2)];
    }
    return set.toList();
  }
}
