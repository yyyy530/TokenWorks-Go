# TokenWorks-Go AI 交接文档

> 交接时间：2026-11-19。本文替代 2026-11-18 版本，以下一位 AI 可以直接开工为目标。
> 开始工作前先读本文、`README.md`、`docs/roadmap.md`、`docs/quality.md` 和 `docs/upstream-provenance.md`。不要把聊天摘要、界面文案或规划文档当作完成度证据。

## 1. 项目定位

产品目标仍是 **完全类比**：

```text
DeepSeek Harness : dsh-Go = USTC TokenWorks : TokenWorks-Go
```

目标是 TokenWorks 的完整手机版，同时保留 dsh-Go 的本机引擎、SSH、DSH Remote、移动会话和插件能力，而不是只做一个远程聊天窗口。

本轮用户明确授权并完成的是：**多主机、SSH、DSH Remote 配对、自动化任务、插件市场、语音通话**。iOS / 鸿蒙本轮明确不做。

## 2. 仓库与精确 Git 状态

- GitHub：https://github.com/yyyy530/TokenWorks-Go
- 默认分支：`main`
- 本地路径：`E:\ai闲聊\05_项目\TokenWorks-Go`（2026-11-19 从原工作区根目录归入）
- 本地 HEAD：`4916b40 Add on-device runtime and mobile feature suite`
- `origin/main`：`4916b401fb4795441fb23ad82237f1b65242dbf5`（2026-11-20 已核对）
- 三个优化提交均已推送到远端；本文件提交前的唯一本地修改是更新本交接文档：

| 提交 | 内容 |
|---|---|
| `ba85edd` | 初始骨架、核心包、复用包与测试 |
| `fe3abb3` | 注释清理与心跳 fixture 修复 |
| `c1feccc` | Android 工作区和 USTC 校园接入，已在远端 |
| `92935d0` | GitHub Actions 验证，已在远端 |
| `4916b40` | 本机运行时和本轮六项移动端功能，已在远端 |

### 已解决的推送阻断

2026-11-19 曾因 PAT 缺少 `workflow` 权限而无法推送 `92935d0`。2026-11-20 已确认远端 `main` 与本地均为 `4916b40`，该问题已经解决。

本次上传前通过 `git ls-remote origin refs/heads/main` 和 `git fetch origin main` 双重核对。保留历史时，不 rebase、不删除 CI 提交、不强推。

## 3. 当前真实完成度

### 3.1 已具备的通用能力

- HTTPS DSH 主机连接、模型选择、新建会话、流式回复、停止、审批、提问、历史翻页、断线恢复和幂等重试。
- 工作区文件浏览、文本预览、附件上传与下载，单文件上限 10 MiB。
- Android 工程、双架构 debug APK 构建配置和已推送的 GitHub Actions 工作流。
- TokenWorks 四模式按主机实际预设选择并核对；兼容主机的额度只读查询。
- 校园接入：系统浏览器统一身份、服务端换码、按账号发现模型、单轮问答、iWAN 入口和网关检测。**仍需校方批准的接入服务和真实账号验收。**
- 本机运行时代码：随 ARM64 APK 打包上游 Ubuntu、Node、DSH 和 PRoot 的安装/启动/停止与本机工作区入口。**本轮构建验证未能读取 runtime-bundle，真机链路未验收。**

### 3.2 本轮交付

