import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'screen_source_enumerator.dart';

/// FFmpeg-based screen capture and RTMP streaming service.
///
/// Launches an ffmpeg subprocess to capture the desktop (or a specific window)
/// and push an RTMP stream to SRS.  The resulting stream is consumed by other
/// clients through the existing HTTP-FLV pipeline (Go reverse-proxy → media_kit).
///
/// This follows the same "embedded helper binary" pattern used by
/// [WireGuardService] – ffmpeg.exe is shipped alongside the Flutter executable.
class ScreenCaptureService {
  Process? _ffmpegProcess;
  StreamSubscription? _stderrSub;

  final _statusController = StreamController<CaptureStatus>.broadcast();
  final _statsController = StreamController<CaptureStats>.broadcast();

  CaptureStatus _status = CaptureStatus.idle;
  String? _activeStreamKey;

  // ─── Public API ──────────────────────────────────────────────────────────

  CaptureStatus get status => _status;
  String? get activeStreamKey => _activeStreamKey;
  Stream<CaptureStatus> get statusStream => _statusController.stream;
  Stream<CaptureStats> get statsStream => _statsController.stream;

  /// Whether ffmpeg.exe exists next to the application binary.
  bool get isAvailable => File(_ffmpegPath).existsSync();

  // ─── Paths ───────────────────────────────────────────────────────────────

  String get _ffmpegPath {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return p.join(exeDir, 'ffmpeg.exe');
  }

  // ─── Start capture ──────────────────────────────────────────────────────

