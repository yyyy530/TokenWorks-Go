# TokenWorks-Go

> **致谢与出处**：本项目借鉴并复用了 **[ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go)**（作者：ccch1mneyyy，AGPL-3.0）的移动架构与核心包（`dsh_client`、`dsh_remote`），以及 **[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)** 的 Agent 引擎理念。在此向原作者致谢。详细溯源与本地修改见 [docs/upstream-provenance.md](docs/upstream-provenance.md)。

词元工坊（USTC TokenWorks）的完整手机版 —— 正如 dsh-Go 是 DeepSeek Harness 的手机版，TokenWorks-Go 把词元工坊的统一身份、学校模型与额度、四种模式、专属工作流装进 Android 手机，同时保留 dsh-Go 的本机运行与远程连接双模式。

## 状态

**M1 开发中** —— 当前为可运行的 Flutter 骨架 + 纯 Dart 领域层，尚未接入真实学校服务。

## 快速开始

### 前提

- Flutter 3.47.7+（Dart 3.13.5+）
- Android SDK（arm64 / x64）
- 或：仅做核心层验证时只需 Dart SDK

### 运行核心测试

```bash
cd packages/tokenworks_core
dart pub get
dart analyze
dart test
```

### 运行 App

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

### 连接真实 TokenWorks

1. 确保 TokenWorks 桌面端已登录且在校内网络
2. TokenWorks-Go 中选择「连接电脑」→ 扫码配对或 SSH
3. 统一身份认证登录（系统浏览器）
4. 模型与额度自动下发，选择模式开始对话

## 架构

```
TokenWorks-Go App (Flutter)
├── packages/tokenworks_core    纯 Dart 领域层（模型/额度/身份/工作区端口）
├── app/                        Flutter 移动应用
├── packages/dsh_client         DSH Web API 客户端（复用 dsh-Go）
├── packages/dsh_remote         远程传输（复用 dsh-Go）
└── runtime/                    Android PRoot 引擎（复用 dsh-Go）
```

详见 [docs/architecture.md](docs/architecture.md)。

## 与上游的关系

- 基于 [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go)（AGPL-3.0）的移动架构
- 基于 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 Agent 引擎
- TokenWorks 专属层为原创实现，与 dsh-Go 无代码重叠

## 许可

- 主体代码：AGPL-3.0（继承自 dsh-Go）
- `packages/tokenworks_core`：MIT（原创）
- 第三方组件各自许可，见 `THIRD_PARTY_NOTICES.md`（待生成）

DSH Go 名称、标识、Deepy、鲸娘形象不在本仓库授权范围内。TokenWorks 名称、USTC 校徽、糯籽形象需另行确认。

## 贡献

当前阶段优先修复 M1 阻塞项，暂不接受功能扩展 PR。问题反馈请开 Issue。
