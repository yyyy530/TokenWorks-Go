# TokenWorks-Go

TokenWorks-Go 是面向 Android 的词元工坊移动工作区项目。当前代码提供一个 DSH 桌面会话客户端，复用 ccch1mneyyy/dsh-Go 的客户端与远程传输库。学校身份、模型额度和本机引擎的集成进度见[路线图](docs/roadmap.md)。

## 当前能力

- 连接一台自有的 HTTPS DSH 主机，读取会话列表与消息历史。
- 从主机返回的目录选择模型，新建会话，接收流式回复并停止当前生成。
- 响应主机的逐次审批和普通用户提问，网络恢复后重新同步会话。
- 浏览工作区目录和预览文本，通过系统文件选择器发送附件或下载文件，单个文件上限为 10 MiB。
- 可用 Android Keystore 加密保存主机地址和登录 Cookie，支持断开并清除。
- 新建会话可选主机实际提供的 TokenWorks 模式。兼容的主机通过只读额度插件提供数据时，手机可查看学校额度和重置时间。
- 「校园接入」提供 iWAN 指南、Android VPN 设置和模型网关检测。配置校方批准的校园接入服务后，可在系统浏览器完成学校登录并自动同步授权模型目录。
- Dart 核心层保留学校身份、四种模式、模型与额度的接口和校验。

校园接入服务需要校方批准和部署。TokenWorks 桌面专属插件、SSH、DSH Remote 配对和 PRoot 引擎仍在路线图中。现有桌面连接面向兼容的 `dsh web`，TokenWorks 桌面兼容性需要实际主机验证。

## 本地构建与运行

使用 Flutter 3.47.7（Dart 3.13.5）、JDK 17、Android SDK 36、Build Tools 36.0.0 和 NDK 28.2.13676358。最低系统版本为 Android 7.0（API 24）。

```bash
flutter pub get
cd app
flutter build apk --debug --no-pub --target-platform android-arm64,android-x64
```

构建产物位于 `app/build/app/outputs/flutter-apk/app-debug.apk`。如已连接 Android 设备，可在 `app/` 下运行 `flutter run`。

## 连接 DSH 桌面主机

1. 在自己的电脑或服务器上启动 `dsh web`，保留启动链接中的 `token` 参数值。
2. 使用手机可访问的私有 HTTPS 入口，配置有效的 TLS 证书并转发 HTTP 与 WebSocket。代理后的 `Host` 必须符合 DSH 主机的可信主机配置。代理日志应排除带登录令牌的查询参数。
3. 在 App 分别填写 HTTPS 地址和令牌并连接。选中「在此手机上记住登录」时，App 保存换取的会话 Cookie。
4. 打开已有会话，或从主机提供的模型目录选择模型创建会话。新会话继承主机的工具权限设置。

## 开发与溯源

- [质量门禁](docs/quality.md)列出四套测试与 Android 验收步骤。
- [校园接入](docs/campus-access.md)说明统一身份、学校模型授权和 iWAN 的配置与验收。
- [路线图](docs/roadmap.md)记录剩余功能及实际依赖。
- [TokenWorks 功能迁移清单](docs/tokenworks-parity.md)逐项对照官方桌面版 0.2.204。
- [架构](docs/architecture.md)说明目标设计，[AI 交接文档](docs/AI_HANDOVER.zh-CN.md)保留最初交接时的基线。
- [上游溯源](docs/upstream-provenance.md)记录来自 [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go)（AGPL-3.0）的代码与本地修改。引擎设计参考 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)。

## 许可

仓库主体使用 [AGPL-3.0](LICENSE.upstream-dsh-go)，原创核心包使用 [MIT](packages/tokenworks_core/LICENSE)。[第三方声明](THIRD_PARTY_NOTICES.md)记录单独许可与署名。专属品牌图标和吉祥物素材需获得其权利人许可。
