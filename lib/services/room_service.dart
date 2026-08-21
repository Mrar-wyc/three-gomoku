import '../models/room.dart';
import 'supabase_service.dart';

class RoomService {
  /// PostgREST 对「返回表行」的函数返回数组，取第一条即可。
  static Room _parse(dynamic data) {
    Map<String, dynamic> map;
    if (data is List && data.isNotEmpty) {
      map = Map<String, dynamic>.from(data.first as Map);
    } else if (data is Map) {
      map = Map<String, dynamic>.from(data);
    } else {
      throw Exception('意外的返回数据: $data');
    }
    return Room.fromJson(map);
  }

  static Future<Room> createRoom(String name, int aiCount) async {
    final data = await SupabaseService.client.rpc(
      'create_room',
      params: {'player_name': name, 'ai_count': aiCount},
    );
    return _parse(data);
  }

  static Future<Room> joinRoom(String code, String name) async {
    final data = await SupabaseService.client.rpc(
      'join_room',
      params: {'p_code': code, 'player_name': name},
    );
    return _parse(data);
  }

  static Future<Room> submitMove(String roomId, int slot, int row, int col) async {
    final data = await SupabaseService.client.rpc(
      'submit_move',
      params: {'room_id': roomId, 'slot': slot, 'rrow': row, 'ccol': col},
    );
    return _parse(data);
  }

  static Future<Room> setConnected(String roomId, bool connected) async {
    final data = await SupabaseService.client.rpc(
      'set_connected',
      params: {'room_id': roomId, 'connected': connected},
    );
    return _parse(data);
  }

  static Future<Room> leaveRoom(String roomId) async {
    final data = await SupabaseService.client.rpc(
      'leave_room',
      params: {'room_id': roomId},
    );
    return _parse(data);
  }
}
