import 'package:flutter_test/flutter_test.dart';
import 'package:three_gomoku/core/ai.dart';
import 'package:three_gomoku/core/game_logic.dart';

void main() {
  test('横向五连获胜', () {
    final b = GameLogic.newBoard();
    for (int c = 5; c <= 9; c++) {
      b[GameLogic.indexOf(5, c)] = 1;
    }
    expect(GameLogic.winnerAfterMove(b, 5, 9), 0);
  });

  test('斜线五连获胜', () {
    final b = GameLogic.newBoard();
    for (int i = 0; i < 5; i++) {
      b[GameLogic.indexOf(3 + i, 3 + i)] = 2;
    }
    expect(GameLogic.winnerAfterMove(b, 7, 7), 1); // stone 2 -> 座位 1
  });

  test('四连不算赢', () {
    final b = GameLogic.newBoard();
    for (int c = 2; c <= 5; c++) {
      b[GameLogic.indexOf(8, c)] = 1;
    }
    expect(GameLogic.winnerAfterMove(b, 8, 5), isNull);
  });

  test('AI 优先补五取胜', () {
    final b = GameLogic.newBoard();
    for (int c = 4; c <= 7; c++) {
      b[GameLogic.indexOf(10, c)] = 1; // 黑方已有四连
    }
    final idx = GomokuAI.bestMove(b, 1);
    final a = GameLogic.indexOf(10, 3);
    final z = GameLogic.indexOf(10, 8);
    expect(idx == a || idx == z, isTrue);
  });

  test('中等难度封堵对手活三，简单难度不封堵', () {
    final b = GameLogic.newBoard();
    // 白方(stone 2)在 (9,5),(9,6),(9,7) 形成活三
    b[GameLogic.indexOf(9, 5)] = 2;
    b[GameLogic.indexOf(9, 6)] = 2;
    b[GameLogic.indexOf(9, 7)] = 2;
    final blocks = {GameLogic.indexOf(9, 4), GameLogic.indexOf(9, 8)};

    final medium = GomokuAI.bestMove(b, 1);
    final easy = GomokuAI.bestMove(b, 1, difficulty: 'easy');

    expect(blocks.contains(medium), isTrue, reason: '中等难度应封堵活三');
    expect(blocks.contains(easy), isFalse, reason: '简单难度不防守');
  });

  test('满盘判胜：唯一最长连子者胜', () {
    final b = GameLogic.newBoard();
    // 黑 3 连
    b[GameLogic.indexOf(5, 5)] = 1;
    b[GameLogic.indexOf(5, 6)] = 1;
    b[GameLogic.indexOf(5, 7)] = 1;
    // 白 4 连
    for (int c = 2; c <= 5; c++) {
      b[GameLogic.indexOf(10, c)] = 2;
    }
    // 红 2 连
    b[GameLogic.indexOf(15, 15)] = 3;
    b[GameLogic.indexOf(15, 16)] = 3;

    expect(GameLogic.longestLine(b, 2), 4);
    expect(GameLogic.winnerByLongestLine(b), 1); // 白(stone 2) → 座位 1
  });

  test('满盘并列最长 → 和棋', () {
    final b = GameLogic.newBoard();
    b[GameLogic.indexOf(5, 5)] = 1;
    b[GameLogic.indexOf(5, 6)] = 1;
    b[GameLogic.indexOf(5, 7)] = 1;
    b[GameLogic.indexOf(10, 2)] = 2;
    b[GameLogic.indexOf(10, 3)] = 2;
    b[GameLogic.indexOf(10, 4)] = 2;
    b[GameLogic.indexOf(15, 15)] = 3;
    b[GameLogic.indexOf(15, 16)] = 3;
    b[GameLogic.indexOf(15, 17)] = 3;

    expect(GameLogic.longestLine(b, 1), 3);
    expect(GameLogic.winnerByLongestLine(b), isNull); // 三方并列
  });
}
