# NexusRoom 实现清单

> 说明：此清单基于当前仓库代码对照技术规划文档整理。已实现的功能已勾选。

## 第一阶段：基础设施 + IM

### 后端
- [x] 配置加载与服务入口启动
- [x] PostgreSQL 连接与自动迁移
- [x] Redis 连接与连通性检测
- [x] 认证模块：注册 / 登录 / JWT 生成与验证
- [x] 用户模块：获取当前用户、修改昵称、按 display_id 搜索
- [x] 房间模块：创建、加入、列表、详情、踢出成员
- [x] 消息模块：HTTP 拉取消息（after_id / before_id / latest）
- [x] WebSocket Hub：连接管理与消息广播
- [x] 消息清理定时任务（retention_days）
- [x] 头像上传接口
- [x] 文件上传接口

### 客户端
- [x] 服务器配置页（UI）
- [x] 登录页面（UI）
- [x] 注册页面（UI）
- [x] 房间列表页（UI）
- [x] 创建房间页（UI）
- [x] 房间主界面（UI）
- [x] /ping 连通性验证与保存服务器地址
- [x] 登录/注册 API 调用与 Token 存储
- [x] 房间列表/创建/加入 API 调用
- [x] WebSocket 连接管理与消息收发
- [x] 本地 SQLite（drift）存储与增量同步

## 第二阶段：音视频集成

### 后端
- [x] LiveKit Token 生成接口
- [x] Ingress 管理接口（创建/列表/删除）
- [x] 语音状态 WebSocket 事件处理
- [x] 房间设置 PATCH 接口（更新房间名/公告）

### 客户端
- [x] LiveKit Flutter SDK 集成
- [x] 语音频道接入与静音/开麦控制
- [x] 直播侧边栏与主视窗订阅逻辑
- [x] 房间设置页：Ingress 管理
- [x] 窗口最小化/失焦资源管理

## 第三阶段：管理功能与扩展接口

### 后端
- [x] 超管 API（用户/房间/配置/统计）
- [x] 好友系统：申请/接受/拒绝/列表
- [x] QQ 机器人 Webhook
- [x] Webhook Secret 校验

### Web 管理后台
- [ ] Vue 3 管理后台项目与页面实现

### 客户端
- [x] 好友系统 UI 与邀请入房
- [x] 头像上传与昵称修改
- [x] 客户端设置页（更换服务器、退出登录）

## 第四阶段：VLAN 与屏幕共享

### 后端
- [x] WireGuard 服务端初始化与密钥生成
- [x] VLAN API：join / leave / peers
- [x] WebSocket vlan.peer_update 事件

### 客户端
- [x] WireGuard 集成（Windows/macOS）
- [x] VLAN UI：开关、虚拟 IP、成员列表

### 屏幕共享
- [ ] 桌面端屏幕采集评估与接入（依赖 LiveKit Flutter SDK 桌面端支持）
- [ ] Simulcast 分辨率切换逻辑
