# TokenWorks-Go

TokenWorks-Go 是面向 Android 的词元工坊移动工作区项目。App 可以连接 DSH 桌面主机，也可以从内置 Linux APK 启动本机 DSH。项目复用 ccch1mneyyy/dsh-Go 的客户端与运行时。学校身份、模型额度和本机引擎的集成进度见[路线图](docs/roadmap.md)。

## 当前能力

- 连接一台或多台自有的 HTTPS、SSH、DSH Remote 主机，读取会话列表与消息历史；可切换、改名、删除主机，并选择是否自动连接上次主机。
- SSH 支持密码或私钥登录、主机密钥 SHA-256 指纹信任、托管启动 `dsh web` 和只连接端口转发。当前 SSH 库只支持未压缩传输。
- DSH Remote 支持浏览器或邮箱密码登录、在线主机目录和身份指纹确认。当前版本使用端到端加密 Relay 中转，局域网 / P2P / TURN 与扫码配对尚未接入。
- 查看、筛选和搜索自动化任务，编辑名称、指令和运行时间，查看历史、立即运行或删除；新建任务交给当前对话的模型调用官方 `schedule_create`。
- 管理已装插件，浏览官方和 dshfind 插件市场，完成安装前检查、风险确认、构建脚本批准、开关和卸载撤销。插件完整设置仍在桌面网页版。
- 在会话中打开语音通话，使用 Android 系统语音识别和系统朗读，支持停顿发送、分句朗读、插话打断、静音、免提/听筒和手动审批；切到后台结束通话，需要真机验收。
- 内置 Linux 的 ARM64 包可以在 Android 8.0 及以上直接解包 Ubuntu、Node.js 和 DSH，通过 PRoot 启动并进入本机工作区。
- 从主机返回的目录选择模型，新建会话，接收流式回复并停止当前生成。
- 响应主机的逐次审批和普通用户提问，网络恢复后重新同步会话。
- 浏览工作区目录和预览文本，通过系统文件选择器发送附件或下载文件，单个文件上限为 10 MiB。
- 可用 Android Keystore 加密保存主机地址和登录 Cookie，支持断开并清除。
- 新建会话可选主机实际提供的 TokenWorks 模式。兼容的主机通过只读额度插件提供数据时，手机可查看学校额度和重置时间。
- 「校园接入」提供 iWAN 指南、Android VPN 设置和模型网关检测。配置校方批准的校园接入服务后，可在系统浏览器完成学校登录并自动同步授权模型目录。
- Dart 核心层保留学校身份、四种模式、模型与额度的接口和校验。

校园接入服务需要校方批准和部署。TokenWorks 桌面专属插件仍在路线图中。现有桌面连接面向兼容的 `dsh web`，TokenWorks 桌面兼容性需要实际主机验证。SSH、Remote、插件安装和系统语音均已通过静态分析与可控测试，但尚未完成真机或真实主机端到端验收。

## 本地构建与运行

使用 Flutter 3.47.7（Dart 3.13.5）、JDK 17、Android SDK 36、Build Tools 36.0.0 和 NDK 28.2.13676358。最低系统版本为 Android 7.0（API 24）。

```bash
flutter pub get
cd app
flutter build apk --debug --no-pub --target-platform android-arm64,android-x64
```

构建产物位于 `app/build/app/outputs/flutter-apk/app-debug.apk`。如已连接 Android 设备，可在 `app/` 下运行 `flutter run`。

## 构建和使用内置 Linux 版

从 [dsh-Go v1.1.0 Releases](https://github.com/ccch1mneyyy/dsh-Go/releases/tag/v1.1.0) 下载 `dsh-go-1.1.0-arm64.apk`。在仓库根目录用 Python 3.11 或更高版本准备运行时。脚本核对上游发布包和 rootfs 的 SHA-256，将运行时、所需的原生库和许可文件放到 `app/android/runtime-bundle/`。

```bash
python tool/prepare_android_runtime.py /path/to/dsh-go-1.1.0-arm64.apk
flutter pub get
cd app
flutter build apk --debug --no-pub --target-platform android-arm64
```

安装后打开「本机运行」，点「启动本机引擎」。首次从 APK 解包需要约 1 GB 可用空间。引擎启动后进入「本机工作区」，用「配置本机模型」设置自己的模型提供商。返回工作区即可新建会话。模型请求仍由所选提供商处理。校园登录和学校模型目前使用独立的「校园接入」页面。

## 连接 DSH 桌面主机

1. 在自己的电脑或服务器上启动 `dsh web`，保留启动链接中的 `token` 参数值。
2. 使用手机可访问的私有 HTTPS 入口，配置有效的 TLS 证书并转发 HTTP 与 WebSocket。代理后的 `Host` 必须符合 DSH 主机的可信主机配置。代理日志应排除带登录令牌的查询参数。
3. 在 App 分别填写 HTTPS 地址和令牌并连接。选中「在此手机上记住登录」时，App 保存换取的会话 Cookie。
4. 打开已有会话，或从主机提供的模型目录选择模型创建会话。新会话继承主机的工具权限设置。

## 其他主机与会话功能

- 在「主机管理」中添加 SSH 主机。托管启动会执行配置的启动命令并追加 `--port 0 --no-open`，从输出解析 loopback 启动链接；只连接模式只转发到远端 `127.0.0.1` 的指定端口。密码、私钥、口令和令牌只保存在手机 Keystore 保险库中。
- 在「DSH Remote 配对」中登录与电脑 Remote 插件相同的账号，选择在线电脑并核对身份指纹。首次连接只走 Relay，不依赖 WebRTC 原生库。
- 「自动化任务」的新建表单不会虚构主机创建接口：填写后发送给当前对话，由模型调用 `schedule_create`，并在对话中确认工具审批。
- 「插件」读取真实主机和公开市场索引。安装前由主机检查包，风险标记与构建脚本必须明确确认。
- 在会话顶栏电话图标进入「语音通话」。麦克风权限仅用于通话，识别和朗读使用系统服务，后台自动挂断。

## 开发与溯源

- [质量门禁](docs/quality.md)列出四套测试与 Android 验收步骤。
- [校园接入](docs/campus-access.md)说明统一身份、学校模型授权和 iWAN 的配置与验收。
- [路线图](docs/roadmap.md)记录剩余功能及实际依赖。
- [TokenWorks 功能迁移清单](docs/tokenworks-parity.md)逐项对照官方桌面版 0.2.204。
- [架构](docs/architecture.md)说明目标设计，[AI 交接文档](docs/AI_HANDOVER.zh-CN.md)保留最初交接时的基线。
- [上游溯源](docs/upstream-provenance.md)记录来自 [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go)（AGPL-3.0）的代码与本地修改。引擎设计参考 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)。

## 许可

仓库主体使用 [AGPL-3.0](LICENSE.upstream-dsh-go)，原创核心包使用 [MIT](packages/tokenworks_core/LICENSE)。[第三方声明](THIRD_PARTY_NOTICES.md)记录单独许可与署名。专属品牌图标和吉祥物素材需获得其权利人许可。
