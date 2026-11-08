import 'dart:io';
import 'dart:typed_data';

import 'package:denk/core/database/app_database.dart';
import 'package:denk/core/database/data_generation.dart';
import 'package:denk/features/accounts/data/accounts_repository.dart';
import 'package:denk/services/backup/backup_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../helpers/fake_backup.dart';

void main() {
  late AppDatabase db;
  late FakeDriveConnection connection;
  late FakeBackupStore drive;
  late ProviderContainer container;

  BackupController controller() =>
      container.read(backupControllerProvider.notifier);
  BackupState state() => container.read(backupControllerProvider);
  Future<List<String>> accountNames() async => (await LocalAccountsRepository(
    db,
  ).fetchAll()).map((a) => a.name).toList();

  setUp(() {
    db = AppDatabase.inMemory();
    connection = FakeDriveConnection();
    drive = connection.store;
    container = ProviderContainer(
      overrides: backupTestOverrides(database: db, connection: connection),
    );
    addTearDown(container.dispose);
    addTearDown(db.close);
  });

  /// Başka bir telefondaki veritabanının yedeği (içinde [account] hesabı olan).
  Future<Uint8List> backupBytesWith(String account) async {
    final other = AppDatabase.inMemory();
    await LocalAccountsRepository(other)
        .create(name: account, openingBalance: 0);
    final dir = Directory.systemTemp.createTempSync('denk_other');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/b.db';
    other.snapshotTo(path);
    other.close();
    return File(path).readAsBytesSync();
  }

  group('bağlanma', () {
    test(
      'Drive boşsa bu telefonun verisi hemen yedeklenir, otomatik yedek açılır',
      () async {
        await controller().connect();

        expect(state().account, 'ayse@gmail.com');
        expect(state().autoBackup, isTrue);
        expect(state().lastBackupAt, isNotNull);
        expect(state().message, isNull);
        expect(drive.files, hasLength(1));
        expect(db.getSetting(BackupSettings.enabled), '1');
        expect(db.getSetting(BackupSettings.dirty), '0');
      },
    );

    test(
      "Drive'da yedek varsa üzerine yazılmaz, kullanıcıya sorulur",
      () async {
        drive.add('eski.db', await backupBytesWith('Banka'));

        await controller().connect();

        expect(drive.uploads, 0);
        expect(state().autoBackup, isFalse);
        expect(state().needsDecision, isTrue);
        // Değişiklik olsa da otomatik yedek, karar verilene kadar çalışmaz.
        await LocalAccountsRepository(db)
            .create(name: 'Yeni', openingBalance: 0);
        await controller().backupIfChanged();
        expect(drive.uploads, 0);
      },
    );

    test('kullanıcı vazgeçerse hiçbir şey değişmez', () async {
      connection.email = null;
      await controller().connect();
      expect(state().connected, isFalse);
      expect(db.getSetting(BackupSettings.enabled), isNull);
    });

    test('bağlantı kesilince ayarlar silinir, yedekler kalır', () async {
      await controller().connect();
      await controller().disconnect();

      expect(state().connected, isFalse);
      expect(connection.disconnected, isTrue);
      expect(db.getSetting(BackupSettings.enabled), isNull);
      expect(drive.files, hasLength(1));
    });

    test('bağlantı açılışta veritabanından okunur', () async {
      await controller().connect();
      final again = ProviderContainer(
        overrides: backupTestOverrides(database: db, connection: connection),
      );
      addTearDown(again.dispose);
      final s = again.read(backupControllerProvider);
      expect(s.account, 'ayse@gmail.com');
      expect(s.autoBackup, isTrue);
      expect(s.lastBackupAt, isNotNull);
    });
  });

  group('otomatik yedek', () {
    setUp(() => controller().connect());

    test('değişiklik yoksa yedeklenmez', () async {
      await controller().backupIfChanged();
      expect(drive.uploads, 1);
    });

    test('kayıt eklenince, değişince, silinince yedeklenir', () async {
      final repo = LocalAccountsRepository(db);
      await repo.create(name: 'Banka', openingBalance: 0);
      await controller().backupIfChanged();
      expect(drive.uploads, 2);

      final id = (await repo.fetchAll()).last.id;
      await repo.update(id, name: 'Banka 2', openingBalance: 5);
      await controller().backupIfChanged();
      expect(drive.uploads, 3);

      await repo.setArchived(id, archived: true);
      await controller().backupIfChanged();
      expect(drive.uploads, 4);

      await controller().backupIfChanged();
      expect(drive.uploads, 4);
    });

    test('açılışta bağlantı tazelenip değişiklik yedekleniyor', () async {
      await LocalAccountsRepository(db)
          .create(name: 'Banka', openingBalance: 0);
      await controller().onAppStart();
      expect(drive.uploads, 2);
    });

    test(
      'açılışta sessiz bağlanılamazsa yedeklenmez, uyarı gösterilir',
      () async {
        connection.signedIn = false;
        await LocalAccountsRepository(db)
            .create(name: 'Banka', openingBalance: 0);
        await controller().onAppStart();
        expect(drive.uploads, 1);
        expect(state().message, contains('yenilenmeli'));
      },
    );

    test('yükleme başarısız olursa değişiklik işareti geri gelir', () async {
      await LocalAccountsRepository(db)
          .create(name: 'Banka', openingBalance: 0);
      drive.failNextUpload = const SocketException('yok');

      await controller().backupIfChanged();
      expect(state().message, contains('İnternet'));
      expect(db.getSetting(BackupSettings.dirty), '1');

      await controller().backupIfChanged();
      expect(drive.uploads, 2);
      expect(db.getSetting(BackupSettings.dirty), '0');
      expect(state().message, isNull);
    });

    test('en fazla $keepBackups yedek saklanır, en eskiler silinir', () async {
      for (var i = 0; i < 7; i++) {
        await controller().backupNow();
      }
      final kept = await drive.list();
      expect(kept, hasLength(keepBackups));
      expect(state().backups, hasLength(keepBackups));
      expect(kept.first.createdAt.isAfter(kept.last.createdAt), isTrue);
    });

    test(
      'erişim anahtarının süresi dolmuşsa yenilenip tekrar denenir',
      () async {
        drive.unauthorizedCalls = 1;
        await controller().backupNow();
        expect(connection.forgotTokens, 1);
        expect(drive.uploads, 2);
        expect(state().message, isNull);
      },
    );

    test('"Tüm verilerimi sil" yedek bağlantısına dokunmaz', () async {
      db.deleteAllData();
      expect(db.getSetting(BackupSettings.enabled), '1');
      expect(db.getSetting(BackupSettings.dirty), '1');
    });
  });

  group('geri yükleme', () {
    test("seçilen yedekteki veriler bu telefona gelir", () async {
      final backup = drive.add('eski.db', await backupBytesWith('Banka'));
      await controller().connect();
      await LocalAccountsRepository(db)
          .create(name: 'Silinecek', openingBalance: 0);
      final generation = container.read(dataGenerationProvider);

      await controller().restore(backup);

      expect(state().message, isNull);
      expect(await accountNames(), ['Nakit', 'Banka']);
      expect(container.read(dataGenerationProvider), generation + 1);
      expect(state().autoBackup, isTrue);
      expect(state().lastBackupAt, backup.createdAt);
      expect(db.getSetting(BackupSettings.enabled), '1');
      expect(db.getSetting(BackupSettings.account), 'ayse@gmail.com');
      expect(db.getSetting(BackupSettings.dirty), '0');

      // Geri yüklenen veride de değişiklikler izleniyor.
      await LocalAccountsRepository(db).create(name: 'Yeni', openingBalance: 0);
      expect(db.getSetting(BackupSettings.dirty), '1');
    });

    test('bozuk dosya geri yüklenmez, veriye dokunulmaz', () async {
      final backup = drive.add(
        'bozuk.db',
        Uint8List.fromList(List.filled(4096, 7)),
      );
      await controller().connect();

      await controller().restore(backup);

      expect(state().message, contains('bozuk'));
      expect(await accountNames(), ['Nakit']);
    });

    test('daha yeni sürümden yedek geri yüklenmez', () async {
      final dir = Directory.systemTemp.createTempSync('denk_new');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/n.db';
      final other = AppDatabase.open(path);
      await LocalAccountsRepository(other)
          .create(name: 'Banka', openingBalance: 0);
      other.close();
      final raw = sqlite3.open(path)..execute('PRAGMA user_version = 99');
      raw.close();
      final backup = drive.add('yeni.db', File(path).readAsBytesSync());
      await controller().connect();

      await controller().restore(backup);

      expect(state().message, contains('daha yeni'));
      expect(await accountNames(), ['Nakit']);
    });

    test('eski şema sürümündeki yedek geri yüklenip güncellenir', () async {
      // Sürüm 1: settings tablosu ve yedek tetikleyicileri yok.
      final bytes = await backupBytesWith('Banka');
      final dir = Directory.systemTemp.createTempSync('denk_old');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/o.db';
      File(path).writeAsBytesSync(bytes);
      final raw = sqlite3.open(path);
      raw.execute('DROP TABLE settings');
      for (final row in raw.select(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' "
        "AND name LIKE '%marks_backup_dirty'",
      )) {
        raw.execute('DROP TRIGGER ${row['name']}');
      }
      raw.execute('PRAGMA user_version = 1');
      raw.close();
      final backup = drive.add('v1.db', File(path).readAsBytesSync());
      await controller().connect();

      await controller().restore(backup);

      expect(state().message, isNull);
      expect(await accountNames(), ['Nakit', 'Banka']);
      expect(db.getSetting(BackupSettings.enabled), '1');
      await LocalAccountsRepository(db).create(name: 'Yeni', openingBalance: 0);
      expect(db.getSetting(BackupSettings.dirty), '1');
    });
  });

  test('Drive yedeklerinin hepsi silinebilir', () async {
    await controller().connect();
    await controller().backupNow();
    await controller().deleteAllBackups();
    expect(drive.files, isEmpty);
    expect(state().backups, isEmpty);
    expect(state().lastBackupAt, isNull);
    expect(state().connected, isTrue);
  });
}
