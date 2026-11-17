# TokenWorks-Go 架构

> 目标：词元工坊的完整手机版（TokenWorks-Go），正如 dsh-Go 是 DeepSeek Harness 的手机版。
> 当前里程碑 M1：Android 双模式可用垂直切片，不引入酒馆/桌宠/自更新。

## 总体架构

```text
TokenWorks-Go App (Flutter + Riverpod)
├── UI 层
│   ├── TokenWorks 首页（账户/额度/四模式/会话列表）
│   ├── 会话详情（流式、审批、提问、附件）
│   ├── 设置（外观、语言、通知、隐私）
│   └── 主机管理（本机 / SSH / DSH Remote）
│
├── 状态层
│   ├── auth_state: 统一身份认证
│   ├── account_state: 模型/额度/网络
│   ├── hosts_state: 主机列表与激活
│   ├── sessions_state: 会话列表与归属
│   └── runtime_state: 本机引擎状态（Android PRoot 事实源在 Kotlin）
│
├── 客户端层
│   ├── packages/tokenworks_core: 纯 Dart 领域模型与端口
│   │   ├── models: SchoolModel, QuotaWindow, HostProfile, SessionSummary, AccountSnapshot
│   │   ├── ports: IdentityGateway, TokenStore, TokenWorksDirectory, WorkspaceGateway
│   │   ├── validation: LaunchPolicy（权限/网络/模型校验）
│   │   └── oidc: PKCE + 回调解析
│   │
│   └── packages/dsh_client (upstream): HTTP/SSE/RPC/mux 与 DSH 桥协议
│       复用 dsh-Go 的纯 Dart 客户端，无 Flutter 依赖
│
├── 桥接层
│   └── /dsh-go/v1/* + TokenWorks 专属扩展
│       ├── 通用：会话、审批、工具、插件、文件、设置
│       └── TokenWorks：统一身份状态、学校模型下发、额度、四种模式
│
├── 引擎层
│   ├── 本机：Android PRoot Ubuntu + Node + dsh web + TokenWorks 插件
│   └── 远程：SSH 托管/只连接 + DSH Remote（端到端加密）
│
└── 数据层
    ├── 本机工作区（文件、会话、附件）
    ├── 安全存储（OAuth token、API key）
    └── 远程主机（TokenWorks 桌面或服务器）
```

## 与 dsh-Go 的关系

- **复用**：`packages/dsh_client`、`packages/dsh_remote`、`packages/dartssh2`、Android runtime 链、桥协议 `/dsh-go/v1/*`、聊天/审批/会话/设置 UI 主干。
- **替换**：品牌、启动页、关于页、图标、吉祥物、主题默认色、深链 scheme、应用 ID。
- **新增**：`packages/tokenworks_core`、TokenWorks 首页、统一身份、学校额度卡片、四种模式选择器、知识工作室入口、文献工具入口、邮件助手入口、微信桥。
- **不引入**：Deepy、鲸娘、DSH Go logo、原 README 展示素材、任何未授权 USTC 校徽/形象。

## 桥协议策略

首版继续使用 `/dsh-go/v1/*` 与 `dsh/*` 通道名，避免无收益地同时改客户端、桥和 Host 插件。
capabilities 协商遵循 `docs/design/bridge-contract.md`：
- 按 `v` 判协议主版本，`bridge` 字段仅供诊断
- 未知能力忽略，业务错误优先嵌套 `{error:{code,message}}`
- 404 分类：`route-not-found` → null；其他结构化 404 → 抛原码
- 不永久缓存 null；每代 Host/mux generation 管理失效

## 许可与署名

- 修改后的主体按 AGPL-3.0 发布；`packages/dsh_client` 等源自 dsh-Go 的文件保留原有版权头，新增文件标 TokenWorks-Go。
- `sdk/`、`examples/` 保持 MIT（若引入）。
- 关于页与 README 标注：基于 [ccch1mneyyy/dsh-Go](https://github.com/ccch1mneyyy/dsh-Go)（AGPL-3.0）与 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 构建。
- TokenWorks 名称、USTC 校徽、糯籽形象不在本仓库授权范围内，发布前需另行确认。
