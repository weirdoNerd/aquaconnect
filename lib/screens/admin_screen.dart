import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../dev/dummy_sources.dart';
import '../models/water_report.dart';
import '../models/water_source.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/provider_admin_provider.dart';
import '../providers/source_provider.dart';
import '../widgets/availability_badge.dart';
import '../widgets/status_chip.dart';
import 'listing_review_sheet.dart';
import 'provider_admin_tab.dart';
import 'review_sheet.dart';
import 'source_form_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.read<AuthProvider>().isAdmin) {
        context.read<AdminProvider>().start();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Pengecekan UI saja. Pembatasan sebenarnya ada di Security Rules.
    if (!context.watch<AuthProvider>().isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Panel Pengelola')),
        body: const Center(child: Text('Akses ditolak. Khusus pengelola.')),
      );
    }

    final pending = context.watch<AdminProvider>().pendingCount;
    final pendingProviders = context.watch<ProviderAdminProvider>().pendingCount;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel Pengelola'),
          bottom: TabBar(tabs: [
            Tab(text: pending > 0 ? 'Laporan ($pending)' : 'Laporan'),
            const Tab(text: 'Sumber air'),
            Tab(
                text: pendingProviders > 0
                    ? 'Penyedia ($pendingProviders)'
                    : 'Penyedia'),
          ]),
        ),
        body: const TabBarView(
          children: [_ReportsTab(), _SourcesTab(), ProviderAdminTab()],
        ),
      ),
    );
  }
}

class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final items = admin.items;

    Widget body;
    if (admin.loading && items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (admin.loadError != null && items.isEmpty) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(admin.loadError!, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: admin.reload, child: const Text('Coba lagi')),
        ]),
      );
    } else if (items.isEmpty) {
      body = Center(
          child: Text('Tidak ada laporan ${admin.filter.label.toLowerCase()}.'));
    } else {
      body = RefreshIndicator(
        onRefresh: admin.reload,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (_, i) => _AdminReportCard(report: items[i]),
        ),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Wrap(spacing: 8, children: [
          for (final s in ReportStatus.values)
            ChoiceChip(
              label: Text(s.label),
              selected: admin.filter == s,
              onSelected: (_) => context.read<AdminProvider>().setFilter(s),
            ),
        ]),
      ),
      Expanded(child: body),
    ]);
  }
}

class _AdminReportCard extends StatelessWidget {
  final WaterReport report;
  const _AdminReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final source = context
        .select<SourceProvider, WaterSource?>((p) => p.byId(report.sourceId));
    final date = report.createdAt == null
        ? 'Baru saja'
        : DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(report.createdAt!);
    final pending = report.status == ReportStatus.pending;

    return Card(
      child: InkWell(
        onTap: pending ? () => showReviewSheet(context, report) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(source?.name ?? 'Sumber air tidak ditemukan',
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
              if (report.adminNote.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Catatan: ${report.adminNote}',
                    style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 6),
              Text(date, style: Theme.of(context).textTheme.bodySmall),
              if (pending)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => showReviewSheet(context, report),
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

class _SourcesTab extends StatefulWidget {
  const _SourcesTab();

  @override
  State<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<_SourcesTab> {
  bool _onlyPending = false;
  bool _migrating = false;

  Future<void> _migrateLegacy() async {
    final messenger = ScaffoldMessenger.of(context);
    final sp = context.read<SourceProvider>();
    setState(() => _migrating = true);

    final preview = await sp.previewLegacyMigration();
    if (!mounted) return;
    setState(() => _migrating = false);
    if (preview.error != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(preview.error!)));
      return;
    }

    final count = preview.count ?? 0;
    if (count == 0) {
      messenger.clearSnackBars();
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'Semua data sumber air sudah sesuai (0 dokumen perlu diperbarui).'),
      ));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Perbaiki data lama?'),
        content: Text(
          'Ditemukan $count dokumen sumber air lama yang belum memiliki '
          'isActive atau listingStatus. Pembaruan dijalankan per potongan 8 '
          'dokumen dan aman diulang bila terputus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Perbaiki ($count)'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _migrating = true);
    final res = await sp.runLegacyMigration();
    if (!mounted) return;
    setState(() => _migrating = false);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content:
          Text(res.error ?? '${res.done ?? 0} dokumen lama berhasil diperbarui.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SourceProvider>();
    final allSources = sp.all;
    final pendingCount =
        allSources.where((s) => s.listingStatus == ListingStatus.pending).length;
    final sources = _onlyPending
        ? allSources
            .where((s) => s.listingStatus == ListingStatus.pending)
            .toList()
        : allSources;
    const showSeed = kDebugMode && useFirebase;

    final header = <Widget>[
      FilledButton.icon(
        onPressed: () => _open(context, null),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Tambah sumber air'),
      ),
      OutlinedButton.icon(
        onPressed: _migrating ? null : _migrateLegacy,
        icon: _migrating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.build_outlined),
        label: const Text('Perbaiki data lama'),
      ),
      if (showSeed)
        OutlinedButton.icon(
          onPressed: () => _seed(context),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Isi data contoh (debug)'),
        ),
      if (sp.skippedSources > 0)
        Card(
          color: Colors.amber.shade100,
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded),
            title: Text('${sp.skippedSources} sumber air tidak dapat dibaca'),
            subtitle: const Text(
                'Formatnya rusak sehingga tidak tampil di aplikasi. Periksa di Firebase Console.'),
          ),
        ),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text('Semua (${allSources.length})'),
            selected: !_onlyPending,
            onSelected: (_) => setState(() => _onlyPending = false),
          ),
          ChoiceChip(
            label: Text('Menunggu verifikasi ($pendingCount)'),
            selected: _onlyPending,
            onSelected: (_) => setState(() => _onlyPending = true),
          ),
        ],
      ),
      if (_onlyPending && sources.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('Tidak ada sumber yang menunggu verifikasi.'),
          ),
        ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: header.length + sources.length,
      itemBuilder: (ctx, i) {
        if (i < header.length) {
          return Padding(
              padding: const EdgeInsets.only(bottom: 8), child: header[i]);
        }
        final s = sources[i - header.length];
        final isPending = s.listingStatus == ListingStatus.pending;
        final owner = s.ownerName?.trim() ?? '';
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(s.type.icon)),
            title: Text(s.name),
            subtitle: Text([
              s.type.label,
              s.address,
              if (owner.isNotEmpty) owner,
              if (isPending)
                'Menunggu verifikasi'
              else if (!s.isActive)
                s.listingStatus.label,
              if (s.qualityFlag) 'Ada penanda kualitas',
            ].join(' • ')),
            trailing: isPending
                ? TextButton(
                    onPressed: () => showListingReviewSheet(ctx, s),
                    child: const Text('Tinjau'),
                  )
                : AvailabilityBadge(availability: s.availability),
            onTap: () => isPending
                ? showListingReviewSheet(ctx, s)
                : _open(ctx, s),
          ),
        );
      },
    );
  }

  void _open(BuildContext context, WaterSource? s) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => SourceFormScreen(source: s)));
  }

  Future<void> _seed(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<SourceProvider>();
    try {
      final n = await provider.seedDemoData(dummySources);
      messenger.showSnackBar(SnackBar(
          content: Text(n > 0
              ? '$n data contoh diunggah.'
              : 'Data sudah ada, tidak ada yang diunggah.')));
    } catch (e) {
      debugPrint('Seed gagal: $e');
      messenger.showSnackBar(const SnackBar(
          content:
              Text('Gagal mengunggah. Pastikan akun ini bertugas sebagai admin.')));
    }
  }
}
