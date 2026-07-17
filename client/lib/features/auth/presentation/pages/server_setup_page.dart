import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/widgets/glass_container.dart';
import '../../../../app/widgets/title_bar.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/network/api_client.dart';

class ServerSetupPage extends ConsumerStatefulWidget {
  const ServerSetupPage({super.key});

  @override
  ConsumerState<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends ConsumerState<ServerSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final serverUrl = ApiClient.normalizeServerUrl(_serverUrlController.text);
      await ref.read(apiClientProvider).ping(serverUrl);
      await ref.read(appSettingsProvider.notifier).setServerUrl(serverUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const TitleBar(),
          Expanded(
            child: Center(
              child: GlassContainer(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.chat_bubble_outline,
                          size: 52, color: AppColors.accent),
                      const SizedBox(height: 18),
                      Text('NexusRoom',
                          textAlign: TextAlign.center, style: AppTypography.h1),
                      const SizedBox(height: 6),
                      Text('配置您的服务器',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySecondary),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _serverUrlController,
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          hintText: 'http://your-server-ip:8080',
                          prefixIcon: Icon(Icons.link),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入服务器地址';
                          }
                          try {
                            ApiClient.normalizeServerUrl(value);
                          } catch (error) {
                            return error.toString();
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _connect,
                        child: _isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('连接'),
                      ),
                      const SizedBox(height: 14),
                      Text('请输入 NexusRoom 服务器的地址',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: AppTypography.sizeCaption,
                              color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
