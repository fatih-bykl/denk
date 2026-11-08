import '../../../core/date/dates.dart';
import '../../categories/domain/category.dart';
import '../../schedule/domain/payment_schedule.dart';

enum DebtDirection {
  payable('Borç', 'Borçlarım', CashFlow.outflow, EntryKind.expense),
  receivable('Alacak', 'Alacaklarım', CashFlow.inflow, EntryKind.income);

  const DebtDirection(this.label, this.plural, this.flow, this.entryKind);

  final String label;
  final String plural;

  /// Taksit planının yönü.
  final CashFlow flow;

  /// Ödeme / tahsilat işleminin türü.
  final EntryKind entryKind;

  static DebtDirection fromName(String name) =>
      values.firstWhere((d) => d.name == name);
}

/// `debt_balances` görünümünden bir satır: borç + hesaplanan ödenen/kalan.
class Debt {
  const Debt({
    required this.id,
    required this.direction,
    required this.counterparty,
    required this.title,
    required this.totalAmount,
    required this.paidAmount,
    required this.remainingAmount,
    this.installmentCount,
    this.dueDate,
    this.note,
    this.closedAt,
    this.scheduleId,
    this.nextDueDate,
  });

  factory Debt.fromJson(Map<String, dynamic> json) => Debt(
    id: json['id'] as String,
    direction: DebtDirection.fromName(json['direction'] as String),
    counterparty: json['counterparty'] as String,
    title: json['title'] as String,
    totalAmount: (json['total_amount'] as num).toInt(),
    paidAmount: (json['paid_amount'] as num).toInt(),
    remainingAmount: (json['remaining_amount'] as num).toInt(),
    installmentCount: json['installment_count'] as int?,
    dueDate: json['due_date'] == null
        ? null
        : Dates.fromDb(json['due_date'] as String),
    note: json['note'] as String?,
    closedAt: json['closed_at'] == null
        ? null
        : DateTime.parse(json['closed_at'] as String),
    scheduleId: json['schedule_id'] as String?,
    nextDueDate: json['next_due_date'] == null
        ? null
        : Dates.fromDb(json['next_due_date'] as String),
  );

  final String id;
  final DebtDirection direction;
  final String counterparty;
  final String title;

  /// Kuruş.
  final int totalAmount;
  final int paidAmount;
  final int remainingAmount;
  final int? installmentCount;

  /// Taksitsiz borcun vadesi.
  final DateTime? dueDate;
  final String? note;
  final DateTime? closedAt;

  /// Taksitliyse taksitlerin ödeme planı.
  final String? scheduleId;

  /// Sıradaki ödenmemiş taksitin vadesi.
  final DateTime? nextDueDate;

  bool get isClosed => closedAt != null;
  bool get hasInstallments => scheduleId != null;

  /// Gösterilecek vade: taksitliyse sıradaki taksit, değilse borcun vadesi.
  DateTime? get upcomingDate => hasInstallments ? nextDueDate : dueDate;

  /// 0–1 arası ödeme oranı.
  double get progress =>
      totalAmount == 0 ? 0 : (paidAmount / totalAmount).clamp(0, 1).toDouble();
}

class DebtDraft {
  const DebtDraft({
    required this.direction,
    required this.counterparty,
    required this.title,
    required this.totalAmount,
    this.installmentCount,
    this.dueDate,
    this.note,
  });

  final DebtDirection direction;
  final String counterparty;
  final String title;
  final int totalAmount;
  final int? installmentCount;
  final DateTime? dueDate;
  final String? note;

  Map<String, dynamic> toJson() => {
    'direction': direction.name,
    'counterparty': counterparty,
    'title': title,
    'total_amount': totalAmount,
    'installment_count': installmentCount,
    'due_date': dueDate == null ? null : Dates.toDb(dueDate!),
    'note': (note == null || note!.trim().isEmpty) ? null : note!.trim(),
  };
}