  /// Begin screen capture and push an RTMP stream to [rtmpUrl]/[streamKey].
  ///
  /// [source] selects what to capture:
  ///   • `CaptureSource.fullScreen(index)` – entire display
  ///   • `CaptureSource.window(title)`     – a specific window
  ///
  /// Optional parameters control encoding quality:
  ///   • [fps]       – frame rate (default 60)
  ///   • [bitrate]   – video bitrate in kbps (default 3000)
  ///   • [preset]    – x264 preset (default "veryfast")
  ///   • [useHwAccel] – attempt NVENC hardware encoding (default false)
  ///   • [captureSystemAudio] – capture desktop audio via dshow (default true)
  ///   • [captureMicrophone]  – capture microphone via dshow (default false)
  ///   • [systemAudioDevice]  – dshow device name for system audio
  ///   • [micDevice]          – dshow device name for microphone
  Future<void> startCapture({
    required String rtmpUrl,
    required String streamKey,
    CaptureSource source = const CaptureSource.fullScreen(),
    int fps = 60,
    int bitrate = 3000,
    String preset = 'veryfast',
    bool useHwAccel = false,
    bool captureSystemAudio = true,
    bool captureMicrophone = false,
    String? systemAudioDevice,
    String? micDevice,
  }) async {
    if (_ffmpegProcess != null) {
      await stopCapture();
    }

    final ffmpeg = _ffmpegPath;
    if (!File(ffmpeg).existsSync()) {
      throw ScreenCaptureException('ffmpeg.exe not found at: $ffmpeg');
    }

    _setStatus(CaptureStatus.starting);
    _activeStreamKey = streamKey;

    // Build the full RTMP destination URL.
    // rtmpUrl typically ends with "/live/", streamKey is appended.
    final destination = rtmpUrl.endsWith('/')
        ? '$rtmpUrl$streamKey'
        : '$rtmpUrl/$streamKey';

    final args = <String>[];

    // ── Input ────────────────────────────────────────────────────────────
    if (Platform.isWindows) {
      // Real-time buffer: gdigrab is a real-time capture source.  Without a
      // large buffer, frames are dropped when the encoder stalls momentarily
      // (e.g. encoding a complex frame).  150 MB holds ~2 seconds of raw
      // 1080p BGRA frames, preventing capture-side frame drops.
      args.addAll(['-rtbufsize', '150M']);
      // Thread queue: number of frames buffered in the input thread before
      // the encoder consumes them.  Default is too small for real-time.
      args.addAll(['-thread_queue_size', '1024']);

      // gdigrab for Windows – reliable software-mode capture.
      args.addAll(['-f', 'gdigrab']);
      args.addAll(['-framerate', '$fps']);
      // Capture the mouse cursor for utility (can be toggled off later).
      args.addAll(['-draw_mouse', '1']);

      if (source.isWindow) {
        args.addAll(['-i', 'title=${source.windowTitle}']);
      } else {
        // Full-screen capture (optionally a specific monitor offset).
        if (source.displayIndex > 0) {
          args.addAll(['-offset_x', '${source.offsetX}']);
          args.addAll(['-offset_y', '${source.offsetY}']);
          args.addAll(['-video_size', source.videoSize ?? '1920x1080']);
        }
        args.addAll(['-i', 'desktop']);
      }
    } else {
      // macOS / Linux – avfoundation / x11grab (future-proof).
      args.addAll(['-f', 'avfoundation']);
      args.addAll(['-framerate', '$fps']);
      args.addAll(['-i', source.isWindow ? source.windowTitle! : '1']);
    }

    // ── Video filter ─────────────────────────────────────────────────────
    // 1. fps=$fps  — resample gdigrab's irregular VFR output to exact
    //    constant frame rate.  This is more reliable than `-fps_mode cfr`
    //    because it actually re-timestamps and duplicates/drops frames
    //    instead of merely adjusting DTS values.
    // 2. pad=ceil(iw/2)*2:ceil(ih/2)*2  — libx264 requires even dimensions.
    //    Window capture can produce any size (e.g. 1471x982).
    args.addAll(['-vf', 'fps=$fps,pad=ceil(iw/2)*2:ceil(ih/2)*2']);

    // ── Audio inputs (dshow) ────────────────────────────────────────
    // Audio inputs are added AFTER the video input so that the video is
    // always stream 0:v and audio streams are 1:a, 2:a, etc.
    int audioInputCount = 0;
    if (captureSystemAudio && Platform.isWindows) {
      String? device = systemAudioDevice;
      if (device == null) {
        // Auto-detect: use the first available dshow audio device.
        final devices = await ScreenSourceEnumerator.listAudioDevices();
        if (devices.isNotEmpty) {
          device = devices.first.name;
        }
      }
      if (device != null) {
        args.addAll(['-thread_queue_size', '1024']);
        args.addAll(['-f', 'dshow']);
        args.addAll(['-audio_buffer_size', '50']);
        args.addAll(['-i', 'audio=$device']);
        audioInputCount++;
      }
    }
    if (captureMicrophone && Platform.isWindows) {
      final device = micDevice ?? 'Microphone';
      args.addAll(['-thread_queue_size', '1024']);
      args.addAll(['-f', 'dshow']);
      args.addAll(['-audio_buffer_size', '50']);
      args.addAll(['-i', 'audio=$device']);
      audioInputCount++;
    }

    // ── Encoding ─────────────────────────────────────────────────────────
    if (useHwAccel && Platform.isWindows) {
      // Try NVIDIA NVENC; if the GPU doesn't support it ffmpeg will exit and
      // we can fall back to software.
      args.addAll(['-c:v', 'h264_nvenc']);
      args.addAll(['-preset', 'p4']); // NVENC preset
      args.addAll(['-rc', 'vbr']);
      args.addAll(['-cq', '20']); // quality-based with VBV cap
      args.addAll(['-b:v', '${bitrate}k']);
      args.addAll(['-maxrate', '${bitrate}k']);
      args.addAll(['-bufsize', '${bitrate * 2}k']);
    } else {
      args.addAll(['-c:v', 'libx264']);
      args.addAll(['-preset', preset]);
      args.addAll(['-tune', 'zerolatency']);
      // CRF + VBV mode: CRF sets quality target, maxrate caps the peak.
      // This avoids the ABR problem where static scenes get far less than
      // the requested bitrate.  CRF 18 is near-visually-lossless; the
      // encoder will use whatever bitrate is needed (up to maxrate) to
      // maintain that quality.
      args.addAll(['-crf', '18']);
      args.addAll(['-maxrate', '${bitrate}k']);
      args.addAll(['-bufsize', '${bitrate * 2}k']);
    }

    args.addAll(['-pix_fmt', 'yuv420p']);
    args.addAll(['-g', '${fps * 2}']); // keyframe interval

    // ── Audio encoding ─────────────────────────────────────────────────
    if (audioInputCount == 0) {
      args.addAll(['-an']);
    } else {
      if (audioInputCount == 2) {
        // Mix both audio inputs into a single stereo stream.
        // Input 0 is video, input 1 is first audio, input 2 is second.
        args.addAll([
          '-filter_complex', '[1:a][2:a]amix=inputs=2:duration=longest[aout]',
          '-map', '0:v',
          '-map', '[aout]',
        ]);
      }
      args.addAll(['-c:a', 'aac']);
      args.addAll(['-b:a', '128k']);
      args.addAll(['-ar', '44100']);
    }

    // ── Output ───────────────────────────────────────────────────────────
    // -flvflags no_duration_filesize: required for live FLV streaming to
    // prevent the muxer from trying to write duration at file end.
    args.addAll(['-flvflags', 'no_duration_filesize']);
    args.addAll(['-f', 'flv', destination]);

    debugPrint('[ScreenCapture] Starting: $ffmpeg ${args.join(' ')}');

    try {
      _ffmpegProcess = await Process.start(ffmpeg, args);

      // Parse FFmpeg stderr for progress stats.
      _stderrSub = _ffmpegProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_parseStderr);

      // Monitor process exit.
      _ffmpegProcess!.exitCode.then((code) {
        debugPrint('[ScreenCapture] FFmpeg exited with code $code');
        if (_status != CaptureStatus.stopping) {
          _setStatus(code == 0 ? CaptureStatus.idle : CaptureStatus.error);
        } else {
          _setStatus(CaptureStatus.idle);
        }
        _cleanup();
      });

      // Give FFmpeg a moment to start up; if it doesn't crash immediately,
      // consider it running.
      await Future.delayed(const Duration(milliseconds: 1500));
      if (_ffmpegProcess != null) {
        _setStatus(CaptureStatus.streaming);
      }
    } catch (e) {
      debugPrint('[ScreenCapture] Failed to start: $e');
      _setStatus(CaptureStatus.error);
      _cleanup();
      rethrow;
    }
  }

  // ─── Stop capture ───────────────────────────────────────────────────────

  /// Gracefully stop the running capture.
  Future<void> stopCapture() async {
    if (_ffmpegProcess == null) return;

    _setStatus(CaptureStatus.stopping);

    try {
      // Send 'q' to FFmpeg stdin for a graceful shutdown.
      _ffmpegProcess!.stdin.writeln('q');
      await _ffmpegProcess!.stdin.flush();

      // Wait up to 5 seconds for FFmpeg to finish.
      final exitCode = await _ffmpegProcess!.exitCode
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('[ScreenCapture] FFmpeg did not exit in time, killing');
        _ffmpegProcess?.kill(ProcessSignal.sigkill);
        return -1;
      });
      debugPrint('[ScreenCapture] FFmpeg stopped (exit $exitCode)');
    } catch (e) {
      debugPrint('[ScreenCapture] Error stopping: $e');
      _ffmpegProcess?.kill();
    }

    _cleanup();
    _setStatus(CaptureStatus.idle);
  }

  // ─── Dispose ────────────────────────────────────────────────────────────

  /// Synchronously kill FFmpeg and release resources.
  ///
  /// This is called by the Riverpod provider's `onDispose`.  We MUST kill
  /// the process synchronously here because the app may be shutting down
  /// and an async `stopCapture()` would never complete, leaving FFmpeg
  /// running in the background.
  void dispose() {
    _ffmpegProcess?.kill();
    _stderrSub?.cancel();
    _stderrSub = null;
    _ffmpegProcess = null;
    _activeStreamKey = null;
    _statusController.close();
    _statsController.close();
  }

  // ─── Internals ──────────────────────────────────────────────────────────

  void _setStatus(CaptureStatus status) {
    if (_status == status) return;
    _status = status;
    _statusController.add(status);
    debugPrint('[ScreenCapture] Status → $status');
  }

  void _cleanup() {
    _stderrSub?.cancel();
    _stderrSub = null;
    _ffmpegProcess = null;
    _activeStreamKey = null;
  }

  /// Parse FFmpeg stderr lines to extract encoding stats.
  ///
  /// Example FFmpeg progress line:
  /// ```
  /// frame=  120 fps= 30 q=28.0 size=    768kB time=00:00:04.00 bitrate=1572.9kbits/s speed=1.00x
  /// ```
  void _parseStderr(String line) {
    // Only parse progress lines (contain "frame=" and "fps=").
    if (!line.contains('frame=') || !line.contains('fps=')) {
      // Still log diagnostic messages.
      if (line.isNotEmpty) {
        debugPrint('[FFmpeg] $line');
      }
      return;
    }

    try {
      final fpsMatch = RegExp(r'fps=\s*([\d.]+)').firstMatch(line);
      final bitrateMatch =
          RegExp(r'bitrate=\s*([\d.]+)kbits/s').firstMatch(line);
      final frameMatch = RegExp(r'frame=\s*(\d+)').firstMatch(line);
      final timeMatch = RegExp(r'time=(\S+)').firstMatch(line);

      _statsController.add(CaptureStats(
        fps: double.tryParse(fpsMatch?.group(1) ?? '') ?? 0,
        bitrateKbps: double.tryParse(bitrateMatch?.group(1) ?? '') ?? 0,
        totalFrames: int.tryParse(frameMatch?.group(1) ?? '') ?? 0,
        elapsed: timeMatch?.group(1) ?? '00:00:00',
      ));
    } catch (_) {
      // Silently ignore parse errors.
    }
  }
}

