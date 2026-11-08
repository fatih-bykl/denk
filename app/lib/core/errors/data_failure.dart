import 'package:sqlite3/sqlite3.dart' show SqliteException;

/// Veri işlemlerinde kullanıcıya gösterilecek Türkçe hata.
class DataFailure implements Exception {
  const DataFailure(this.message);

  static const notFound = DataFailure(
    'Kayıt bulunamadı. Sayfayı yenileyip tekrar dene.',
  );
  static const alreadyClosed = DataFailure('Bu dönem zaten kapatılmış.');

  factory DataFailure.from(Object error) => switch (error) {
    DataFailure() => error,
    // SQLite genişletilmiş hata kodları: https://sqlite.org/rescode.html
    SqliteException(extendedResultCode: 2067 || 1555) => const DataFailure(
      'Bu adla bir kayıt zaten var.',
    ),
    SqliteException(extendedResultCode: 787) => const DataFailure(
      'Bu kayıt başka kayıtlarda kullanıldığı için değiştirilemiyor.',
    ),
    SqliteException(extendedResultCode: 275 || 1299) => const DataFailure(
      'Girilen değer geçerli değil.',
    ),
    // Denk'in kendi tetikleyicisi: işlemin kategorisi işlemin türüne uymuyor.
    SqliteException(:final message) when message.contains('DNK04') =>
      const DataFailure('Seçilen kategori bu işlem türüne uymuyor.'),
    _ => const DataFailure('Kayıt kaydedilemedi. Lütfen tekrar dene.'),
  };

  final String message;

  @override
  String toString() => message;
}

/// Hatayı [DataFailure]'a çevirerek yeniden fırlatır.
///
/// Yerel veritabanı eşzamanlı çalışır; yine de arayüz `Future` döndürür ki
/// ekranlar ve testler veri kaynağından bağımsız kalsın.
Future<T> guardData<T>(T Function() action) async {
  try {
    return action();
  } catch (e) {
    throw DataFailure.from(e);
  }
}
