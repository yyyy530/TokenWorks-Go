# 第三方许可与署名

| 组件 | 上游 | 许可 |
|---|---|---|
| `packages/dsh_client` 及其 companion 测试门面 | [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) | [AGPL-3.0](LICENSE.upstream-dsh-go) |
| `packages/dsh_remote` | [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) | [AGPL-3.0](LICENSE.upstream-dsh-go)，附带 [DSH Remote MIT 许可](packages/dsh_remote/LICENSE-ds-harness-remote) |
| Android 平台工程模板 | [Flutter](https://github.com/flutter/flutter) | [BSD 3-Clause](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/LICENSE) |
| 系统文件选择器 | [file_picker](https://pub.dev/packages/file_picker) | MIT |
| SSH 客户端 | [dartssh2 4.1.0](https://pub.dev/packages/dartssh2) | MIT |
| 系统浏览器跳转 | [url_launcher 6.3.3](https://pub.dev/packages/url_launcher) | BSD 3-Clause |

上游版本与本地修改见[上游溯源](docs/upstream-provenance.md)。App 的「关于」菜单可打开运行时依赖许可列表。

内置 Linux 的 ARM64 安装包复用 [dsh-Go v1.1.0](https://github.com/ccch1mneyyy/dsh-Go/releases/tag/v1.1.0) 的 Ubuntu 24.04.5、Node.js 24.22.1、DeepSeek Harness 0.2.2-rc.1、PRoot 和相关库。对应组件、许可和上游源码地址见 [v1.1.0 第三方声明](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.1.0/THIRD_PARTY_NOTICES.md)及[运行时构建脚本](https://github.com/ccch1mneyyy/dsh-Go/blob/v1.1.0/runtime/build-runtime.sh)。随包的 `assets/tokenworks/runtime/licenses/` 保留原生库声明，解包后的 `/usr/share/doc/` 保留 Ubuntu 软件包声明。