| 功能 | 实现 | 明确限制 |
|---|---|---|
| 多主机 | `HostManager` 单一连接状态 owner；HTTPS / SSH / Remote 注册表；切换、改名、删除、自动连接上次主机；旧单主机 Cookie 自动迁移 | 多主机凭据恢复仍需真机验收 |
| SSH | `dartssh2` 密码/私钥认证；SHA-256 指纹 TOFU；托管启动 `dsh web` 与只连接隧道；保存托管端口和令牌用于复用 | `dartssh2` 4.1.0 只协商 `none` 压缩；托管复用是本项目自己的状态，不是上游状态文件契约；未连真实 SSH 主机 |
| DSH Remote | `RemoteAccount` 浏览器 OAuth / 邮箱密码登录、在线主机目录、身份指纹信任、Noise 加密会话 | **仅 Relay**；未接 WebRTC 局域网 / P2P / TURN 和扫码配对；未用真实账号验收 |
| 自动化任务 | 目录、筛选、搜索、详情、历史翻页、编辑标题/指令/时间、立即运行、删除、关联会话跳转 | 新建没有私有 RPC：表单交给当前对话模型调用官方 `schedule_create`，仍需在对话中处理工具审批；未做真实执行验收 |
| 插件市场 | 已安装分组、开关、详情、卸载 4 秒撤销；官方与 dshfind format-1 索引；搜索、分类、安装检查、风险确认、构建脚本批准 | 插件完整原生设置表单未迁移，仍提示去桌面网页版；Remote 连接按能力只开关；未做真实安装验收 |
| 语音通话 | Android 系统 SpeechRecognizer 和 TextToSpeech；停顿发送、流式分句朗读、插话打断、点光球跳过、静音、免提/听筒、后台挂断、手动审批与提问 | 使用系统服务而非 DeepSeek ASR 或主机语音模型；需要麦克风权限和真机音频路由验收；历史消息不会自动朗读 |

### 3.3 仍未完成或不在本轮范围

- SSH 压缩、上游托管状态文件的完整语义、Remote 直连与扫码配对。
- 插件原生设置表单。
- 手机操控、定时任务之外的后台自动化、通用伙伴/桌宠；专属品牌素材仍需授权。
- TokenWorks 知识工作室、文献、Office/PDF、邮件、微信、CAD、图像、检查点等专属工作流。
- 学校账号自动接入本机 DSH 工作区并进行多轮对话与工具调用的完整链路。
- iOS / 鸿蒙（本轮明确排除）。

## 4. 代码地图与架构

### 4.1 App 状态与存储

- `app/lib/main.dart`：创建并共享 `HostManager` 和 `RemoteHostAccess`。
- `app/lib/src/host_manager.dart`：注册表、活动连接、会话列表、连接状态、错误和 busy 的唯一 owner。`HostConnection` 可携带 `updatedHost` 和 `updatedSecret`，用于保存 SSH 指纹和托管状态。
- `app/lib/src/host_registry.dart`：`HostEntry`、`SshHostSettings`、`HostRegistry` JSON。秘密不进入注册表。
- `app/lib/src/host_vault.dart`：`HostVault` 接口、`MethodChannelHostVault` 和测试用 `MemoryHostVault`。
- `app/lib/src/hosts_page.dart`：主机目录、HTTPS 添加、自动连接开关、编辑和删除。
- `app/lib/src/desktop_home.dart`：改为消费 `HostManager`，本机引擎使用独立 manager。

Android 端 `MainActivity.kt` 的 `tokenworks_go/host_vault` 通道使用 Android Keystore AES/GCM，将每个 key 加密保存为 `noBackupFilesDir/host-vault/<key>` 的 `AtomicFile`。旧 `desktop_store` 只在生产入口显式传入并迁移一次，测试不调用平台旧通道。

### 4.2 传输实现

- `app/lib/src/ssh_host.dart`：SSH 凭据校验、启动链接解析、本地 `ServerSocket` 转发和托管启动。
  - 托管命令追加 `--port 0 --no-open`，通过 `nohup` 写入远端 `$HOME/.tokenworks-go/dsh-<timestamp>.log`，轮询解析 loopback `?token=` 启动链接。
  - 复用先尝试已保存端口和令牌，失败后才重新启动，不自动杀远端进程。
  - `SshTunnel` 每条本地连接建立一个 direct-tcpip channel，普通 `DshClient` 通过 `http://127.0.0.1:<port>` 工作。
- `app/lib/src/ssh_host_page.dart`：完整表单、私钥导入、测试连接、指纹清除。编辑时秘密不回显；凭据未读完时禁止保存覆盖。
- `app/lib/src/remote_host.dart`：`VaultSecretStore`、`RemoteHostAccess.connect` 和错误映射。默认服务器为 `https://dsh.r2049.cn`，`peerConnector: null`。
- `app/lib/src/remote_page.dart`：登录、在线主机列表、指纹确认、密钥变化后重新信任。重复选择同一 Remote 主机不会重复注册。

