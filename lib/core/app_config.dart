/// Supabase 配置。
/// anon key 是公开的，可以安全地内置进 App（不要放 service_role key）。
class AppConfig {
  // TODO(用户): 创建 Supabase 项目后，把下面两行替换成你自己的值。
  static const String supabaseUrl = 'https://YOUR-PROJECT.supabase.co';
  static const String supabaseAnonKey = 'YOUR-ANON-KEY';
}
