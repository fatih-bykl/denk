import 'app_database.dart';

/// Taslak nesnelerinin `toJson` haritalarını tabloya yazmak için kısayollar.
/// Sütun adları uygulama kodundan gelir (kullanıcı girdisi değil); değerler her
/// zaman parametre olarak geçer.
extension SqlWrites on AppDatabase {
  void insert(String table, Map<String, Object?> values) {
    final columns = values.keys.join(', ');
    final marks = List.filled(values.length, '?').join(', ');
    execute(
      'INSERT INTO $table ($columns) VALUES ($marks)',
      values.values.map(toSql).toList(),
    );
  }

  void updateById(String table, String id, Map<String, Object?> values) {
    final sets = values.keys.map((c) => '$c = ?').join(', ');
    execute('UPDATE $table SET $sets WHERE id = ?', [
      ...values.values.map(toSql),
      id,
    ]);
  }
}

/// SQLite'ın bilmediği Dart türlerini çevirir (bool → 0/1).
Object? toSql(Object? value) => switch (value) {
  bool b => b ? 1 : 0,
  _ => value,
};
