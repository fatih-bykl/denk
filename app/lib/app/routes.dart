/// Rota yolları. Ekranlar router'ı import etmeden buradan kullanır.
abstract final class Routes {
  static const dashboard = '/';
  static const transactions = '/islemler';
  static const schedule = '/takvim';
  static const schedulesSegment = 'planlar';
  static const schedules = '$schedule/$schedulesSegment';
  static const debts = '/borclar';
  static const settings = '/ayarlar';

  static const accountsSegment = 'hesaplar';
  static const accounts = '$settings/$accountsSegment';
  static const categoriesSegment = 'kategoriler';
  static const categories = '$settings/$categoriesSegment';
  static const backupSegment = 'yedek';
  static const backup = '$settings/$backupSegment';
}
