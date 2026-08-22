import '../models/chat_message.dart';
import 'supabase_service.dart';

class ChatService {
  /// 发送一条消息（服务端校验成员身份与长度）。
  static Future<void> send(String roomId, String body) async {
    await SupabaseService.client.rpc(
      'send_message',
      params: {'room_id': roomId, 'body': body},
    );
  }

  /// 拉取最近 [limit] 条历史消息（按时间正序返回）。
  static Future<List<ChatMessage>> history(String roomId, {int limit = 50}) async {
    final data = await SupabaseService.client
        .from('messages')
        .select()
        .eq('room_id', roomId)
        .order('id', ascending: false)
        .limit(limit);
    final list = (data as List?) ?? const [];
    final msgs = list
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return msgs.reversed.toList();
  }
}
