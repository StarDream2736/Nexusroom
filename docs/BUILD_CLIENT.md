# NexusRoom 客户端编译文档

## 环境要求

- **Flutter**: 3.x Stable
- **Dart**: 3.x
- **操作系统**: Windows 10+ / macOS 11+ / Linux

## 目录结构

```
client/
├── lib/
│   ├── main.dart              # 程序入口
│   ├── app/
│   │   ├── router/            # GoRouter 路由配置
│   │   └── theme/             # 全局主题
│   ├── features/              # 按功能模块分层
│   │   ├── auth/              # 登录/注册/服务器绑定
│   │   │   ├── data/          # Repository + API 调用
│   │   │   ├── domain/        # 业务模型 & 用例
│   │   │   └── presentation/  # UI 页面 + Provider
│   │   ├── room/              # 房间
│   │   ├── chat/              # 消息
│   │   ├── voice/             # 语音
│   │   ├── stream/            # 直播推流
│   │   ├── vlan/              # 虚拟局域网
│   │   └── user/              # 用户/好友
│   ├── core/
│   │   ├── db/                # SQLite (drift) 本地数据库
│   │   ├── network/           # HTTP Client + WebSocket
│   │   └── native/            # Platform Channel (WireGuard)
│   └── shared/                # 通用组件 & 工具
├── assets/                    # 静态资源
├── test/                      # 测试文件
├── pubspec.yaml               # 依赖配置
└── README.md
```

## 环境配置

### 1. 安装 Flutter

```bash
# 使用 git 克隆 Flutter SDK
git clone https://github.com/flutter/flutter.git -b stable

# 添加到 PATH
export PATH="$PATH:`pwd`/flutter/bin"

# 验证安装
flutter doctor
```

### 2. 启用桌面支持

```bash
# Windows
flutter config --enable-windows-desktop

# macOS
flutter config --enable-macos-desktop

# Linux
flutter config --enable-linux-desktop
```

### 3. 安装依赖

```bash
cd nexusroom/client
flutter pub get
```

## 开发运行

### 运行调试版本

```bash
# Windows
flutter run -d windows

# macOS
flutter run -d macos

# Linux
flutter run -d linux
```

### 热重载

在运行状态下，按 `r` 进行热重载，按 `R` 进行热重启。

## 编译发布版本

### Windows

```bash
# 编译发布版本
flutter build windows --release

# 输出目录
# build/windows/x64/runner/Release/

# 创建安装包（使用 Inno Setup）
# 1. 安装 Inno Setup: https://jrsoftware.org/isinfo.php
# 2. 编译 iss 脚本（见下方）
```

#### Inno Setup 安装脚本示例

创建 `nexusroom.iss` 文件：

```iss
[Setup]
AppName=NexusRoom
AppVersion=1.3.1
DefaultDirName={autopf}\NexusRoom
DefaultGroupName=NexusRoom
OutputDir=.
OutputBaseFilename=NexusRoom-Setup
Compression=lzma
SolidCompression=yes

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\NexusRoom"; Filename: "{app}\nexusroom.exe"
Name: "{autodesktop}\NexusRoom"; Filename: "{app}\nexusroom.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\nexusroom.exe"; Description: "启动 NexusRoom"; Flags: nowait postinstall skipifsilent
```

编译安装包：

```bash
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" nexusroom.iss
```

### macOS

```bash
# 编译发布版本
flutter build macos --release

# 输出目录
# build/macos/Build/Products/Release/

# 创建 DMG（使用 create-dmg）
brew install create-dmg

create-dmg \
  --volname "NexusRoom" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 450 185 \
  "NexusRoom-1.3.1.dmg" \
  "build/macos/Build/Products/Release/NexusRoom.app"
```

### Linux

```bash
# 编译发布版本
flutter build linux --release

# 输出目录
# build/linux/x64/release/bundle/

# 创建 AppImage（可选）
# 参考: https://appimage.org/
```

## 依赖包清单

