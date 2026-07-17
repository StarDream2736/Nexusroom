import 'dart:io';

import 'package:path/path.dart' as path;

/// Owns every persistent path created by the desktop client.
class AppDataPaths {
  AppDataPaths._();

  static const dataDirectoryName = 'data';
  static const databaseFileName = 'nexusroom.sqlite';

  static Future<Directory> dataDirectory() async {
    final directory = dataDirectoryForExecutable(Platform.resolvedExecutable);
    await directory.create(recursive: true);
    return directory;
  }

  static Directory dataDirectoryForExecutable(String executablePath) {
    final executableDirectory = File(executablePath).absolute.parent;
    return Directory(path.join(executableDirectory.path, dataDirectoryName));
  }

  static Future<File> databaseFile() async {
    final directory = await dataDirectory();
    return File(path.join(directory.path, databaseFileName));
  }
}