### 4.3 自动化与插件

- `app/lib/src/schedules_page.dart`：复用 `schedule/catalog`、`schedule/history`、`schedule/update` / `schedule/edit`、`schedule/run`、`schedule/delete`。
- `scheduleCreatePrompt` 生成严格 JSON 参数，交给当前会话模型调用 `schedule_create`，不要虚构 `schedule/create`。
- `app/lib/src/plugin_market.dart`：有 8 MiB 上限的市场索引下载。
  - 官方：`https://go.dshtui.com/market/index.json`
  - 全部：`https://api.dshfind.com/market/dsh-index.json`
- `app/lib/src/plugins_page.dart`：`pluginManager/*` 管理流和 format-1 市场 UI。安装前必须 `inspect` 并确认风险；`pendingBuilds` 必须单独批准后重试。

### 4.4 语音

- `app/lib/src/voice_bridge.dart`：可替换的 `VoiceBridge` 接口与 MethodChannel 实现。
- `app/lib/src/voice_call.dart`：通话状态机。历史快照只建立上下文，不朗读；新回复按完整句子进入 TTS 队列；插话只停止朗读，不自动取消主机回合。
- `app/lib/src/voice_call_page.dart`：光球、识别文本、审批与提问卡、静音/挂断/免提。审批只能由用户点按。
- `app/android/.../VoiceChannel.kt`：麦克风运行时权限、系统识别、TTS 队列、utterance 回调和音频路由。`AndroidManifest.xml` 新增 `RECORD_AUDIO`。
- 切后台结束通话；关闭页面必须停止识别和朗读。

## 5. 包关系与外部依赖

根目录仍是 Pub workspace：`app` + `packages/tokenworks_core`。

`dsh_client` 和 `dsh_remote` 继续作为上游独立包维护，各自 `pub get`、分析和测试。**不要加入根 workspace，也不要添加 `resolution: workspace`。**

新增 App 依赖：

- `dartssh2: ^4.1.0`（MIT）
- `url_launcher: ^6.3.3`（BSD 3-Clause）

语音使用 Android 系统服务，没有引入额外语音库。多主机、SSH、Remote、自动化、插件和语音的 App 页面与状态管理为本仓库原创，没有复制上游 App 对应页面。

上游锁定提交仍是 `de8979d89d2205fc8872871e54904ddcda891b87`。修改记录见 `docs/upstream-provenance.md`。

## 6. 安全与行为边界

- 密码、私钥、口令、Cookie、Remote identity/token/pin 和托管令牌只能进入 Keystore 保险库，不能写进注册表、日志、文档、测试 fixture 或 Git。
- SSH 首次连接必须核对指纹；已保存指纹变化时拒绝连接，不能自动信任。
- Remote 首次连接必须核对身份指纹；密钥变化需要用户重新确认。
- 语音、模型或任何自动事件都不能批准工具；审批始终由用户点按。
- 插件风险标记不是安全保证；构建脚本必须单独确认。
- `network_security.xml` 只允许 `127.0.0.1` 的 loopback 明文 HTTP，用于本机引擎和 SSH 隧道；远端 HTTPS 要求不变。
- 不读取与项目无关的个人目录或凭据存储。

## 7. 已实际运行的验证

2026-11-19 在 Windows 11、Flutter 3.47.7 / Dart 3.13.5 环境实际执行：

```bash
# 三个 Dart 包分别执行
dart analyze
dart test

# App
flutter analyze
flutter test

# 校园服务
node --test services/campus/server.test.mjs

# Android（ASCII 副本）
flutter build apk --debug --no-pub --target-platform android-arm64,android-x64
```

| 套件 | 结果 |
|---|---|
| `tokenworks_core` | 静态分析通过，18 项测试通过 |
| `dsh_client` | 静态分析通过，908 项通过，32 项跳过 |
| `dsh_remote` | 静态分析通过，499 项通过，4 项跳过 |
| `app` | 静态分析零问题，28 项测试通过 |
| 校园接入服务 | 4 项测试通过 |
| Android | 双架构 debug APK 构建成功，apksigner v2 校验通过，1 个签名者 |

