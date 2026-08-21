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
}
