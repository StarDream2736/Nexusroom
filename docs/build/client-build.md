# 客户端编译与打包

NexusRoom 3.0.0 客户端是 Electron + React + TypeScript 应用，使用 Electron Builder 生成 Windows x64 ZIP。客户端的本地 SQLite 固定在 `NexusRoom.exe` 同级 `data` 目录；发布包不携带这个目录。

## 1. 构建环境

在 Windows x64 安装：

- Windows 10 或 Windows 11。
- Node.js 和 npm。
- Git。

检查版本：

```powershell
node --version
npm --version
```

不需要额外的桌面 UI 框架或客户端媒体转码程序。只有重新编译 `native/wg-helper` 时才需要 Go 和 `go-winres`。

## 2. 安装依赖和开发运行

```powershell
cd client
npm ci
npm run dev
```

`npm ci` 按 `package-lock.json` 安装 Electron、React、Vite、TypeScript、Vitest、ESLint、mpegts.js 和 Electron Builder。`npm run dev` 启动 Vite，并让 Electron 加载开发渲染页面。

## 3. 构建检查

```powershell
cd client
npm run build
```

构建脚本依次执行：

1. `typecheck`：检查 React 渲染进程和 Electron 主进程 TypeScript。
2. `lint`：运行 ESLint 且不允许警告。
3. `test`：运行 Vitest。
4. `build:renderer`：使用 Vite 构建 Chromium 页面。
5. `build:electron`：编译主进程和预加载脚本。

## 4. Windows x64 ZIP

```powershell
cd client
npm run package:win
```

产物路径和名称：

```text
client/release/NexusRoom-3.0.0-windows-x64.zip
```

Electron Builder 配置使用 `asar: true`，并把 `dist/` 和 `dist-electron/` 放入归档。源映射文件不进入 asar；它们只在构建目录中用于调试。WireGuard 文件通过 `extraFiles` 放在 exe 同级，不放进 asar：

```text
NexusRoom.exe
nexusroom-wg.exe
wintun.dll
```

ZIP 不含 `data`、SQLite、日志或开发机缓存。解压后必须放入用户具有写权限的目录；不要直接放到 `Program Files` 等受保护位置。启动时主进程在 exe 同级创建 `data\nexusroom.sqlite`，运行期间可能产生 `-wal` 和 `-shm` 文件。

可以用以下检查确认 ZIP 内容：

```powershell
$zip = 'release\NexusRoom-3.0.0-windows-x64.zip'
$temp = Join-Path $env:TEMP 'nexusroom-3.0.0-check'
Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $zip -DestinationPath $temp
Test-Path (Join-Path $temp 'NexusRoom.exe')
Test-Path (Join-Path $temp 'nexusroom-wg.exe')
Test-Path (Join-Path $temp 'wintun.dll')
Test-Path (Join-Path $temp 'data')
```

前三个检查应为 `True`，最后一个应为 `False`。发布目录和 `data` 目录必须可分开备份；复制本地状态前先退出客户端。

## 5. 本地数据库和清理

开发运行的数据库位于 `client\data\nexusroom.sqlite`，打包运行的路径由 exe 所在目录决定。数据库表保存设置、账号会话和消息缓存；查询必须同时带规范化服务器 URL 与账号 ID。客户端不读取旧路径，也没有历史数据库迁移逻辑。

清除本地数据会在现有连接上以事务删除设置、会话和消息，再执行压缩。它不会删除 `data` 目录、数据库文件或 schema，也不会关闭仍被渲染进程使用的连接。

## 6. WireGuard Helper

`nexusroom-wg.exe` 和 `wintun.dll` 必须与 `NexusRoom.exe` 同级。主进程通过受控 IPC 启动 Helper；启动隧道时 Windows 可能显示 UAC 提示，停止隧道通过现有 Helper 连接完成。用户拒绝 UAC、Helper 缺失或 Wintun 加载失败时，VLAN 会报告不可用，不会阻止消息和直播功能。

需要重建 WireGuard Helper 时，`build.bat` 使用 Go 和 `go-winres`，并以 `CGO_ENABLED=0` 构建：

```powershell
go install github.com/tc-hib/go-winres@latest
cd client\native\wg-helper
.\build.bat
```

## 7. 服务端联调

客户端连接服务端 Origin，例如 `http://127.0.0.1:8080`。关键接口包括：

| 功能 | 客户端入口 | 服务端 API/事件 |
| --- | --- | --- |
| 登录和会话 | 账号密码表单 | `POST /api/v1/auth/login`、本地 SQLite |
| 房间和消息 | 房间面板 | `/api/v1/rooms/*`、`/ws?token=...` |
| 图片 | 图片选择 | `POST /api/v1/files/upload`、受保护下载 |
| 语音 | 房间语音按钮 | `rtc.offer`、`rtc.answer`、`rtc.ice` |
| 直播 | 直播入口和播放器 | `GET /api/v1/stream/:streamKey`、`POST /api/v1/web/rtc/play` |
| VLAN | 房间 VLAN 开关 | `/api/v1/rooms/:id/vlan/*`、WireGuard Helper |

服务端 `/ping` 和 WebSocket `connected.server_version` 当前均返回 `3.0.0`。房间消息必须先收到 `room.joined`，直播回退后刷新才重新尝试 WebRTC。

## 8. 发布前检查

```powershell
cd client
npm ci
npm run build
npm run package:win
npm audit --audit-level=moderate
```

人工检查至少覆盖：ZIP 根部三个运行文件、没有 `data`、可写目录首次启动、账号/服务器缓存隔离、历史和实时文字、图片鉴权显示、静音和成员说话状态、直播 WebRTC 到 FLV 的锁定回退，以及 UAC 允许或拒绝时的 VLAN 提示。
