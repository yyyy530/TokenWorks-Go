# TokenWorks-Go 路线图

## M1 · Android 远程会话

- [x] Android 工程与 arm64/x64 debug APK 构建配置
- [x] HTTPS DSH 主机连接、Android Keystore 登录存储、会话列表
- [x] 模型选择、新建会话、流式回复、历史翻页、停止、单次审批与普通提问
- [x] 网络恢复后的会话同步与发送重试幂等
- [x] 四套 CI 门禁和 Android debug APK 产物配置
- [ ] Android 真机与真实 DSH 主机端到端验收
- [x] 工作区文件浏览、文本预览和附件上传/下载
- [ ] 按主机工作区组织会话和归档状态
- [ ] 多主机管理、SSH 托管和仅连接模式、DSH Remote 配对
- [ ] 工具权限与工作区的完整配置、继续型提问、诊断导出

## M2 · TokenWorks 集成

- [x] 系统浏览器统一身份登录和服务端授权码交换
- [x] 通过已核验身份自动发现授权模型并支持单轮文本问答，提供官方 iWAN 入口与网关检测
- [ ] 部署校方批准的校园接入服务，验收真实校园登录、模型发现和校外 iWAN
- [ ] 接入官方 TokenWorks 签名配置，衔接多轮智能体工作区
- [x] 按主机实际提供的预设选择 TokenWorks 模式，并确认创建结果
- [x] 通过兼容主机的额度插件读取额度和重置时间
- [ ] 用真实 TokenWorks 逐项核对四种模式、剩余用量、限速和重置
- [ ] 对接知识工作室、文献工具、Office/PDF、邮件助手、微信、CAD 与图像插件
- [ ] 使用授权 TokenWorks 主机与学校账号逐项验收

学校应用接入文档描述了[大模型公共服务平台接入流程](https://llm.ustc.edu.cn/guide/application-access/)。TokenWorks 移动集成还需要对应客户端注册、桌面桥协议和插件契约。公开的[词元工坊试用公告](https://llm.ustc.edu.cn/)说明了桌面端现有能力。

## M3 · 本机引擎与手机能力

- [ ] 在 Linux x86_64 构建和验证 Android PRoot、Node、引擎与宿主桥
- [ ] 保持本机与远程主机状态隔离，验证升级、恢复、文件与审批
- [ ] 支持语音、自动化、手机操控和通用伙伴；专属品牌素材待授权
- [ ] 适配 iOS 宿主

## M4 · 鸿蒙与生态

- [ ] OHOS ArkTS 宿主与进程内 Node
- [ ] MCP 审核服务、插件市场与创意工坊

桌面功能的逐项差异见[迁移清单](tokenworks-parity.md)。测试与验收命令见[质量门禁](quality.md)。
