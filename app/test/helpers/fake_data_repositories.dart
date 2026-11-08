import 'package:denk/core/errors/data_failure.dart';
import 'package:denk/features/accounts/data/accounts_repository.dart';
import 'package:denk/features/accounts/domain/account.dart';
import 'package:denk/features/categories/data/categories_repository.dart';
import 'package:denk/features/categories/domain/category.dart';
import 'package:denk/features/debts/data/debts_repository.dart';
import 'package:denk/features/debts/domain/debt.dart';
import 'package:denk/features/schedule/data/schedule_repository.dart';
import 'package:denk/features/schedule/domain/occurrence.dart';
import 'package:denk/features/schedule/domain/payment_schedule.dart';
import 'package:denk/features/transactions/data/transactions_repository.dart';
import 'package:denk/features/transactions/domain/transaction.dart';

/// Bellekte çalışan hesap deposu. Bakiye = açılış + [movements].
class FakeAccountsRepository implements AccountsRepository {
  final List<Account> _accounts = [];
  final Map<String, int> movements = {};
  int _nextId = 1;

  /// Verilirse bir sonraki yazma işlemi bu hatayı fırlatır.
  DataFailure? nextFailure;

  String add(
    String name, {
    int opening = 0,
    int movement = 0,
    bool archived = false,
  }) {
    final id = 'a${_nextId++}';
    _accounts.add(
      Account(
        id: id,
        name: name,
        openingBalance: opening,
        balance: opening + movement,
        archivedAt: archived ? DateTime(2026) : null,
      ),
    );
    movements[id] = movement;
    return id;
  }

  void _failIfNeeded() {
    final f = nextFailure;
    nextFailure = null;
    if (f != null) throw f;
  }

  Account byName(String name) => _accounts.firstWhere((a) => a.name == name);

  /// Verilirse bakiyeye bu hesaptaki işlemlerin toplamı da eklenir.
  int Function(String accountId)? transactionTotal;

  /// Verilirse okuma bu hatayı fırlatır (bağlantı kopması gibi).
  DataFailure? fetchFailure;

  @override
  Future<List<Account>> fetchAll() async => [
    if (fetchFailure != null) throw fetchFailure!,
    for (final a in _accounts)
      Account(
        id: a.id,
        name: a.name,
        openingBalance: a.openingBalance,
        balance: a.balance + (transactionTotal?.call(a.id) ?? 0),
        archivedAt: a.archivedAt,
      ),
  ];

  @override
  Future<void> create({
    required String name,
    required int openingBalance,
  }) async {
    _failIfNeeded();
    add(name, opening: openingBalance);
  }

  @override
  Future<void> update(
    String id, {
    required String name,
    required int openingBalance,
  }) async {
    _failIfNeeded();
    final i = _accounts.indexWhere((a) => a.id == id);
    final old = _accounts[i];
    _accounts[i] = Account(
      id: id,
      name: name,
      openingBalance: openingBalance,
      balance: openingBalance + (movements[id] ?? 0),
      archivedAt: old.archivedAt,
    );
  }

  @override
  Future<void> setArchived(String id, {required bool archived}) async {
    _failIfNeeded();
    final i = _accounts.indexWhere((a) => a.id == id);
    final old = _accounts[i];
    _accounts[i] = Account(
      id: id,
      name: old.name,
      openingBalance: old.openingBalance,
      balance: old.balance,
      archivedAt: archived ? DateTime(2026) : null,
    );
  }
}

class FakeCategoriesRepository implements CategoriesRepository {
  final List<Category> _categories = [];
  int _nextId = 1;

  void add(EntryKind kind, String name, {String? icon, bool archived = false}) {
    _categories.add(
      Category(
        id: 'c${_nextId++}',
        kind: kind,
        name: name,
        icon: icon,
        archivedAt: archived ? DateTime(2026) : null,
      ),
    );
  }

  Category byName(String name) => _categories.firstWhere((c) => c.name == name);

  @override
  Future<List<Category>> fetchAll() async => List.of(_categories);

  @override
  Future<void> create({
    required EntryKind kind,
    required String name,
    required String icon,
  }) async {
    if (_categories.any((c) => c.kind == kind && c.name == name)) {
      throw const DataFailure('Bu adla bir kayıt zaten var.');
    }
    add(kind, name, icon: icon);
  }

  @override
  Future<void> update(
    String id, {
    required String name,
    required String icon,
  }) async {
    final i = _categories.indexWhere((c) => c.id == id);
    final old = _categories[i];
    _categories[i] = Category(
      id: id,
      kind: old.kind,
      name: name,
      icon: icon,
      archivedAt: old.archivedAt,
    );
  }

  @override
  Future<void> setArchived(String id, {required bool archived}) async {
    final i = _categories.indexWhere((c) => c.id == id);
    final old = _categories[i];
    _categories[i] = Category(
      id: id,
      kind: old.kind,
      name: old.name,
      icon: old.icon,
      archivedAt: archived ? DateTime(2026) : null,
    );
  }
}

