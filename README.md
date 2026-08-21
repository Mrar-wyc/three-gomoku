# 三人五子棋

三人轮流在 19×19 棋盘落子，**先连成五子（横/竖/斜）者胜**、整局结束的联机小游戏。Android 端（Flutter 开发），通过 GitHub Actions 自动打包 APK。

## 功能

- 🎮 三人轮流落子，19×19 棋盘，黑/白/红三色
- 🌐 公网联机：房主建房生成 6 位房间号，另两人输入加入（游客制，无需注册）
- 🤖 AI 补位：房间空位可由 AI 顶替，人不够三人也能开局；掉线者由 AI 托管
- 📱 本地三人对局（热座 + 可选 AI），离线也能玩
- 📦 GitHub Actions 自动构建 release APK

## 技术栈

- Flutter（Dart）
- Supabase（Postgres + Realtime + 匿名登录）：房间状态、落子同步
- 五子棋 AI：启发式评分（攻守加权，三人局同时盯两个对手）

## 目录结构

~~~
lib/
├── main.dart / app.dart          # 入口与主题
├── core/
│   ├── game_logic.dart           # 规则：落子、五子判定（纯函数）
│   ├── ai.dart                   # 五子棋 AI
│   ├── constants.dart            # 颜色
│   └── app_config.dart           # Supabase 配置（需你填写）
├── models/                       # Player / Room
├── services/                     # Supabase 初始化 + 房间 RPC
├── state/                        # 本地对局控制器 / 联机房间控制器
└── ui/                           # 页面与棋盘控件
supabase/migrations/0001_init.sql # 建表 + RPC + RLS + Realtime
.github/workflows/build-apk.yml    # 自动打包
~~~

## 本地运行

~~~
flutter pub get
flutter run
~~~

> 本机只需装 Flutter SDK；APK 由 GitHub Actions 在云端构建，flutter doctor 里 Android 项报红可忽略。

## 配置 Supabase（联机功能）

1. 到 supabase.com 免费注册并新建项目。
2. 打开项目 SQL Editor，把 supabase/migrations/0001_init.sql 全文粘贴执行一次。
3. 打开 Authentication → Providers，启用 Anonymous sign-ins（匿名登录）。
4. 打开 Project Settings → API，复制 Project URL 和 publishable（anon）key。
5. 填入 lib/core/app_config.dart 的 supabaseUrl 与 supabaseAnonKey（该 key 是公开的，可安全内置）。

## 通过 GitHub 打包 APK

1. 推代码到 main 分支自动构建；也可在仓库 Actions 页手动运行（workflow_dispatch）。
2. 下载：Actions → 最近一次构建 → Artifacts → three-gomoku-apk。

### 发布新版本（打 tag）

1. 在 pubspec.yaml 里把 version 升一档（如 1.3.0+4）。
2. 提交推送后打 tag 并推送：

~~~
git tag v1.3.0
git push origin v1.3.0
~~~

3. Actions 构建完成后，APK 会自动附在该 tag 的 Release 里，朋友可直接下载安装。

### 签名说明

- 当前使用 debug 签名：CI 每次构建用同一 keystore、签名一致，新版本可直接覆盖安装旧版，无需卸载。
- 未来若要上架应用商店，需换正式 keystore（届时再配置，代码无需改动）。

安装 APK：把 APK 传到手机点击安装（需允许「未知来源」）。

## 规则说明

- 座位 0/1/2 依次为黑、白、红，按 0→1→2 循环落子。
- 任一玩家先连成五子即整局结束；棋盘下满无人连五判和。
- 房主固定为黑方；AI 依次顶替白方、红方。
