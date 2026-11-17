# TokenWorks-Go 路线图

## M1：Android 双模式可用垂直切片（当前）

- [ ] 独立品牌 Android App（arm64 + x64）
- [ ] 本机引擎：PRoot Ubuntu + Node + dsh web + TokenWorks 桥插件
- [ ] 远程主机：SSH 托管/只连接 + DSH Remote
- [ ] 会话：新建、流式、审批、提问、停止、恢复
- [ ] 工作区：文件浏览、附件上传、下载
- [ ] 统一身份认证：OIDC 系统浏览器登录
- [ ] 账户卡片：模型列表、额度窗口、网络状态
- [ ] 四种模式：标准/科研/教学/学习（当前能力相同，先提供入口）
- [ ] 插件：原生工具卡、表单、面板
- [ ] 关于页、许可、诊断导出
- [ ] 桥协议 fixtures 与双模式 E2E

## M2：TokenWorks 专属工作流

- [ ] 知识工作室：报告/演示/思维导图/测验/闪卡
- [ ] 文献检索：DBLP/arXiv/BibTeX/全文下载
- [ ] Office/PDF：读取、生成、预览
- [ ] 邮件助手：学校邮箱查信/读信/发信（确认制）
- [ ] 微信桥：扫码绑定、手机派活、审批推送
- [ ] 生图与改图：Qwen Image 确认制

## M3：移动端深度

- [ ] 手机操控：无障碍读屏、点按、输入、三档确认
- [ ] 悬浮条与不打扰模式
- [ ] 桌宠/伙伴小屋
- [ ] 语音朗读/输入/通话
- [ ] 应用内更新（差量）
- [ ] iOS 宿主（NodeMobile + CoreDevice）

## M4：鸿蒙与生态

- [ ] OHOS ArkTS 宿主 + 进程内 Node
- [ ] MCP 接入学校审核服务
- [ ] 插件市场与创意工坊

## 里程碑验收

每个 M 结束必须：
1. `flutter pub get && flutter analyze && flutter test` 通过
2. `dart analyze && dart test`（tokenworks_core）通过
3. 桥协议契约测试通过
4. Android 真机/模拟器关键场景通过
5. 更新说明与许可核验完成
