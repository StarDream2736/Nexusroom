import 'package:dio/dio.dart';

import '../models/file_models.dart';
import '../network/api_client.dart';

class FileRepository {
  FileRepository(this._client);

  final ApiClient _client;

  Future<UploadedFile> uploadFile(String path, {required int roomId}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(path),
      'room_id': roomId,
    });

    final data = await _client.postForm('/api/v1/files/upload', formData);
    final file = UploadedFile.fromJson(data as Map<String, dynamic>);
    if (file.url.startsWith('/') && _client.baseUrl != null) {
      return UploadedFile(
        fileId: file.fileId,
        url: '${_client.baseUrl}${file.url}',
        mimeType: file.mimeType,
        sizeBytes: file.sizeBytes,
      );
    }
    return file;
  }
}
