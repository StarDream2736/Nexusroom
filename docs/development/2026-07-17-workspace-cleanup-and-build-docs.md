# 2026-07-17 工作空间清理与构建文档

## 完成内容

- 清理 Flutter、Dart、Go 和服务端本地编译产生的可再生缓存、临时目录与验证二进制。
- 保留屏幕推流所需的本地 FFmpeg、WireGuard Helper、Wintun、部署私有配置和运行数据。
- 重写根目录 `.gitignore`，覆盖操作系统、编辑器、临时文件、测试覆盖率、应用密钥、SQLite、Docker 归档、Go 构建产物、Flutter 生成目录和可选 Web 管理端构建目录。
- 将 `client/pubspec.lock` 从忽略列表移除，使客户端应用依赖可以锁定并复现。
- 对照服务端 REST 路由、WebSocket 信封、RTC 信令、ICE 配置、RTMP ingress 和 HTTP-FLV 路径检查客户端接口。
- 修正 RTC 首次进入与重连时的入房时序：客户端等待 WebSocket connected，按顺序发送 `room.join` 和 `rtc.offer`，并避免重复加入。
- 新增客户端编译打包文档和服务端编译、Docker、离线镜像打包文档。

## 验证结果

- `go vet ./...` 通过。
- `go test ./...` 通过。
- 服务端 Release 参数编译通过。
- `flutter pub get` 通过。
- `flutter analyze` 无 error 和 warning，保留 22 条既有 info 级 lint。
- `flutter test` 通过。
- `docker compose config` 通过。
- 三份部署 Shell 脚本通过 Bash 语法检查。
- `git diff --check` 通过。

## 清理边界

以下内容是本地运行或打包输入，不属于可随意删除的中间产物：

- `client/tools/ffmpeg.exe`
- `client/native/wg-helper/nexusroom-wg.exe`
- `client/native/wg-helper/wintun.dll`
- `deployment/.env`
- `deployment/config/server.yaml`
- `deployment/data/`

其中私有配置、运行数据、FFmpeg 和发布归档由 `.gitignore` 排除。源码、配置模板和依赖锁文件继续由 Git 管理。
