import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';

import 'schema.dart';

export 'ids.dart' show newId;

/// `main` içinde açılan yerel veritabanı. Testlerde [AppDatabase.inMemory] ile override edilir.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) =>
      throw StateError('appDatabaseProvider main içinde override edilmeli'),
);

/// Telefondaki SQLite veritabanı. Tüm veriler burada durur; sunucu yoktur.
///
/// Tutarlar kuruş (int), tarihler `2026-11-05` biçiminde metin, zaman damgaları
/// UTC ISO-8601 metindir. Şema ve sürüm geçişleri [schema.dart] içindedir.
class AppDatabase {
  AppDatabase._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    migrate(_db);
  }

  /// [path] konumundaki dosyayı açar (yoksa oluşturur) ve şemayı günceller.
  factory AppDatabase.open(String path) => AppDatabase._(sqlite3.open(path));

  /// Testler için bellek içi veritabanı.
  factory AppDatabase.inMemory() => AppDatabase._(sqlite3.openInMemory());

  final Database _db;

  /// Satırları sütun adı → değer haritası olarak döndürür.
  List<Map<String, Object?>> select(
    String sql, [
    List<Object?> params = const [],
  ]) => [
    for (final row in _db.select(sql, params)) {...row},
  ];

  Map<String, Object?>? selectOne(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final rows = select(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  void execute(String sql, [List<Object?> params = const []]) =>
      _db.execute(sql, params);

  /// Son ifadenin değiştirdiği satır sayısı.
  int get updatedRows => _db.updatedRows;

  /// [action] içindeki tüm yazmalar birlikte kaydedilir ya da hiçbiri kaydedilmez.
  T transaction<T>(T Function() action) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Tüm kayıtları siler ve varsayılan hesap ile kategorileri yeniden kurar.
  void deleteAllData() => transaction(() {
    // Yabancı anahtarlar yüzünden sıra önemli: önce bağlı kayıtlar.
    for (final table in dataTables.reversed) {
      _db.execute('DELETE FROM $table');
    }
    seedDefaults(_db);
  });

  String? getSetting(String key) =>
      selectOne('SELECT value FROM settings WHERE key = ?', [key])?['value']
          as String?;

  void setSetting(String key, String? value) => value == null
      ? _db.execute('DELETE FROM settings WHERE key = ?', [key])
      : _db.execute(
          'INSERT INTO settings (key, value) VALUES (?, ?) '
          'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
          [key, value],
        );

  /// Veritabanının tutarlı bir kopyasını [path] dosyasına yazar (dosya olmamalı).
  void snapshotTo(String path) => _db.execute('VACUUM INTO ?', [path]);

  /// Bu veritabanının içeriğini [path] dosyasındaki yedekle değiştirir.
  ///
  /// Yedek önce ayrı açılıp sınanır (bozuk mu, Denk veritabanı mı, bu uygulamadan
  /// yeni mi); geçmezse [BackupFileException] fırlatılır ve mevcut veriye dokunulmaz.
  /// Eski şema sürümündeki yedek kopyalandıktan sonra güncel sürüme yükseltilir.
  Future<void> replaceWith(String path) async {
    if (!File(path).existsSync()) {
      throw const BackupFileException('Yedek dosyası bulunamadı.');
    }
    final source = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      try {
        _checkBackup(source);
      } on SqliteException {
        throw const BackupFileException(
          'Yedek dosyası bozuk ya da Denk yedeği değil.',
        );
      }
      await source.backup(_db, nPage: -1).drain<void>();
    } finally {
      source.close();
    }
    _db.execute('PRAGMA foreign_keys = ON');
    migrate(_db);
  }

  static void _checkBackup(Database source) {
    final ok = switch (source.select('PRAGMA quick_check').first.values.first) {
      'ok' => true,
      _ => false,
    };
    final tables = {
      for (final row in source.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name'] as String,
    };
    if (!ok || !tables.containsAll(dataTables)) {
      throw const BackupFileException(
        'Yedek dosyası bozuk ya da Denk yedeği değil.',
      );
    }
    if (userVersion(source) > schemaVersion) {
      throw const BackupFileException(
        'Bu yedek Denk\'in daha yeni bir sürümüyle alınmış. Önce uygulamayı güncelle.',
      );
    }
  }

  void close() => _db.close();

  /// Şu an, UTC ISO-8601 (veritabanındaki zaman damgası biçimi).
  static String now() => DateTime.now().toUtc().toIso8601String();
}

/// Yedek dosyası geri yüklenemediğinde; [message] kullanıcıya gösterilir.
class BackupFileException implements Exception {
  const BackupFileException(this.message);

  final String message;

  @override
  String toString() => message;
}
