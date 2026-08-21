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
}
