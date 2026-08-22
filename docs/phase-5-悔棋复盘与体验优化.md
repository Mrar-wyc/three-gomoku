# Phase 5 · 悔棋 + 复盘与胜利高亮 + 体验优化包

> 版本：1.7.0+8（M1）→ 1.8.0+9（M2）→ 1.9.0+10（M3）· 状态：进行中（M1 待开工）

## 目标
- 联机悔棋（其他真人座位全员同意）+ 本地局悔棋。
- 终局复盘回放 + 胜利连线高亮。
- 体验优化包：AI 后台计算、昵称长度限制、聊天未读角标。

## M1 · 悔棋（v1.7.0+8）
### 规则
- 发起者 = 最后落子者（含超时 AI 代下的座位主人）；只撤销最后一步。
- 其他真人座位全员同意（AI/托管视为同意）；30 秒未全同意自动作废；发起者可取消。
- 撤销后回合回到发起者、胜负清空回 playing、限时截止时间刷新；发起期间落子被拒。
### 改动
- 数据库 `supabase/migrations/0006_undo.sql`：`moves` 落子历史表（RLS 成员可读，不进 Realtime）+ `rooms` 加 `last_move_slot/undo_slot/undo_accepts/undo_expires_at` + `board_from_moves` 重放函数 + `do_undo` 内部撤销函数 + `request_undo/respond_undo/cancel_undo` RPC + `submit_move` 记录落子并拦截 pending（30 秒过期自动解除）+ `reset_room` 清历史 + 昵称 ≤20 校验（顺手加固）。
- 客户端：`lib/models/room.dart`（悔棋字段 + undoPending）、`lib/services/room_service.dart`（3 个 RPC）、`lib/state/room_controller.dart`（canRequestUndo/iAmUndoRequester/iAmUndoVoter、request/respond/cancel、undoMessage 提示、submitMove 捕获 'undo pending'）、`lib/ui/screens/room_screen.dart`（悔棋按钮、同意弹窗、pending 横幅+取消、复制房间号）。
- 本地局：`local_game_controller.dart`（棋盘+回合快照栈、canUndo/undo，AI 落子与思考中不可悔）、`local_game_screen.dart`（AppBar 悔棋按钮，随状态启停）。
- 测试：`test/local_undo_test.dart`（4 例）、`test/room_model_test.dart` 补悔棋字段解析。版本 1.7.0+8。
### 验证清单（真机，需 2–3 台）
- [ ] 最后落子者能看到「悔棋」按钮，其他人看不到
- [ ] 发起后：其他真人弹同意窗；拒绝→提示被拒；全员同意→撤销成功、棋盘回退、回合回发起者
- [ ] AI/托管座位不弹窗；无人需同意（纯 AI 局外场景）直接撤销
- [ ] 30 秒未响应自动作废；发起者可取消
- [ ] 悔棋发起期间其他人落子被拒并提示
- [ ] 本地局（热座/AI）悔棋正常：局面与回合还原，AI 思考中不可悔
- [ ] 大厅复制房间号可用
### 已知问题与修复
- **42702 撞名 bug**（真机发现）：0006 中 `where room_id = room_id` / `values (room_id, ...)` 的裸标识符被 PL/pgSQL 解析为列而非函数参数 → 发起悔棋与「再来一局」报 ambiguous。
- 修复：`supabase/migrations/0007_fix_ambiguous.sql` 重写 5 个函数，参数名保持 `room_id` 不变（客户端按命名参数调用），函数体内引入局部变量 `p_room := room_id` 并全部引用 p_room。签名不变 → 无需重新 grant。
- 经验（已沉淀进坑清单）：**plpgsql 里参数名与列名相同时，SQL 语句内裸引用一律解析为列**；要么参数起名不与任何列重名（如 p_room），要么函数体内先复制到局部变量。

### 真机结果
（待填写）

## M2 · 复盘 + 胜利连线高亮（v1.8.0+9）
（待填写）

## M3 · 体验优化包（v1.9.0+10）
（待填写）

## 明确不做（本阶段）
观战、快速匹配、排行榜（游客身份不可靠）、pg_cron 超时兜底、胜利音效资产、暗色主题、本地局复盘。
