import 'package:shared_preferences/shared_preferences.dart';

/// 持久化当前房间号与昵称，用于「断线重连 / 回到房间」。
class RoomPrefs {
  static const _codeKey = 'room_code';
  static const _nameKey = 'player_name';

  static Future<void> save(String code, String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_codeKey, code);
    await p.setString(_nameKey, name);
  }

  /// 只更新昵称（保留当前房间号，用于设置页改名）。
  static Future<void> saveName(String name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_nameKey, name);
  }

  static Future<(String?, String?)> load() async {
    final p = await SharedPreferences.getInstance();
    return (p.getString(_codeKey), p.getString(_nameKey));
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_codeKey);
    await p.remove(_nameKey);
  }
}
