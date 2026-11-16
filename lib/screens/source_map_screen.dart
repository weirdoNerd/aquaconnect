import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/water_source.dart';
import '../providers/source_provider.dart';
import '../services/location_service.dart';
import '../utils/location_ui.dart';
import 'source_detail_screen.dart';

class SourceMapScreen extends StatefulWidget {
  const SourceMapScreen({super.key});

  @override
  State<SourceMapScreen> createState() => _SourceMapScreenState();
}

class _SourceMapScreenState extends State<SourceMapScreen> {
  // Hanya cadangan saat belum ada data (Cengkareng, Jakarta Barat).
  static const _fallbackCenter = LatLng(-6.1480, 106.7370);
  final _controller = MapController();

  /// Pusat awal: lokasi pengguna, lalu batas semua sumber, lalu cadangan.
  MapOptions _options(SourceProvider sp) {
    final user = sp.userLocation;
    if (user != null) return MapOptions(initialCenter: user, initialZoom: 15);

    final points = [for (final s in sp.items) LatLng(s.latitude, s.longitude)];
    if (points.length >= 2) {
      return MapOptions(
        initialCenter: points.first,
        initialCameraFit: CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.all(48),
          maxZoom: 16,
        ),
      );
    }
    if (points.length == 1) {
      return MapOptions(initialCenter: points.first, initialZoom: 15);
    }
    return const MapOptions(initialCenter: _fallbackCenter, initialZoom: 14);
  }

  Marker _marker(WaterSource s, Freshness freshness) {
    final dimmed = freshness != Freshness.fresh;
    return Marker(
      point: LatLng(s.latitude, s.longitude),
      width: 44,
      height: 44,
      // Ujung pin tepat di koordinat (bagian bawah ikon menyentuh titik).
      alignment: Alignment.topCenter,
      child: Semantics(
        button: true,
        label: dimmed
            ? '${s.name}, ${s.availability.label}, belum dikonfirmasi'
            : '${s.name}, ${s.availability.label}',
        child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SourceDetailScreen(sourceId: s.id)),
          ),
          child: Opacity(
            opacity: dimmed ? 0.5 : 1.0,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Icon(Icons.location_on, size: 44, color: s.availability.color),
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Icon(s.availability.icon, size: 16, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _myLocation() async {
    final sp = context.read<SourceProvider>();
    final status = await sp.locate();
    if (!mounted) return;
    if (status == LocationStatus.ok) {
      final p = sp.userLocation;
      if (p != null) _controller.move(p, 15);
    } else {
      showLocationError(context, sp, status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<SourceProvider>();
    final items = sp.items;
    final user = sp.userLocation;

    return Scaffold(
      appBar: AppBar(title: const Text('Peta Sumber Air')),
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'Lokasiku',
        onPressed: sp.locating ? null : _myLocation,
        child: sp.locating
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.my_location),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: _options(sp),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: kAppPackage,
              ),
              MarkerLayer(
                markers: [
                  if (user != null)
                    Marker(
                      point: user,
                      width: 24,
                      height: 24,
                      child: Semantics(
                        label: 'Lokasimu',
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(blurRadius: 4, color: Colors.black38)
                            ],
                          ),
                        ),
                      ),
                    ),
                  for (final s in items) _marker(s, sp.freshnessOf(s)),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors')
                ],
              ),
            ],
          ),
          const Positioned(left: 8, bottom: 8, child: _Legend()),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final a in Availability.values)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(a.icon, size: 16, color: a.color),
                const SizedBox(width: 6),
                Text(a.label, style: const TextStyle(fontSize: 12)),
              ]),
          ],
        ),
      ),
    );
  }
}
