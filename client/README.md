# NexusRoom 桌面客户端

`client/` 是 NexusRoom 3.0.0 的 Electron + React + TypeScript Windows 桌面端。Electron 主进程管理窗口、SQLite 和 WireGuard Helper，预加载脚本通过窄 IPC 向 Chromium 渲染进程提供受控能力。

## 开发

在 Windows x64 安装 Node.js 和 npm 后执行：

```powershell
npm ci
npm run dev
```

完整质量检查和构建：

```powershell
npm run build
```

## Windows ZIP

```powershell
npm run package:win
```

输出为 `release\NexusRoom-3.0.0-windows-x64.zip`。解压到当前用户可写目录后运行。ZIP 根部包含 `NexusRoom.exe`、`nexusroom-wg.exe` 和 `wintun.dll`，不带 `data` 目录；不要把便携版直接放入需要管理员写权限的目录。

运行时 SQLite 固定写在 `NexusRoom.exe` 同级的 `data\nexusroom.sqlite`，并按规范化服务器地址和账号 ID 隔离。清除本地数据只清空业务设置、会话和消息内容，保留数据库结构、连接和 `data` 目录。

WireGuard Helper 启动隧道时会请求 UAC。缺少 Helper 或 Wintun 时，VLAN 会显示不可用，不影响文字和图片消息。

源码入口：`src/main.ts`、`src/preload.ts`、`src/renderer/`，本地原生 Helper 位于 `native/wg-helper/`。
