# Denk

Gelir/gider, hesap bakiyeleri, borç/alacak ve ödeme takvimi için kişisel finans uygulaması.
Android'de çalışır. Hesap açmak yok, sunucu yok: veriler yalnızca telefonda durur,
istenirse kullanıcının kendi Google Drive'ına yedeklenir.

## İndir

**[Denk-android.apk](https://github.com/fatih-bykl/denk/releases/latest/download/Denk-android.apk)**
(Android 7.0 ve üzeri). Telefona indirip aç; "bilinmeyen kaynaklardan yükleme" izni istenirse ver.

Tanıtım sayfası: https://www.internetsihirbazi.com/denk/ · Tüm sürümler: [Releases](https://github.com/fatih-bykl/denk/releases)

| Katman | Teknoloji |
|---|---|
| İstemci | Flutter (Android), Riverpod, go_router |
| Veri | SQLite (`sqlite3` paketi), telefonda |
| Bildirimler | flutter_local_notifications (yerel bildirimler) |

## Klasörler

- `app/` — Flutter uygulaması
  - `lib/core/database/` — yerel veritabanı: şema ve sürüm geçişleri (`schema.dart`)
  - `lib/features/` — ekranlar ve veri katmanı (accounts, categories, transactions, schedule, debts, dashboard, settings)
  - `lib/core/` — para, tarih, tekrar kuralı, ortak bileşenler
  - `lib/services/notifications/` — ödeme hatırlatmaları
- `site/` — internetsihirbazi.com/denk/ sayfaları: tanıtım (`index.html`) ve gizlilik politikası (`gizlilik.html`)
- `store/` — Google Play mağaza görselleri

## Geliştirme

`app/` klasöründe:

```sh
flutter run            # bağlı telefonda
flutter test           # tüm testler
dart analyze           # analiz
```

Not: Proje yolundaki Türkçe karakter `flutter analyze` komutunu çökertiyor, onun yerine
`dart analyze` kullan.

## Veritabanı

Telefondaki SQLite veritabanı (`denk.db`, uygulamanın kendi klasöründe). Şema
`app/lib/core/database/schema.dart` içinde sürüm adımları olarak durur; sürüm
`PRAGMA user_version` ile tutulur.

**Kural:** Yayınlanmış bir adım asla değiştirilmez; her şema değişikliği listeye yeni bir
adım olarak eklenir. Kullanıcıların telefonundaki veritabanı eski adımları zaten uygulamıştır.

Kurallar ve hesaplamalar `app/test/data/local_database_test.dart` içinde sınanır
(bakiye, ödeme, dönem eşitleme, borç kalanı, kısıtlar).

İlk derlemede `sqlite3` paketi SQLite'ı GitHub'dan indirip parmak izini doğrular. GitHub
o an hata verirse derleme "Hash of downloaded file" hatasıyla durur; birkaç dakika sonra
tekrar dene.

## Web sayfaları

`site/` klasörü `main` dalına gönderildiğinde GitHub Actions ("Web sitesine yükle") onu
FTPS ile sunucudaki `denk/` klasörüne eşitler. FTP bilgileri depo sırlarındadır
(`FTP_USERNAME`, `FTP_PASSWORD`).

Gizlilik politikası: `https://www.internetsihirbazi.com/denk/gizlilik.html`

## Android yayını

İmza: `app/android/key.properties` ve `app/android/upload-keystore.jks` (git'e girmez).
**İkisini de güvenli bir yere yedekle;** kaybolursa güncelleme yüklenemez. Dosyalar yoksa
yayın derlemesi deneme anahtarıyla imzalanır.

Her yeni sürümde `app/pubspec.yaml` içindeki `version` artırılır (ör. `2.0.1+3`; `+` sonrası
her yüklemede büyümeli).

```sh
cd app
flutter build apk --release            # GitHub sürümü için (tüm telefonlar)
flutter build appbundle --release      # Google Play için: build/app/outputs/bundle/release/app-release.aab
```

Not: Bildirim eklentisi Android 37 API ile derleme istediği için `compileSdk = 37`
(`android/app/build.gradle.kts`).
