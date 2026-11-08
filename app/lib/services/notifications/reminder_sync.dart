import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date/dates.dart';
import '../../features/schedule/application/schedule_providers.dart';
import '../../features/schedule/data/schedule_repository.dart';
import 'notification_service.dart';
import 'reminder.dart';

/// Şu an (saatli). Testlerde sabitlenir.
final nowProvider = Provider<DateTime>((ref) => DateTime.now());

/// Önümüzdeki [reminderWindowDays] günün bekleyen dönemleri, planlarının
/// hatırlatma ayarıyla birlikte.
final remindableOccurrencesProvider =
    FutureProvider<List<RemindableOccurrence>>((ref) async {
      await ref.watch(horizonSyncProvider.future);
      final today = ref.watch(todayProvider);
      final schedules = await ref.watch(schedulesProvider.future);
      final remindDays = {for (final s in schedules) s.id: s.remindDaysBefore};
      final occurrences = await ref
          .watch(scheduleRepositoryProvider)
          .fetchOccurrences(
            from: today,
            to: today.add(const Duration(days: reminderWindowDays + 1)),
          );
      return [
        for (final o in occurrences)
          if (o.isPending)
            RemindableOccurrence(o, remindDays[o.scheduleId] ?? 3),
      ];
    });

/// Hatırlatma zamanı gelmiş, vadesi geçmemiş ödemeler (Özet ekranındaki uyarı).
final dueSoonProvider = FutureProvider<List<RemindableOccurrence>>((ref) async {
  final items = await ref.watch(remindableOccurrencesProvider.future);
  return dueSoon(items, ref.watch(todayProvider));
});

/// Cihazdaki bildirimleri güncel dönemlerle eşitler; kurulan bildirim sayısını
/// döndürür. Planlar veya dönemler değiştikçe yeniden çalışır.
final reminderSyncProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(notificationServiceProvider);
  if (!service.isSupported) return 0;
  final items = await ref.watch(remindableOccurrencesProvider.future);
  final reminders = planReminders(items, ref.watch(nowProvider));
  await service.replaceAll(reminders);
  return reminders.length;
});

/// Bu cihazdaki tüm hatırlatmaları siler (ör. tüm veriler silinmeden önce).
Future<void> clearReminders(WidgetRef ref) =>
    ref.read(notificationServiceProvider).replaceAll(const []);

/// Bugünden itibaren gün farkı (ör. Özet uyarısı için).
int daysUntil(DateTime today, DateTime day) =>
    Dates.dateOnly(day).difference(Dates.dateOnly(today)).inDays;
