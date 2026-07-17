import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Owns every persistent path created by the desktop client.
class AppDataPaths {
  AppDataPaths._();

  static const applicationDirectoryName = 'NexusRoom';
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
    final target = File(path.join(directory.path, databaseFileName));
    final candidates = <File>[];

    // 2.1.0 briefly stored the database below the operating system's
    // application-data directory. Keep it as the first migration source.
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.trim().isNotEmpty) {
      candidates.add(
        File(
          path.join(
            localAppData,
            applicationDirectoryName,
            dataDirectoryName,
            databaseFileName,
          ),
        ),
      );
    }

    final supportDirectory = await getApplicationSupportDirectory();
    candidates.add(
      File(
        path.join(
          supportDirectory.path,
          dataDirectoryName,
          databaseFileName,
        ),
      ),
    );
    final legacyDirectory = await getApplicationDocumentsDirectory();
    candidates.add(File(path.join(legacyDirectory.path, databaseFileName)));

    return migrateFirstAvailableDatabase(
      target: target,
      legacyCandidates: candidates,
    );
  }

  static Future<File> migrateFirstAvailableDatabase({
    required File target,
    required Iterable<File> legacyCandidates,
  }) async {
    final targetPath = path.canonicalize(target.absolute.path);
    for (final legacy in legacyCandidates) {
      if (path.canonicalize(legacy.absolute.path) == targetPath) continue;
      await migrateLegacyDatabase(target: target, legacy: legacy);
      if (await target.exists()) break;
    }
    return target;
  }

  /// Moves a database from an older storage location before Drift opens it.
  /// SQLite sidecars are moved with the main file so an interrupted WAL can
  /// still be recovered normally.
  static Future<File> migrateLegacyDatabase({
    required File target,
    required File legacy,
  }) async {
    await target.parent.create(recursive: true);
    if (await target.exists() || !await legacy.exists()) return target;

    final temporary = File('${target.path}.migrating');
    final suffixes = <String>['-wal', '-shm'];
    await _deleteIfPresent(temporary);
    for (final suffix in suffixes) {
      await _deleteIfPresent(File('${temporary.path}$suffix'));
      await _deleteIfPresent(File('${target.path}$suffix'));
    }

    await legacy.copy(temporary.path);
    for (final suffix in suffixes) {
      final source = File('${legacy.path}$suffix');
      if (await source.exists()) {
        await source.copy('${temporary.path}$suffix');
      }
    }

    for (final suffix in suffixes) {
      final sidecar = File('${temporary.path}$suffix');
      if (await sidecar.exists()) {
        await sidecar.rename('${target.path}$suffix');
      }
    }
    await temporary.rename(target.path);

    await _deleteIfPresent(legacy);
    for (final suffix in suffixes) {
      await _deleteIfPresent(File('${legacy.path}$suffix'));
    }
    return target;
  }

  static Future<void> _deleteIfPresent(File file) async {
    if (await file.exists()) await file.delete();
  }
}
