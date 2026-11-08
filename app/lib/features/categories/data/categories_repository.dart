import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/data_generation.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/database/app_database.dart';
import '../domain/category.dart';

/// Tüm metotlar hata durumunda [DataFailure] fırlatır.
abstract interface class CategoriesRepository {
  Future<List<Category>> fetchAll();
  Future<void> create({
    required EntryKind kind,
    required String name,
    required String icon,
  });
  Future<void> update(String id, {required String name, required String icon});
  Future<void> setArchived(String id, {required bool archived});
}

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => LocalCategoriesRepository(ref.watch(appDatabaseProvider)),
);

/// Arşivlenenler dahil tüm kategoriler, ada göre sıralı.
final categoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(dataGenerationProvider);
  return ref.watch(categoriesRepositoryProvider).fetchAll();
});

class LocalCategoriesRepository implements CategoriesRepository {
  LocalCategoriesRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<Category>> fetchAll() => guardData(
    () => _db
        .select('SELECT * FROM categories ORDER BY name, rowid')
        .map(Category.fromJson)
        .toList(),
  );

  @override
  Future<void> create({
    required EntryKind kind,
    required String name,
    required String icon,
  }) => guardData(
    () => _db.execute(
      'INSERT INTO categories (id, kind, name, icon) VALUES (?, ?, ?, ?)',
      [newId(), kind.name, name, icon],
    ),
  );

  @override
  Future<void> update(
    String id, {
    required String name,
    required String icon,
  }) => guardData(
    () => _db.execute('UPDATE categories SET name = ?, icon = ? WHERE id = ?', [
      name,
      icon,
      id,
    ]),
  );

  @override
  Future<void> setArchived(String id, {required bool archived}) => guardData(
    () => _db.execute('UPDATE categories SET archived_at = ? WHERE id = ?', [
      archived ? AppDatabase.now() : null,
      id,
    ]),
  );
}
