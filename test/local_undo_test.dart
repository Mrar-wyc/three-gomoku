import 'package:flutter_test/flutter_test.dart';
import 'package:three_gomoku/core/game_logic.dart';
import 'package:three_gomoku/state/local_game_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('本地悔棋：撤销最后一步并还原回合', () {
    final c = LocalGameController()..start(0);
    c.placeAt(0, 0); // 黑
    c.placeAt(0, 1); // 白
    c.placeAt(1, 0); // 红
    expect(c.turn, 0);
    expect(c.canUndo, isTrue);
    c.undo();
    expect(c.board[GameLogic.indexOf(1, 0)], GameLogic.empty);
    expect(c.board[GameLogic.indexOf(0, 0)], 1);
    expect(c.board[GameLogic.indexOf(0, 1)], 2);
    expect(c.turn, 2); // 回到红方
  });

  test('可连续悔棋（栈式回退）', () {
    final c = LocalGameController()..start(0);
    c.placeAt(0, 0); // 黑
    c.placeAt(0, 1); // 白
    c.placeAt(1, 0); // 红
    c.placeAt(1, 1); // 黑
    c.undo(); // 撤 (1,1) 黑 → turn=0
    c.undo(); // 撤 (1,0) 红 → turn=2
    expect(c.turn, 2);
    expect(c.board[GameLogic.indexOf(1, 0)], GameLogic.empty);
    expect(c.board[GameLogic.indexOf(1, 1)], GameLogic.empty);
    expect(c.board[GameLogic.indexOf(0, 0)], 1);
    expect(c.board[GameLogic.indexOf(0, 1)], 2);
  });

  test('AI 思考中不可悔棋', () async {
    final c = LocalGameController()..start(1); // 白方 AI
    c.placeAt(0, 0); // 黑落子 → 轮到白(AI)，aiThinking 同步置位
    expect(c.canUndo, isFalse);
    // 等 AI 落完子，避免遗留 Timer
    await Future.delayed(const Duration(milliseconds: 600));
    expect(c.players[c.turn].isAi, isFalse); // 轮到红(真人)
  });

  test('AI 落下的子不可悔，真人落的可悔', () async {
    final c = LocalGameController()..start(1);
    c.placeAt(0, 0); // 黑(真人)
    await Future.delayed(const Duration(milliseconds: 600)); // 白(AI)落子
    c.placeAt(5, 5); // 红(真人)落子 → 轮到黑
    expect(c.canUndo, isTrue); // 最后一步是红(真人)
    c.undo();
    expect(c.turn, 2);
    expect(c.board[GameLogic.indexOf(5, 5)], GameLogic.empty);
  });
}
