import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/data_failure.dart';

/// Telefondaki tüm verileri silme. Hata durumunda [DataFailure] fırlatır.
abstract interface class DataResetRepository {
  /// Tüm kayıtlar silinir; varsayılan Nakit hesabı ve kategoriler yeniden kurulur.
  Future<void> deleteAllData();
}

final dataResetRepositoryProvider = Provider<DataResetRepository>(
  (ref) => LocalDataResetRepository(ref.watch(appDatabaseProvider)),
);

class LocalDataResetRepository implements DataResetRepository {
  LocalDataResetRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> deleteAllData() => guardData(_db.deleteAllData);
}
