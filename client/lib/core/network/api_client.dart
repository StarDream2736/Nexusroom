import 'package:dio/dio.dart';

import 'api_response.dart';

class ApiClient {
  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  late final Dio _dio;

  String? get baseUrl => _dio.options.baseUrl.isEmpty ? null : _dio.options.baseUrl;

  void updateConfig({String? baseUrl, String? token}) {
    if (baseUrl != null && baseUrl.isNotEmpty) {
      _dio.options.baseUrl = baseUrl;
    }
    if (token != null && token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  Future<void> ping(String serverUrl) async {
    final dio = Dio(BaseOptions(
      baseUrl: serverUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ));

    final response = await dio.get('/ping');
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

  dynamic _unwrap(dynamic responseData) {
    if (responseData is! Map<String, dynamic>) {
      throw ApiException('Invalid server response');
    }

    final code = responseData['code'] as int? ?? 0;
    final message = responseData['message'] as String? ?? 'Unknown error';
    if (code != 20000) {
      throw ApiException(message);
    }

    return responseData['data'];
  }
}
