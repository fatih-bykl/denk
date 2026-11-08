import '../../../core/date/dates.dart';
import '../../../core/recurrence/recurrence.dart';
import '../../categories/domain/category.dart';

enum CashFlow {
  outflow('Ödeme', EntryKind.expense),
  inflow('Tahsilat', EntryKind.income);

  const CashFlow(this.label, this.entryKind);

  final String label;

  /// Ödendiğinde oluşan işlemin türü.
  final EntryKind entryKind;

  static CashFlow fromName(String name) =>
      values.firstWhere((f) => f.name == name);
}

class PaymentSchedule {
  const PaymentSchedule({
    required this.id,
    required this.title,
    required this.flow,
    required this.amount,
    required this.frequency,
    required this.startDate,
    this.intervalCount = 1,
    this.endDate,
    this.occurrenceLimit,
    this.remindDaysBefore = 3,
    this.categoryId,
    this.debtId,
    this.isActive = true,
  });

  factory PaymentSchedule.fromJson(Map<String, dynamic> json) =>
      PaymentSchedule(
        id: json['id'] as String,
        title: json['title'] as String,
        flow: CashFlow.fromName(json['flow'] as String),
        amount: (json['amount'] as num).toInt(),
        frequency: Frequency.fromName(json['frequency'] as String),
        intervalCount: json['interval_count'] as int,
        startDate: Dates.fromDb(json['start_date'] as String),
        endDate: json['end_date'] == null
            ? null
            : Dates.fromDb(json['end_date'] as String),
        occurrenceLimit: json['occurrence_limit'] as int?,
        remindDaysBefore: json['remind_days_before'] as int,
        categoryId: json['category_id'] as String?,
        debtId: json['debt_id'] as String?,
        isActive: json['is_active'] as bool,
      );

  final String id;
  final String title;
  final CashFlow flow;

  /// Kuruş, her dönem için.
  final int amount;
  final Frequency frequency;
  final int intervalCount;
  final DateTime startDate;
  final DateTime? endDate;
  final int? occurrenceLimit;
  final int remindDaysBefore;
  final String? categoryId;
  final String? debtId;
  final bool isActive;

  factory PaymentSchedule.fromDraft(String id, ScheduleDraft d) =>
      PaymentSchedule(
        id: id,
        title: d.title,
        flow: d.flow,
        amount: d.amount,
        frequency: d.frequency,
        intervalCount: d.intervalCount,
        startDate: d.startDate,
        endDate: d.endDate,
        occurrenceLimit: d.occurrenceLimit,
        remindDaysBefore: d.remindDaysBefore,
        categoryId: d.categoryId,
        debtId: d.debtId,
        isActive: d.isActive,
      );

  RecurrenceRule get rule => RecurrenceRule(
    frequency: frequency,
    start: startDate,
    interval: intervalCount,
    end: endDate,
    limit: occurrenceLimit,
  );

  /// "Aylık", "Her 2 haftada bir", "Tek seferlik" gibi kısa açıklama.
  String get frequencyLabel {
    if (frequency == Frequency.once || intervalCount == 1) {
      return frequency.label;
    }
    return 'Her $intervalCount ${frequency.unit}da bir';
  }
}

/// Yeni plan veya düzenleme için gönderilen alanlar.
class ScheduleDraft {
  const ScheduleDraft({
    required this.title,
    required this.flow,
    required this.amount,
    required this.frequency,
    required this.startDate,
    this.intervalCount = 1,
    this.endDate,
    this.occurrenceLimit,
    this.remindDaysBefore = 3,
    this.categoryId,
    this.debtId,
    this.isActive = true,
  });

  final String title;
  final CashFlow flow;
  final int amount;
  final Frequency frequency;
  final int intervalCount;
  final DateTime startDate;
  final DateTime? endDate;
  final int? occurrenceLimit;
  final int remindDaysBefore;
  final String? categoryId;

  /// Bu plan bir taksitli borcun taksitleriyse borcun kimliği.
  final String? debtId;
  final bool isActive;

  Map<String, dynamic> toJson() => {
    'title': title,
    'flow': flow.name,
    'amount': amount,
    'frequency': frequency.name,
    'interval_count': intervalCount,
    'start_date': Dates.toDb(startDate),
    'end_date': endDate == null ? null : Dates.toDb(endDate!),
    'occurrence_limit': occurrenceLimit,
    'remind_days_before': remindDaysBefore,
    'category_id': categoryId,
    'debt_id': debtId,
    'is_active': isActive,
  };
}