/// Bellekte çalışan işlem deposu. Bağlı hesap deposunun bakiyelerini günceller.
class FakeTransactionsRepository implements TransactionsRepository {
  FakeTransactionsRepository([FakeAccountsRepository? accounts]) {
    accounts?.transactionTotal = (accountId) => items
        .where((t) => t.accountId == accountId)
        .fold(0, (sum, t) => sum + t.signedAmount);
  }

  final List<Transaction> items = [];
  int _nextId = 1;

  Transaction _build(String id, TransactionDraft d) => Transaction(
    id: id,
    accountId: d.accountId,
    categoryId: d.categoryId,
    type: d.type,
    amount: d.amount,
    occurredOn: d.occurredOn,
    note: (d.note == null || d.note!.trim().isEmpty) ? null : d.note!.trim(),
    debtId: d.debtId,
  );

  void add(TransactionDraft draft) => items.add(_build('t${_nextId++}', draft));

  DataFailure? fetchFailure;

  @override
  Future<List<Transaction>> fetchMonth(DateTime month) async {
    if (fetchFailure != null) throw fetchFailure!;
    final list =
        items
            .where(
              (t) =>
                  t.occurredOn.year == month.year &&
                  t.occurredOn.month == month.month,
            )
            .toList()
          ..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
    return list;
  }

  @override
  Future<List<Transaction>> fetchByDebt(String debtId) async =>
      items.where((t) => t.debtId == debtId).toList();

  @override
  Future<void> create(TransactionDraft draft) async => add(draft);

  @override
  Future<void> update(String id, TransactionDraft draft) async {
    final i = items.indexWhere((t) => t.id == id);
    items[i] = _build(id, draft);
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((t) => t.id == id);
}

/// Bellekte çalışan ödeme takvimi deposu. Veritabanı fonksiyonlarının
/// davranışını taklit eder: eşitleme ödenmiş dönemlere dokunmaz, ödeme işlem
/// oluşturur, işlem silinince dönem yeniden açılır.
class FakeScheduleRepository implements ScheduleRepository {
  FakeScheduleRepository(this.transactions);

  final FakeTransactionsRepository transactions;
  final List<PaymentSchedule> schedules = [];
  final List<Occurrence> occurrences = [];
  int _nextId = 1;

  PaymentSchedule _fromDraft(String id, ScheduleDraft d) =>
      PaymentSchedule.fromDraft(id, d);

  PaymentSchedule byTitle(String title) =>
      schedules.firstWhere((s) => s.title == title);

  /// İşlemi silinmiş ödenen dönemleri yeniden açar (veritabanı tetikleyicisi).
  List<Occurrence> _current() {
    for (var i = 0; i < occurrences.length; i++) {
      final o = occurrences[i];
      if (o.status == OccurrenceStatus.paid &&
          !transactions.items.any((t) => t.id == o.transactionId)) {
        occurrences[i] = _copy(
          o,
          status: OccurrenceStatus.pending,
          clearTx: true,
        );
      }
    }
    return occurrences;
  }

  Occurrence _copy(
    Occurrence o, {
    OccurrenceStatus? status,
    int? amount,
    String? transactionId,
    bool clearTx = false,
  }) => Occurrence(
    id: o.id,
    scheduleId: o.scheduleId,
    dueDate: o.dueDate,
    amount: amount ?? o.amount,
    status: status ?? o.status,
    title: o.title,
    flow: o.flow,
    transactionId: clearTx ? null : (transactionId ?? o.transactionId),
  );

  DataFailure? fetchFailure;

  @override
  Future<List<PaymentSchedule>> fetchSchedules() async {
    if (fetchFailure != null) throw fetchFailure!;
    return List.of(schedules);
  }

  @override
  Future<String> createSchedule(ScheduleDraft draft) async {
    final id = 's${_nextId++}';
    schedules.add(_fromDraft(id, draft));
    return id;
  }

  @override
  Future<void> updateSchedule(String id, ScheduleDraft draft) async {
    final i = schedules.indexWhere((s) => s.id == id);
    schedules[i] = _fromDraft(id, draft);
  }

  @override
  Future<void> deleteSchedule(String id) async {
    schedules.removeWhere((s) => s.id == id);
    occurrences.removeWhere((o) => o.scheduleId == id);
  }

  @override
  Future<List<Occurrence>> fetchOccurrences({
    DateTime? from,
    DateTime? to,
  }) async =>
      _current()
          .where(
            (o) =>
                (from == null || !o.dueDate.isBefore(from)) &&
                (to == null || o.dueDate.isBefore(to)),
          )
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  @override
  Future<List<Occurrence>> fetchOverdue(DateTime before) async => _current()
      .where((o) => o.isPending && o.dueDate.isBefore(before))
      .toList();

