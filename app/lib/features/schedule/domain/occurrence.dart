import '../../../core/date/dates.dart';
import 'payment_schedule.dart';

enum OccurrenceStatus {
  pending,
  paid,
  skipped;

  static OccurrenceStatus fromName(String name) =>
      values.firstWhere((s) => s.name == name);
}

/// Bir ödeme planının tek bir vadesi.
class Occurrence {
  const Occurrence({
    required this.id,
    required this.scheduleId,
    required this.dueDate,
    required this.amount,
    required this.status,
    required this.title,
    required this.flow,
    this.transactionId,
  });

  /// `payment_occurrences` satırı, `payment_schedules(title, flow)` ile birlikte.
  factory Occurrence.fromJson(Map<String, dynamic> json) {
    final schedule = json['payment_schedules'] as Map<String, dynamic>;
    return Occurrence(
      id: json['id'] as String,
      scheduleId: json['schedule_id'] as String,
      dueDate: Dates.fromDb(json['due_date'] as String),
      amount: (json['amount'] as num).toInt(),
      status: OccurrenceStatus.fromName(json['status'] as String),
      transactionId: json['transaction_id'] as String?,
      title: schedule['title'] as String,
      flow: CashFlow.fromName(schedule['flow'] as String),
    );
  }

  final String id;
  final String scheduleId;
  final DateTime dueDate;

  /// Kuruş.
  final int amount;
  final OccurrenceStatus status;
  final String? transactionId;
  final String title;
  final CashFlow flow;

  bool get isPending => status == OccurrenceStatus.pending;

  /// Vadesi geçmiş ve hâlâ ödenmemiş.
  bool isOverdue(DateTime today) => isPending && dueDate.isBefore(today);
}