App 测试覆盖多主机与旧凭据迁移、SSH 配置和启动链接解析、Remote 存储、自动化任务、插件索引/安装、语音识别/朗读、历史不朗读和手动审批。

验证 APK：

```text
E:\tokenworks-tooling\twg-analyze-qoder\app\build\app\outputs\flutter-apk\app-debug.apk
```

**该副本未能读取 `app/android/runtime-bundle/`，所以这次 APK 不包含本机 Linux 运行时，只用于验证新增功能的编译和签名，不是完整内置 Linux 包。**

未运行：Android 真机、真实 SSH 主机、真实 Remote 账号、真实插件安装、自动化任务实际执行、真实 TokenWorks 学校账号、麦克风和系统 TTS。

## 8. 工具链与已知坑

隔离工具链：

- Flutter：`E:\tokenworks-tooling\flutter-sdk\flutter\`
- Pub cache：`E:\tokenworks-tooling\pub-cache\`
- HOME / TEMP：`E:\tokenworks-tooling\home\`、`E:\tokenworks-tooling\temp\`
- JDK：`E:\tokenworks-tooling\android-build\jdk-17.0.21.0.2+1`
- Android SDK：`E:\tokenworks-tooling\android-build\sdk`
- Gradle：`E:\tokenworks-tooling\android-build\gradle`

环境变量按本次进程设置：`HOME`、`USERPROFILE`、`APPDATA`、`TEMP`、`TMP`、`PUB_CACHE`；构建再加 `ANDROID_HOME`、`ANDROID_SDK_ROOT`、`JAVA_HOME`、`GRADLE_USER_HOME`、`ANDROID_USER_HOME`。

- 中文绝对路径会让 `flutter analyze` 的 LSP 崩溃。当前 ASCII 副本是 `E:\tokenworks-tooling\twg-analyze-qoder`，测试仍在原仓库运行。
- 不要机械覆盖或删除这个副本；先确认它确实是专用临时目录。
- 原目录的 `app/android/runtime-bundle/` 当前读取为 permission denied。完整内置 Linux 包需要先恢复可读运行时，或用 `tool/prepare_android_runtime.py` 从上游 APK 重新准备。
- 关闭主机连接时，状态流订阅用 `unawaited(_statusSubscription?.cancel())` 后再 `client.close()`；等待该 cancel 曾在测试夹具中形成等待。
- 上游测试在 Windows 并发运行的已知 fixture 修复不要回退。
- ADB 当前未检测到 Android 设备，不能把构建成功写成真机通过。

## 9. 推荐后续顺序

1. 托管 CI 已全绿（`0b90ea3`，run `44703180606`），可直接进入真机验收；后续改 CI 时留意 workflow 权限与 Android SDK 安装步骤。
2. 在 ARM64 真机验收：多主机存储、SSH 密码/私钥与两种实例模式、Remote 登录与指纹、插件安装、自动化任务、语音权限和音频路由。
3. 恢复可读的 `runtime-bundle`，重新构建完整内置 Linux APK，再验收本机引擎。
4. 接 Remote 局域网 / P2P / TURN 和扫码配对；评估 SSH 压缩与上游托管状态契约。
5. 迁移插件原生设置表单，补真实 TokenWorks 四模式、额度和学校账号验收。
6. 再做手机操控、通用伙伴和 TokenWorks 专属工作流；不要同时铺空页面。

## 10. 给下一位 AI 的简短工作指令

> 当前仓库已经有可编译、可测试的六项移动端实现，优化提交已全部推送到 GitHub，托管 CI 已全绿，但没有真机或真实主机验收。下一步做真机验收。Remote 只有 Relay，SSH 没有压缩，插件设置仍在网页版，语音使用系统服务，验证 APK 不含 Linux 运行时。不要把这些限制写成已完成。保留上游 AGPL 署名和修改记录；秘密只进 Keystore；所有危险操作需要明确用户确认；未经用户要求不提交、不推送、不改写历史。
