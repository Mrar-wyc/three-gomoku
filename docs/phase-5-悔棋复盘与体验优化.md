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
- **0007 未彻底修复，追加 `0008_fix_ambiguous2.sql`**：真机+SQL 直调（CONTEXT 行号）定位出真正根因 —— PostgreSQL 9.6+ 对「列与 PL/pgSQL 变量**同名**」直接报 42702（不是文档说的"列优先"）。0007 消除了"变量=列"的左侧歧义，但 `where room_id = p_room` 里裸 `room_id` 仍与参数 `room_id` 同名 → 只有 `request_undo` 与 `reset_room`（引用 moves.room_id 的函数）炸。修复：moves 加表别名，列引用全部限定 `m.room_id` / `m.id`。
- 经验（已沉淀进坑清单）：**SQL 语句中任何裸列引用都不能与函数参数/变量同名**；参数名避开所有列名，或列引用一律表别名限定。已用 REST 全链路闭环验证（发起→全员同意→撤销、终局→再来一局→新局落子→新局悔棋）。
- 经验（已沉淀进坑清单）：**plpgsql 里参数名与列名相同时，SQL 语句内裸引用一律解析为列**；要么参数起名不与任何列重名（如 p_room），要么函数体内先复制到局部变量。

### 真机结果
（待填写）

## M2 · 复盘 + 胜利连线高亮（v1.8.0+9）
### 改动
- **胜利连线高亮**：`lib/core/game_logic.dart` 新增纯函数 `winningLineCells(board, idx)`（过 idx 的整条五连）与 `longestLineCells(board, stone)`（最长连子格子）；`lib/ui/widgets/board_widget.dart` 新增 `highlight` 集合，制胜子画橙色高亮环；本地局与联机局终局时自动计算（5 连胜 → winningLineCells(lastIndex)；满盘判胜 → longestLineCells(胜方)；和棋不高亮）。
- **复盘（联机）**：`lib/services/moves_service.dart`（moves 表按 id 正序拉取，RLS 成员可读）+ `lib/ui/screens/replay_screen.dart`（只读棋盘 + 进度条拖动 + 上一步/下一步/自动播放 600ms + 当前手信息 + 终局制胜高亮）；`room_screen.dart` 终局弹窗新增「复盘」按钮。
- 测试：`test/game_logic_test.dart` 追加 3 例（五连格子/四连空/最长连子）；版本 1.8.0+9。
### 验证清单（真机）
- [ ] `flutter analyze` 零告警、`flutter test` 全绿
- [ ] 本地局与联机局：五连获胜后制胜子出现橙色高亮环
- [ ] 满盘最长连子判胜时高亮最长连子
- [ ] 终局弹窗点「复盘」→ 回放整局：拖动/上一步/下一步/自动播放正常，终局高亮同步
- [ ] 复盘界面棋盘只读（点击无反应）
### 真机结果
（待填写）

## M3 · 体验优化包（v1.9.0+10）
### 改动
- **AI 后台计算**：`room_controller._scheduleAiIfNeeded` 与 `local_game_controller._maybeAi` 的 AI 计算移入 `Isolate.run`（ai.dart 为纯 Dart，无 Flutter 依赖）→ 困难档不再卡 UI；isolate 失败安全回退。
- **昵称限制**：建房/加入/设置页输入框 `maxLength: 20`（服务端校验已随 0006 生效）。
- **聊天未读角标**：RoomController 新增 `unreadChatCount`/`markChatRead`（进房基线=历史数）；房间页聊天按钮 `Badge.count` 显示未读数；打开面板标记已读，面板内静默同步（避免 build 期间通知）。
- 版本 1.9.0+10。
### 验证清单（真机）
- [ ] `flutter analyze` 零告警、`flutter test` 全绿
- [ ] 困难 AI 落子时界面不卡顿（对比优化前）
- [ ] 昵称输入超过 20 字被截断；服务端超长昵称被拒（返回 invalid name）
- [ ] 有人发消息时聊天按钮出现未读数角标；打开面板后角标消失；面板开着时新消息不累计角标
### 真机结果
（待填写）

## 明确不做（本阶段）
观战、快速匹配、排行榜（游客身份不可靠）、pg_cron 超时兜底、胜利音效资产、暗色主题、本地局复盘。
