import 'dart:io';

import 'package:flutter/foundation.dart';

/// Enumerates available screen-capture sources (displays).
///
/// On Windows this uses PowerShell to list connected monitors.
/// The results are lightweight value objects that can be passed to
/// [ScreenCaptureService.startCapture].
class ScreenSourceEnumerator {
  /// List connected displays / monitors.
  ///
  /// On Windows this uses PowerShell with WMI to get display info.
  /// Each [DisplaySource] contains the index, resolution, and screen offset
  /// needed by FFmpeg's `-offset_x` / `-offset_y` / `-video_size` params.
  static Future<List<DisplaySource>> listDisplays() async {
    if (!Platform.isWindows) {
      // Fallback: return a single "primary" display.
      return [
        const DisplaySource(
          index: 0,
          name: '主显示器',
          width: 1920,
          height: 1080,
          offsetX: 0,
          offsetY: 0,
        ),
      ];
    }

    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        r'''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Screen]::AllScreens | ForEach-Object {
  "$($_.DeviceName)|$($_.Bounds.Width)|$($_.Bounds.Height)|$($_.Bounds.X)|$($_.Bounds.Y)|$($_.Primary)"
}
'''
      ]);

      if (result.exitCode != 0) {
        debugPrint('[ScreenSourceEnum] PowerShell error: ${result.stderr}');
        return _fallbackDisplay();
      }

      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && l.contains('|'));

      final displays = <DisplaySource>[];
      int idx = 0;
      for (final line in lines) {
        final parts = line.split('|');
        if (parts.length < 6) continue;

        final deviceName = parts[0];
        final width = int.tryParse(parts[1]) ?? 1920;
        final height = int.tryParse(parts[2]) ?? 1080;
        final offsetX = int.tryParse(parts[3]) ?? 0;
        final offsetY = int.tryParse(parts[4]) ?? 0;
        final primary = parts[5].toLowerCase() == 'true';

        final label = primary
            ? '主显示器 ($width×$height)'
            : '显示器 ${idx + 1} ($width×$height)';

        displays.add(DisplaySource(
          index: idx,
          name: label,
          deviceName: deviceName,
          width: width,
          height: height,
          offsetX: offsetX,
          offsetY: offsetY,
        ));
        idx++;
      }

      if (displays.isEmpty) return _fallbackDisplay();

      // Put primary display first.
      displays.sort((a, b) {
        if (a.offsetX == 0 && a.offsetY == 0) return -1;
        if (b.offsetX == 0 && b.offsetY == 0) return 1;
        return a.index.compareTo(b.index);
      });

      return displays;
    } catch (e) {
      debugPrint('[ScreenSourceEnum] Failed to enumerate displays: $e');
      return _fallbackDisplay();
    }
  }

  static List<DisplaySource> _fallbackDisplay() {
    return [
      const DisplaySource(
        index: 0,
        name: '主显示器',
        width: 1920,
        height: 1080,
        offsetX: 0,
        offsetY: 0,
      ),
    ];
  }
}

// ─── Data classes ──────────────────────────────────────────────────────────

class DisplaySource {
  final int index;
  final String name;
  final String? deviceName;
  final int width;
  final int height;
  final int offsetX;
  final int offsetY;

  const DisplaySource({
    required this.index,
    required this.name,
    this.deviceName,
    required this.width,
    required this.height,
    required this.offsetX,
    required this.offsetY,
  });

  /// FFmpeg video_size parameter.
  String get videoSize => '${width}x$height';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplaySource &&
          index == other.index &&
          width == other.width &&
          height == other.height &&
          offsetX == other.offsetX &&
          offsetY == other.offsetY;

  @override
  int get hashCode => Object.hash(index, width, height, offsetX, offsetY);

  @override
  String toString() =>
      'DisplaySource($name, ${width}x$height @ $offsetX,$offsetY)';
}
