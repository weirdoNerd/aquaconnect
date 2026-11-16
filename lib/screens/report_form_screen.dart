import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/water_report.dart';
import '../models/water_source.dart';
import '../providers/auth_provider.dart';
import '../providers/report_provider.dart';
import '../providers/source_provider.dart';

class ReportFormScreen extends StatefulWidget {
  final String sourceId;
  const ReportFormScreen({super.key, required this.sourceId});

  @override
  State<ReportFormScreen> createState() => _ReportFormScreenState();
}

class _ReportFormScreenState extends State<ReportFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _desc = TextEditingController();
  ReportType? _type;
  bool _typeError = false;

  @override
  void initState() {
    super.initState();
    // Error pengiriman sebelumnya tidak boleh terbawa ke formulir baru.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ReportProvider>().clearSubmitError();
    });
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final okForm = _formKey.currentState!.validate();
    setState(() => _typeError = _type == null);
    if (!okForm || _type == null) return;

    final uid = context.read<AuthProvider>().user?.uid;
    if (uid == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final outcome = await context.read<ReportProvider>().submit(
          sourceId: widget.sourceId,
          reporterId: uid,
          type: _type!,
          description: _desc.text,
        );

    switch (outcome) {
      case SubmitOutcome.sent:
        nav.pop();
        messenger.showSnackBar(const SnackBar(
            content: Text('Laporan terkirim dan menunggu verifikasi pengelola.')));
      case SubmitOutcome.queued:
        nav.pop();
        messenger.showSnackBar(const SnackBar(
            content: Text(
                'Belum ada konfirmasi server. Laporan akan dikirim otomatis saat koneksi kembali.')));
      case SubmitOutcome.failed:
        break; // pesan error tampil di formulir
    }
  }

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReportProvider>();
    final source = context
        .select<SourceProvider, WaterSource?>((p) => p.byId(widget.sourceId));
    final scheme = Theme.of(context).colorScheme;

    if (source == null || !source.isActive) {
      return Scaffold(
        appBar: AppBar(title: const Text('Laporkan Kondisi')),
        body: const Center(child: Text('Sumber air ini sudah tidak tersedia.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Laporkan Kondisi')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(source.type.icon),
                    title: Text(source.name),
                    subtitle: Text(source.address),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Jenis laporan', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // `noLongerOperating` baru ditampilkan di S10, setelah rules Fase 2
                    // diterapkan; sebelum itu server menolaknya.
                    for (final t in ReportType.values
                        .where((t) => t != ReportType.noLongerOperating))
                      ChoiceChip(
                        avatar: Icon(t.icon, size: 18),
                        label: Text(t.label),
                        selected: _type == t,
                        onSelected: (_) {
                          setState(() {
                            _type = t;
                            _typeError = false;
                          });
                          context.read<ReportProvider>().clearSubmitError();
                        },
                      ),
                  ],
                ),
                if (_typeError)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Pilih jenis laporan',
                        style: TextStyle(color: scheme.error, fontSize: 12)),
                  ),
                if (_type == ReportType.qualityConcern)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Jika air diduga tercemar, jangan dikonsumsi dan hubungi '
                      'pihak berwenang setempat. Laporan ini tidak menggantikan '
                      'pemeriksaan kualitas air resmi.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _desc,
                  maxLines: 4,
                  maxLength: 300,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Deskripsi kondisi',
                    hintText: 'Contoh: air sudah habis sejak pagi',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => context.read<ReportProvider>().clearSubmitError(),
                  validator: (v) => (v == null || v.trim().length < 10)
                      ? 'Jelaskan minimal 10 karakter'
                      : null,
                ),
                if (rp.submitError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(rp.submitError!, style: TextStyle(color: scheme.error)),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: rp.submitting ? null : _submit,
                    icon: rp.submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('Kirim laporan'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Laporan akan diperiksa pengelola sebelum mengubah status sumber air.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
