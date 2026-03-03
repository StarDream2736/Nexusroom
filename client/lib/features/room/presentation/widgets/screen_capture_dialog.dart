import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/widgets/glass_container.dart';
import '../../../../core/models/livekit_models.dart';
import '../../../../core/native/screen_capture_service.dart';
import '../../../../core/native/screen_source_enumerator.dart';
import '../../../../core/providers/app_providers.dart';
import '../providers/screen_capture_provider.dart';

/// Dialog that lets the user configure and start screen capture streaming
/// for a specific Ingress push entry.
///
/// The user can:
///   1. Select the capture source (full screen / specific window)
///   2. Configure resolution, FPS, bitrate
///   3. Start / stop capture
///   4. Monitor real-time encoding stats
class ScreenCaptureDialog extends ConsumerStatefulWidget {
  final IngressModel ingress;

  const ScreenCaptureDialog({super.key, required this.ingress});

  @override
  ConsumerState<ScreenCaptureDialog> createState() =>
      _ScreenCaptureDialogState();
}

class _ScreenCaptureDialogState extends ConsumerState<ScreenCaptureDialog> {
  // ─── Capture settings ──────────────────────────────────────────────────
  DisplaySource? _selectedDisplay;

  int _fps = 60;
  int _bitrate = 8000;
  bool _useHwAccel = true;

