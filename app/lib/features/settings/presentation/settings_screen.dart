import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/date/dates.dart';
import '../../../services/backup/backup_controller.dart';
import '../../../services/notifications/notification_service.dart';
import '../../../services/notifications/reminder_sync.dart';
import '../../../core/widgets/async_body.dart';
import '../../../core/database/data_generation.dart';
import '../../../core/errors/data_failure.dart';
import '../data/data_reset_repository.dart';

/// Bildirim izninin durumu (yalnızca bildirim destekleyen cihazlarda).
final _notificationsEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(notificationServiceProvider).areEnabled(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Hesaplar'),
            subtitle: const Text('Nakit, banka ve kart hesapların'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.accounts),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Kategoriler'),
            subtitle: const Text('Gelir ve gider kategorileri'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.categories),
          ),
          const _BackupTile(),
          const _NotificationsTile(),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Tüm verilerimi sil',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text(
              'Bu telefondaki tüm kayıtların kalıcı olarak silinir',
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const _DeleteAllDataDialog(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupTile extends ConsumerWidget {
  const _BackupTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backup = ref.watch(backupControllerProvider);
    final last = backup.lastBackupAt;
    return ListTile(
      leading: Icon(
        backup.connected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
      ),
      title: const Text('Google Drive yedeği'),
      subtitle: Text(switch (backup) {
        BackupState(connected: false) =>
          'Kapalı · verilerin yalnızca bu telefonda',
        BackupState(message: final String m) => m,
        _ when last != null => 'Son yedek: ${Dates.dateTime(last)}',
        _ => 'Açık · henüz yedek yok',
      }),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(Routes.backup),
    );
  }
}

class _NotificationsTile extends ConsumerWidget {
  const _NotificationsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(notificationServiceProvider);
    if (!service.isSupported) {
      return const ListTile(
        leading: Icon(Icons.notifications_none),
        title: Text('Bildirimler'),
        subtitle: Text(
          'Bu cihazda bildirim yok; yaklaşan ödemeler Özet ekranında gösterilir.',
        ),
      );
    }
    final enabled = ref.watch(_notificationsEnabledProvider).value;
    final count = ref.watch(reminderSyncProvider).value;
    return ListTile(
      leading: Icon(
        enabled == true
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
      ),
      title: const Text('Bildirimler'),
      subtitle: Text(switch (enabled) {
        true => 'Açık · ${count ?? 0} hatırlatma kurulu · denemek için dokun',
        false => 'Kapalı · ödeme hatırlatmaları gelmez',
        null => 'Kontrol ediliyor…',
      }),
      onTap: enabled == true ? () => _sendTest(context, service) : null,
      trailing: enabled == false
          ? TextButton(
              onPressed: () async {
                await service.requestPermission();
                ref
                  ..invalidate(_notificationsEnabledProvider)
                  ..invalidate(reminderSyncProvider);
              },
              child: const Text('İzin ver'),
            )
          : null,
    );
  }

  /// Bildirimlerin bu telefonda çalıştığını denemek için 2 dakika sonrasına
  /// bir bildirim kurar.
  Future<void> _sendTest(
    BuildContext context,
    NotificationService service,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final at = await service.scheduleTest(const Duration(minutes: 2));
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    messenger.showSnackBar(
      SnackBar(content: Text('Deneme bildirimi $hh:$mm civarında gelecek.')),
    );
  }
}

/// Tüm verileri silme onayı: geri alınamaz olduğu için "SİL" yazılması istenir.
class _DeleteAllDataDialog extends ConsumerStatefulWidget {
  const _DeleteAllDataDialog();

  @override
  ConsumerState<_DeleteAllDataDialog> createState() =>
      _DeleteAllDataDialogState();
}

class _DeleteAllDataDialogState extends ConsumerState<_DeleteAllDataDialog> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await clearReminders(ref);
      await ref.read(dataResetRepositoryProvider).deleteAllData();
      ref.read(dataGenerationProvider.notifier).bump();
      if (navigator.mounted) navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Tüm verilerin silindi.')),
      );
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typed = _confirm.text.trim();
    final ready =
        typed == 'SİL' || typed.toUpperCase() == 'SIL' || typed == 'sil';
    return AlertDialog(
      title: const Text('Tüm verilerin silinsin mi?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bu telefondaki tüm kayıtların (hesaplar, işlemler, ödeme planları, '
            'borçlar) kalıcı olarak silinir ve uygulama ilk kurulduğu hâline döner. '
            'Bu işlem geri alınamaz.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            decoration: const InputDecoration(
              labelText: 'Onaylamak için SİL yaz',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FormErrorText(_error!),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: _busy || !ready ? null : _delete,
          child: const Text('Tümünü sil'),
        ),
      ],
    );
  }
}
