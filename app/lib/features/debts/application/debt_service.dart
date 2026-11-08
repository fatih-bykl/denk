import '../../../core/recurrence/recurrence.dart';
import '../../schedule/application/schedule_providers.dart';
import '../../schedule/data/schedule_repository.dart';
import '../../schedule/domain/payment_schedule.dart';
import '../data/debts_repository.dart';
import '../domain/debt.dart';

/// Borç kaydı ile taksit planını birlikte yönetir.
class DebtService {
  DebtService({
    required this.debts,
    required this.schedules,
    required this.today,
  });

  final DebtsRepository debts;
  final ScheduleRepository schedules;
  final DateTime today;

  /// Borcu kaydeder. [firstInstallment] verilirse ([DebtDraft.installmentCount]
  /// ile birlikte) aylık taksit planı oluşturulur/güncellenir; verilmezse
  /// varsa eski plan silinir.
  Future<void> save({
    Debt? existing,
    PaymentSchedule? existingSchedule,
    required DebtDraft draft,
    DateTime? firstInstallment,
  }) async {
    final String id;
    if (existing != null) {
      await debts.update(existing.id, draft);
      id = existing.id;
    } else {
      id = await debts.create(draft);
    }

    final count = draft.installmentCount;
    if (count == null || firstInstallment == null) {
      if (existingSchedule != null) {
        await schedules.deleteSchedule(existingSchedule.id);
      }
      return;
    }

    final split = splitInstallments(draft.totalAmount, count);
    final scheduleDraft = ScheduleDraft(
      title: '${draft.title} (${draft.counterparty})',
      flow: draft.direction.flow,
      amount: split.first,
      frequency: Frequency.monthly,
      startDate: firstInstallment,
      occurrenceLimit: count,
      remindDaysBefore: existingSchedule?.remindDaysBefore ?? 3,
      categoryId: existingSchedule?.categoryId,
      debtId: id,
      isActive: !(existing?.isClosed ?? false),
    );
    final String scheduleId;
    if (existingSchedule != null) {
      await schedules.updateSchedule(existingSchedule.id, scheduleDraft);
      scheduleId = existingSchedule.id;
    } else {
      scheduleId = await schedules.createSchedule(scheduleDraft);
    }
    await syncSchedule(
      schedules,
      PaymentSchedule.fromDraft(scheduleId, scheduleDraft),
      today,
      debtTotal: draft.totalAmount,
    );
  }

  /// Kapatılan borcun bekleyen taksitleri takvimden kalkar; yeniden açılınca geri gelir.
  Future<void> setClosed(
    Debt debt,
    PaymentSchedule? schedule, {
    required bool closed,
  }) async {
    await debts.setClosed(debt.id, closed: closed);
    if (schedule == null) return;
    final updated = ScheduleDraft(
      title: schedule.title,
      flow: schedule.flow,
      amount: schedule.amount,
      frequency: schedule.frequency,
      intervalCount: schedule.intervalCount,
      startDate: schedule.startDate,
      endDate: schedule.endDate,
      occurrenceLimit: schedule.occurrenceLimit,
      remindDaysBefore: schedule.remindDaysBefore,
      categoryId: schedule.categoryId,
      debtId: schedule.debtId,
      isActive: !closed,
    );
    await schedules.updateSchedule(schedule.id, updated);
    await syncSchedule(
      schedules,
      PaymentSchedule.fromDraft(schedule.id, updated),
      today,
      debtTotal: debt.totalAmount,
    );
  }
}
