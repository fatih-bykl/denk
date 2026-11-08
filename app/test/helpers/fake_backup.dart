import 'dart:io';
import 'dart:typed_data';

import 'package:denk/core/database/app_database.dart';
import 'package:denk/services/backup/backup_controller.dart';
import 'package:denk/services/backup/backup_store.dart';
import 'package:denk/services/backup/drive_connection.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:googleapis/drive/v3.dart' as drive show DetailedApiRequestError;

/// Bellekteki sahte Drive klasörü.
class FakeBackupStore implements BackupStore {
  final files = <String, (BackupFile, Uint8List)>{};
  var _clock = DateTime(2026, 11, 8, 10);
  var _nextId = 0;

  /// Bir sonraki yüklemede fırlatılacak hata.
  Object? failNextUpload;

  /// Bu kadar çağrı boyunca 401 (süresi dolmuş anahtar) döndürür.
  int unauthorizedCalls = 0;

  int uploads = 0;

  void _maybe401() {
    if (unauthorizedCalls > 0) {
      unauthorizedCalls--;
      throw drive.DetailedApiRequestError(401, 'expired');
    }
  }

  /// Testte doğrudan bir yedek dosyası ekler.
  BackupFile add(String name, Uint8List bytes) {
    _clock = _clock.add(const Duration(minutes: 1));
    final file = BackupFile(
      id: 'f${_nextId++}',
      name: name,
      createdAt: _clock,
      sizeBytes: bytes.length,
    );
    files[file.id] = (file, bytes);
    return file;
  }

  @override
  Future<List<BackupFile>> list() async {
    _maybe401();
    final all = files.values.map((e) => e.$1).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  @override
  Future<void> upload(String name, File file) async {
    _maybe401();
    final error = failNextUpload;
    if (error != null) {
      failNextUpload = null;
      throw error;
    }
    uploads++;
    add(name, file.readAsBytesSync());
  }

  @override
  Future<void> download(String id, File target) async {
    _maybe401();
    target.writeAsBytesSync(files[id]!.$2);
  }

  @override
  Future<void> delete(String id) async {
    _maybe401();
    files.remove(id);
  }
}

class FakeDriveConnection implements DriveConnection {
  FakeDriveConnection({FakeBackupStore? store, this.configured = true})
    : store = store ?? FakeBackupStore();

  final FakeBackupStore store;
  final bool configured;

  /// `connect` sonucu; `null` kullanıcı vazgeçti demek.
  String? email = 'ayse@gmail.com';
  bool signedIn = false;
  int forgotTokens = 0;
  bool disconnected = false;

  @override
  bool get isConfigured => configured;

  @override
  Future<String?> connect() async {
    if (email != null) signedIn = true;
    return email;
  }

  @override
  Future<String?> restoreSilently() async => signedIn ? email : null;

  @override
  Future<BackupStore> open({required bool interactive}) async {
    if (!signedIn && !interactive) throw const BackupNeedsSignIn();
    signedIn = true;
    return store;
  }

  @override
  Future<void> forgetToken() async => forgotTokens++;

  @override
  Future<void> disconnect() async {
    signedIn = false;
    disconnected = true;
  }
}

/// Uygulamayı kuran testler için: bellek içi veritabanı, sahte Drive, geçici klasör.
List<Override> backupTestOverrides({
  AppDatabase? database,
  FakeDriveConnection? connection,
}) => [
  appDatabaseProvider.overrideWithValue(database ?? AppDatabase.inMemory()),
  driveConnectionProvider.overrideWithValue(
    connection ?? FakeDriveConnection(),
  ),
  backupTempDirProvider.overrideWithValue(
    Future.value(Directory.systemTemp.createTempSync('denk_backup_test')),
  ),
];
