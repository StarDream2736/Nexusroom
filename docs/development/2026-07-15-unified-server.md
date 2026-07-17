# 2026-07-15 服务端能力内建与单体化改造

## 需求确认

本次工作的目标不是把 LiveKit、SRS 等项目作为第三方服务打包进 NexusRoom，也不是在主进程内启动这些程序。目标是只参考开源实现和协议库，将项目当前实际使用的能力重构为 NexusRoom 自己的模块，使其成为产品源码和生命周期的一部分。

确认的交付边界：

- 完成整体改造。
- 保留 Docker 和直接部署两种方案。
- SQLite 不做旧数据迁移。
- UI 不改动，UI 中承担状态表达的 emoji 保留。
- 完成后先供审查，不自动提交或推送。

## 完成的改造

### 数据与进程

- 使用 SQLite、WAL、busy timeout 和外键检查替代 PostgreSQL。
- 删除 Redis 初始化和配置。
- 服务端启动时自动建表并执行数据库完整性检查。
- 网页资源通过 `go:embed` 编译进服务端。

### 语音

- 新增 NexusRoom 内建 Opus SFU。
- SDP 和 ICE 通过应用 WebSocket 传输。
- 服务端维护房间 PeerConnection、RTP 转发、成员静音和说话状态。
- Flutter 从 `livekit_client` 改为 `flutter_webrtc`，不再请求 LiveKit Token。

### 直播

- 新增内建 RTMP 发布端点和 Stream Key 鉴权。
- 新增活跃流注册表与低延迟订阅分发。
- 新增 H.264/AAC FLV 封装，`/api/v1/stream/:streamKey` 不再反向代理 SRS。
- 新增浏览器 H.264 WebRTC 播放协商。
- 删除 SRS Webhook、SRS API 查询和 SRS 播放代理。

### 网络穿透

- 新增内建 STUN/TURN 服务。
- 直连媒体和 TURN 中继使用不同 UDP 端口范围。
- WebSocket 连接成功事件下发客户端 ICE Server 配置。

### 部署

- Docker Compose 从多个服务收敛为一个 `nexusroom` 容器。
- 删除 PostgreSQL、Redis、LiveKit、SRS 和 nginx 服务配置。
- 新增直接构建脚本、直接安装脚本和 systemd unit。
- 两种部署方式使用同一二进制和同一配置结构。

## 当前限制

- 浏览器 WebRTC 播放当前为 H.264 视频；含 AAC 的直播自动使用 HTTP-FLV，以保留音频而不引入转码进程。
- WebRTC 与 TURN 的生产部署仍需要真实公网 IP、端口映射和跨网络实测。
- 浏览器生产使用应配置 HTTPS/WSS 入口。

## 已执行验证

- `go test ./...`：通过，包括 SQLite 和 FLV 单元测试。
- `flutter analyze`：无 error 和 warning；剩余 22 项为仓库既有 info 级静态检查提示。
- `flutter test`：通过。
- `docker compose config --quiet`：通过。
- 三个 Linux 安装/构建脚本通过 Bash 语法检查。
- 单体服务通过本地启动探针，`GET /ping` 返回 HTTP 200。
- Docker 镜像构建在当前 Docker Desktop 环境中长时间无输出，未得到完成结果。
- Windows Release 干净构建首次因原有 `media_kit` 的 mpv 下载包完整性校验失败而停止；重试在同一下载阶段超时，未出现本次 RTC 改造相关的 Dart 或 C++ 编译错误。

## UI 与 emoji

媒体实现和数据模型发生变化，但现有页面布局、颜色、组件结构和状态表现未重做。UI 中的在线圆点、说话动画和 emoji 继续保留；服务日志、脚本与维护文档使用纯文本状态。