// ─── Data classes ──────────────────────────────────────────────────────────

enum CaptureStatus {
  idle,
  starting,
  streaming,
  stopping,
  error,
}

/// Describes what to capture.
class CaptureSource {
  final String? windowTitle;
  final int displayIndex;
  final int offsetX;
  final int offsetY;
  final String? videoSize;

  /// Capture the entire primary screen (or a specific display by index).
  const CaptureSource.fullScreen({
    this.displayIndex = 0,
    this.offsetX = 0,
    this.offsetY = 0,
    this.videoSize,
  }) : windowTitle = null;

  /// Capture a specific window by its title.
  const CaptureSource.window(String title)
      : windowTitle = title,
        displayIndex = 0,
        offsetX = 0,
        offsetY = 0,
        videoSize = null;

  bool get isWindow => windowTitle != null;

  @override
  String toString() => isWindow
      ? 'CaptureSource.window("$windowTitle")'
      : 'CaptureSource.fullScreen($displayIndex)';
}

/// Encoding statistics parsed from FFmpeg stderr.
class CaptureStats {
  final double fps;
  final double bitrateKbps;
  final int totalFrames;
  final String elapsed;

  const CaptureStats({
    required this.fps,
    required this.bitrateKbps,
    required this.totalFrames,
    required this.elapsed,
  });

  @override
  String toString() =>
      'CaptureStats(fps=$fps, bitrate=${bitrateKbps}kbps, frames=$totalFrames, elapsed=$elapsed)';
}

class ScreenCaptureException implements Exception {
  final String message;
  const ScreenCaptureException(this.message);
  @override
  String toString() => 'ScreenCaptureException: $message';
}
