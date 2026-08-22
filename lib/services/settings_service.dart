import 'package:shared_preferences/shared_preferences.dart';

/// 用户设置（音效/震动开关）。启动时加载进内存缓存，切换即时生效。
class SettingsService {
  static const _soundKey = 'setting_sound';
  static const _hapticKey = 'setting_haptic';

  static bool sound = true;
  static bool haptic = true;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    sound = p.getBool(_soundKey) ?? true;
    haptic = p.getBool(_hapticKey) ?? true;
  }

  static Future<void> setSound(bool v) async {
    sound = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_soundKey, v);
  }

  static Future<void> setHaptic(bool v) async {
    haptic = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_hapticKey, v);
  }
}
