import '../../core/date/dates.dart';
import '../../core/money/money.dart';
import '../../features/schedule/domain/occurrence.dart';
import '../../features/schedule/domain/payment_schedule.dart';

/// Hatırlatma bildirimlerinin gönderildiği saat.
const reminderHour = 9;

/// Bildirim kurulan dönem penceresi (gün) ve en fazla bildirim sayısı.
/// Android'in zamanlanmış bildirim sınırının çok altında kalınır.
const reminderWindowDays = 60;
const maxReminders = 50;

/// Hatırlatılacak bir dönem ve planındaki "kaç gün önce" ayarı.
class RemindableOccurrence {
  const RemindableOccurrence(this.occurrence, this.remindDaysBefore);

  final Occurrence occurrence;
  final int remindDaysBefore;

  /// Hatırlatmanın başladığı gün (vade − gün sayısı).
  DateTime get remindFrom => DateTime(
    occurrence.dueDate.year,
    occurrence.dueDate.month,
    occurrence.dueDate.day - remindDaysBefore,
  );
}

/// Cihaza kurulacak tek bir bildirim.
class Reminder {
  const Reminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Dönem kimliğinden türetilen, her çalıştırmada aynı kalan bildirim kimliği.
  final int id;
  final DateTime at;
  final String title;
  final String body;

  @override
  String toString() => 'Reminder($id, $at, $title, $body)';
}

/// Dönem kimliğinden kararlı, pozitif 31 bitlik bildirim kimliği (FNV-1a).
int reminderId(String occurrenceId) {
  var hash = 0x811c9dc5;
  for (final unit in occurrenceId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// "bugün", "yarın", "3 gün sonra"
String relativeDay(DateTime from, DateTime to) {
  final days = Dates.dateOnly(to).difference(Dates.dateOnly(from)).inDays;
  return switch (days) {
    0 => 'bugün',
    1 => 'yarın',
    _ => '$days gün sonra',
  };
}

/// Bekleyen dönemlerden kurulacak bildirimleri hesaplar.
///
/// Bildirim, vadeden [RemindableOccurrence.remindDaysBefore] gün önce saat
/// [reminderHour]'da gelir. O an geçmişse ama vade henüz gelmediyse vade günü
/// aynı saatte gelir; ikisi de geçmişse bildirim kurulmaz (uygulama içi uyarı
/// ve gecikmiş listesi bunları gösterir).
List<Reminder> planReminders(
  Iterable<RemindableOccurrence> items,
  DateTime now,
) {
  final reminders = <Reminder>[];
  for (final item in items) {
    final o = item.occurrence;
    if (!o.isPending) continue;
    DateTime at(DateTime day) =>
        DateTime(day.year, day.month, day.day, reminderHour);
    final candidates = [at(item.remindFrom), at(o.dueDate)];
    final when = candidates.where((t) => t.isAfter(now)).firstOrNull;
    if (when == null) continue;

    final isInflow = o.flow == CashFlow.inflow;
    reminders.add(
      Reminder(
        id: reminderId(o.id),
        at: when,
        title: '${isInflow ? 'Tahsilat' : 'Ödeme'}: ${o.title}',
        body:
            '${Money.format(o.amount)} · ${Dates.long(o.dueDate)} '
            '(${relativeDay(when, o.dueDate)})',
      ),
    );
  }
  reminders.sort((a, b) => a.at.compareTo(b.at));
  return reminders.take(maxReminders).toList();
}

/// Hatırlatma zamanı gelmiş, vadesi henüz geçmemiş dönemler (uygulama içi uyarı).
List<RemindableOccurrence> dueSoon(
  Iterable<RemindableOccurrence> items,
  DateTime today,
) => items
    .where(
      (i) =>
          i.occurrence.isPending &&
          !today.isBefore(i.remindFrom) &&
          !i.occurrence.dueDate.isBefore(today),
    )
    .toList();
