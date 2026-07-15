# Client

本目录只存放 NexusRoom 桌面客户端及其客户端专用依赖，不包含服务端或部署配置。

## 目录

```text
client/
├── lib/                    # Flutter/Dart 业务代码
├── test/                   # 客户端测试
├── windows/                # Windows Runner 与打包配置
├── native/wg-helper/       # WireGuard Windows 辅助进程（Go）
└── tools/                  # FFmpeg 等本地工具
```

## 开发

```bash
flutter pub get
flutter run -d windows
flutter analyze
flutter test
```

发布构建：

```bash
flutter build windows --release
```

Windows 构建会从 `native/wg-helper/` 打包 `nexusroom-wg.exe`、`wintun.dll`，并从 `tools/` 打包 `ffmpeg.exe`。`tools/*.exe` 是本地依赖，不提交到 Git。

WireGuard helper 可在 `native/wg-helper/` 中运行 `build.bat` 单独构建。
