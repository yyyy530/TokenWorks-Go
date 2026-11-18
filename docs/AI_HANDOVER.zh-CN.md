# TokenWorks-Go AI 交接文档

> 交接时间：2026-11-18。本文以下一位 AI 可以直接开工为目标，优先记录已验证事实、未完成能力和操作边界。
> 开始工作前先读本文件、`README.md`、`docs/upstream-provenance.md`、`docs/roadmap.md` 与对应目录现有说明；不要仅依据聊天历史或文件名推断完成度。

## 1. 项目定位

用户确定的产品目标是 **完全类比**：

```text
DeepSeek Harness : dsh-Go = USTC TokenWorks : TokenWorks-Go
```

目标是 TokenWorks 的完整手机版，同时保留 dsh-Go 的移动体验、手机本机引擎、SSH 主机和 DSH Remote，而不是只做一个远程聊天窗口。

长期能力范围包括：

- TokenWorks：统一身份、学校模型和额度、标准/科研/教学/学习四模式、工作区、知识工作室、文献工具、Office/PDF、邮件助手、微信远程、语音/图像/CAD 等。
- dsh-Go：本机 PRoot 引擎、远程主机、流式会话、审批与提问、文件与终端、插件、手机操控、自动化、桌宠/伙伴等。
- 目前这些目标多数尚未实现，详见第 4 节。

## 2. 仓库与当前基线

- GitHub：https://github.com/yyyy530/TokenWorks-Go
- 默认分支：`main`
- 本地路径（原开发机）：`E:\ai闲聊\TokenWorks-Go`
- 交接时 HEAD：`fe3abb31ccd5dc652a0c6f177fd47caa7d4d6b35`
- 历史提交：
  - `ba85edd`：初始骨架、核心包、复用包与测试。
  - `fe3abb3`：注释清理、失实说明修正、心跳测试夹具竞态修复。
- 交接时工作区干净，未发现待推送提交。
- Git 身份：`yyyy530 <292983627+yyyy530@users.noreply.github.com>`，仅为本仓库配置。

开始工作：

```bash
git clone https://github.com/yyyy530/TokenWorks-Go.git
cd TokenWorks-Go
git status --short
git log --oneline -3
```

若本地已有仓库，先 `git status --short` 检查用户改动，再同步远程；不要直接 reset、clean、强推或删除文件。

## 3. 当前真实完成度

### 3.1 已有可测试代码

| 模块 | 现状 | 验证情况 |
|---|---|---|
| `packages/tokenworks_core/` | 原创纯 Dart 领域模型、接口、OIDC/PKCE 辅助、会话启动策略、策略装饰器 | 静态分析通过，18 项测试通过 |
| `packages/dsh_client/` | 从 dsh-Go 复制的纯 Dart DSH 客户端及完整测试 | 静态分析通过，908 项通过、32 项跳过 |
| `packages/dsh_remote/` | 从 dsh-Go 复制的远程传输包及测试 | 静态分析通过，499 项通过、4 项跳过 |
| `app/` | Flutter Material 3 首页演示骨架 | 静态分析通过，4 项 widget 测试通过 |
| `docs/` | 目标架构、路线图、质量门禁、上游溯源 | 文档；部分描述是规划而非现状 |

上述数字是交接前本机最后一次实际运行结果。它们只覆盖单元/widget/协议测试，不代表真机、桌面 TokenWorks 或学校账号端到端验证。接手后应重新运行；如果结果不同，以新的实际输出为准。

### 3.2 核心层实际做什么

`packages/tokenworks_core/lib/src/`：

- `models.dart`：四种模式 ID（`tw-standard`、`tw-research`、`tw-teach`、`tw-study`）、学校模型、额度窗口、主机、会话摘要、账户快照及校验。
- `oidc.dart`：PKCE S256 生成、回调 `state` 校验和授权码解析。没有学校 issuer/client 注册信息，也没有完成真实浏览器登录。
- `ports.dart`：身份、凭据存储、账户目录和工作区的抽象接口。
- `validation.dart`：创建会话时校验工作区、模型归属、本机网络条件及完全权限确认。
- `adapters.dart`：`PolicyEnforcingWorkspaceAdapter` 在创建会话前应用策略；`TokenWorksHostAdapter` 是显式未实现的占位边界。
- 测试中的 `RecordingGateway` 是内存测试替身，不是网络实现。

重要语义：创建会话必须传入用户选择的 `SchoolModel`；不能再用 Host ID 猜模型，也不能静默回退到第一个模型。

