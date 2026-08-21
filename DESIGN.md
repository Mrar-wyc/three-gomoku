# 三人五子棋 —— 技术设计文档

> 版本 v0.1 · 状态：待评审 · 目标平台：Android（Flutter）· 联机：Supabase 免费云（MVP）

## 1. 概述

三人轮流在 19×19 棋盘落子，先连成五子（横/竖/斜）者胜、整局结束。公网联机，房主建房生成 6 位房间号，其余两人输入加入；房间空位可由 AI 顶替；掉线者由 AI 托管或判负。游客制，无需注册登录。

## 2. 技术选型

| 层 | 选择 | 理由 |
|---|---|---|
| 客户端 | Flutter (stable) | 跨平台、打包 APK 成熟 |
| 状态管理 | provider (ChangeNotifier) | 小游戏够用，易读易维护 |
| 后端 | Supabase（Postgres + Realtime + 匿名登录） | 免费额度、免自建、Realtime 同步落子；架构预留切换自建 |
| 打包 | GitHub Actions | push/tag 自动构建 release APK |
| AI | 本地启发式评分（客户端内运行） | 无需服务端算力 |

## 3. 项目目录结构

```
three-gomoku/
├── android/                        # Android 工程（签名配置）
├── lib/
│   ├── main.dart
│   ├── app.dart                    # MaterialApp、主题、路由
│   ├── core/
│   │   ├── app_config.dart         # Supabase URL / anon key（公开，可内置）
│   │   ├── constants.dart          # 颜色、棋盘尺寸、房间号格式
│   │   ├── game_logic.dart         # 纯逻辑：落子合法性、五子判定、回合推进
│   │   └── ai.dart                 # 五子棋 AI（评分 + 一步前瞻）
│   ├── models/
│   │   ├── player.dart             # 座位/玩家（含 is_ai、connected）
│   │   ├── room.dart               # 房间状态模型（与后端字段一一对应）
│   │   └── game_state.dart         # 单局对局状态
│   ├── services/
│   │   ├── supabase_service.dart   # 客户端初始化、匿名登录
│   │   └── room_service.dart       # 房间 RPC 调用 + Realtime 订阅
│   ├── state/
│   │   ├── app_controller.dart     # 全局（登录态、当前房间）
│   │   └── game_controller.dart    # 对局状态（棋盘、回合、胜负）
│   └── ui/
│       ├── screens/
│       │   ├── home_screen.dart        # 主菜单：创建 / 加入 / 本地练习
│       │   ├── create_room_screen.dart # 建房：选空位填 AI 或留空
│       │   ├── join_room_screen.dart   # 输入房间号加入
│       │   ├── lobby_screen.dart       # 等待大厅：显示座位、开始条件
│       │   └── game_screen.dart        # 对局棋盘
│       └── widgets/
│           ├── board_widget.dart       # 棋盘绘制 + 点击落子
│           ├── stone_painter.dart      # CustomPainter 画棋子/星位
│           └── player_bar.dart         # 顶栏：三色、当前回合、状态
├── supabase/
│   └── migrations/0001_init.sql    # 建表 + RPC + RLS（可一键执行）
├── .github/workflows/build-apk.yml # 自动打包
├── pubspec.yaml
└── README.md
```

## 4. 核心游戏规则（lib/core/game_logic.dart，纯函数、可离线测试）

- 棋盘：19×19，用长度 361 的字符串/列表表示，0=空，1/2/3=三位玩家。
- 落子合法性：坐标在界内、格为空、且轮到该座位。
- 回合顺序：slot 0 → 1 → 2 → 0 …（按加入顺序固定）。
- 胜负判定：以落子点为中心，沿 4 条轴（横、竖、主斜、副斜）双向计数，同色连续 ≥5 即胜。
- 和棋：棋盘下满（361 子）无人连五 → 判和。
- 颜色：黑 / 白 / 红，三种在 19×19 上辨识度最高。

## 5. 数据模型（Supabase / Postgres）

单行表示一局，**服务端为唯一事实源**，客户端通过 Realtime 订阅该行变化。

