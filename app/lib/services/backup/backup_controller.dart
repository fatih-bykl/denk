import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInException;
import 'package:googleapis/drive/v3.dart' as drive show DetailedApiRequestError;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/app_database.dart';
import '../../core/database/data_generation.dart';
import 'backup_store.dart';
import 'drive_connection.dart';

/// Drive'da tutulan en fazla yedek sayısı; daha eskiler silinir.
const keepBackups = 5;

final driveConnectionProvider = Provider<DriveConnection>(
  (ref) => GoogleDriveConnection(),
);

/// Yedek dosyalarının geçici olarak yazıldığı klasör. Testlerde override edilir.
final backupTempDirProvider = Provider<Future<Directory>>(
  (ref) => getTemporaryDirectory(),
);

final backupControllerProvider =
    NotifierProvider<BackupController, BackupState>(BackupController.new);

/// Veritabanındaki `settings` anahtarları.
abstract final class BackupSettings {
  /// '1': kullanıcı Drive yedeğini bağladı.
  static const enabled = 'drive_backup_enabled';

  /// Bağlı Google hesabının e-postası (ekranda göstermek için).
  static const account = 'drive_backup_account';

  /// '1': değişiklik olunca kendiliğinden yedeklenir. Yeni bir telefonda, Drive'da
  /// başka yedekler varken boş veriyi yedekleyip onları ezmemek için kullanıcı
  /// ilk kez geri yükleyene ya da elle yedekleyene kadar kapalı kalır.
  static const auto = 'drive_backup_auto';

  /// '1': son yedekten beri veri değişti (şemadaki tetikleyiciler yazar).
  static const dirty = 'backup_dirty';

  /// Son başarılı yedeğin zamanı (UTC ISO-8601).
  static const lastBackupAt = 'drive_backup_last_at';
}

class BackupState {
  const BackupState({
    this.configured = true,
    this.account,
    this.autoBackup = false,
    this.lastBackupAt,
    this.backups,
    this.busy = false,
    this.message,
  });

  /// Uygulamada Google ayarı var mı.
  final bool configured;

  /// Bağlı hesap; `null` ise yedekleme kapalı.
  final String? account;
  final bool autoBackup;
  final DateTime? lastBackupAt;

  /// Drive'daki yedekler; henüz yüklenmediyse `null`.
  final List<BackupFile>? backups;
  final bool busy;

  /// Kullanıcıya gösterilecek son hata.
  final String? message;

  bool get connected => account != null;

  /// Yeni bağlanılmış ve Drive'da önceki yedekler var: kullanıcı karar vermeli.
  bool get needsDecision =>
      connected && !autoBackup && (backups?.isNotEmpty ?? false);

  BackupState copyWith({
    String? Function()? account,
    bool? autoBackup,
    DateTime? Function()? lastBackupAt,
    List<BackupFile>? Function()? backups,
    bool? busy,
    String? Function()? message,
  }) => BackupState(
    configured: configured,
    account: account != null ? account() : this.account,
    autoBackup: autoBackup ?? this.autoBackup,
    lastBackupAt: lastBackupAt != null ? lastBackupAt() : this.lastBackupAt,
    backups: backups != null ? backups() : this.backups,
    busy: busy ?? this.busy,
    message: message != null ? message() : this.message,
  );
}

class BackupController extends Notifier<BackupState> {
  AppDatabase get _db => ref.read(appDatabaseProvider);
  DriveConnection get _connection => ref.read(driveConnectionProvider);

  @override
  BackupState build() {
    final db = ref.watch(appDatabaseProvider);
    final connection = ref.watch(driveConnectionProvider);
    final enabled = db.getSetting(BackupSettings.enabled) == '1';
    final last = db.getSetting(BackupSettings.lastBackupAt);
    return BackupState(
      configured: connection.isConfigured,
      account: enabled ? db.getSetting(BackupSettings.account) ?? '' : null,
      autoBackup: enabled && db.getSetting(BackupSettings.auto) == '1',
      lastBackupAt: last == null ? null : DateTime.parse(last).toLocal(),
    );
  }

  bool get _hasChanges => _db.getSetting(BackupSettings.dirty) != '0';

  /// Hesap seçtirir, Drive iznini alır ve yedekleri listeler. Drive'da önceki
  /// yedekler yoksa bu telefonun verisi hemen yedeklenir ve otomatik yedek açılır.
  Future<void> connect() => _run(() async {
    final email = await _connection.connect();
    if (email == null) return; // Kullanıcı vazgeçti.
    _db
      ..setSetting(BackupSettings.enabled, '1')
      ..setSetting(BackupSettings.account, email);
    state = state.copyWith(account: () => email);
    final backups = await _withStore(interactive: true, (s) => s.list());
    state = state.copyWith(backups: () => backups);
    if (backups.isEmpty) await _backup(interactive: true);
  });

  /// Uygulama açılırken: bağlantıyı ekran göstermeden tazeler, değişiklik
  /// varsa yedekler. Bağlanamazsa yedeklemez; uyarı Ayarlar'da görünür.
  Future<void> onAppStart() async {
    if (!state.connected || state.busy) return;
    String? email;
    try {
      email = await _connection.restoreSilently();
    } catch (_) {
      email = null;
    }
    if (email == null) {
      state = state.copyWith(
        message: () => backupErrorMessage(const BackupNeedsSignIn()),
      );
      return;
    }
    await backupIfChanged();
  }

  /// Otomatik yedek açıksa ve son yedekten beri değişiklik varsa yedekler
  /// (uygulama arka plana geçerken). Ekran göstermez, hata fırlatmaz.
  Future<void> backupIfChanged() async {
    if (!state.connected || !state.autoBackup || state.busy || !_hasChanges) {
      return;
    }
    await _run(() => _backup(interactive: false));
  }

