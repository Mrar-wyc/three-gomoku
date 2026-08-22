# Phase 2 · 联机功能

> 版本：1.2.x · 状态：已完成

## 目标
公网联机：房主建房生成 6 位房间号，朋友输入加入；空位 AI 补位；掉线 AI 托管；断线可重连回房。

## 交付内容
- Supabase 后端（`supabase/migrations/0001_init.sql` + `0002_online_features.sql`）：
  - 单表 `rooms`（一行一局，服务端为唯一事实源），RPC：`create_room` / `join_room` / `submit_move` / `set_connected` / `leave_room` / `take_over` / `reset_room` / `gen_room_code` / `cleanup_stale_rooms`。
  - RLS：仅本房成员可 SELECT 房间行；所有写操作走 SECURITY DEFINER RPC。
  - Realtime：订阅 `rooms` 行变更，整行替换本地状态。
- 客户端：
  - `lib/services/supabase_service.dart`（匿名登录）、`room_service.dart`（RPC 封装）、`room_prefs.dart`（房间号/昵称持久化）。
  - `lib/state/room_controller.dart`：心跳（10s）、掉线检测（90s→`take_over`）、AI 代下、重连恢复被托管座位、再来一局。
  - 页面：创建房间 / 加入房间 / 房间（棋盘对战）。
- GitHub Actions `build-apk.yml`：push/tag 自动构建 release APK。

## 关键决策
- 完整棋盘状态存单行 + Realtime 广播整行 → 天然支持中途重进拉取全量状态；回合串行无并发写冲突。
- AI 在房主客户端本地运行（不占服务端算力），房主代 AI 座位调 `submit_move`。
- 匿名登录（游客制），uid 持久化用于重连。

## 已知问题（后续修复）
- 0002 中 `gen_room_code` 变量与 `rooms.code` 撞名 → 已改名 `v_code` 修复。

## 验证
- 后端全链路 RPC 验证通过；真机双机同房对局、掉线托管、重连恢复均通过。
