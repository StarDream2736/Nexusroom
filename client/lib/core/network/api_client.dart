import 'package:dio/dio.dart';

import 'api_response.dart';

class ApiClient {
  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      // 接受所有 HTTP 状态码，由 _unwrap 统一处理业务错误
      validateStatus: (status) => true,
    ));
  }

  late final Dio _dio;

  String? get baseUrl =>
      _dio.options.baseUrl.isEmpty ? null : _dio.options.baseUrl;

  static String normalizeServerUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const ApiException('请输入有效的服务器根地址，例如 http://host:8080');
    }
    return uri.replace(path: '', query: null, fragment: null).toString();
  }

  void updateConfig({String? baseUrl, String? token}) {
    _dio.options.baseUrl =
        baseUrl == null || baseUrl.isEmpty ? '' : normalizeServerUrl(baseUrl);
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  Future<void> ping(String serverUrl) async {
    final normalizedUrl = normalizeServerUrl(serverUrl);
    final dio = Dio(BaseOptions(
      baseUrl: normalizedUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (status) => true,
    ));

    final response = await dio.get('/ping');
    if (response.statusCode != 200 || response.data is! Map<String, dynamic>) {
      throw ApiException('服务器健康检查失败（HTTP ${response.statusCode ?? '未知'}）');
    }
    final data = response.data as Map<String, dynamic>;
    if (data['code'] != 20000) {
      throw ApiException(data['message'] as String? ?? 'Ping failed');
    }
  }

  Future<dynamic> getData(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _dio.get(path, queryParameters: queryParameters);
    return _unwrap(response.data);
  }

  Future<dynamic> postData(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _dio.post(path, data: body ?? {});
    return _unwrap(response.data);
  }

  Future<dynamic> postForm(String path, FormData data) async {
    final response = await _dio.post(path, data: data);
    return _unwrap(response.data);
  }

  Future<dynamic> patchData(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _dio.patch(path, data: body ?? {});
    return _unwrap(response.data);
  }

  Future<dynamic> deleteData(String path) async {
    final response = await _dio.delete(path);
    return _unwrap(response.data);
  }

  dynamic _unwrap(dynamic responseData) {
    if (responseData is! Map<String, dynamic>) {
      throw const ApiException('Invalid server response');
    }

    final code = (responseData['code'] as num?)?.toInt() ?? 0;
    final message = responseData['message'] as String? ?? 'Unknown error';
    if (code != 20000) {
      throw ApiException(message);
    }

    return responseData['data'];
  }
}