### 3.3 App 实际做什么

`app/lib/main.dart` 目前提供：

- 账户/额度演示卡片。
- 四模式选择器和本地状态切换。
- 一个输入框、进行中会话列表和侧栏。
- `WorkspaceHomeState.activeMode` 供 widget 测试验证选择状态。

`app/lib/src/demo_data.dart` 中账户、额度、模型、会话全部是演示数据。以下按钮多为空实现或仅有静态入口：

- 开始任务、添加附件、主机与连接。
- 会话详情、插件与技能、自动化任务、设置。

**不要把这些 UI 文案当成已经接通的后端能力。**

### 3.4 明确未完成

| 能力 | 当前事实 |
|---|---|
| Android 可安装包 | `app/` 没有 `android/` 平台工程，未生成或验证 APK |
| Flutter 真机运行 | 没有 Android SDK/JDK/真机验证；当前完成的是 Flutter 测试 |
| 真实统一身份登录 | 未接学校服务，无移动端 OIDC 客户端注册 |
| 真实学校模型/额度 | 未接配置下发；动态 JSON 解析只是自定义模型边界 |
| 桌面 TokenWorks 连接 | 未实现，无配对、添加主机或 TokenWorks 能力协商流程 |
| 真实聊天/审批/文件链路 | 有底层客户端包，未接 App 状态与 UI |
| 本机引擎 | 没有 `runtime/`、PRoot、Node、Kotlin 宿主或桥插件 |
| SSH 完整链路 | 没有引入 `packages/dartssh2`，也没有 App SSH 管理实现 |
| DSH Remote 产品化 | 有底层包，无配对 UI、凭据存储或端到端测试 |
| 邮件助手 | 未实现 |
| 糯籽及其他宠物 | 未实现；测试 fixture 不是宠物功能 |
| 微信绑定和派活 | 未实现 |
| 知识工作室、文献工具 | 未实现 |
| Office/PDF/CAD、图像生成/修改 | 未实现 |
| 语音/视频、自动化、手机操控 | 未实现 |
| 插件、技能、MCP | 无真实管理页面；MCP 不能当作已公开稳定接口 |

另外，`TokenWorksHostAdapter` 内部部分方法抛 `UnimplementedError`，watch/list 抛 `IntegrationException`。这不是生产实现，应替换为真实适配器或清晰的不可用能力声明。

## 4. 技术底座与依赖解析

### 4.1 包关系

```text
pubspec.yaml（Pub workspace）
├── app/（resolution: workspace）
└── packages/tokenworks_core/（resolution: workspace）

app 通过 path 依赖：
├── packages/tokenworks_core
├── packages/dsh_client（独立包，不属于 workspace）
└── packages/dsh_remote（独立包，不属于 workspace）
    └── packages/dsh_client（path 依赖）
```

`dsh_client`、`dsh_remote` **不要加入根 workspace，也不要添加 `resolution: workspace`**。它们按上游独立包维护，各自 `pub get`、静态分析和测试。曾加入 workspace 后，Flutter 分析上下文使客户端的 `dart:mirrors` 测试无法解析。

根 `pubspec.lock` 被 `.gitignore` 排除，但当前已被 Git 跟踪，修改忽略规则前要决定是否继续跟踪该文件。两个独立客户端包有自己的 lockfile。

### 4.2 开发工具链

已使用版本：Flutter 3.47.7 / Dart 3.13.5。

原开发机的隔离工具链：

- `E:\tokenworks-tooling\flutter-sdk\flutter\`
- `E:\tokenworks-tooling\pub-cache\`
- `E:\tokenworks-tooling\home\`
- `E:\tokenworks-tooling\temp\`

这些工具目录不在 GitHub 仓库中，也不是项目运行时依赖。换机器时可使用自己的标准 Flutter 安装。

原开发机将 `HOME`、`USERPROFILE`、`APPDATA`、`TEMP`、`TMP`、`PUB_CACHE` 指向上述隔离目录，用于避开原 Windows 用户目录写入问题。不要在新环境机械照抄这些路径。

上游 dsh-Go 的 PRoot/Android runtime 构建目标是 **Linux x86_64、JDK 17、Flutter 3.47.7、Android SDK/NDK**。当前 Windows Flutter 工具链只跑过 Dart/Flutter 测试，不能据此推断 APK 可构建。

## 5. 标准验证命令

标准 Flutter 安装环境下，从仓库根执行：

```bash
flutter pub get

