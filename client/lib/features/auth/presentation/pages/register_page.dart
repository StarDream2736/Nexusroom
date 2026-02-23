import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_providers.dart';
import '../providers/auth_controller.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _adminTokenController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    _adminTokenController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      final nickname = _nicknameController.text.trim();
      final adminToken = _adminTokenController.text.trim();

      await ref.read(authControllerProvider).register(
            username: username,
            password: password,
            nickname: nickname,
            adminToken: adminToken.isEmpty ? null : adminToken,
          );
      // 导航由 app_router 的 redirect 自动处理
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('注册失败: $e')),
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
      appBar: AppBar(
        title: const Text('注册账号'),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 昵称输入
                  TextFormField(
                    controller: _nicknameController,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      prefixIcon: Icon(Icons.face),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入昵称';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // 用户名输入
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入用户名';
                      }
                      if (value.length < 3) {
                        return '用户名至少3个字符';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // 密码输入
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入密码';
                      }
                      if (value.length < 6) {
                        return '密码至少6个字符';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // 管理员令牌（可选）
                  TextFormField(
                    controller: _adminTokenController,
                    decoration: const InputDecoration(
                      labelText: '管理员令牌（可选）',
                      prefixIcon: Icon(Icons.admin_panel_settings),
                      hintText: '如需注册为管理员，请输入令牌',
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 注册按钮
                  ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('注册'),
                  ),
                  const SizedBox(height: 16),
                  
                  // 登录链接
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('已有账号？'),
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('立即登录'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // 返回服务器配置
                  TextButton(
                    onPressed: () async {
                      // 清除认证信息后跳转到服务器配置
                      await ref.read(appSettingsProvider.notifier).clearAuth();
                      if (context.mounted) {
                        context.go('/setup');
                      }
                    },
                    child: const Text('更换服务器'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
