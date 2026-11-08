import '../../../core/date/dates.dart';
import '../../categories/domain/category.dart';

class Transaction {
  const Transaction({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    required this.occurredOn,
    this.categoryId,
    this.note,
    this.debtId,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
    id: json['id'] as String,
    accountId: json['account_id'] as String,
    categoryId: json['category_id'] as String?,
    type: EntryKind.fromName(json['type'] as String),
    amount: (json['amount'] as num).toInt(),
    occurredOn: Dates.fromDb(json['occurred_on'] as String),
    note: json['note'] as String?,
    debtId: json['debt_id'] as String?,
  );

  final String id;
  final String accountId;
  final String? categoryId;
  final EntryKind type;

  /// Kuruş, her zaman pozitif. Yönü [type] belirler.
  final int amount;
  final DateTime occurredOn;
  final String? note;
  final String? debtId;

  /// Bakiyeye etkisi: gelir artı, gider eksi.
  int get signedAmount => type == EntryKind.income ? amount : -amount;
}

/// Yeni işlem veya düzenleme için gönderilen alanlar.
class TransactionDraft {
  const TransactionDraft({
    required this.accountId,
    required this.type,
    required this.amount,
    required this.occurredOn,
    this.categoryId,
    this.note,
    this.debtId,
  });

  final String accountId;
  final String? categoryId;
  final EntryKind type;
  final int amount;
  final DateTime occurredOn;
  final String? note;

  /// Bu işlem bir borcun ödemesi / alacağın tahsilatıysa borcun kimliği.
  final String? debtId;

  Map<String, dynamic> toJson() => {
    'account_id': accountId,
    'category_id': categoryId,
    'type': type.name,
    'amount': amount,
    'occurred_on': Dates.toDb(occurredOn),
    'note': (note == null || note!.trim().isEmpty) ? null : note!.trim(),
    'debt_id': debtId,
  };
}
