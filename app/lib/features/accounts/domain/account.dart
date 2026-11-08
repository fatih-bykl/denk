class Account {
  const Account({
    required this.id,
    required this.name,
    required this.openingBalance,
    required this.balance,
    this.archivedAt,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    name: json['name'] as String,
    openingBalance: (json['opening_balance'] as num).toInt(),
    balance: (json['balance'] as num).toInt(),
    archivedAt: json['archived_at'] == null
        ? null
        : DateTime.parse(json['archived_at'] as String),
  );

  final String id;
  final String name;

  /// Kuruş.
  final int openingBalance;

  /// Kuruş: açılış bakiyesi + gelirler − giderler.
  final int balance;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;
}
