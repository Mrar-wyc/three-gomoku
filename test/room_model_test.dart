import 'package:flutter_test/flutter_test.dart';
import 'package:three_gomoku/models/room.dart';

void main() {
  test('Room.fromJson 解析新增限时字段', () {
    final r = Room.fromJson({
      'id': 'a',
      'code': 'ABC123',
      'host_id': 'h',
      'players': [
        {'slot': 0, 'name': '甲', 'is_ai': false, 'uid': 'u1', 'connected': true},
      ],
      'board': '',
      'turn': 0,
      'status': 'playing',
      'winner': null,
      'ai_difficulty': 'medium',
      'turn_timeout_sec': 60,
      'move_deadline': '2025-01-01 12:00:00+00',
    });
    expect(r.turnTimeoutSec, 60);
    expect(r.moveDeadline, DateTime.parse('2025-01-01T12:00:00+00:00'));
  });

  test('Room.fromJson 兼容旧数据（无限时字段）', () {
    final r = Room.fromJson({
      'id': 'a',
      'code': 'ABC123',
      'host_id': 'h',
      'players': <Object>[],
      'board': '',
      'turn': 0,
      'status': 'waiting',
      'winner': null,
    });
    expect(r.turnTimeoutSec, isNull);
    expect(r.moveDeadline, isNull);
  });

  test('Room.fromJson 解析悔棋字段', () {
    final r = Room.fromJson({
      'id': 'a',
      'code': 'ABC123',
      'host_id': 'h',
      'players': <Object>[],
      'board': '',
      'turn': 1,
      'status': 'playing',
      'winner': null,
      'last_move_slot': 1,
      'undo_slot': 1,
      'undo_accepts': ['u1'],
      'undo_expires_at': '2025-01-01 12:00:00+00',
    });
    expect(r.lastMoveSlot, 1);
    expect(r.undoPending, isTrue);
    expect(r.undoSenderSlot, 1);
    expect(r.undoAccepts, ['u1']);
    expect(r.undoExpiresAt, DateTime.parse('2025-01-01T12:00:00+00:00'));
  });

  test('undoPending 兼容旧数据', () {
    final r = Room.fromJson({
      'id': 'a',
      'code': 'ABC123',
      'host_id': 'h',
      'players': <Object>[],
      'board': '',
      'turn': 0,
      'status': 'waiting',
      'winner': null,
    });
    expect(r.undoPending, isFalse);
    expect(r.lastMoveSlot, isNull);
    expect(r.undoAccepts, isEmpty);
  });
}
