---
name: android-flutter-playbook
description: 从「三人五子棋」实战项目复盘沉淀的 Android（Flutter）小游戏完整开发手册：架构分层、联机后端（Supabase）模式、小步快跑里程碑工作流、玩法机制模板、坑清单与验收模板。开发安卓软件、Flutter 应用、联机小游戏、需要 Supabase 后端或 GitHub Actions 打包 APK 时使用。
whenToUse: 用户要求开发或迭代安卓/Flutter 应用、联机小游戏、移动端项目；涉及 Supabase/Realtime/RLS 联机、GitHub Actions 出 APK、里程碑节奏交付、断线托管/超时/悔棋等玩法机制时。
---

# Android（Flutter）小游戏开发手册 —— 三人五子棋实战复盘

## 0. 结论一句话

Flutter 客户端（纯逻辑层可单测）+ Supabase 服务端唯一事实源（SECURITY DEFINER RPC + RLS + Realtime 整行广播）+ GitHub Actions 自动打包（debug 签名）+ 小步快跑（每阶段文档、每里程碑一个 APK、真机验证后前进）——这套组合已完整跑通 5 个阶段、16 个里程碑式迭代，可直接复用。

## 1. 项目背景（可复制的参照）

- 三人五子棋：19×19、三人轮流（黑/白/红）、先连五者胜；游客制 6 位房间号联机。
- 技术栈：Flutter 3.47 / Dart 3.13、supabase_flutter ^2.8、shared_preferences；Supabase 免费档（Postgres + Realtime + 匿名登录）；GitHub Actions 构建 release APK。
- 演进：本地玩法 → 联机 → 满盘判胜/困难AI/战绩/图标 → 聊天/回合计时/设置 → 悔棋/复盘/胜利高亮。每阶段 1~3 个里程碑。

## 2. 架构分层（游戏应用通用模板）

```
lib/
├── core/        # 纯逻辑，零 Flutter/网络依赖，必须可单测
│   ├── game_logic.dart   # 规则：落子合法性、胜负判定、满盘判胜（纯函数）
│   ├── ai.dart           # AI 评分（启发式 + 前瞻，纯 Dart）
│   ├── constants.dart    # 颜色/名称等常量
│   ├── app_config.dart   # 后端 URL / 公开 key（可内置）
│   └── feedback.dart     # 音效/震动统一入口（读取设置开关）
├── models/       # 数据模型，与后端字段一一对应
├── services/     # RPC 封装 / 本地偏好 / 统计
├── state/        # ChangeNotifier 控制器：本地局控制器 + 联机房控制器分开
├── ui/screens/   # 页面
├── ui/widgets/   # 可复用控件（棋盘、玩家栏、聊天面板…）
├── main.dart / app.dart
supabase/migrations/0001_init.sql ...  # 编号迁移，create or replace 可重跑
.github/workflows/build-apk.yml
docs/phase-N-*.md                     # 每阶段开发文档
```

### 关键代码模式

**纯逻辑（core）**：规则判定写成 static 纯函数，输入输出都是基本类型，离线可测：

```dart
static int? winnerAfterMove(List<int> board, int row, int col) { ... } // 返回座位号或 null
static int? winnerByLongestLine(List<int> board) { ... } // 满盘按最长连子判胜
```

**模型时间戳容错**（Postgres 返回空格分隔，DateTime.parse 不接受）：

```dart
static DateTime? _parseTs(dynamic v) => v is String ? DateTime.tryParse(v.replaceFirst(' ', 'T')) : null;
```

**控制器**：ChangeNotifier + notifyListeners；UI 用 ListenableBuilder；状态变更用「diff 检测」触发一次性副作用（如胜负弹窗、悔棋投票弹窗、超时 SnackBar），用 bool 字段防重复触发。

**落子反馈统一入口**（可被设置开关控制；测试涉及平台通道）：

```dart
class MoveFeedback {
  static void play() {
    if (SettingsService.sound) unawaited(SystemSound.play(SystemSoundType.click));
    if (SettingsService.haptic) unawaited(HapticFeedback.lightImpact());
  }
}
```

## 3. 联机后端模式（服务端唯一事实源）

### 核心思想

- 单行状态表 = 一局游戏（board 字符串、turn、status、winner、players jsonb 座位数组）；Realtime 广播整行 UPDATE，客户端收到即整行替换本地状态，天然支持中途重进拉全量。
- 回合串行 → 无并发写冲突；所有写操作走 SECURITY DEFINER RPC，在事务内做全部校验（回合/身份/格位/状态），失败 raise exception 由客户端提示。
- RLS 只开 SELECT：主表 `auth.uid() = any(member_ids)`；子表（聊天/落子历史）用 exists 子查询引用主表。
- 匿名登录（游客）：uid 持久化到本地用于重连；但**重装即换 uid** → 战绩类数据本机存，排行榜需先做登录体系。

### 必须遵守的规则

