import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/water_report.dart';
import '../models/water_source.dart';
import '../providers/admin_provider.dart';
import '../providers/source_provider.dart';
import '../widgets/availability_badge.dart';

Future<void> showReviewSheet(BuildContext context, WaterReport report) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Pakai context milik builder agar padding keyboard akurat.
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ReviewSheet(report: report),
    ),
  );
}

class ReviewSheet extends StatefulWidget {
  final WaterReport report;
  const ReviewSheet({super.key, required this.report});

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  final _note = TextEditingController();
  Availability? _availability;
  late bool _suspend;
  String? _noteError;

  @override
  void initState() {
    super.initState();
    final current = context.read<SourceProvider>().byId(widget.report.sourceId);
    _suspend = widget.report.type == ReportType.noLongerOperating;
    // Saran awal; admin bebas mengubahnya.
    _availability = switch (widget.report.type) {
      ReportType.noWater ||
      ReportType.inaccessible ||
      ReportType.noLongerOperating =>
        Availability.unavailable,
      ReportType.backAvailable => Availability.available,
      ReportType.qualityConcern => current?.availability,
    };
    // Error tinjauan sebelumnya tidak boleh terbawa ke sheet baru.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AdminProvider>().clearReviewError();
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    if (!approve && _note.text.trim().length < 5) {
      setState(() => _noteError = 'Alasan penolakan wajib diisi (min. 5 karakter)');
      return;
    }
    final source = context.read<SourceProvider>().byId(widget.report.sourceId);
    final suspendNow = approve && _suspend;
    if (suspendNow) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Tangguhkan sumber air?'),
          content: Text(
            'Sumber "${source?.name ?? 'ini'}" akan ditangguhkan dan '
            'disembunyikan dari daftar publik.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya, tangguhkan'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context.read<AdminProvider>().review(
          widget.report,
          approve: approve,
          note: _note.text,
          newAvailability: approve && !suspendNow ? _availability : null,
          suspendSource: suspendNow,
        );
    if (!mounted) return;
    if (ok) {
      nav.pop();
      messenger.showSnackBar(SnackBar(
          content: Text(!approve
              ? 'Laporan ditolak dan alasan dicatat.'
              : suspendNow
                  ? 'Laporan disetujui, sumber air ditangguhkan.'
                  : 'Laporan disetujui, data sumber air diperbarui.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final source = context.watch<SourceProvider>().byId(widget.report.sourceId);
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tinjau laporan', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(source?.name ?? 'Sumber air tidak ditemukan',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (source != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Text('Status saat ini: '),
              AvailabilityBadge(availability: source.availability),
            ]),
          ],
          const SizedBox(height: 8),
          Text(widget.report.type.label),
          const SizedBox(height: 4),
          Text(widget.report.description),
          const Divider(height: 28),
          if (widget.report.type == ReportType.noLongerOperating) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tangguhkan sumber air (disarankan)'),
              subtitle: const Text(
                'Sumber disembunyikan dari daftar warga dan tidak lagi tampil sebagai tersedia.',
              ),
              value: _suspend,
              onChanged: (v) => setState(() => _suspend = v),
            ),
            const SizedBox(height: 8),
          ],
          if (!_suspend) ...[
            Text('Status sumber air jika disetujui',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final a in Availability.values)
                  ChoiceChip(
                    label: Text(a.label),
                    selected: _availability == a,
                    onSelected: (_) => setState(() => _availability = a),
                  ),
              ],
            ),
          ],
          if (widget.report.type == ReportType.qualityConcern)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Menyetujui laporan kualitas akan menandai sumber dengan peringatan '
                '"hindari konsumsi sampai diperiksa". Teks tujuan penggunaan tidak diubah.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 2,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'Catatan pengelola',
              helperText: 'Wajib diisi jika menolak',
              errorText: _noteError,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_noteError != null) setState(() => _noteError = null);
            },
          ),
          if (admin.reviewError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(admin.reviewError!, style: TextStyle(color: scheme.error)),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: admin.busy ? null : () => _decide(false),
                  child: const Text('Tolak'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: admin.busy ? null : () => _decide(true),
                  child: admin.busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
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
