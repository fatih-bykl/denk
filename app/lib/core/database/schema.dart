import 'package:sqlite3/sqlite3.dart';

import 'ids.dart';

/// Şema sürümleri. Yeni bir değişiklik listeye yeni bir adım olarak eklenir;
/// eski adımlar asla değiştirilmez (kullanıcının telefonundaki veritabanı onları
/// zaten uygulamıştır). Sürüm `PRAGMA user_version` içinde tutulur.
final List<void Function(Database)> _steps = [_v1, _v2];

int get schemaVersion => _steps.length;

/// Veri tutan tablolar. Yedek gerekip gerekmediği bunlardaki değişikliklerden anlaşılır.
const dataTables = [
  'accounts',
  'categories',
  'debts',
  'transactions',
  'payment_schedules',
  'payment_occurrences',
];

int userVersion(Database db) =>
    db.select('PRAGMA user_version').first.values.first! as int;

void migrate(Database db) {
  final current = userVersion(db);
  if (current > _steps.length) {
    throw StateError(
      'Veritabanı bu uygulamadan daha yeni bir sürüme ait ($current > ${_steps.length}).',
    );
  }
  for (var v = current; v < _steps.length; v++) {
    db.execute('BEGIN');
    try {
      _steps[v](db);
      db.execute('PRAGMA user_version = ${v + 1}');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

const _now = "(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))";

/// Sürüm 1: hesaplar, kategoriler, borçlar, işlemler, ödeme planları ve dönemleri;
/// bakiye ve borç görünümleri. Veritabanı tek kişinin telefonunda durur.
void _v1(Database db) {
  db.execute('''
CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 60),
  opening_balance INTEGER NOT NULL DEFAULT 0,
  archived_at TEXT,
  created_at TEXT NOT NULL DEFAULT $_now
);

CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('income', 'expense')),
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 40),
  icon TEXT,
  archived_at TEXT,
  created_at TEXT NOT NULL DEFAULT $_now,
  UNIQUE (kind, name)
);

CREATE TABLE debts (
  id TEXT PRIMARY KEY,
  direction TEXT NOT NULL CHECK (direction IN ('payable', 'receivable')),
  counterparty TEXT NOT NULL CHECK (length(trim(counterparty)) BETWEEN 1 AND 80),
  title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 80),
  total_amount INTEGER NOT NULL CHECK (total_amount > 0),
  installment_count INTEGER CHECK (installment_count > 0),
  due_date TEXT,
  note TEXT CHECK (length(note) <= 500),
  closed_at TEXT,
  created_at TEXT NOT NULL DEFAULT $_now
);

CREATE TABLE transactions (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts (id) ON DELETE RESTRICT,
  category_id TEXT REFERENCES categories (id) ON DELETE SET NULL,
  type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
  amount INTEGER NOT NULL CHECK (amount > 0),
  occurred_on TEXT NOT NULL,
  note TEXT CHECK (length(note) <= 500),
  debt_id TEXT REFERENCES debts (id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT $_now
);

CREATE TABLE payment_schedules (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 80),
  flow TEXT NOT NULL CHECK (flow IN ('outflow', 'inflow')),
  amount INTEGER NOT NULL CHECK (amount > 0),
  frequency TEXT NOT NULL CHECK (frequency IN ('once', 'weekly', 'monthly', 'yearly')),
  interval_count INTEGER NOT NULL DEFAULT 1 CHECK (interval_count BETWEEN 1 AND 120),
  start_date TEXT NOT NULL,
  end_date TEXT CHECK (end_date >= start_date),
  occurrence_limit INTEGER CHECK (occurrence_limit > 0),
  remind_days_before INTEGER NOT NULL DEFAULT 3 CHECK (remind_days_before BETWEEN 0 AND 30),
  category_id TEXT REFERENCES categories (id) ON DELETE SET NULL,
  debt_id TEXT REFERENCES debts (id) ON DELETE CASCADE,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT $_now
);

CREATE TABLE payment_occurrences (
  id TEXT PRIMARY KEY,
  schedule_id TEXT NOT NULL REFERENCES payment_schedules (id) ON DELETE CASCADE,
  due_date TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK (amount > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'skipped')),
  transaction_id TEXT REFERENCES transactions (id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT $_now,
  UNIQUE (schedule_id, due_date)
);

CREATE INDEX transactions_occurred_on ON transactions (occurred_on);
CREATE INDEX transactions_account ON transactions (account_id);
CREATE INDEX transactions_category ON transactions (category_id);
CREATE INDEX transactions_debt ON transactions (debt_id);
CREATE INDEX schedules_category ON payment_schedules (category_id);
CREATE INDEX schedules_debt ON payment_schedules (debt_id);
CREATE INDEX occurrences_due_date ON payment_occurrences (due_date);
CREATE INDEX occurrences_transaction ON payment_occurrences (transaction_id);

-- İşlemin kategorisi işlemin türüyle aynı türde olmalı (gider işlemine gelir kategorisi verilemez).
CREATE TRIGGER transactions_category_kind_insert
BEFORE INSERT ON transactions
WHEN NEW.category_id IS NOT NULL
  AND (SELECT kind FROM categories WHERE id = NEW.category_id) <> NEW.type
BEGIN
  SELECT RAISE(ABORT, 'DNK04 kategori türü uyuşmuyor');
END;

CREATE TRIGGER transactions_category_kind_update
BEFORE UPDATE OF category_id, type ON transactions
WHEN NEW.category_id IS NOT NULL
  AND (SELECT kind FROM categories WHERE id = NEW.category_id) <> NEW.type
BEGIN
  SELECT RAISE(ABORT, 'DNK04 kategori türü uyuşmuyor');
END;

-- Ödemesini oluşturan işlem silinen dönem yeniden "bekliyor" durumuna döner.
-- (İşlem silinince yabancı anahtar transaction_id'yi boşaltır; bu tetikleyici durumu düzeltir.)
CREATE TRIGGER reopen_unpaid_occurrence
AFTER UPDATE OF transaction_id ON payment_occurrences
WHEN NEW.status = 'paid' AND NEW.transaction_id IS NULL AND OLD.transaction_id IS NOT NULL
BEGIN
  UPDATE payment_occurrences SET status = 'pending' WHERE id = NEW.id;
END;

-- Hesap bakiyeleri: açılış bakiyesi + gelirler − giderler. Saklanmaz, hesaplanır.
CREATE VIEW account_balances AS
SELECT
  a.id,
  a.rowid AS seq,
  a.name,
  a.opening_balance,
  a.archived_at,
  a.created_at,
  a.opening_balance + coalesce(
    sum(CASE t.type WHEN 'income' THEN t.amount ELSE -t.amount END),
    0
  ) AS balance
FROM accounts a
LEFT JOIN transactions t ON t.account_id = a.id
GROUP BY a.id;

-- Borç bakiyeleri: ödenen = borca bağlı, borcun yönüne uyan işlemler
-- (borçta giderler, alacakta gelirler). Kalan = toplam − ödenen.
CREATE VIEW debt_balances AS
SELECT
  x.id,
  x.seq,
  x.direction,
  x.counterparty,
  x.title,
  x.total_amount,
  x.installment_count,
  x.due_date,
  x.note,
  x.closed_at,
  x.created_at,
  x.paid AS paid_amount,
  x.total_amount - x.paid AS remaining_amount,
  x.schedule_id,
  (
    SELECT min(o.due_date)
    FROM payment_occurrences o
    WHERE o.schedule_id = x.schedule_id AND o.status = 'pending'
  ) AS next_due_date
FROM (
  SELECT
    d.*,
    d.rowid AS seq,
    coalesce((
      SELECT sum(t.amount)
      FROM transactions t
      WHERE t.debt_id = d.id
        AND t.type = CASE d.direction WHEN 'payable' THEN 'expense' ELSE 'income' END
    ), 0) AS paid,
    (
      SELECT ps.id
      FROM payment_schedules ps
      WHERE ps.debt_id = d.id
      ORDER BY ps.created_at, ps.rowid
      LIMIT 1
    ) AS schedule_id
  FROM debts d
) x;
''');

  seedDefaults(db);
}

/// Sürüm 2: uygulama ayarları ve Drive yedeği için "değişiklik var" işareti.
///
/// `settings` tablosu yedeğin içinde de taşınır; "Tüm verilerimi sil" ona dokunmaz.
/// Veri tablolarındaki her yazma `backup_dirty` değerini 1 yapar; başarılı bir
/// yedekten sonra uygulama onu 0'a çeker.
void _v2(Database db) {
  db.execute('''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT
);
INSERT INTO settings (key, value) VALUES ('backup_dirty', '1');
''');
  for (final table in dataTables) {
    for (final op in const ['INSERT', 'UPDATE', 'DELETE']) {
      db.execute('''
CREATE TRIGGER ${table}_${op.toLowerCase()}_marks_backup_dirty
AFTER $op ON $table
BEGIN
  UPDATE settings SET value = '1' WHERE key = 'backup_dirty' AND value <> '1';
END;
''');
    }
  }
}

/// Varsayılan hesap ve kategoriler: ilk açılışta ve tüm veriler silindikten sonra.
void seedDefaults(Database db) {
  db.execute("INSERT INTO accounts (id, name) VALUES (?, 'Nakit')", [newId()]);
  const categories = [
    ('expense', 'Market', 'shopping_cart'),
    ('expense', 'Kira', 'home'),
    ('expense', 'Faturalar', 'receipt'),
    ('expense', 'Ulaşım', 'directions_bus'),
    ('expense', 'Yeme-İçme', 'restaurant'),
    ('expense', 'Sağlık', 'medical_services'),
    ('expense', 'Eğitim', 'school'),
    ('expense', 'Giyim', 'checkroom'),
    ('expense', 'Eğlence', 'celebration'),
    ('expense', 'Abonelikler', 'subscriptions'),
    ('expense', 'Kredi ve borç ödemesi', 'credit_card'),
    ('expense', 'Diğer', 'more_horiz'),
    ('income', 'Maaş', 'payments'),
    ('income', 'Ek gelir', 'work'),
    ('income', 'Kira geliri', 'apartment'),
    ('income', 'Alacak tahsilatı', 'handshake'),
    ('income', 'Diğer', 'more_horiz'),
  ];
  final stmt = db.prepare(
    'INSERT INTO categories (id, kind, name, icon) VALUES (?, ?, ?, ?)',
  );
  for (final (kind, name, icon) in categories) {
    stmt.execute([newId(), kind, name, icon]);
  }
  stmt.close();
}
