# Phase 1 · 本地对局

> 版本：初版（里程碑 M1–M6 合并交付）· 状态：已完成

## 目标
可安装可玩的「三人五子棋」最小闭环：本地三人轮流落子 + 可选 AI 补位，规则正确、界面可看、AI 可战。

## 交付内容
- Flutter 工程（package `three_gomoku`，Android applicationId `com.threegomoku.three_gomoku`）。
- 19×19 棋盘，黑/白/红三色（`lib/core/constants.dart` 的 `GomokuPalette`）。
- 纯逻辑层 `lib/core/game_logic.dart`：落子合法性、五子判定、满盘和棋（纯函数，可单测）。
- 本地 AI `lib/core/ai.dart`：启发式评分（连五/活四/冲四/活三…加权），三人局防守取两个对手威胁最大值，候选点裁剪（曼哈顿距离 ≤2）。
- 页面：主菜单 / 本地对局（热座 + 0–2 个 AI）。
- 测试 `test/game_logic_test.dart`：规则、AI 立即取胜、中等挡杀等。

## 关键决策
- 棋盘用长度 361 的字符串（服务端） / int 列表（客户端）表示，索引 `row*19+col`。
- 回合固定 slot 0 → 1 → 2 → 0。
- 和棋规则（当时）：满盘无人连五 → 和棋（Phase 3 改为按最长连子判胜）。

## 验证
- `flutter analyze` 零告警、`flutter test` 全绿。
- 真机可玩，AI 能在秒级内落子。
