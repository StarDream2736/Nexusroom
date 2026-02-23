class UploadedFile {
  const UploadedFile({
    required this.fileId,
    required this.url,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String fileId;
  final String url;
  final String mimeType;
  final int sizeBytes;

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(
      fileId: json['file_id'] as String,
      url: json['url'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
    );
  }
}
