/// Tutarlar uygulama boyunca kuruş cinsinden `int` olarak taşınır (1250,50 TL = 125050).
/// Kayan nokta kullanılmaz, böylece yuvarlama hatası olmaz.
abstract final class Money {
  /// Girilebilecek en büyük tutar: 1 trilyon TL.
  static const maxKurus = 100000000000000;

  /// 125050 → "1.250,50 ₺"
  static String format(int kurus, {bool symbol = true}) {
    final abs = kurus.abs();
    final lira = (abs ~/ 100).toString();
    final buffer = StringBuffer(kurus < 0 ? '-' : '');
    for (var i = 0; i < lira.length; i++) {
      if (i > 0 && (lira.length - i) % 3 == 0) buffer.write('.');
      buffer.write(lira[i]);
    }
    buffer
      ..write(',')
      ..write((abs % 100).toString().padLeft(2, '0'));
    if (symbol) buffer.write(' ₺');
    return buffer.toString();
  }

  /// Kullanıcı girdisini kuruşa çevirir; geçersizse null döner.
  ///
  /// Kabul edilenler: "1250", "1250,5", "1.250,50", "1250.50", "-300", "1.250,50 ₺".
  static int? parse(String input, {bool allowNegative = false}) {
    var s = input.replaceAll(RegExp(r'[\s₺]'), '');
    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1);
    }
    if (negative && !allowNegative) return null;
    // Virgül yoksa ve tek nokta ile 1-2 hane varsa nokta ondalık ayıracıdır.
    if (!s.contains(',') && RegExp(r'^\d+\.\d{1,2}$').hasMatch(s)) {
      s = s.replaceFirst('.', ',');
    }
    final match = RegExp(r'^(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2}))?$')
        .firstMatch(s);
    if (match == null) return null;

    final lira = int.tryParse(match.group(1)!.replaceAll('.', ''));
    if (lira == null || lira > maxKurus ~/ 100) return null;
    final fraction = match.group(2);
    final kurus =
        lira * 100 +
        (fraction == null ? 0 : int.parse(fraction.padRight(2, '0')));
    if (kurus > maxKurus) return null;
    return negative ? -kurus : kurus;
  }
}
