import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../models/water_source.dart';
import '../providers/auth_provider.dart';
import '../providers/source_provider.dart';
import '../widgets/availability_badge.dart';
import 'login_screen.dart';
import 'report_form_screen.dart';

/// Menerima id (bukan salinan objek) agar selalu menampilkan data terbaru
/// saat admin memperbarui status ketika layar ini terbuka.
class SourceDetailScreen extends StatelessWidget {
  final String sourceId;
  const SourceDetailScreen({super.key, required this.sourceId});

  Future<void> _openNavigation(BuildContext context, WaterSource s) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${s.latitude},${s.longitude}');
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('launchUrl gagal: $e'); // mis. PlatformException tanpa peramban
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Tidak dapat membuka aplikasi peta atau peramban.')));
    }
  }

  void _report(BuildContext context, WaterSource source) {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);

    if (!auth.isLoggedIn) {
      messenger.showSnackBar(SnackBar(
        content: const Text('Masuk dulu untuk mengirim laporan.'),
        action: SnackBarAction(
          label: 'Masuk',
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const LoginScreen())),
        ),
      ));
      return;
    }
    if (kRequireVerifiedEmail && !(auth.user?.emailVerified ?? false)) {
      messenger.showSnackBar(SnackBar(
        content: const Text('Verifikasi email dulu untuk mengirim laporan.'),
        action: SnackBarAction(
          label: 'Kirim ulang',
          onPressed: () => auth.sendVerification(),
        ),
      ));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReportFormScreen(sourceId: source.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source =
        context.select<SourceProvider, WaterSource?>((p) => p.byId(sourceId));
    final isAdmin = context.select<AuthProvider, bool>((a) => a.isAdmin);
    final distance = context.select<SourceProvider, String?>((p) {
      final s = p.byId(sourceId);
      return s == null ? null : p.distanceLabel(s);
    });
    final freshness = context.select<SourceProvider, Freshness?>((p) {
      final s = p.byId(sourceId);
      return s == null ? null : p.freshnessOf(s);
    });
    final stale = context.select<SourceProvider, String?>((p) {
      final s = p.byId(sourceId);
      return s == null ? null : p.staleLabelOf(s);
    });

    if (source == null || (!source.isActive && !isAdmin)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Sumber Air')),
        body: const Center(child: Text('Sumber air ini sudah tidak tersedia.')),
      );
    }

    final isDegraded = (freshness ?? source.freshness()) != Freshness.fresh;
    final fmt = DateFormat('d MMM yyyy, HH:mm', 'id_ID');
    final updated = source.updatedAt == null
        ? 'Belum pernah diperbarui'
        : fmt.format(source.updatedAt!);
    final verified = source.verifiedAt == null
        ? 'Belum pernah dikonfirmasi'
        : fmt.format(source.verifiedAt!);
    final confirmedText = source.verifiedAt == null
        ? 'Belum pernah dikonfirmasi'
        : switch (source.verifiedBy) {
            VerifiedBy.provider => 'Dikonfirmasi oleh penyedia $verified',
            VerifiedBy.admin => 'Dikonfirmasi oleh admin $verified',
            null => verified,
          };
    final ownerName = source.ownerName?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Sumber Air')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (source.qualityFlag)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade800),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade800),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(kQualityWarning,
                      style: TextStyle(
                          color: Colors.red.shade900, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          if (!source.isActive)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Nonaktif: tidak tampil untuk warga.'),
            ),
          if (source.isSimulated)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Data simulasi untuk demo, bukan lokasi nyata.'),
            ),
          Text(source.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: AvailabilityBadge(
              availability: source.availability,
              stale: isDegraded,
            ),
          ),
          if (stale != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Colors.orange.shade900),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      stale,
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (isDegraded)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade800),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: Colors.orange.shade900),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Status mungkin sudah tidak benar. Hubungi pengelola bila perlu.',
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (source.ownerId != null && ownerName.isNotEmpty)
            _row(
              Icons.storefront_outlined,
              'Pengelola',
              'Dikelola oleh $ownerName',
            ),
          _row(Icons.category, 'Jenis', source.type.label),
          _row(Icons.place, 'Alamat', source.address),
          _row(Icons.schedule, 'Jam layanan', source.openingHours),
          _row(Icons.info_outline, 'Penggunaan', source.intendedUse),
          if (distance != null)
            _row(Icons.near_me, 'Jarak', '$distance dari lokasimu'),
          _row(Icons.verified_outlined, 'Dikonfirmasi', confirmedText),
          _row(Icons.update, 'Diperbarui', updated),
          const SizedBox(height: 8),
          const Text(
            'Status "tersedia" berarti air dilaporkan ada, bukan jaminan aman diminum.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _openNavigation(context, source),
            icon: const Icon(Icons.directions),
            label: const Text('Buka petunjuk arah'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: source.isActive ? () => _report(context, source) : null,
            icon: const Icon(Icons.flag_outlined),
            label: const Text('Laporkan kondisi'),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData i, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(i, size: 20),
            const SizedBox(width: 12),
            SizedBox(width: 96, child: Text(k)),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
