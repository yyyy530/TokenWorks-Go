# 上游溯源与修改记录

TokenWorks-Go 复用了 [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) 的部分代码。

## 锁定上游

- 仓库：https://github.com/ccch1mneyyy/dsh-Go
- 提交：`de8979d89d2205fc8872871e54904ddcda891b87`
- 上游根许可：AGPL-3.0（见 `LICENSE.upstream-dsh-go`）

## 复制路径（字节级原样复制，未做品牌替换）

| 本仓库路径 | 上游路径 | 用途 |
|---|---|---|
| `packages/dsh_client/` | `packages/dsh_client/` | DSH Web API 纯 Dart 客户端 |
| `packages/dsh_remote/` | `packages/dsh_remote/` | 远程传输（Noise IK / WebRTC / 中继） |
| `packages/dsh_client/test/fixtures/companion/companion_context.dart` | `app/lib/companion/companion_context.dart` | dsh_client 测试引用的上游 App 门面（纯 Dart，无 Flutter 依赖） |
| `packages/dsh_client/test/fixtures/companion/companion_local.dart` | `app/lib/companion/companion_local.dart` | dsh_client 测试引用的上游 App 门面（纯 Dart，无 Flutter 依赖） |
| `packages/dsh_client/test/fixtures/companion/companion_signals.dart` | `app/lib/companion/companion_signals.dart` | dsh_client 测试引用的上游 App 门面（纯 Dart，无 Flutter 依赖） |

## 本地修改（全部为平台/环境适配，可审计）

| 文件 | 修改 | 原因 |
|---|---|---|
| `packages/dsh_client/test/session_path_whitespace_test.dart` | Windows 下跳过「文件名尾随空格」断言 | Windows 文件系统不保留文件名尾随空格，上游测试仅 POSIX 成立 |
| `packages/dsh_remote/test/support/fake_remote.dart` | `_sendControl` 对已关闭 socket 丢弃帧 | 修复全套件运行时的 fixture 时序 flake，与真实中继行为一致 |
| `packages/dsh_client/test/companion_prompt_commit_test.dart` | import 路径改为 `fixtures/companion/` | 测试引用的上游 App 门面按 fixture 方式随包提供，不引入 Flutter 上下文 |
| `packages/dsh_client/test/companion_local_store_test.dart` | import 路径改为 `fixtures/companion/` | 同上 |
| `packages/dsh_client/test/companion_signal_gate_test.dart` | import 路径改为 `fixtures/companion/` | 同上 |
| `packages/dsh_client/test/dsh_go_heartbeat_test.dart` | Host 发送前检查 closeCode，并处理检查与写入之间的关闭竞态 | 避免 pong 在 peer 关闭后写入导致全套件偶发失败 |

## 合规要点

- 以上包整体按 AGPL-3.0 分发；发布 TokenWorks-Go 时须提供对应源码。
- `packages/tokenworks_core/` 与 `app/lib/` 为原创代码，不继承上游 AGPL。
- DSH Go 名称、标识、Deepy、鲸娘及 `site/home/` 素材均未复制，不在授权范围内。
- 关于页与 README 需保留上游署名（见 README「与上游的关系」）。