(cd packages/tokenworks_core && dart analyze && dart test)
(cd packages/dsh_client && dart pub get && dart analyze && dart test)
(cd packages/dsh_remote && dart pub get && dart analyze && dart test)
(cd app && flutter analyze && flutter test)
```

PowerShell 不适合直接照抄上面的 `(cd ... && ...)` 子 shell 写法，应分别进入目录运行，并检查 `$LASTEXITCODE`。不要在长管道里只看最后几行就宣称成功；测试命令的失败退出码需要保留。

原开发机已知环境问题：

- 原 Windows 用户目录无法创建 Pub/analytics/temp 文件，因此使用隔离 HOME 和 Pub cache。
- `flutter analyze` 在包含中文的绝对路径上发生过 LSP 崩溃。临时将**完整仓库**复制到 `E:\tokenworks-tooling\` 下的 ASCII 路径进行分析，测试在原目录运行。
- 这种分析副本只是规避本机工具问题，不能替代真实跨平台 CI。

原开发机的 PowerShell 验证方式如下；它只设置当前进程环境，不修改系统环境。`$repo` 是仓库路径，`$tooling` 是隔离工具目录：

```powershell
$repo = 'E:\ai闲聊\TokenWorks-Go'
$tooling = 'E:\tokenworks-tooling'
$dart = "$tooling\flutter-sdk\flutter\bin\cache\dart-sdk\bin\dart.exe"
$flutter = "$tooling\flutter-sdk\flutter\bin\flutter.bat"
$env:HOME = "$tooling\home"
$env:USERPROFILE = "$tooling\home"
$env:APPDATA = "$tooling\home\AppData\Roaming"
$env:TEMP = "$tooling\temp"
$env:TMP = "$tooling\temp"
$env:PUB_CACHE = "$tooling\pub-cache"

Set-Location "$repo\packages\tokenworks_core"
& $dart analyze; if ($LASTEXITCODE -ne 0) { throw 'core analyze failed' }
& $dart test; if ($LASTEXITCODE -ne 0) { throw 'core test failed' }

Set-Location "$repo\packages\dsh_client"
& $dart pub get
& $dart analyze; if ($LASTEXITCODE -ne 0) { throw 'client analyze failed' }
& $dart test; if ($LASTEXITCODE -ne 0) { throw 'client test failed' }

Set-Location "$repo\packages\dsh_remote"
& $dart pub get
& $dart analyze; if ($LASTEXITCODE -ne 0) { throw 'remote analyze failed' }
& $dart test; if ($LASTEXITCODE -ne 0) { throw 'remote test failed' }