```sql
create table public.rooms (
  id         uuid primary key default gen_random_uuid(),
  code       text unique not null,             -- 6 位大写房间号
  host_id    uuid not null,                    -- 房主 uid
  member_ids uuid[] not null default '{}',     -- 用于 RLS 成员判断
  players    jsonb not null default '[]',      -- [{slot,name,is_ai,uid,connected}]
  board      text  not null default repeat('0',361), -- 361 字符，row*19+col
  turn       int   not null default 0,         -- 当前回合座位 0/1/2
  status     text  not null default 'waiting', -- waiting | playing | finished
  winner     int,                              -- 胜者 slot；null=未定或和棋
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

> 说明：三人小游戏落子事件量小，把完整棋盘状态存单行 + Realtime 广播整行更新，天然支持「中途重进房间拉取全量状态」，比 append-only 事件流更简单。回合天然串行（只有当前回合者能落子），不存在并发写冲突。

## 6. 服务端逻辑：RPC + RLS + Realtime

所有写操作走 **SECURITY DEFINER 的 RPC 函数**，在事务内校验并更新，规避竞态与越权：

- `create_room(player_name, seats)` → 生成唯一 6 位 code，返回房间。
- `join_room(code, player_name)` → 有空位则占座，返回房间；满则报错。
- `submit_move(room_id, slot, row, col)` → 核心落子：
  1. 校验 status=playing 且 turn=slot；
  2. 校验调用者 uid 是 host 或该座位本人（AI 座位仅 host 可代下）；
  3. 校验格为空 → 写 board、推进 turn、判定胜负、更新 status/winner；
  4. 返回最新房间行（落子者即时拿到，其余人靠 Realtime）。
- `leave_room(room_id)` → 移除/标记掉线，空位改为 AI 托管或判负。
- `set_connected(room_id, connected)` → 心跳/重连更新 connected 标志。

**RLS**：客户端用 **Supabase 匿名登录**（`signInAnonymously`）获得 uid；`rooms` 表 SELECT 策略为 `auth.uid() = any(member_ids)`，保证只能读到/订阅到自己所在房间；写操作一律经 RPC（definer 权限）。

**Realtime**：每房间一个 channel，订阅 `postgres_changes`（`rooms` 过滤 `id=eq.<room_id>`）。客户端收到 UPDATE 即用服务端行整体替换本地状态，避免状态分叉。

## 7. 客户端架构与通信时序

```
[启动] signInAnonymously → 持久化 uid（本地 SharedPreferences 缓存）
[建房] create_room → 进入 Lobby（订阅 Realtime）→ 满 3 座且含真人即开局
[加入] 输入 code → join_room → 进入 Lobby
[落子] 点击棋盘 → submit_move → 立即应用返回行 + Realtime 广播给他人
[AI 回合] 房主客户端本地算 AI 落点 → submit_move 代下
[掉线] set_connected(false) → 房主判其 AI 托管（或判负）→ 继续对局
```

## 8. AI 算法（lib/core/ai.dart）

- **评分法**：对每个候选空位，计算「我方落子得分」与「两个对手的最大威胁分」，总分 = 攻 × w1 + 守 × w2。四方向统计连子形态：连五/活四/冲四/活三/眠三/活二，加权求和。
- **三人局关键差异**：同时盯两个对手——防守项取两个对手威胁的 **最大值**，而不是像双人局只盯一个。
- **候选点裁剪**：只搜索「已有棋子曼哈顿距离 ≤2 的格子」（约几十~百个），19×19 全盘评分也毫秒级。
- **难度**：MVP 做「中等」（攻守加权 + 一步前瞻）；预留「简单（纯贪心）」。
- AI 在**房主客户端本地运行**（不占服务端算力），房主代 AI 座位调用 submit_move。

## 9. 边界情况

| 场景 | 处理 |
|---|---|
| 房主掉线 | 其座位 AI 托管；全员掉线则房间保留，超时清理（可选定时函数） |
| 普通成员掉线 | 由房主决定：AI 托管 或 判负（MVP 默认 AI 托管） |
| 并发落子 | RPC 事务内 turn 校验，非当前回合直接拒绝 |
| 重复加入/重连 | 同 uid 再 join 只更新 connected，不新增座位 |
| 房间号冲突 | 生成后查重，冲突重试 |
| 满 361 无人连五 | status=finished，winner=null（和棋） |
| 中途退出再进 | 按 code 重拉全量 room 行，恢复棋盘 |

## 10. GitHub Actions 打包（.github/workflows/build-apk.yml）

- 触发：push 到 main、tag `v*`、手动 `workflow_dispatch`。
- 步骤：checkout → `subosito/flutter-action@v2`（stable）→ `flutter pub get` → `flutter build apk --release` → 上传 artifact；打 tag 时创建/附加 Release。
- 签名：默认用 debug 签名即可侧载安装（朋友间安装够用）；后续要上架再加正式 keystore。
- Supabase URL / anon key 属于公开配置，直接内置进 `app_config.dart`，无需 Secrets。

## 11. 里程碑

1. **M1 脚手架**：工程、依赖、目录、App 主题与路由。
2. **M2 规则 + 棋盘 UI**：本地三人热座可玩，五子判定 + 和棋 + 胜负提示。
3. **M3 AI**：本地可「人 vs 2 AI」，验证评分与攻守。
4. **M4 Supabase 联机**：建房/加入/Realtime 同步/断线。
5. **M5 AI 补位接入联机**：空位托管 + 掉线接管。
6. **M6 打包发布**：GitHub Actions 出 APK，README 写安装说明。

## 12. 需要你后续提供的配置（到对应步骤再要）

- GitHub 仓库（我来指导创建，Actions 需代码推到该仓库）。
- Supabase 免费项目：URL + anon key（需在 Auth 里开启「匿名登录」，我会给步骤）。