  @override
  Future<void> syncOccurrences(
    String scheduleId,
    DateTime from,
    List<DateTime> dates, {
    List<int>? amounts,
  }) async {
    int amountFor(DateTime d, int fallback) {
      final i = dates.indexOf(d);
      return amounts != null && i >= 0 && i < amounts.length
          ? amounts[i]
          : fallback;
    }

    final s = schedules.firstWhere((s) => s.id == scheduleId);
    occurrences.removeWhere(
      (o) =>
          o.scheduleId == scheduleId &&
          o.isPending &&
          !o.dueDate.isBefore(from) &&
          !dates.contains(o.dueDate),
    );
    for (var i = 0; i < occurrences.length; i++) {
      final o = occurrences[i];
      if (o.scheduleId == scheduleId &&
          o.isPending &&
          !o.dueDate.isBefore(from)) {
        occurrences[i] = _copy(o, amount: amountFor(o.dueDate, s.amount));
      }
    }
    for (final d in dates.where((d) => !d.isBefore(from))) {
      if (!occurrences.any(
        (o) => o.scheduleId == scheduleId && o.dueDate == d,
      )) {
        occurrences.add(
          Occurrence(
            id: 'o${_nextId++}',
            scheduleId: scheduleId,
            dueDate: d,
            amount: amountFor(d, s.amount),
            status: OccurrenceStatus.pending,
            title: s.title,
            flow: s.flow,
          ),
        );
      }
    }
  }

  @override
  Future<String> pay(
    String occurrenceId, {
    required String accountId,
    required int amount,
    required DateTime paidOn,
  }) async {
    final i = occurrences.indexWhere((o) => o.id == occurrenceId);
    final o = occurrences[i];
    if (!o.isPending) throw const DataFailure('Bu dönem zaten kapatılmış.');
    final s = schedules.firstWhere((s) => s.id == o.scheduleId);
    transactions.add(
      TransactionDraft(
        accountId: accountId,
        type: s.flow.entryKind,
        amount: amount,
        occurredOn: paidOn,
        categoryId: s.categoryId,
        note: s.title,
        debtId: s.debtId,
      ),
    );
    final txId = transactions.items.last.id;
    occurrences[i] = _copy(
      o,
      status: OccurrenceStatus.paid,
      amount: amount,
      transactionId: txId,
    );
    return txId;
  }

  @override
  Future<void> setSkipped(String occurrenceId, {required bool skipped}) async {
    final i = occurrences.indexWhere((o) => o.id == occurrenceId);
    occurrences[i] = _copy(
      occurrences[i],
      status: skipped ? OccurrenceStatus.skipped : OccurrenceStatus.pending,
    );
  }
}

/// Bellekte çalışan borç deposu. Ödenen tutarı işlem deposundan, taksit planını
/// takvim deposundan hesaplar (veritabanındaki debt_balances görünümü gibi).
class FakeDebtsRepository implements DebtsRepository {
  FakeDebtsRepository(this.transactions, this.schedule);

  final FakeTransactionsRepository transactions;
  final FakeScheduleRepository schedule;
  final Map<String, (DebtDraft, DateTime?)> rows = {};
  int _nextId = 1;

  Debt byTitle(String title) => _view().firstWhere((d) => d.title == title);

  List<Debt> _view() => [
    for (final MapEntry(key: id, value: (d, closedAt)) in rows.entries)
      () {
        final paid = transactions.items
            .where((t) => t.debtId == id && t.type == d.direction.entryKind)
            .fold(0, (s, t) => s + t.amount);
        final plan = schedule.schedules
            .where((s) => s.debtId == id)
            .firstOrNull;
        final pending = plan == null
            ? const <Occurrence>[]
            : (schedule.occurrences
                  .where((o) => o.scheduleId == plan.id && o.isPending)
                  .toList()
                ..sort((a, b) => a.dueDate.compareTo(b.dueDate)));
        return Debt(
          id: id,
          direction: d.direction,
          counterparty: d.counterparty,
          title: d.title,
          totalAmount: d.totalAmount,
          paidAmount: paid,
          remainingAmount: d.totalAmount - paid,
          installmentCount: d.installmentCount,
          dueDate: d.dueDate,
          note: d.note,
          closedAt: closedAt,
          scheduleId: plan?.id,
          nextDueDate: pending.isEmpty ? null : pending.first.dueDate,
        );
      }(),
  ];

  DataFailure? fetchFailure;

  @override
  Future<List<Debt>> fetchAll() async {
    if (fetchFailure != null) throw fetchFailure!;
    return _view();
  }

  @override
  Future<String> create(DebtDraft draft) async {
    final id = 'd${_nextId++}';
    rows[id] = (draft, null);
    return id;
  }

  @override
  Future<void> update(String id, DebtDraft draft) async =>
      rows[id] = (draft, rows[id]!.$2);

  @override
  Future<void> delete(String id) async {
    rows.remove(id);
    for (final s in schedule.schedules.where((s) => s.debtId == id).toList()) {
      await schedule.deleteSchedule(s.id);
    }
    for (var i = 0; i < transactions.items.length; i++) {
      final t = transactions.items[i];
      if (t.debtId == id) {
        transactions.items[i] = Transaction(
          id: t.id,
          accountId: t.accountId,
          categoryId: t.categoryId,
          type: t.type,
          amount: t.amount,
          occurredOn: t.occurredOn,
          note: t.note,
        );
      }
    }
  }

  @override
  Future<void> setClosed(String id, {required bool closed}) async =>
      rows[id] = (rows[id]!.$1, closed ? DateTime(2026, 11, 5) : null);
}