- RPC 新签名必须 `grant execute ... to authenticated;`（改签名 = 新函数）。
- 函数体 `create or replace` 可重复执行；变量不要与列名撞名（加 v_ 前缀防 ambiguous）。
- **Realtime 广播整行** → 行内绝不能放无限增长的大字段（如全量落子历史）；历史放子表且**不进 publication**，按需拉取。
- 心跳/掉线：`set_connected` 更新 last_seen（10s 心跳）；90s 无心跳 → 服务端 `take_over` 原子托管（校验 last_seen 与幂等），客户端可重连恢复。
- 回合计时：服务端 `move_deadline`（now()+限时）是唯一权威；客户端只做倒计时显示；超时后任何成员可触发 AI 代下（RPC 校验 deadline 已过）。
- 悔棋：落子历史表（moves）+ 发起者=最后落子者 + 其他真人全员同意 + 30s 过期 + 从历史重放重建棋盘；历史表同时服务复盘。
- 满盘判胜等规则要在**客户端纯函数与服务端 SQL 双实现并保持一致**，并各写单测。

## 4. 小步快跑工作流（每阶段/每里程碑）

### 节奏

1. 每阶段开始：先写 `docs/phase-N-<主题>.md`（目标/改动/边界与失败模式/验证清单/真机结果），回填前阶段文档保持完整。
2. 每里程碑：写代码 → `flutter analyze` + `flutter test` 全绿 → Supabase SQL Editor 按序执行新迁移 → 用户提交推送 → Actions 自动出 APK → 真机 2~3 台验证 → 更新文档验证结果 → `git tag vX.Y.Z` 自动发 Release（APK 附在 Release）。
3. 版本号与里程碑同步：1.0.0+1 → 1.1.0+2 → …（中间版本未发布也递增，最终版以当前为准）。
4. **阶段间等待**：前一阶段提交并真机验证完再写下一阶段代码，避免一个提交混两个阶段。

### 协作分工（DSH 沙箱环境）

- Agent 写全部代码与文档；**用户执行** `flutter analyze/test`、`flutter build`、`git commit/push`（沙箱禁 flutter/git 子进程）、Supabase SQL Editor 执行迁移。
- 大陆网络：GitHub HTTPS 被墙 → 用 SSH 推送（VS Code 或 git@github.com）。
- 每轮交付给用户的操作清单要按顺序编号，明确「先做哪步」。

## 5. 玩法机制模板（可直接套用）

| 机制 | 实现要点 |
|---|---|
| 三人回合 | 座位 0→1→2→0；players jsonb 数组存 {slot,name,is_ai,uid,connected,last_seen,taken_over} |
| AI | 客户端本地计算（房主代下），服务端零算力；难度参数化（easy 贪心 / medium 攻守 / hard 1.5 层前瞻） |
| AI 补位/托管 | 建房时空位填 AI；掉线 90s 转 AI(托管)（taken_over 标记，可重连夺回） |
| 超时 | move_deadline 服务端权威 + 客户端倒计时（≤10s 变红）；超时 AI 代下解锁 |
| 悔棋 | 历史表 + 全员同意 + 过期作废 + 重放重建 |
| 聊天 | messages 表 + RLS + Realtime insert 订阅 + 列表封顶 100 |
| 战绩 | 本机 SharedPreferences（对局/胜/和/胜率/连胜连负，负=对局-胜-和），每局记一次防重 |
| 满盘判胜 | 三方最长连子比较，唯一最大者胜，并列和棋 |
| 再来一局 | reset RPC：清棋盘/回合/胜负/历史/截止时间，不换座位 |

## 6. 坑清单（踩过，直接避开）

- **Postgres 时间戳** '2025-01-01 12:00:00+00' → replaceFirst(' ', 'T') 才能 parse。
- **PostgREST** 返回表行是数组 → data.first 再转模型。
- **plpgsql** 变量与列撞名 → column reference is ambiguous，变量加 v_ 前缀。
- **SQL 嵌套**：do $$ ... $$ 块内不能再写 $$（报 syntax error），内层改单引号字符串。
- **Supabase anon key** 新版 sb_publishable_ 前缀 → 客户端用 publishableKey: 参数（anonKey 已废弃告警）。
- **Realtime 载荷**：广播行变大（如塞历史数组）会撑爆消息限制 → 历史放子表不进 publication。
- **flutter analyze**：中文串插值不必要的花括号（'${name}'→'$name'）、if (x == null) { x = ... } 改 x ??= ...、删除平台调用后清理 unused_import。
- **flutter test**：任何触发平台通道的代码（SystemSound/HapticFeedback）所在测试文件必须 TestWidgetsFlutterBinding.ensureInitialized()。
- **困难 AI 卡 UI** → Isolate.run(() => bestMove(...)) 后台计算（要求 AI 是纯 Dart 无 Flutter 依赖）。
- **GitHub Actions Release**：工作流需 permissions: contents: write（否则 403）；Node20 弃用警告无害。
- **测试断言**：写本地悔棋等状态测试时，先把期望的回合/棋盘演变算清楚再写 expect。

## 7. 里程碑验收清单（模板）

- [ ] `flutter analyze` 0 告警、`flutter test` 全绿（含新增单测）
- [ ] Supabase 迁移按序执行（可重跑验证）
- [ ] 真机 2~3 台逐项验证（含断网/掉线/重连等异常路径）
- [ ] 版本号递增、tag 推送、Release 附 APK
- [ ] 阶段文档验证结果已更新

## 8. 常用命令速查

```powershell
flutter analyze        # 静态检查（0 告警目标）
flutter test           # 全部单测
git tag v1.0.0 && git push origin v1.0.0   # 发版（工作流自动建 Release）
```