import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../models/water_source.dart';
import '../providers/auth_provider.dart';
import '../providers/my_sources_provider.dart';
import '../providers/source_provider.dart';
import '../services/source_service.dart';
import '../widgets/availability_badge.dart';

const List<String> _kCloseReasonPresets = [
  'Tidak lagi menyediakan air',
  'Lokasi pindah',
  'Sumber rusak',
  'Lainnya',
];

class MySourcesScreen extends StatelessWidget {
  const MySourcesScreen({super.key});

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _confirmSingle(
    BuildContext context,
    MySourcesProvider mySources,
    WaterSource source,
  ) async {
    final ok = await mySources.confirmStillCurrent(source.id);
    if (!context.mounted) return;
    if (ok) {
      _snack(context, 'Status "${source.name}" berhasil dikonfirmasi.');
    }
  }

  Future<void> _updateAvailability(
    BuildContext context,
    MySourcesProvider mySources,
    WaterSource source,
    Availability next,
  ) async {
    final ok = await mySources.updateOperational(source.id, availability: next);
    if (!context.mounted) return;
    if (ok) {
      _snack(context, 'Status "${source.name}" diperbarui menjadi ${next.label}.');
    }
  }

  Future<void> _closeSingle(
    BuildContext context,
    MySourcesProvider mySources,
    WaterSource source,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CloseReasonDialog(
        title: 'Tutup sumber "${source.name}"?',
        warning:
            'Penutupan bersifat permanen dan penyedia tidak bisa membatalkan '
            'setelah sumber ditutup.',
        confirmLabel: 'Tutup sumber',
      ),
    );
    if (reason == null || !context.mounted) return;
    final ok = await mySources.closeOwned(source.id, reason);
    if (!context.mounted) return;
    if (ok) {
      _snack(context, 'Sumber "${source.name}" telah ditutup.');
    }
  }

  Future<void> _closeAll(
    BuildContext context,
    MySourcesProvider mySources,
  ) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _CloseReasonDialog(
        title: 'Hentikan semua sumber saya?',
        warning:
            'Semua sumber yang masih tayang, menunggu verifikasi, atau ditolak '
            'akan ditutup permanen dan penyedia tidak bisa membatalkannya.\n\n'
            'Catatan: sumber yang ditangguhkan admin tidak ikut tertutup.',
        confirmLabel: 'Hentikan semua',
      ),
    );
    if (reason == null || !context.mounted) return;
    final closed = await mySources.closeAllOwned(reason);
    if (!context.mounted) return;
    if (closed != null) {
      _snack(
        context,
        closed == 0
            ? 'Tidak ada sumber yang dapat ditutup.'
            : '$closed sumber berhasil ditutup.',
      );
    }
  }

  Future<void> _confirmAll(
    BuildContext context,
    MySourcesProvider mySources,
    List<WaterSource> due,
  ) async {
    final res = await mySources.confirmAll(due);
    if (!context.mounted) return;
    if (res.failedNames.isEmpty) {
      _snack(context, '${res.succeeded} sumber berhasil dikonfirmasi.');
    } else {
      _snack(
        context,
        '${res.succeeded} berhasil, ${res.failedNames.length} gagal dikonfirmasi.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    if (!auth.isProvider || user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sumber Saya')),
        body: _NonProviderNotice(user: user),
      );
    }

    final sourceProv = context.watch<SourceProvider>();
    final mySources = context.watch<MySourcesProvider>();
    final owned = mySources.ownedFrom(sourceProv.all);
    final due = mySources.dueFrom(sourceProv.all);
    final hasClosable =
        owned.any((s) => kProviderClosable.contains(s.listingStatus));

    return Scaffold(
      appBar: AppBar(title: const Text('Sumber Saya')),
      body: sourceProv.loading && owned.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : owned.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.water_drop_outlined, size: 56),
                        SizedBox(height: 12),
                        Text(
                          'Kamu belum punya sumber air',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (due.isNotEmpty)
                      _ReminderBanner(
                        count: due.length,
                        busy: mySources.bulkBusy,
                        onConfirmAll: () => _confirmAll(context, mySources, due),
                      ),
                    if (mySources.bulkError != null) ...[
                      _ErrorNotice(
                        message: mySources.bulkError!,
                        onDismiss: mySources.clearBulkError,
                      ),
                      const SizedBox(height: 8),
                    ],
                    for (final s in owned)
                      _OwnedSourceCard(
                        source: s,
                        busy: mySources.isBusy(s.id) || mySources.bulkBusy,
                        error: mySources.errorFor(s.id),
                        needsReconfirm: MySourcesProvider.needsReconfirm(s),
                        onConfirm: () => _confirmSingle(context, mySources, s),
                        onSelectAvailability: (a) =>
                            _updateAvailability(context, mySources, s, a),
                        onClose: () => _closeSingle(context, mySources, s),
                      ),
                    if (hasClosable) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade800,
                          side: BorderSide(color: Colors.red.shade800),
                        ),
                        onPressed: mySources.bulkBusy
                            ? null
                            : () => _closeAll(context, mySources),
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('Hentikan semua sumber saya'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Catatan: sumber yang ditangguhkan admin tidak ikut tertutup.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _NonProviderNotice extends StatelessWidget {
  final AppUser? user;
  const _NonProviderNotice({required this.user});

  @override
  Widget build(BuildContext context) {
    final terminated = user?.providerStatus == ProviderStatus.terminated;
    final note = user?.providerNote?.trim() ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                terminated ? Icons.block : Icons.info_outline,
                size: 56,
                color: terminated
                    ? Colors.red.shade800
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                terminated
                    ? 'Kemitraan penyedia diputus'
                    : 'Khusus penyedia air aktif',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                terminated
                    ? (note.isNotEmpty
                        ? 'Anda tidak lagi dapat mengelola sumber air. Alasan: $note'
                        : 'Kemitraan penyedia Anda telah dihentikan oleh admin.')
                    : 'Halaman ini hanya tersedia untuk akun dengan status penyedia aktif.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReminderBanner extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onConfirmAll;
  const _ReminderBanner({
    required this.count,
    required this.busy,
    required this.onConfirmAll,
  });

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade900;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.notifications_active, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count sumber perlu dikonfirmasi',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: busy ? null : onConfirmAll,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Konfirmasi semua'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorNotice({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final errColor = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: errColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: errColor),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: errColor),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(color: errColor))),
          IconButton(
            tooltip: 'Tutup pesan',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _OwnedSourceCard extends StatelessWidget {
  final WaterSource source;
  final bool busy;
  final String? error;
  final bool needsReconfirm;
  final VoidCallback onConfirm;
  final ValueChanged<Availability> onSelectAvailability;
  final VoidCallback onClose;

  const _OwnedSourceCard({
    required this.source,
    required this.busy,
    required this.error,
    required this.needsReconfirm,
    required this.onConfirm,
    required this.onSelectAvailability,
    required this.onClose,
  });

  String _confirmedLabel() {
    final v = source.verifiedAt;
    if (v == null) return 'Belum pernah dikonfirmasi';
    final diff = DateTime.now().difference(v);
    final age = diff.inMinutes < 1
        ? 'baru saja'
        : diff.inHours < 1
            ? '${diff.inMinutes} menit lalu'
            : diff.inHours < 24
                ? '${diff.inHours} jam lalu'
                : '${diff.inDays} hari lalu';
    final by = switch (source.verifiedBy) {
      VerifiedBy.admin => ' (Admin)',
      VerifiedBy.provider => ' (Penyedia)',
      null => '',
    };
    return 'Dikonfirmasi $age$by';
  }

  @override
  Widget build(BuildContext context) {
    final ls = source.listingStatus;
    final note = source.reviewNote?.trim() ?? '';
    final closedReason = source.closedReason?.trim() ?? '';
    final errColor = Theme.of(context).colorScheme.error;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    source.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                _ListingStatusChip(status: ls),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AvailabilityBadge(availability: source.availability),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      needsReconfirm ? Icons.schedule : Icons.verified_outlined,
                      size: 16,
                      color: needsReconfirm ? Colors.orange.shade900 : null,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _confirmedLabel(),
                      style: TextStyle(
                        fontSize: 12,
                        color: needsReconfirm ? Colors.orange.shade900 : null,
                        fontWeight:
                            needsReconfirm ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (ls == ListingStatus.rejected && note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Alasan ditolak: $note',
                style: TextStyle(color: Colors.red.shade800),
              ),
            ],
            if (ls == ListingStatus.suspended) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.pause_circle_outline,
                      size: 18, color: Colors.blueGrey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note.isNotEmpty
                          ? 'Ditangguhkan admin, hubungi admin. Catatan: $note'
                          : 'Ditangguhkan admin, hubungi admin',
                      style: TextStyle(color: Colors.blueGrey.shade700),
                    ),
                  ),
                ],
              ),
            ],
            if (ls == ListingStatus.closed) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline,
                      size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      closedReason.isNotEmpty
                          ? 'Sumber sudah ditutup ($closedReason).'
                          : 'Sumber sudah ditutup.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ],
            if (busy) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: errColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(error!, style: TextStyle(color: errColor)),
                  ),
                ],
              ),
            ],
            if (ls == ListingStatus.published) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : onConfirm,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Konfirmasi masih tersedia'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in Availability.values)
                    _AvailabilityActionButton(
                      availability: a,
                      selected: source.availability == a,
                      onPressed:
                          busy ? null : () => onSelectAvailability(a),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade800,
                  ),
                  onPressed: busy ? null : onClose,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Tutup sumber'),
                ),
              ),
            ] else if (ls == ListingStatus.pending ||
                ls == ListingStatus.rejected) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade800,
                  ),
                  onPressed: busy ? null : onClose,
                  icon: const Icon(Icons.lock_outline, size: 18),
                  label: const Text('Tutup sumber'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListingStatusChip extends StatelessWidget {
  final ListingStatus status;
  const _ListingStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = status.darkColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: c,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityActionButton extends StatelessWidget {
  final Availability availability;
  final bool selected;
  final VoidCallback? onPressed;
  const _AvailabilityActionButton({
    required this.availability,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = availability.darkColor;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        backgroundColor: selected ? availability.color.withValues(alpha: 0.14) : null,
        side: BorderSide(color: c, width: selected ? 1.8 : 1),
      ),
      onPressed: onPressed,
      icon: Icon(availability.icon, size: 16),
      label: Text(availability.label),
    );
  }
}

class _CloseReasonDialog extends StatefulWidget {
  final String title;
  final String warning;
  final String confirmLabel;

  const _CloseReasonDialog({
    required this.title,
    required this.warning,
    required this.confirmLabel,
  });

  @override
  State<_CloseReasonDialog> createState() => _CloseReasonDialogState();
}

class _CloseReasonDialogState extends State<_CloseReasonDialog> {
  String _selected = _kCloseReasonPresets.first;
  final _noteCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String _composeReason() {
    final note = _noteCtrl.text.trim();
    if (_selected == 'Lainnya') return note;
    if (note.isEmpty) return _selected;
    return '$_selected: $note';
  }

  void _confirm() {
    final reason = _composeReason();
    try {
      final clean = validateCloseReason(reason);
      Navigator.pop(context, clean);
    } on SourceException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.warning),
            const SizedBox(height: 12),
            const Text(
              'Pilih alasan penutupan:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            RadioGroup<String>(
              groupValue: _selected,
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _selected = v;
                  _error = null;
                });
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final preset in _kCloseReasonPresets)
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(preset),
                      value: preset,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: _selected == 'Lainnya'
                    ? 'Tulis alasan penutupan (min. 3 karakter)'
                    : 'Catatan tambahan (opsional)',
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
          onPressed: _confirm,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