  bool _isStarting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Pre-refresh display list.
    Future.microtask(() {
      ref.invalidate(displaySourcesProvider);
    });
  }

  // ─── Actions ───────────────────────────────────────────────────────────

  Future<void> _startCapture() async {
    setState(() {
      _isStarting = true;
      _error = null;
    });

    try {
      final service = ref.read(screenCaptureServiceProvider);

      final display = _selectedDisplay;
      final source = CaptureSource.fullScreen(
        displayIndex: display?.index ?? 0,
        offsetX: display?.offsetX ?? 0,
        offsetY: display?.offsetY ?? 0,
        videoSize: display?.videoSize,
      );

      await service.startCapture(
        rtmpUrl: widget.ingress.rtmpUrl,
        streamKey: widget.ingress.streamKey,
        source: source,
        fps: _fps,
        bitrate: _bitrate,
        useHwAccel: _useHwAccel,
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _stopCapture() async {
    final service = ref.read(screenCaptureServiceProvider);
    await service.stopCapture();
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(captureStatusProvider);
    final status =
        statusAsync.valueOrNull ?? ref.read(screenCaptureServiceProvider).status;
    final isStreaming = status == CaptureStatus.streaming ||
        status == CaptureStatus.starting;

    return Dialog(
      backgroundColor: AppColors.sidebar,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, minWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────
              Row(
                children: [
                  Icon(Icons.screen_share,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('屏幕捕获推流',
                        style: AppTypography.h2),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        size: 18, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '入口: ${widget.ingress.label}',
                style: TextStyle(
                    fontSize: AppTypography.sizeCaption,
                    color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),

              // ── Scrollable content ──────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isStreaming) _buildStreamingBanner(),
                      if (_error != null) _buildErrorBanner(),
                      if (!isStreaming) ...[
                        _buildSourceSelector(),
                        const SizedBox(height: 16),
                        _buildQualitySettings(),
                      ],
                      if (isStreaming) _buildStats(),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Actions ─────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 8),
                  if (!isStreaming)
                    ElevatedButton.icon(
                      onPressed: _isStarting ? null : _startCapture,
                      icon: _isStarting
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.textPrimary))
                          : const Icon(Icons.play_arrow, size: 16),
                      label: Text(_isStarting ? '启动中...' : '开始推流'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _stopCapture,
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text('停止推流'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Sub-widgets ───────────────────────────────────────────────────────

  Widget _buildStreamingBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('正在推流中...',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_error!,
                  style: TextStyle(
                      color: AppColors.error, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceSelector() {
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('捕获源', style: AppTypography.h3),
          const SizedBox(height: 10),
          _buildDisplaySelector(),
        ],
      ),
    );
  }

  Widget _buildDisplaySelector() {
    final displaysAsync = ref.watch(displaySourcesProvider);

    return displaysAsync.when(
      data: (displays) {
        // Ensure _selectedDisplay is a valid item from the current list.
        // Provider refreshes create new DisplaySource objects; with == on
        // DisplaySource, contains() performs a value comparison.
        if (_selectedDisplay == null || !displays.contains(_selectedDisplay)) {
          _selectedDisplay = displays.isNotEmpty ? displays.first : null;
        }
        return DropdownButton<DisplaySource>(
          value: _selectedDisplay,
          isExpanded: true,
          dropdownColor: AppColors.sidebar,
          style: TextStyle(
              fontSize: 13, color: AppColors.textPrimary),
          underline: Container(height: 1, color: AppColors.border),
          items: displays.map((d) {
            return DropdownMenuItem(
              value: d,
              child: Text(d.name),
            );
          }).toList(),
          onChanged: (v) => setState(() => _selectedDisplay = v),
        );
      },
      loading: () => const SizedBox(
          height: 32,
          child: Center(
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)))),
      error: (e, _) => Text('加载失败: $e',
          style: TextStyle(color: AppColors.error, fontSize: 12)),
    );
  }

  Widget _buildQualitySettings() {
    return GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('画质设置', style: AppTypography.h3),
          const SizedBox(height: 12),

          // FPS
          Row(
            children: [
              SizedBox(
                  width: 70,
                  child: Text('帧率',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary))),
              Expanded(
                child: DropdownButton<int>(
                  value: _fps,
                  isExpanded: true,
                  dropdownColor: AppColors.sidebar,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  underline: Container(height: 1, color: AppColors.border),
                  items: const [
                    DropdownMenuItem(value: 15, child: Text('15 FPS (低)')),
                    DropdownMenuItem(value: 24, child: Text('24 FPS')),
                    DropdownMenuItem(value: 30, child: Text('30 FPS')),
                    DropdownMenuItem(value: 60, child: Text('60 FPS (推荐)')),
                    DropdownMenuItem(value: 120, child: Text('120 FPS (高)')),
                  ],
                  onChanged: (v) => setState(() => _fps = v ?? 60),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Bitrate
          Row(
            children: [
              SizedBox(
                  width: 70,
                  child: Text('码率',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary))),
              Expanded(
                child: DropdownButton<int>(
                  value: _bitrate,
                  isExpanded: true,
                  dropdownColor: AppColors.sidebar,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textPrimary),
                  underline: Container(height: 1, color: AppColors.border),
                  items: const [
                    DropdownMenuItem(
                        value: 1500, child: Text('1500 kbps (流畅)')),
                    DropdownMenuItem(
                        value: 3000, child: Text('3000 kbps (标清)')),
                    DropdownMenuItem(
                        value: 5000, child: Text('5000 kbps (高清)')),
                    DropdownMenuItem(
                        value: 8000, child: Text('8000 kbps (推荐)')),
                    DropdownMenuItem(
                        value: 10000, child: Text('10000 kbps (超清)')),
                    DropdownMenuItem(
                        value: 12000, child: Text('12000 kbps (极清)')),
                  ],
                  onChanged: (v) => setState(() => _bitrate = v ?? 8000),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Hardware acceleration
          Row(
            children: [
              SizedBox(
                  width: 70,
                  child: Text('硬件加速',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary))),
              Switch(
                value: _useHwAccel,
                onChanged: (v) => setState(() => _useHwAccel = v),
                activeColor: AppColors.primary,
              ),
              Text(
                _useHwAccel ? 'NVENC (需要 NVIDIA 显卡)' : '软件编码 (x264)',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final statsAsync = ref.watch(captureStatsProvider);
    final stats = statsAsync.valueOrNull;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: GlassContainer(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('推流状态', style: AppTypography.h3),
            const SizedBox(height: 10),
            if (stats != null)
              Row(
                children: [
                  _StatChip(label: 'FPS', value: stats.fps.toStringAsFixed(1)),
                  const SizedBox(width: 12),
                  _StatChip(
                      label: '码率',
                      value: '${stats.bitrateKbps.toStringAsFixed(0)} kbps'),
                  const SizedBox(width: 12),
                  _StatChip(label: '时长', value: stats.elapsed),
                  const SizedBox(width: 12),
                  _StatChip(
                      label: '帧数', value: stats.totalFrames.toString()),
                ],
              )
            else
              Text('等待数据...',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }
}
