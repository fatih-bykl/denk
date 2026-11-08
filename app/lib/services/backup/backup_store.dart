import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;

/// Drive'daki bir yedek dosyası.
class BackupFile {
  const BackupFile({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;
}

/// Yedeklerin durduğu yer. Uygulamada Google Drive'ın gizli uygulama klasörü,
/// testlerde bellekteki sahte depo.
abstract interface class BackupStore {
  /// Yeniden eskiye sıralı.
  Future<List<BackupFile>> list();
  Future<void> upload(String name, File file);
  Future<void> download(String id, File target);
  Future<void> delete(String id);
}

/// Google Drive'daki `appDataFolder`: kullanıcının Drive'ında yalnızca Denk'in
/// görebildiği gizli klasör. Denk, Drive'daki diğer dosyalara erişemez.
class DriveBackupStore implements BackupStore {
  DriveBackupStore(this._api);

  final drive.DriveApi _api;

  static const _folder = 'appDataFolder';

  @override
  Future<List<BackupFile>> list() async {
    final result = await _api.files.list(
      spaces: _folder,
      orderBy: 'createdTime desc',
      pageSize: 100,
      $fields: 'files(id,name,createdTime,size)',
    );
    return [
      for (final f in result.files ?? const <drive.File>[])
        BackupFile(
          id: f.id!,
          name: f.name ?? '',
          createdAt: (f.createdTime ?? DateTime.now()).toLocal(),
          sizeBytes: int.tryParse(f.size ?? '') ?? 0,
        ),
    ];
  }

  @override
  Future<void> upload(String name, File file) async {
    final meta = drive.File()
      ..name = name
      ..parents = [_folder];
    await _api.files.create(
      meta,
      uploadMedia: drive.Media(
        file.openRead(),
        await file.length(),
        contentType: 'application/x-sqlite3',
      ),
    );
  }

  @override
  Future<void> download(String id, File target) async {
    final media = await _api.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final sink = target.openWrite();
    try {
      await media.stream.pipe(sink);
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> delete(String id) => _api.files.delete(id);
}
