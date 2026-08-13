# 客户端开发指南

NexusRoom 3.0.0 桌面端使用 Electron、React、TypeScript、Vite 和 Chromium，面向 Windows x64。完整架构见 [NexusRoom 技术规范](../NexusRoom.md)，发布步骤见 [客户端编译与打包](../build/client-build.md)。

## 当前职责

桌面端未登录时显示紧凑认证窗口，填写服务端 Origin 后可登录或注册并恢复会话；认证成功后同一窗口展开完整 UI。登录后提供房间列表、创建、邀请码加入、退出和切换；房间内提供历史与实时文字消息，以及图片上传和鉴权 Blob 显示。WebSocket 负责房间事件和语音信令，WebRTC 负责语音；直播播放器优先 WebRTC，失败后在当前页面会话锁定 HTTP-FLV，刷新播放才会重新协商 WebRTC。WireGuard VLAN 通过随客户端分发的 Helper 和 Wintun 工作。

服务端仍拥有好友、文件 API 和其他协议能力；当前 Electron UI 提供基础注册入口，但不提供 `admin_token` 输入、好友管理、任意文件消息、屏幕采集、音频设备选择或客户端 FFmpeg 推流界面。

## 目录

```text
client/
├── src/main.ts                 Electron 主进程、窗口和生命周期
├── src/preload.ts              contextBridge 和窄 IPC
├── src/main/                   主进程 IPC、SQLite、权限和 WireGuard 控制；其中 rest-client.ts 和 ws-client.ts 是随 Vite 打入 renderer 的浏览器安全网络模块
├── src/renderer/               React 页面、消息、语音、直播和 VLAN UI
├── src/shared/                 主进程与渲染进程共享类型
├── tests/                      Vitest 单元与组件测试
├── native/wg-helper/           Windows WireGuard Helper 和 Wintun
├── vite.config.mjs             渲染进程构建
└── package.json                Electron Builder Windows ZIP 配置
```

主进程创建窗口时启用 `contextIsolation`、`sandbox` 和 `webSecurity`，关闭 `nodeIntegration`、子帧 Node 集成和 `webviewTag`。渲染进程不能直接访问 Node；只通过预加载脚本暴露的存储和 WireGuard IPC 调用本地能力。

## Windows 开发

安装 Windows x64、Node.js 和 npm。在 `client` 目录执行：

```powershell
npm ci
npm run dev
```

开发服务器启动后，Electron 窗口加载 Vite 渲染页面。服务端地址在登录页填写 Origin，例如 `http://127.0.0.1:8080`；不要填写 `/api/v1`。

提交前运行完整检查：

```powershell
npm run build
```

这个命令依次执行 TypeScript 类型检查、ESLint、Vitest、Vite 渲染构建和 Electron 主进程构建。需要单独运行时可以使用 `npm run typecheck`、`npm run lint` 或 `npm test`。

## 本地数据

开发时数据库位于项目目录的 `data\nexusroom.sqlite`；打包后固定在 `NexusRoom.exe` 同级的 `data\nexusroom.sqlite`。SQLite 保存设置、账号会话和房间消息缓存，并以规范化服务器地址和账号 ID 作为隔离键。客户端不扫描、导入或迁移 `%LOCALAPPDATA%`、Documents 或其他旧目录中的数据库，也没有旧数据库迁移逻辑。

发布 ZIP 不包含 `data`。首次运行会创建目录和数据库结构，运行期间可能出现 `nexusroom.sqlite-wal` 与 `nexusroom.sqlite-shm`。备份或迁移时先退出客户端，再整体复制 `data`。

“清除本地数据”在数据库连接保持打开时事务性删除设置、会话和消息内容，随后压缩数据库。它不会删除 `data` 目录、数据库文件或表结构；操作完成后客户端返回服务器设置并可继续写入。

## 图片、语音和直播

图片上传使用房间成员权限，消息中的 URL 只作为服务端标识。渲染进程请求图片时带当前会话令牌，校验服务端 Origin 和 `image/*` Content-Type 后从 Blob 创建临时显示 URL。

语音加入房间后等待 WebSocket `connected` 和 `room.joined`，再通过 `rtc.offer`、`rtc.answer` 和 `rtc.ice` 建立 WebRTC。麦克风按钮反映真实连接状态；静音和说话状态通过房间事件同步，切换房间会停止旧房间媒体。

直播入口由服务端返回 `stream_key`。播放器先调用 `/api/v1/web/rtc/play` 尝试 WebRTC，并检查视频首帧和预期音频轨道；协商、连接或媒体检查失败时切换到 HTTP-FLV。回退后只在 FLV 内有限重连，不会自动回到 WebRTC；点击刷新播放才开始新的 WebRTC 尝试。

## WireGuard VLAN

ZIP 根目录必须包含以下文件：

```text
NexusRoom.exe
nexusroom-wg.exe
wintun.dll
```

Helper 由主进程以隐藏窗口启动。启动或重新启动 Helper 建立隧道时可能触发 UAC；停止隧道通过现有 Helper 连接完成。用户应在 Windows 提示中允许启动操作。Helper 缺失、Wintun 不可用或权限被拒绝时，UI 会显示 VLAN 错误并保留其他房间功能。

## 约定和边界

新增渲染功能应保持主进程、预加载和渲染进程边界，不得在 React 代码中引入 Node 模块或裸 `ipcRenderer`。持久化查询必须带服务器和账号隔离键。需要修改 REST、WebSocket、SQLite 或打包结构时，同时更新 [技术规范](../NexusRoom.md) 及相应测试。