  /// "Şimdi yedekle": otomatik yedeği de açar.
  Future<void> backupNow() => _run(() => _backup(interactive: true));

  Future<void> refreshList() => _run(() async {
    final backups = await _withStore(interactive: true, (s) => s.list());
    state = state.copyWith(backups: () => backups);
  });

  /// Seçilen yedeği geri yükler: bu telefondaki veriler yedektekiyle değişir.
  Future<void> restore(BackupFile backup) => _run(() async {
    final file = await _tempFile('geri-yukle');
    try {
      await _withStore(interactive: true, (s) => s.download(backup.id, file));
      await _db.replaceWith(file.path);
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
    // Ayarlar yedeğin içinden geldi; bu telefonun bağlantı bilgisiyle düzelt.
    _db
      ..setSetting(BackupSettings.enabled, '1')
      ..setSetting(BackupSettings.account, state.account)
      ..setSetting(BackupSettings.auto, '1')
      ..setSetting(BackupSettings.dirty, '0')
      ..setSetting(
        BackupSettings.lastBackupAt,
        backup.createdAt.toUtc().toIso8601String(),
      );
    state = state.copyWith(
      autoBackup: true,
      lastBackupAt: () => backup.createdAt,
    );
    ref.read(dataGenerationProvider.notifier).bump();
  });

  /// Drive'daki tüm Denk yedeklerini siler (bağlantı açık kalır).
  Future<void> deleteAllBackups() => _run(() async {
    await _withStore(interactive: true, (s) async {
      for (final b in await s.list()) {
        await s.delete(b.id);
      }
    });
    _db.setSetting(BackupSettings.lastBackupAt, null);
    state = state.copyWith(backups: () => const [], lastBackupAt: () => null);
  });

  /// Bağlantıyı keser; Drive'daki yedekler silinmez.
  Future<void> disconnect() => _run(() async {
    await _connection.disconnect();
    for (final key in [
      BackupSettings.enabled,
      BackupSettings.account,
      BackupSettings.auto,
    ]) {
      _db.setSetting(key, null);
    }
    state = state.copyWith(
      account: () => null,
      autoBackup: false,
      backups: () => null,
    );
  });

  Future<void> _backup({required bool interactive}) async {
    final file = await _tempFile('yedek');
    // "Değişiklik var" işareti kopyadan önce indirilir: yükleme sürerken yapılan
    // değişiklikler işareti yeniden kaldırır ve bir sonraki yedeğe girer.
    _db.setSetting(BackupSettings.dirty, '0');
    try {
      _db.snapshotTo(file.path);
      final now = DateTime.now();
      final backups = await _withStore(interactive: interactive, (s) async {
        await s.upload(_fileName(now), file);
        final all = await s.list();
        for (final old in all.skip(keepBackups)) {
          await s.delete(old.id);
        }
        return all.take(keepBackups).toList();
      });
      _db
        ..setSetting(BackupSettings.auto, '1')
        ..setSetting(
          BackupSettings.lastBackupAt,
          now.toUtc().toIso8601String(),
        );
      state = state.copyWith(
        autoBackup: true,
        lastBackupAt: () => now,
        backups: () => backups,
      );
    } catch (_) {
      _db.setSetting(BackupSettings.dirty, '1');
      rethrow;
    } finally {
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// Depoyu açıp [action]'ı çalıştırır; erişim anahtarının süresi dolmuşsa
  /// (401) anahtarı yenileyip bir kez daha dener.
  Future<T> _withStore<T>(
    Future<T> Function(BackupStore store) action, {
    required bool interactive,
  }) async {
    try {
      return await action(await _connection.open(interactive: interactive));
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status != 401) rethrow;
      await _connection.forgetToken();
      return action(await _connection.open(interactive: interactive));
    }
  }

  /// İşlemi çalıştırır; hata fırlatmaz, hatayı [BackupState.message] olarak gösterir.
  Future<void> _run(Future<void> Function() action) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, message: () => null);
    try {
      await action();
      state = state.copyWith(busy: false);
    } catch (e) {
      state = state.copyWith(busy: false, message: () => backupErrorMessage(e));
    }
  }

  Future<File> _tempFile(String prefix) async {
    final dir = await ref.read(backupTempDirProvider);
    return File(
      p.join(dir.path, '$prefix-${DateTime.now().microsecondsSinceEpoch}.db'),
    );
  }

  static String _fileName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'denk-yedek-${t.year}-${two(t.month)}-${two(t.day)}_'
        '${two(t.hour)}-${two(t.minute)}-${two(t.second)}.db';
  }
}

/// Yedekleme hatasının kullanıcıya gösterilecek Türkçe karşılığı.
String backupErrorMessage(Object error) => switch (error) {
  BackupFileException(:final message) => message,
  BackupNeedsSignIn() =>
    'Google bağlantısı yenilenmeli. Yedekleme ekranından tekrar bağlan.',
  GoogleSignInException() => 'Google hesabına bağlanılamadı. İnternet bağlantını kontrol edip tekrar dene.',
  SocketException() || HttpException() =>
    'İnternet bağlantısı yok. Bağlantını kontrol edip tekrar dene.',
  drive.DetailedApiRequestError(status: 403) =>
    'Google Drive erişim izni yok. Bağlantıyı kesip tekrar bağlan.',
  drive.DetailedApiRequestError(status: 507) ||
  drive.DetailedApiRequestError(status: 413) => 'Google Drive alanın dolu.',
  _ => 'Yedekleme yapılamadı. Lütfen tekrar dene.',
};