### 核心依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # 状态管理
  flutter_riverpod: ^2.4.0
  riverpod_annotation: ^2.2.0
  
  # 路由
  go_router: ^12.0.0
  
  # 本地数据库
  drift: ^2.13.0
  drift_flutter: ^0.1.0
  
  # 网络请求
  dio: ^5.3.0
  web_socket_channel: ^2.4.0
  
  # LiveKit WebRTC
  livekit_client: ^2.0.0
  
  # 图片处理
  image_picker: ^1.0.0
  cached_network_image: ^3.3.0
  
  # 窗口管理
  window_manager: ^0.3.0
  
  # 其他工具
  freezed_annotation: ^2.4.0
  json_annotation: ^4.8.0

dev_dependencies:
  build_runner: ^2.4.0
  drift_dev: ^2.13.0
  freezed: ^2.4.0
  json_serializable: ^6.7.0
  riverpod_generator: ^2.3.0
```

## 代码生成

Drift 和 Freezed 需要代码生成：

```bash
# 生成数据库和模型代码
flutter pub run build_runner build

# 持续监听文件变化（开发时使用）
flutter pub run build_runner watch
```

## 测试

### 运行单元测试

```bash
flutter test
```

### 运行集成测试

```bash
flutter test integration_test/
```

### 代码分析

```bash
flutter analyze
```

## 签名与发布

### Windows 代码签名

```powershell
# 使用 signtool 签名（需要代码签名证书）
signtool sign /f certificate.pfx /p password /tr http://timestamp.digicert.com /td sha256 /fd sha256 "build\windows\x64\runner\Release\nexusroom.exe"
```

### macOS 代码签名与公证

```bash
# 签名应用
codesign --force --deep --sign "Developer ID Application: Your Name" build/macos/Build/Products/Release/NexusRoom.app

# 公证
xcrun altool --notarize-app \
  --primary-bundle-id "com.yourcompany.nexusroom" \
  --username "your-apple-id" \
  --password "app-specific-password" \
  --file NexusRoom-1.3.1.dmg
```

## 常见问题

### 1. Flutter 命令未找到

```bash
# 确保 Flutter 在 PATH 中
export PATH="$PATH:/path/to/flutter/bin"

# 验证
which flutter
flutter --version
```

### 2. 依赖冲突

```bash
# 清理并重新获取依赖
flutter clean
flutter pub get
```

### 3. 编译失败

```bash
# 清理构建缓存
flutter clean

# 删除生成的文件
find . -name "*.g.dart" -delete
find . -name "*.freezed.dart" -delete

# 重新生成代码
flutter pub run build_runner build --delete-conflicting-outputs

# 重新编译
flutter build [platform]
```

### 4. LiveKit 编译问题

Windows 平台可能需要安装 Visual Studio 2019 或更高版本，并选择 "Desktop development with C++" 工作负载。

### 5. 窗口管理器问题

macOS 需要在 `macos/Runner/DebugProfile.entitlements` 和 `Release.entitlements` 中添加：

```xml
<key>com.apple.security.network.client</key>
<true/>
```

## 调试技巧

### 启用详细日志

```dart
// 在 main.dart 中
void main() {
  // 启用详细日志
  LiveKitClient.enableVerboseLogging();
  
  runApp(const MyApp());
}
```

### 网络调试

使用 Dart DevTools：

```bash
flutter pub global activate devtools
devtools
```

然后在浏览器中打开 http://localhost:9100 查看网络请求。

## 性能优化

### 1. 发布模式构建

始终使用 `--release` 标志构建发布版本。

### 2. 减小包体积

```bash
# 分析包体积
flutter build apk --analyze-size

# 启用 tree shaking
flutter build [platform] --tree-shake-icons
```

### 3. 图片优化

- 使用 WebP 格式
- 提供多分辨率图片
- 使用 `cached_network_image` 缓存网络图片

## 参考资源

- [Flutter 官方文档](https://docs.flutter.dev/)
- [LiveKit Flutter SDK](https://github.com/livekit/client-sdk-flutter)
- [Drift 文档](https://drift.simonbinder.eu/)
- [Riverpod 文档](https://riverpod.dev/)
