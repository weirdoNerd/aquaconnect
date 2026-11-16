import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../models/provider_application.dart';
import '../models/provider_profile.dart';
import '../providers/provider_admin_provider.dart';
import '../providers/source_provider.dart';
import '../services/provider_service.dart';

/// Tab ketiga di Panel Pengelola: tinjauan pengajuan penyedia dan daftar
/// penyedia aktif/diputus.
class ProviderAdminTab extends StatelessWidget {
  const ProviderAdminTab({super.key});

  @override
  Widget build(BuildContext context) {
    final pa = context.watch<ProviderAdminProvider>();
    final sources = context.watch<SourceProvider>().all;

    if (pa.loading && pa.pending.isEmpty && pa.providers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pa.loadError != null && pa.pending.isEmpty && pa.providers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(pa.loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: pa.reload,
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: pa.reload,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (pa.loadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                pa.loadError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Text(
            'Pengajuan',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (pa.pending.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Tidak ada pengajuan yang menunggu'),
              ),
            )
          else
            for (final app in pa.pending) _PendingApplicationCard(app: app),
          const SizedBox(height: 16),
          Text(
            'Penyedia',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (pa.providers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Belum ada penyedia terdaftar'),
              ),
            )
          else
            for (final p in pa.providers)
              _ProviderProfileCard(
                profile: p,
                sourceCount: sources.where((s) => s.ownerId == p.uid).length,
              ),
        ],
      ),
    );
  }
}

class _PendingApplicationCard extends StatelessWidget {
  final ProviderApplication app;
  const _PendingApplicationCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final date = app.createdAt == null
        ? 'Baru saja'
        : DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(app.createdAt!);

    return Card(
      child: InkWell(
        onTap: () => _showProviderReviewSheet(context, app),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.organizationName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text(app.contactPhone),
                ],
              ),
              const SizedBox(height: 4),
              Text(app.description),
              const SizedBox(height: 6),
              Text(date, style: Theme.of(context).textTheme.bodySmall),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showProviderReviewSheet(context, app),
                  child: const Text('Tinjau'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showProviderReviewSheet(
  BuildContext context,
  ProviderApplication app,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _ProviderReviewSheet(app: app),
    ),
  );
}

class _ProviderReviewSheet extends StatefulWidget {
  final ProviderApplication app;
  const _ProviderReviewSheet({required this.app});

  @override
  State<_ProviderReviewSheet> createState() => _ProviderReviewSheetState();
}

class _ProviderReviewSheetState extends State<_ProviderReviewSheet> {
  final _note = TextEditingController();
  String? _noteError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProviderAdminProvider>().clearError();
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    String cleanNote;
    try {
      cleanNote = validateAdminNote(_note.text, required: !approve);
    } on ProviderException catch (e) {
      setState(() => _noteError = e.message);
      return;
    }

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context.read<ProviderAdminProvider>().review(
          widget.app.uid,
          approve: approve,
          note: cleanNote,
        );
    if (!mounted) return;
    if (ok) {
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(approve
            ? 'Pengajuan disetujui. Akun menjadi penyedia aktif.'
            : 'Pengajuan ditolak dan catatan disimpan.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pa = context.watch<ProviderAdminProvider>();
    final date = widget.app.createdAt == null
        ? '-'
        : DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(widget.app.createdAt!);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tinjau pengajuan penyedia',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            widget.app.organizationName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text('Telepon: ${widget.app.contactPhone}'),
          const SizedBox(height: 4),
          Text('Deskripsi: ${widget.app.description}'),
          const SizedBox(height: 4),
          Text(
            'Dikirim: $date • Ketentuan v${widget.app.termsVersion}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Catatan admin (wajib jika menolak, min. 5 karakter)',
              errorText: _noteError,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_noteError != null) setState(() => _noteError = null);
            },
          ),
          if (pa.error != null) ...[
            const SizedBox(height: 8),
            Text(
              pa.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade800,
                  ),
                  onPressed: pa.busy ? null : () => _decide(false),
                  child: const Text('Tolak'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: pa.busy ? null : () => _decide(true),
                  child: pa.busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Setujui'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderProfileCard extends StatelessWidget {
  final ProviderProfile profile;
  final int sourceCount;
  const _ProviderProfileCard({
    required this.profile,
    required this.sourceCount,
  });

  Future<void> _terminate(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _TerminateDialog(name: profile.name),
    );
    if (reason == null || !context.mounted) return;
    final pa = context.read<ProviderAdminProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await pa.terminate(profile.uid, reason);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Kemitraan diputus dan semua sumbernya ditangguhkan.'
          : pa.error ?? 'Gagal memutus kemitraan.'),
    ));
  }

  Future<void> _reactivate(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aktifkan kembali "${profile.name}"?'),
        content: const Text(
          'Status penyedia akan kembali aktif, tetapi sumber yang sebelumnya '
          'ditangguhkan TIDAK otomatis tayang lagi dan harus ditayangkan satu per satu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aktifkan kembali'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final pa = context.read<ProviderAdminProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await pa.reactivate(profile.uid);
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Penyedia diaktifkan kembali.'
          : pa.error ?? 'Gagal mengaktifkan penyedia.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pa = context.watch<ProviderAdminProvider>();
    final active = profile.status == ProviderStatus.active;
    final note = profile.note?.trim() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (profile.email.isNotEmpty)
                        Text(
                          profile.email,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                _ProviderStatusChip(active: active),
              ],
            ),
            const SizedBox(height: 6),
            Text('Jumlah sumber: $sourceCount'),
            if (!active && note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Alasan pemutusan: $note',
                style: TextStyle(color: Colors.red.shade800),
              ),
            ],
            // Admin tidak bisa memutus/mengubah status sesama admin.
            if (!profile.isAdmin) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: active
                    ? OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade800,
                        ),
                        onPressed: pa.busy ? null : () => _terminate(context),
                        icon: const Icon(Icons.block, size: 18),
                        label: const Text('Putuskan kemitraan'),
                      )
                    : FilledButton.icon(
                        onPressed: pa.busy ? null : () => _reactivate(context),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Aktifkan kembali'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProviderStatusChip extends StatelessWidget {
  final bool active;
  const _ProviderStatusChip({required this.active});

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.green.shade800 : Colors.red.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle : Icons.block,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            active ? 'Aktif' : 'Diputus',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminateDialog extends StatefulWidget {
  final String name;
  const _TerminateDialog({required this.name});

  @override
  State<_TerminateDialog> createState() => _TerminateDialogState();
}

class _TerminateDialogState extends State<_TerminateDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final clean = validateAdminNote(_ctrl.text, required: true);
      Navigator.pop(context, clean);
    } on ProviderException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Putuskan kemitraan "${widget.name}"?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Penyedia tidak lagi bisa mengelola atau menambah sumber, dan '
              'semua sumbernya yang masih tayang/menunggu akan ditangguhkan.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Alasan pemutusan (min. 5 karakter)',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
          onPressed: _submit,
          child: const Text('Putuskan'),
        ),
      ],
    );
  }
}
