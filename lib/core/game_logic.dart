/// 五子棋核心规则：纯函数、无状态，便于离线测试。
class GameLogic {
  static const int size = 19;
  static const int cellCount = size * size;
  static const int empty = 0;

  static int indexOf(int row, int col) => row * size + col;
  static int rowOf(int idx) => idx ~/ size;
  static int colOf(int idx) => idx % size;

  static bool inBounds(int row, int col) =>
      row >= 0 && row < size && col >= 0 && col < size;

  static bool isFull(List<int> board) => !board.contains(empty);

  static List<int> newBoard() => List<int>.filled(cellCount, empty);

  static List<int> boardFromString(String s) =>
      s.split('').map((c) => c.codeUnitAt(0) - 48).toList();

  /// 在 (row, col) 落子后，返回获胜座位号（0/1/2），无人获胜返回 null。
  static int? winnerAfterMove(List<int> board, int row, int col) {
    final stone = board[indexOf(row, col)];
    if (stone == empty) return null;
    const dirs = [
      [0, 1], [1, 0], [1, 1], [1, -1], // 横、竖、主斜、副斜
    ];
    for (final d in dirs) {
      int count = 1;
      for (final sign in const [1, -1]) {
        int r = row + d[0] * sign;
        int c = col + d[1] * sign;
        while (inBounds(r, c) && board[indexOf(r, c)] == stone) {
          count++;
          r += d[0] * sign;
          c += d[1] * sign;
        }
      }
      if (count >= 5) return stone - 1;
    }
    return null;
  }

  /// 某方最长连续同色子（横/竖/斜四方向，封顶 5）。
  static int longestLine(List<int> board, int stone) {
    int best = 0;
    const dirs = [
      [0, 1], [1, 0], [1, 1], [1, -1],
    ];
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (board[indexOf(r, c)] != stone) continue;
        for (final d in dirs) {
          int cnt = 1;
          int rr = r + d[0];
          int cc = c + d[1];
          while (inBounds(rr, cc) && board[indexOf(rr, cc)] == stone) {
            cnt++;
            rr += d[0];
            cc += d[1];
          }
          if (cnt >= 5) return 5;
          if (cnt > best) best = cnt;
        }
      }
    }
    return best;
  }

  /// 满盘判胜：唯一最长连子者胜（返回座位号 0..2），并列返回 null。
  static int? winnerByLongestLine(List<int> board) {
    final l1 = longestLine(board, 1);
    final l2 = longestLine(board, 2);
    final l3 = longestLine(board, 3);
    if (l1 > l2 && l1 > l3) return 0;
    if (l2 > l1 && l2 > l3) return 1;
    if (l3 > l1 && l3 > l2) return 2;
    return null;
  }
}
