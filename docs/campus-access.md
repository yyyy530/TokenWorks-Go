# 校园接入

TokenWorks-Go 的「校园接入」页面提供统一身份登录、学校模型问答和校外网络检查。现有 DSH 主机连接继续使用自己的登录方式。Android 用短期 App 会话读取授权模型和问答结果。学校 OAuth 凭据、平台应用凭据和模型 Key 留在服务端。

## 校方授权和部署

校方手册要求移动应用先申请接入。请使用学校批准的 OAuth 2.0 授权码客户端和位于 `ustc.edu.cn` 下的 HTTPS 服务。注册的回调地址为部署源加 `/v1/campus/callback`。大模型平台应用另外申请授权，范围覆盖此应用服务的人员。 [统一身份开发者手册](https://id.ustc.edu.cn/doc/developer/) · [模型平台应用接入](https://llm.ustc.edu.cn/guide/application-access/)

在服务端环境中配置以下变量。用部署环境的秘密管理功能提供两组密钥。

| 变量 | 用途 |
|---|---|
| `TWG_CAMPUS_PUBLIC_URL` | 已注册的校园 HTTPS 源，包含协议与主机 |
| `USTC_OAUTH_CLIENT_ID`、`USTC_OAUTH_CLIENT_SECRET` | 统一身份授权码交换 |
| `LLM_APP_CLIENT_ID`、`LLM_APP_CLIENT_SECRET` | 按已核验的学工号读取本人模型资源。两项均省略时仍可登录 |
| `TWG_CAMPUS_PORT` | 本地监听端口，默认 8788 |

用 Node.js 22 或更新版本执行。

```sh
node --test services/campus/server.test.mjs
node services/campus/server.mjs
```

服务监听回环地址。在同一台受控服务器上的 HTTPS 入口转发 `/v1/campus/`。该入口需对登录流量限流，不记录登录查询串、Cookie、请求体或 Authorization 头。当前部署使用单个进程保留短期登录和会话，进程重启后重新登录。

Android 安装包通过编译参数指向批准的服务地址。

```sh
flutter pub get
cd app
flutter build apk --debug --dart-define=TOKENWORKS_CAMPUS_URL=https://your-approved-host.ustc.edu.cn
```

## 登录和模型发现

1. 在 Android 打开「校园接入」，点统一身份登录。系统浏览器经校园接入服务跳转到学校登录页。完成后点浏览器里的「返回 TokenWorks-Go」。
2. 服务端用学校接入凭据换取访问令牌并核对用户资料。手机用浏览器返回码和本次登录的 S256 验证串换取短期 App 会话，并通过 Android Keystore 加密保存。学校要求的授权码密钥保留在服务端。
3. 登录后，服务端按校方确认的学工号查询授权资源。仅有一个可用 Key 时，动态读取 `GET /v1/models` 并返回模型列表。没有可用 Key 或存在多个可用项目时显示对应状态。
4. 点选已授权模型即可发送单轮文本问题。接入服务核对模型、会话和授权项目，再调用学校的对话 API。该问答入口每次只发送当前问题。 [官方模型 API](https://llm.ustc.edu.cn/guide/api-usage/)

## 校外使用 iWAN

在「校园接入」点「打开 iWAN」。App 核对已安装 Panabit 客户端的发布签名，核验通过后打开客户端，其余情况打开学校安装说明。厂商 2.4.3 安装包包含面向不同 Android 版本的签名，直达只接受厂商发布签名。选择客户域 `iwan.ustc`，在 iWAN 中完成统一身份认证和连接，再回到 App 自动检查学校模型网关。页面也可打开系统 VPN 设置。网关检测由手机直接发出，不消耗模型额度。问答经校园接入服务转发。 [iWAN 校方说明](https://email.ustc.edu.cn/notice/iwan/) · [厂商下载中心](https://download.panabit.com:9443/ecool.php)

真机验收需要已批准的服务地址、校方授予的两组应用凭据和有权访问的学校账号。用校园网和已连接 iWAN 的校外网络分别验收学校登录、授权模型列表、退出和会话过期。
