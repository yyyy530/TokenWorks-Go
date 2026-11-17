# 质量门禁

## 每次提交前

```bash
# 核心包
(cd packages/tokenworks_core && dart pub get && dart analyze && dart test)

# App
(cd app && flutter pub get && flutter analyze && flutter test)
```

## 真机验证（M1 必须）

- Android arm64 真机：本机引擎安装、启动、流式对话、审批、后台恢复
- Android x64 模拟器：UI 与导航
- SSH 托管/只连接：两种模式都完成同一会话流程
- DSH Remote：连接、断线重连、切 Host 后状态隔离

## 契约测试

- 桥 capabilities：v1 解析、未知能力忽略、嵌套/平铺错误、404 分类
- OIDC：PKCE shape、state 匹配、错误回调
- LaunchPolicy：权限、网络、模型、工作区边界

## 性能契约

- 聊天流式渲染不触发抽屉重建
- 长会话（100+ 消息）滚动保持 60fps
- 附件上传/下载进度可见、可取消

## 安全

- OAuth token 只进系统安全存储
- 诊断包导出前人工检查
- 完全权限会话新建需显式确认
