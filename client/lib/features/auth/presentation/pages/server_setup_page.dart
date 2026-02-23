import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_providers.dart';

class ServerSetupPage extends ConsumerStatefulWidget {
  const ServerSetupPage({super.key});

  @override
  ConsumerState<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends ConsumerState<ServerSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  bool _isLoading = false;
  bool _hasNavigated = false;

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final serverUrl = _serverUrlController.text.trim();
      print('🔍 Pinging server: $serverUrl');

      await ref.read(apiClientProvider).ping(serverUrl);
      print('✅ Ping successful');

      await ref.read(appSettingsProvider.notifier).setServerUrl(serverUrl);
      print('✅ Settings saved');
      print('✅ Waiting for settings to update...');
      
    } catch (e, st) {
      print('❌ Error: $e');
      print('Stack trace: $st');
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
    // 监听设置变化，当服务器 URL 设置成功后导航
    final settings = ref.watch(appSettingsProvider);
    
    settings.whenData((value) {
      if (value.hasServerUrl && !_hasNavigated && mounted) {
        _hasNavigated = true;
        print('🚀 Server configured, navigating to login');
        Future.microtask(() {
          if (mounted) {
            context.go('/login');
          }
        });
      }
    });

    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Colors.deepPurple,
                ),
                const SizedBox(height: 24),
                
                // 标题
                const Text(
                  'NexusRoom',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '配置您的服务器',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 48),
                
                // 服务器地址输入
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
                    if (!value.startsWith('http://') && !value.startsWith('https://')) {
                      return '地址必须以 http:// 或 https:// 开头';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                
                // 连接按钮
                ElevatedButton(
                  onPressed: _isLoading ? null : _connect,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('连接'),
                ),
                const SizedBox(height: 16),
                
                // 提示
                const Text(
                  '请输入 NexusRoom 服务器的地址',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