Set-Location "$repo\app"
& $flutter pub get
& $flutter test; if ($LASTEXITCODE -ne 0) { throw 'app test failed' }
```

若中文路径使 `flutter analyze` 崩溃，在确认目标目录为专用临时副本后执行：

```powershell
$review = "$tooling\twg-analyze"
if (Test-Path $review) { Remove-Item -Recurse -Force -LiteralPath $review }
Copy-Item -Recurse -Force $repo $review
Set-Location "$review\app"
& $flutter analyze
```

删除临时副本前先 `Resolve-Path` 检查目标，不能对仓库根目录执行该删除命令。

每次报告验证时，注明：实际运行的命令、通过/失败/跳过数、平台、未运行项。不要把测试通过写成 APK、真机或真实账号通过。

## 6. 上游来源与许可

### 6.1 已复用的真实代码

上游：`ccch1mneyyy/dsh-Go`，锁定提交：

```text
de8979d89d2205fc8872871e54904ddcda891b87
```

- `packages/dsh_client/`
- `packages/dsh_remote/`
- `packages/dsh_client/test/fixtures/companion/` 下三个测试门面，来自上游 `app/lib/companion/`。
- `LICENSE.upstream-dsh-go`：上游 AGPL-3.0 全文。
- `packages/dsh_remote/LICENSE-ds-harness-remote`：相关 MIT 许可。

详细本地适配和 fixture 修复见 `docs/upstream-provenance.md`，每次继续修改复用包都要同步更新。

### 6.2 尚未复用的关键代码

完整 dsh-Go 上游稀疏副本在原开发机 `E:\ai闲聊\.upstream-dsh-go`，文档副本在 `E:\ai闲聊\dsh-go-docs`。它们不属于 TokenWorks-Go 仓库。

计划复用但当前没有复制的包括：

- `app/` 的 Flutter 会话、设置、主机、插件等主体实现。
- Android/iOS/OHOS 宿主。
- `runtime/`、PRoot、桥插件及构建链。
- `packages/dartssh2/`。
- `sdk/`、`examples/` 及插件能力。

因此不能把 README 中的 `runtime/` 树或 `docs/architecture.md` 的整体图当作现有代码地图。

### 6.3 品牌与许可边界

- 保留上游署名与许可；发布修改版时履行 AGPL-3.0 对应源码义务。
- README 声明 `tokenworks_core` 为原创 MIT，但交接时未发现该包单独的 MIT `LICENSE` 文件；需要统一声明和实际许可文件，不能仅凭文字假定已经妥善处理。
- DSH Go 名称、logo、Deepy、鲸娘和展示素材不在自动复用授权范围内。
- TokenWorks/USTC 名称、校徽、糯籽形象、统一身份客户端注册需要单独确认。
- **糯籽不是 dsh-Go companion 包附带的功能或素材。** companion fixture 不能当作宠物实现，也不能据此使用 TokenWorks 专属形象。
- 桌宠可先开发自有、授权清晰的通用伙伴机制，专属形象等待授权。

## 7. TokenWorks 集成事实与未知项

参考公开资料：

- 教程：https://id.ustc.edu.cn/tokenworks/guide/
- 发布说明：https://id.ustc.edu.cn/tokenworks/releases/
- 源码入口：https://git.ustc.edu.cn/wangfeng/tokenworks （需要学校统一身份权限）

已核实的公开行为：

- TokenWorks 0.2.201 起基于 DeepSeek Harness 官方桌面；0.2.204 文档记录底座为 0.2.2-rc.3。
- 首次启动获取并校验学校配置；系统浏览器完成统一身份登录后，动态获得学校模型配置。
- 学校模型网关限制校园网 IP；校外通常需要 iWAN。远程桌面模式应让桌面继续负责学校认证和模型调用。
- 模型、能力、额度窗口和限速动态下发，不能硬编码模型目录或固定每日额度。
- 四模式公开历史 ID 与当前核心模型一致，但公开资料未完整描述新版专属工具/prompt 差异，不能自行编造。
- 邮件、微信、文献、桌宠等以插件形式提供；当前公开教程没有稳定的第三方插件 API 承诺。

不能凭空确定的契约：

- TokenWorks 专属 OIDC authorize/token/profile、client_id、redirect_uri、scope、token 刷新报文。
- 学校模型网关 base URL、鉴权 header、聊天协议、额度/限速 schema。
- 签名配置 URL/schema、插件 SDK/manifest、微信插件协议、更新 feed。
- dsh-Go 的 `/dsh-go/v1/*` 不是 TokenWorks 官方 API；可作为桌面桥扩展的参考，不能宣称为学校接口。

学校通用 OIDC 文档中的 `/cas/oidc/*` 不能直接冒充 TokenWorks 应用端点；公开版本说明中的 `/oidc` 应用入口也不是完整第三方客户端契约。

## 8. 下一步实施顺序

优先做一条真实可用的远程会话垂直链路，再扩展功能，不要同时铺邮件、宠物、CAD 等空页面。

### P0：可构建与协议事实

1. 在干净环境复现四套件测试；补 CI（核心 Dart、客户端、Flutter）。
2. 用 `flutter create --platforms=android .` 等方式补齐 App Android 工程，保留现有 `lib/` 和测试；确认包名、最低 SDK、网络权限与 Java/Gradle 配置。
3. 修正 README：区分当前可运行测试与尚未存在的 APK/真实连接步骤。
4. 获取并阅读实际 TokenWorks 桌面集成方式：优先学校源码/合作方契约，其次在用户明确授权的自有桌面环境中观察可复用插件边界。
5. 确定桌面桥归属：复用 dsh-Go 桥需要实际安装相应 Host 插件；不能假设官方 TokenWorks 已带 `/dsh-go/v1`。

### P1：手机到桌面的真实会话

1. 选定首条连接路径：优先评估 HTTP/HTTPS 或 SSH 到用户自己的 DSH/TokenWorks 主机。
2. 用 `DshClient` 实现 `WorkspaceGateway`：连接、列表、创建、发送、中断、审批，不另写平行聊天协议。
3. 引入安全凭据存储和 Host 隔离；令牌不进日志、诊断包、Git 或 UI。
4. 接会话页面：流式回复、工具卡、审批/提问、停止、重连恢复。
5. 账户页展示桌面身份和模型/额度；没有能力时显示 `unknown/unsupported`，不能用演示数据伪装真实状态。
6. 真机验证后才更新 README 为“支持”。

### P2：TokenWorks 专属能力

按真实桌面插件能力逐项接入：四模式、知识工作室、文献、Office/PDF、邮件、微信、图像、CAD。每项都需要：

- 明确桌面端实现和权限模型。
- 定义 adapter/capability，而非在手机另造学校私有 API。
- 危险操作继续由用户确认，尤其发邮件、完全权限、改图等。
- 增加契约测试和至少一次真实主机验收。

### P3：本机引擎与移动端深度

- 在 Linux 构建环境引入上游 runtime、Android 宿主、构建与升级测试。
- 保留 Host 隔离、引擎升级恢复、文件与审批链。
- 再做手机操控、自动化、语音、通用伙伴/桌宠。
- iOS/OHOS 不应从 Android PRoot 假设直接复制。

## 9. 工程约束与常见坑

- 不要为追求“功能齐全”一次性复制上游所有资源；先确定需要的最小依赖闭包，再逐步适配。
- 上游复用代码尽量保持可对比；确需修改时记录原因、影响和验证，不批量重写注释或许可头。
- 之前已修复 `PolicyEnforcingWorkspaceAdapter` 的模型错配、`OidcCallback` 的 state 校验顺序、完全权限确认参数，不能回退。
- `LaunchPolicy.fullAccessConfirmed` 只是调用方传入的确认信号；真实 UI 必须显示明确确认流程，不能默认设 `true`。
- `AccountSnapshot.fromJson` 是本项目的适配边界，不是已证实的学校 schema。接真实服务时按实际响应建 mapper，未知字段向前兼容。
- 当前没有 Riverpod 实现，架构文档中的 Riverpod/state 名是目标设计；如果引入，保持连接/会话状态单 owner。
- 测试中的 fake Host/RecordingGateway 只能证明局部行为，不能替代真实 TokenWorks。
- 上游测试曾在 Windows 并发运行中出现 WebSocket 已关闭仍写入的问题；现有修复见 `dsh_go_heartbeat_test.dart` 与 `fake_remote.dart`。若再次出现，先保留完整失败输出，别直接重跑后宣称 flake 消失。
- 不要把“演示”“占位”“规划中”的注释或 UI 当成不必要内容全部删除；它们用于避免误报能力。应删除的是失实声明，而非诚实的未完成标记。

## 10. 凭据与安全操作

- 不在仓库、文档、测试 fixture、命令输出、截图或日志中写入真实 API Key、PAT、OIDC token、SSH 私钥、用户会话。
- Git 的 `origin` 是干净 HTTPS URL，不含 token。历史推送曾用一次性认证 URL；不要把它保存进 remote 或脚本。
- 用户曾提供一个 GitHub PAT 用于推送；**本文不记录该 token**。不要从聊天记录复制到任何文件；需要推送时由用户重新提供有效授权，推送后提醒吊销/轮换。
- 提交前用实际 diff 检查秘密；排除 `.credentials.yaml`、`.env`、`key.properties`、签名文件、个人模型配置和真实对话。
- 未经用户明确要求，不提交、不推送、不创建远程仓库、不改分支保护、不强推。
- 不读取与项目无关的个人目录或凭据存储。

## 11. 接手后的首轮建议交付

```text
[ ] 重新克隆并运行四套件门禁，记录真实结果。
[ ] 修正 README 中“flutter run”“连接真实 TokenWorks”“runtime/”等超前描述。
[ ] 补 Android 平台工程并至少构建 debug APK，记录 SDK/JDK/设备环境。
[ ] 用实际 DSH/TokenWorks 桌面证据确定连接契约，写一份最小 adapter 设计。
[ ] 实现一个真实 Host 的只读连接 + 会话列表，凭据入安全存储。
[ ] 再做创建会话、流式发送、审批和恢复；每步补测试。
[ ] 更新 README、功能矩阵、上游修改记录和验证结果。
```

推荐第一轮验收目标：**用户在 Android 上添加自己的桌面主机，看到真实账户/会话列表，并完成一轮流式对话与审批。** 这不是当前仓库已经具备的能力。

## 12. 给下一位 AI 的简短工作指令

> 你先接手的是“有良好测试基础的早期骨架”，不是完整 TokenWorks 手机版。先验证现状、修正文档，再打通一条真实远程会话链。邮件、糯籽、微信、知识工作室等都尚未实现；不要把 companion fixture 或演示 UI 当成功能。学校私有契约未公开的部分必须基于真实源码/运行时证据或学校合作确认，不能猜。保留上游 AGPL 署名和修改记录，不使用未授权品牌素材。所有完成声明都要带实际测试或真机证据。
