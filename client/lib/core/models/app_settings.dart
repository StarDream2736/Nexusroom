enum AppColorMode {
  dark,
  light;

  static AppColorMode fromStorage(String? value) =>
      value == AppColorMode.light.name ? AppColorMode.light : AppColorMode.dark;
}

class AppSettings {
  const AppSettings({
    this.serverUrl,
    this.token,
    this.userId,
    this.userDisplayId,
    this.username,
    this.nickname,
    this.avatarUrl,
    this.audioInputDeviceId,
    this.audioOutputDeviceId,
    this.colorMode = AppColorMode.dark,
  });

  final String? serverUrl;
  final String? token;
  final int? userId;
  final String? userDisplayId;
  final String? username;
  final String? nickname;
  final String? avatarUrl;
  final String? audioInputDeviceId;
  final String? audioOutputDeviceId;
  final AppColorMode colorMode;

  bool get hasServerUrl => serverUrl != null && serverUrl!.isNotEmpty;
  bool get hasToken => token != null && token!.isNotEmpty;
}
