import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';

class SupabaseService {
  static bool _initialized = false;

  /// 懒加载初始化：本地模式不需要 Supabase，只有进入联机流程才初始化。
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// 匿名登录（游客制），返回当前设备 uid。
  static Future<String> ensureSignedIn() async {
    await ensureInitialized();
    final c = client;
    final existing = c.auth.currentUser;
    if (existing != null) return existing.id;
    final res = await c.auth.signInAnonymously();
    return res.user!.id;
  }
}
