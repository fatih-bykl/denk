import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder.dart';

/// Cihazın zamanlanmış bildirimleri. Web'de ve testlerde [NoopNotificationService].
abstract interface class NotificationService {
  /// Bu platformda cihaz bildirimi kurulabiliyor mu?
  bool get isSupported;

  Future<bool> areEnabled();

  /// İzin ister (Android 13+). Verilip verilmediğini döndürür.
  Future<bool> requestPermission();

  /// Kurulu tüm hatırlatmaları siler ve [reminders] listesini kurar.
  /// Kurulu deneme bildirimine dokunmaz.
  Future<void> replaceAll(List<Reminder> reminders);

  /// Hatırlatmalarla aynı yöntemle [delay] sonrasına bir deneme bildirimi kurar.
  /// Kurulan anı döndürür.
  Future<DateTime> scheduleTest(Duration delay);
}

/// Deneme bildiriminin kimliği; hatırlatma kimlikleri 31 bitlik özetlerdir,
/// çakışma olasılığı ihmal edilebilir.
const testNotificationId = 0x7ffffffe;

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => defaultTargetPlatform == TargetPlatform.android
      ? LocalNotificationService()
      : const NoopNotificationService(),
);

class NoopNotificationService implements NotificationService {
  const NoopNotificationService();

  @override
  bool get isSupported => false;

  @override
  Future<bool> areEnabled() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {}

  @override
  Future<DateTime> scheduleTest(Duration delay) async => DateTime.now();
}

/// Android yerel bildirimleri. Telefon yeniden başlayınca eklentinin
/// alıcısı (AndroidManifest'teki ScheduledNotificationBootReceiver) kurulu
/// bildirimleri geri yükler.
class LocalNotificationService implements NotificationService {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;
  bool _askedPermission = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'payment_reminders',
      'Ödeme hatırlatmaları',
      channelDescription: 'Yaklaşan ödeme ve tahsilatlar için hatırlatmalar',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_denk',
      color: Color(0xFF0F766E),
    ),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _init() => _ready ??= () async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Bildirim çubuğu için tek renkli simge (res/drawable-*/ic_stat_denk.png).
        android: AndroidInitializationSettings('ic_stat_denk'),
      ),
    );
  }();

  @override
  bool get isSupported => true;

  @override
  Future<bool> areEnabled() async {
    await _init();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    _askedPermission = true;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    await _init();
    // İlk kez hatırlatma kurulacaksa izin bir kez istenir.
    if (reminders.isNotEmpty && !_askedPermission && !await areEnabled()) {
      await requestPermission();
    }
    // Deneme bildirimi hariç, kurulu tüm bildirimleri kaldır.
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id != testNotificationId) await _plugin.cancel(id: p.id);
    }
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime.from(r.at, tz.local),
        notificationDetails: _details,
        // Tam saat izni (exact alarm) istememek için esnek zamanlama;
        // Android bildirimi birkaç dakika kaydırabilir.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
      );
    }
  }

  @override
  Future<DateTime> scheduleTest(Duration delay) async {
    await _init();
    if (!await areEnabled()) await requestPermission();
    final at = tz.TZDateTime.now(tz.local).add(delay);
    await _plugin.zonedSchedule(
      id: testNotificationId,
      scheduledDate: at,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Denk deneme bildirimi',
      body: 'Ödeme hatırlatmaları bu telefonda çalışıyor.',
    );
    return at;
  }
}
