# 质量门禁

CI 固定使用 Flutter 3.47.7。根目录的 Pub workspace 包含 `app` 与 `tokenworks_core`，两个 DSH 包各自解析依赖。

## 自动验证

在仓库根目录执行 `flutter pub get`。各目录的验证命令如下。

| 目录 | 命令 |
|---|---|
| `packages/tokenworks_core` | `dart analyze`、`dart test` |
| `packages/dsh_client` | `dart pub get`、`dart analyze`、`dart test` |
| `packages/dsh_remote` | `dart pub get`、`dart analyze`、`dart test` |
| `app` | `flutter analyze --no-pub`、`flutter test --no-pub` |
| `app` | `flutter build apk --debug --no-pub --target-platform android-arm64,android-x64` |
| 仓库根目录 | `node --test services/campus/server.test.mjs` |

协议测试使用可控的 DSH 服务端响应，覆盖模型和模式选择、消息重试、流式回复、审批、提问、断线重连、文件传输及额度读取。验证结果需记录实际命令、平台、跳过数及失败输出。

## Android 验收

1. 在 arm64 真机和 x64 模拟器安装 debug APK，启动应用。
2. 通过 HTTPS 连接自己的 DSH 主机，打开已有会话，检查历史消息。
3. 明确选择模型和工作目录，新建会话并发送消息。检查流式回复、停止、逐次审批、提问和网络恢复。
4. 通过系统选择器发送附件，打开工作区目录，预览和下载文本文件，检查保存的内容。
5. 重启应用，验证已保存登录可恢复。断开并清除登录后再次启动，检查会话列表和已保存令牌均未恢复。
6. 连接真正的 TokenWorks 桌面端时，另外记录其版本、可用接口与学校账号验收结果。
7. 配置校园接入服务后，在校园网和 iWAN 环境分别验收浏览器回跳、模型同步和单轮问答。 [校园接入步骤](campus-access.md)

Android 本机引擎、SSH 托管、DSH Remote 配对与学校账号均有独立验收要求，见[路线图](roadmap.md)。

## 2026-11-20 托管 CI 验证

GitHub Actions 在提交 `0b90ea3` 上全绿（run `44703180606`）：

| 作业 | 结果 |
|---|---|
| Campus access service | 通过 |
| Dart / tokenworks_core | 通过 |
| Dart / dsh_client | 通过 |
| Dart / dsh_remote | 通过 |
| Flutter and Android debug APK | 通过，产出 `TokenWorks-Go-debug`（约 64.3 MB） |

首个运行曾在安装 Android SDK 时因 `sdkmanager` 不在 PATH 失败（exit 127）；修复后该步骤正常安装 platform 36、build-tools 36.0.0 与 NDK 28.2.13676358。托管构建的 APK 同样不含 `runtime-bundle`（仓库不跟踪该目录），真机与真实主机验收仍未进行。

## 2026-11-19 本地验证

本轮实际执行 `flutter analyze`、`flutter test`（App），`dart analyze`、`dart test`（三个 Dart 包），`node --test services/campus/server.test.mjs`，以及 `flutter build apk --debug --no-pub --target-platform android-arm64,android-x64`。

| 套件 | Windows 11 结果 |
|---|---|
| `tokenworks_core` | 静态分析通过，18 项测试通过 |
| `dsh_client` | 静态分析通过，908 项通过，32 项跳过 |
| `dsh_remote` | 静态分析通过，499 项通过，4 项跳过 |
| `app` | 静态分析通过，28 项测试通过；覆盖多主机与旧凭据迁移、SSH 配置和启动链接解析、Remote 存储、自动化任务、插件安装、语音识别/朗读与手动审批 |
| 校园接入服务 | 4 项测试通过 |
| Android | 双架构 debug APK 构建成功，apksigner v2 校验通过，1 个签名者 |

App 静态分析在 ASCII 临时副本执行（中文路径触发既有 LSP 崩溃），测试在原仓库运行。验证 APK 位于该副本的 `app/build/app/outputs/flutter-apk/app-debug.apk`。**该副本未能读取 `app/android/runtime-bundle/`，因此这次 APK 不包含本机 Linux 运行时，只用于验证新增功能的编译和签名，不作为完整内置 Linux 包交付。** ADB 未检测到 Android 设备；SSH 真实主机、Remote 真实账号、插件真实安装、自动化任务真实执行、麦克风/系统 TTS 和 Android Keystore 均未做真机验收。

## 2026-11-18 本地验证

| 套件 | Windows 11 结果 |
|---|---|
| `tokenworks_core` | 静态分析通过，18 项测试通过 |
| `dsh_client` | 静态分析通过，908 项通过，32 项跳过 |
| `dsh_remote` | 静态分析通过，499 项通过，4 项跳过 |
| `app` | Flutter 静态分析通过，7 项界面与协议流程测试通过，包含科研模式提交、额度读取、校园 API 和 iWAN 入口 |
| 校园接入服务 | 4 项测试通过，包含 OAuth 浏览器校验与回跳、按用户发现并调用授权模型、退出和多个项目的处理 |
| Android | debug APK 构建及 v2 签名校验通过，包含 arm64-v8a 和 x86_64 |
| DeepSeek Harness 0.2.1-rc.2 | 隔离的真实 HTTPS 主机通过启动令牌登录、新建会话、读取快照，以及用 Cookie 重新连接并读取会话列表。缺少 TokenWorks 预设和额度插件时，普通会话仍可使用 |

Flutter 分析和 APK 构建在 ASCII 路径的源码副本执行。ADB 此次没有检测到 Android 设备，真机启动、原生文件选择器和 Android Keystore 仍需设备验收。GitHub Actions 配置已通过本地 YAML 解析。
