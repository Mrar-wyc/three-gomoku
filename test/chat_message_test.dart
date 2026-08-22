import 'package:flutter_test/flutter_test.dart';
import 'package:three_gomoku/models/chat_message.dart';

void main() {
  test('ChatMessage.fromJson 解析（含空格时间戳）', () {
    final m = ChatMessage.fromJson({
      'id': 3,
      'room_id': 'r1',
      'sender_slot': 1,
      'sender_name': '小明',
      'body': '你好',
      'created_at': '2025-01-01 12:00:00+00',
    });
    expect(m.id, 3);
    expect(m.roomId, 'r1');
    expect(m.senderSlot, 1);
    expect(m.senderName, '小明');
    expect(m.body, '你好');
    expect(m.createdAt, DateTime.parse('2025-01-01T12:00:00+00:00'));
  });
}
