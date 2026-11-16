import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/water_source.dart';
import '../providers/source_provider.dart';
import '../services/location_service.dart';
import '../utils/geo.dart';
import '../utils/location_ui.dart';
import '../widgets/account_button.dart';
import '../widgets/source_card.dart';
import 'source_detail_screen.dart';
import 'source_map_screen.dart';

class SourceListScreen extends StatefulWidget {
  const SourceListScreen({super.key});

  @override
  State<SourceListScreen> createState() => _SourceListScreenState();
}

class _SourceListScreenState extends State<SourceListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowDisclaimer());
  }

  /// Penafian ditampilkan sekali saat aplikasi pertama dibuka.
  Future<void> _maybeShowDisclaimer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('disclaimer_ack') == true || !mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.water_drop_outlined),
          title: const Text('Sebelum memakai AquaConnect'),
          content: const Text(
              'Status "tersedia" berarti sumber air dilaporkan ada, BUKAN jaminan '
              'air aman diminum. Informasi berasal dari pengelola dan laporan warga '
              'dan bisa berubah sewaktu-waktu. Periksa label waktu konfirmasi di '
              'setiap sumber, dan jangan minum air yang diduga tercemar.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      await prefs.setBool('disclaimer_ack', true);
    } catch (e) {
      debugPrint('Penafian: $e');
    }
  }

  Future<void> _toggleNearest(bool on) async {
    final sp = context.read<SourceProvider>();
    if (!on) {
      sp.clearNearest();
      return;
    }
    final status = await sp.locate();
    if (!mounted || status == LocationStatus.ok) return;
    showLocationError(context, sp, status);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SourceProvider>();
    final items = p.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AquaConnect'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            tooltip: 'Lihat peta',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SourceMapScreen())),
          ),
          const AccountButton(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: context.read<SourceProvider>().setQuery,
              decoration: InputDecoration(
                hintText: 'Cari nama atau wilayah',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          // Tanpa tinggi tetap agar tidak terpotong saat teks diperbesar.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _chip(
                  avatar: const Icon(Icons.my_location, size: 18),
                  label: p.locating ? 'Mencari lokasi…' : 'Terdekat',
                  selected: p.sortNearest,
                  onSelected: p.locating ? null : _toggleNearest,
                ),
                _chip(
                  label: 'Semua',
                  selected: p.selectedType == null,
                  onSelected: (_) => p.setType(null),
                ),
                for (final t in SourceType.values)
                  _chip(
                    label: t.label,
                    selected: p.selectedType == t,
                    onSelected: (_) => p.setType(t),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Tampilkan yang belum dikonfirmasi'),
                selected: p.showUnconfirmed,
                onSelected: p.setShowUnconfirmed,
              ),
            ),
          ),
          if (p.fromCache && !p.loading)
            _banner(Icons.cloud_off,
                'Data dari penyimpanan lokal, mungkin tidak terbaru.'),
          if (!p.loading && p.hiddenUnconfirmedCount > 0)
            _banner(
              Icons.visibility_off_outlined,
              '${p.hiddenUnconfirmedCount} sumber disembunyikan karena belum dikonfirmasi',
              action: TextButton(
                onPressed: () => p.setShowUnconfirmed(true),
                child: const Text('Tampilkan'),
              ),
            ),
          if (p.sortNearest && p.nearestDistance != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                p.nearestDistance! > 50000
                    ? 'Belum ada sumber air terdaftar di dekat lokasimu (terdekat ${formatDistance(p.nearestDistance!)}).'
                    : 'Diurutkan dari lokasimu. Terdekat: ${formatDistance(p.nearestDistance!)}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: p.loading
                ? const Center(child: CircularProgressIndicator())
                : p.error != null && items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(p.error!, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: context.read<SourceProvider>().retry,
                              child: const Text('Coba lagi'),
                            ),
                          ],
                        ),
                      )
                    : items.isEmpty
                        ? const Center(
                            child: Text('Tidak ada sumber air ditemukan.'))
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (_, i) => SourceCard(
                              source: items[i],
                              distance: p.distanceLabel(items[i]),
                              freshness: p.freshnessOf(items[i]),
                              staleLabel: p.staleLabelOf(items[i]),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      SourceDetailScreen(sourceId: items[i].id),
                                ),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _banner(IconData icon, String text, {Widget? action}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.amber.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          if (action != null) action,
        ]),
      );

  Widget _chip({
    Widget? avatar,
    required String label,
    required bool selected,
    required ValueChanged<bool>? onSelected,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          avatar: avatar,
          label: Text(label),
          selected: selected,
          onSelected: onSelected,
        ),
      );
}
