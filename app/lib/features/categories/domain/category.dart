enum EntryKind {
  income('Gelir'),
  expense('Gider');

  const EntryKind(this.label);

  final String label;

  static EntryKind fromName(String name) =>
      values.firstWhere((k) => k.name == name);
}

class Category {
  const Category({
    required this.id,
    required this.kind,
    required this.name,
    this.icon,
    this.archivedAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    kind: EntryKind.fromName(json['kind'] as String),
    name: json['name'] as String,
    icon: json['icon'] as String?,
    archivedAt: json['archived_at'] == null
        ? null
        : DateTime.parse(json['archived_at'] as String),
  );

  final String id;
  final EntryKind kind;
  final String name;

  /// [CategoryIcons] içindeki anahtar.
  final String? icon;
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;
}
