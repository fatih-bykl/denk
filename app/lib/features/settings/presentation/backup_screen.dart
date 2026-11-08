import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date/dates.dart';
import '../../../core/widgets/async_body.dart';
import '../../../services/backup/backup_controller.dart';
import '../../../services/backup/backup_store.dart';

/// Ayarlar → Google Drive yedeği.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  @override
  void initState() {
    super.initState();
    // Bağlıysa Drive'daki yedekleri listele.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(backupControllerProvider);
      if (state.connected && state.backups == null) {
        ref.read(backupControllerProvider.notifier).refreshList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(backupControllerProvider);
    final controller = ref.read(backupControllerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive yedeği')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (state.busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          if (!state.configured)
            const _InfoCard(
              icon: Icons.build_outlined,
              text:
                  'Drive yedeği bu sürümde henüz kullanılamıyor. Verilerin bu '
                  'telefonda güvende; uygulamanın bir sonraki sürümünde açılacak.',
            )
          else if (!state.connected)
            _Disconnected(busy: state.busy, onConnect: controller.connect)
          else ...[
            _Status(state: state),
            if (state.needsDecision) ...[
              const SizedBox(height: 12),
              const _InfoCard(
                icon: Icons.info_outline,
                text:
                    "Drive'ında daha önce alınmış yedekler var. Eski verilerini "
                    'bu telefona almak için aşağıdan bir yedeği geri yükle. '
                    'Bu telefondaki verileri yedeklemek istersen "Şimdi yedekle"ye bas; '
                    'otomatik yedekleme o zaman başlar.',
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.busy ? null : controller.backupNow,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Şimdi yedekle'),
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 12),
            FormErrorText(state.message!),
          ],
          if (state.connected) ...[
            const SizedBox(height: 24),
            Text('Yedekler', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              "Son $keepBackups yedek saklanır; daha eskiler kendiliğinden silinir.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            switch (state.backups) {
              null when state.busy => const SizedBox.shrink(),
              null => TextButton(
                onPressed: controller.refreshList,
                child: const Text('Yedekleri göster'),
              ),
              [] => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("Drive'da henüz yedek yok."),
              ),
              final list => Column(
                children: [
                  for (final b in list)
                    _BackupTile(
                      backup: b,
                      enabled: !state.busy,
                      onRestore: () => _confirmRestore(b),
                    ),
                ],
              ),
            },
            const SizedBox(height: 24),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link_off),
              title: const Text('Bağlantıyı kes'),
              subtitle: const Text(
                "Otomatik yedekleme durur; Drive'daki yedekler silinmez.",
              ),
              enabled: !state.busy,
              onTap: controller.disconnect,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                "Drive'daki yedekleri sil",
                style: TextStyle(color: theme.colorScheme.error),
              ),
              enabled: !state.busy && (state.backups?.isNotEmpty ?? false),
              onTap: _confirmDeleteBackups,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRestore(BackupFile backup) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bu yedek geri yüklensin mi?'),
        content: Text(
          '${Dates.dateTime(backup.createdAt)} tarihli yedek yüklenecek. '
          'Bu telefondaki şu anki verilerin yedektekilerle değişir; '
          'yedekten sonra girdiğin kayıtlar silinir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Geri yükle'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(backupControllerProvider.notifier).restore(backup);
    if (ref.read(backupControllerProvider).message == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Yedek geri yüklendi.')),
      );
    }
  }

  Future<void> _confirmDeleteBackups() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Drive'daki yedekler silinsin mi?"),
        content: const Text(
          "Drive'daki tüm Denk yedekleri kalıcı olarak silinir. Bu telefondaki "
          'verilere dokunulmaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yedekleri sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(backupControllerProvider.notifier).deleteAllBackups();
    }
  }
}

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.busy, required this.onConnect});

  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _InfoCard(
          icon: Icons.cloud_outlined,
          text:
              "Verilerin şu an yalnızca bu telefonda. Google Drive'a bağlarsan "
              'değişiklik oldukça kendi Drive hesabına otomatik yedeklenir; '
              'telefonun kaybolursa ya da değişirse yedeği geri yüklersin.\n\n'
              "Yedekler Drive'ında yalnızca Denk'in görebildiği gizli bir "
              "klasörde durur. Denk, Drive'ındaki diğer dosyalarını göremez.",
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : onConnect,
          icon: const Icon(Icons.add_to_drive),
          label: const Text('Google Drive’a bağlan'),
        ),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.state});

  final BackupState state;

  @override
  Widget build(BuildContext context) {
    final last = state.lastBackupAt;
    final account = state.account;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.cloud_done_outlined),
        title: Text(
          account == null || account.isEmpty ? 'Google Drive' : account,
        ),
        subtitle: Text(
          [
            last == null
                ? 'Henüz yedek alınmadı'
                : 'Son yedek: ${Dates.dateTime(last)}',
            state.autoBackup
                ? 'Otomatik yedekleme açık'
                : 'Otomatik yedekleme bekliyor',
          ].join('\n'),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({
    required this.backup,
    required this.enabled,
    required this.onRestore,
  });

  final BackupFile backup;
  final bool enabled;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final kb = (backup.sizeBytes / 1024).ceil();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history),
      title: Text(Dates.dateTime(backup.createdAt)),
      subtitle: Text('$kb KB'),
      trailing: TextButton(
        onPressed: enabled ? onRestore : null,
        child: const Text('Geri yükle'),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
