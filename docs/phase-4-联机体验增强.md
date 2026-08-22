# Phase 4 · 联机体验增强

> 版本：1.4.0+5（M1）→ 1.5.0+6（M2）→ 1.6.0+7（M3）· 状态：进行中

## 目标
- 战绩详情页 + 设置（音效/震动开关、改名）。
- 房间聊天（轻量文字，Realtime 同步）。
- 回合计时 + 超时 AI 代下（解决等人等到天荒地老）。

按风险从低到高排三个里程碑，各自独立出 APK 真机验证；本阶段起每阶段配套开发文档（本文件）。

## M1 · 战绩详情页 + 设置（v1.4.0+5）
### 改动
- 新增 `lib/services/settings_service.dart`（音效/震动开关持久化）、`lib/core/feedback.dart`（`MoveFeedback.play()` 统一反馈入口）、`lib/ui/screens/stats_screen.dart`（战绩详情+清零）、`lib/ui/screens/settings_screen.dart`（开关+改名+关于）。
- `stats_service.dart` 增加连胜/连负统计与 `reset()`；两个控制器改用 `MoveFeedback.play()`；主菜单加入口；`room_prefs` 增加 `saveName`。
### 代码状态：已完成 ✅（待用户 analyze/test）
实际改动文件：`lib/services/settings_service.dart`、`lib/core/feedback.dart`、`lib/services/stats_service.dart`（+连胜/连负/清零）、`lib/ui/screens/stats_screen.dart`、`lib/ui/screens/settings_screen.dart`、`lib/ui/screens/home_screen.dart`（设置入口+战绩详情入口）、`lib/services/room_prefs.dart`（saveName）、`lib/state/local_game_controller.dart` 与 `lib/state/room_controller.dart`（统一 MoveFeedback）、`lib/main.dart`（启动加载设置）、`test/stats_service_test.dart`、`pubspec.yaml`（1.4.0+5）。

### 验证清单（真机）
- [ ] `flutter analyze` 零告警、`flutter test` 全绿（含新增 4 个战绩单测）
- [ ] 战绩页数字/胜率/连胜连负正确，清零生效
- [ ] 关音效/震动即时生效（本地局与联机局都试）
- [ ] 改名后回到房间显示新昵称

### 真机结果
（待填写）

## M2 · 房间聊天（v1.5.0+6）
### 改动
- 数据库 `supabase/migrations/0004_chat.sql`：`messages` 表（id/room_id 级联删除/sender_slot/sender_name/body/created_at）+ 仅成员可读 RLS + `send_message(room_id, body)` RPC（成员校验、trim、≤200 字、取玩家 jsonb 昵称）+ 加入 supabase_realtime publication + 授权。
- 客户端：`lib/models/chat_message.dart`（时间戳空格转 T）、`lib/services/chat_service.dart`（send / history 50 条）、`lib/state/room_controller.dart`（`messages` 列表、`sendChat`、进房拉历史、Realtime insert 订阅去重、列表封顶 100、离开清空）、`lib/ui/widgets/chat_panel.dart`（底部弹层：气泡列表自动滚底 + 输入框 200 字上限）、`lib/ui/screens/room_screen.dart`（AppBar 聊天按钮）、`test/chat_message_test.dart`。
### 边界与失败模式
- 非成员 RLS 拒绝读取；房间删除级联清消息；并发仅追加无冲突；Realtime 乱序按 id 排序兜底；托管座位仍以原座位身份发言。
### 验证清单（真机）
- [ ] `flutter analyze` 零告警、`flutter test` 全绿（含新聊天解析测试）
- [ ] 两机同房互发消息 <1s 送达，双方气泡/昵称/颜色正确
- [ ] 重开聊天面板能拉到最近历史
- [ ] 超过 200 字被拒
- [ ] 非成员（RLS）读取为空
### 真机结果
（待填写）

## M3 · 回合计时 + 超时托管（v1.6.0+7）
### 改动
- 数据库 `supabase/migrations/0005_turn_timer.sql`：
  - `rooms` 加列 `turn_timeout_sec`（null=不限时，校验 15..600）与 `move_deadline`（null=不适用）。
  - 辅助函数 `compute_deadline(r)`：playing 且当前回合为人座且限时非空 → now()+限时，否则 null。
  - `create_room` 加 `turn_timeout_sec` 参数；`join_room` 末位加入转 playing 时设截止时间；`submit_move` 加 `as_timeout_ai`（截止后任何成员可代下解锁，本人迟到落子被拒 'move timed out'），落子后刷新下一手截止时间；`reset_room`/`leave_room`/`take_over` 同步刷新；新签名授权。
- 客户端：
  - `lib/models/room.dart`（+turnTimeoutSec/moveDeadline 解析）、`lib/services/room_service.dart`（createRoom/submitMove 新参数）。
  - `lib/state/room_controller.dart`：1 秒倒计时（`remaining`）、超时触发 `bestMove` + `asTimeoutAi:true` 代下（`_timeoutInFlight` 防重）、`timeoutMessage` 供页面提示。
  - `lib/ui/widgets/player_bar.dart`（当前回合人座显示 ⏱ m:ss，≤10 秒变红）、`lib/ui/screens/room_screen.dart`（超时 SnackBar）、`lib/ui/screens/create_room_screen.dart`（每步限时：不限/30/60/120 秒，默认 60）、`test/room_model_test.dart`。
### 边界与失败模式
- AI 座位回合无倒计时（deadline 为 null）；旧房间无 `turn_timeout_sec` → 不限时，向后兼容。
- 房主离线 + 超时：任何成员都能触发 AI 代下；全员离线则卡局，7 天由 `cleanup_stale_rooms` 清理（已知限制）。
- 双端同时触发：服务端事务 turn 校验保证一方成功，另一方静默忽略，Realtime 收敛。
- 客户端时钟偏差只影响显示，服务端 deadline 是唯一权威。
### 验证清单（真机）
- [ ] `flutter analyze` 零告警、`flutter test` 全绿（含新 Room 解析测试）
- [ ] 60 秒房：倒计时递减显示，≤10 秒变红
- [ ] 不动 → 1–2 秒内 AI 代下一手，三端同步，SnackBar 提示
- [ ] 超时后本人再点被拒（服务端 'move timed out'）
- [ ] 再来一局倒计时重置；不限时无倒计时；AI 座位回合无倒计时
### 真机结果
（待填写）

## 明确不做（本阶段）
观战、分享、快速匹配、排行榜、复盘、正式上架签名、服务端 pg_cron 超时兜底。
