import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Veritabanının tamamı değiştiğinde (tüm verileri silme, yedekten geri yükleme)
/// artar. Veri sağlayıcıları bunu izler; değişince her şey yeniden yüklenir.
final dataGenerationProvider = NotifierProvider<DataGeneration, int>(
  DataGeneration.new,
);

class DataGeneration extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}
