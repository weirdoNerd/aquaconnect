import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/water_report.dart';
import '../models/water_source.dart';
import '../providers/report_provider.dart';
import '../providers/source_provider.dart';
import '../widgets/status_chip.dart';

class MyReportsScreen extends StatelessWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rp = context.watch<ReportProvider>();

    Widget body;
    if (rp.loading && rp.mine.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (rp.loadError != null && rp.mine.isEmpty) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(rp.loadError!, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: rp.retry, child: const Text('Coba lagi')),
        ]),
      );
    } else if (rp.mine.isEmpty) {
      body = const Center(child: Text('Kamu belum mengirim laporan.'));
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: rp.mine.length + (rp.loadError != null ? 1 : 0),
        itemBuilder: (_, i) {
          // Galat tetap ditampilkan walau ada data lama.
          if (rp.loadError != null && i == 0) {
            return Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: Icon(Icons.error_outline, color: Colors.red.shade800),
                title: Text(rp.loadError!),
                trailing: TextButton(onPressed: rp.retry, child: const Text('Coba lagi')),
              ),
            );
          }
          return _ReportTile(report: rp.mine[i - (rp.loadError != null ? 1 : 0)]);
        },
      );
    }

    return Scaffold(appBar: AppBar(title: const Text('Laporan Saya')), body: body);
  }
}

class _ReportTile extends StatelessWidget {
  final WaterReport report;
  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    // Warga hanya melanggan sumber tayang. Sumber yang kemudian ditangguhkan atau
    // ditutup tidak ada di SourceProvider. Selama daftar sumber masih dimuat,
    // jangan menyatakannya "tidak lagi tayang" (belum diketahui).
    final (source, sourcesLoading) =
        context.select<SourceProvider, (WaterSource?, bool)>(
            (p) => (p.byId(report.sourceId), p.loading));
    final title = source?.name ??
        (sourcesLoading ? 'Memuat nama sumber…' : 'Sumber tidak lagi tayang');
    final date = report.createdAt == null
        ? 'Baru saja'
        : DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(report.createdAt!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              ReportStatusChip(status: report.status),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(report.type.icon, size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text(report.type.label)),
            ]),
            const SizedBox(height: 4),
            Text(report.description),
            if (report.status == ReportStatus.rejected && report.adminNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Catatan pengelola: ${report.adminNote}',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 8),
            Text(date, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
