/// 房间聊天消息。
class ChatMessage {
  final int id;
  final String roomId;
  final int senderSlot;
  final String senderName;
  final String body;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderSlot,
    required this.senderName,
    required this.body,
    this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    return ChatMessage(
      id: j['id'] as int,
      roomId: j['room_id'] as String,
      senderSlot: j['sender_slot'] as int? ?? 0,
      senderName: j['sender_name'] as String? ?? '',
      body: j['body'] as String? ?? '',
      createdAt: _parseTs(j['created_at']),
    );
  }

  static DateTime? _parseTs(dynamic v) {
    if (v is! String) return null;
    try {
      // Postgres 返回 "2025-01-01 12:00:00+00"，需补 T 才能被 DateTime.parse 接受
      return DateTime.parse(v.replaceFirst(' ', 'T'));
    } catch (_) {
      return null;
    }
  }
}
