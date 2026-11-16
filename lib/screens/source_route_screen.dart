import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/water_source.dart';
import '../providers/auth_provider.dart';
import '../providers/source_provider.dart';
import '../services/location_service.dart';
import '../utils/geo.dart';
import '../utils/location_ui.dart';

/// Peta dalam aplikasi versi ringan: menampilkan titik tujuan, lokasi pengguna,
/// garis lurus putus-putus, serta jarak dan arah kompas (tanpa layanan rute).
class SourceRouteScreen extends StatefulWidget {
  final String sourceId;
  final LocationService? locationService;

  const SourceRouteScreen({
    super.key,
    required this.sourceId,
    this.locationService,
  });

  @override
  State<SourceRouteScreen> createState() => _SourceRouteScreenState();
}

class _SourceRouteScreenState extends State<SourceRouteScreen> {
  final _controller = MapController();
  bool _mapReady = false;
  bool _locating = false;
  LatLng? _user;
  LocationStatus? _errorStatus;

  LocationService _resolveLocation(BuildContext context) =>
      widget.locationService ?? context.read<SourceProvider>().locationService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchLocation();
    });
  }

  Future<void> _fetchLocation() async {
    if (_locating) return;
    final loc = _resolveLocation(context);
    setState(() {
      _locating = true;
      _errorStatus = null;
    });
    final res = await loc.getCurrent();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (res.status == LocationStatus.ok && res.point != null) {
        _user = res.point;
        _errorStatus = null;
      } else {
        _user = null;
        _errorStatus = res.status;
      }
    });
    _fitToPoints();
  }

  void _fitToPoints() {
    if (!_mapReady) return;
    final source = context.read<SourceProvider>().byId(widget.sourceId);
    if (source == null) return;
    final dest = LatLng(source.latitude, source.longitude);
    final user = _user;
    if (user == null ||
        distanceMeters(user.latitude, user.longitude, dest.latitude,
                dest.longitude) <
            10) {
      _controller.move(dest, 16);
      return;
    }
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: [user, dest],
        padding: const EdgeInsets.all(56),
        maxZoom: 17,
      ),
    );
  }

  MapOptions _initialOptions(LatLng dest) {
    final user = _user;
    if (user != null &&
        distanceMeters(user.latitude, user.longitude, dest.latitude,
                dest.longitude) >=
            10) {
      return MapOptions(
        initialCenter: dest,
        initialCameraFit: CameraFit.coordinates(
          coordinates: [user, dest],
          padding: const EdgeInsets.all(56),
          maxZoom: 17,
        ),
        onMapReady: () {
          _mapReady = true;
          _fitToPoints();
        },
      );
    }
    return MapOptions(
      initialCenter: dest,
      initialZoom: 16,
      onMapReady: () {
        _mapReady = true;
        _fitToPoints();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = context
        .select<SourceProvider, WaterSource?>((p) => p.byId(widget.sourceId));
    final isAdmin = context.select<AuthProvider, bool>((a) => a.isAdmin);

    if (source == null || (!source.isActive && !isAdmin)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Arah ke Sumber Air')),
        body: const Center(child: Text('Sumber air ini sudah tidak tersedia.')),
      );
    }

    final dest = LatLng(source.latitude, source.longitude);
    final user = _user;
    final dist = user == null
        ? null
        : distanceMeters(
            user.latitude, user.longitude, dest.latitude, dest.longitude);
    final bearing = user == null ? null : bearingDegrees(user, dest);
    final loc = _resolveLocation(context);

    return Scaffold(
      appBar: AppBar(title: Text(source.name)),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _controller,
              options: _initialOptions(dest),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: kAppPackage,
                ),
                if (user != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [user, dest],
                        strokeWidth: 4,
                        color: Theme.of(context).colorScheme.primary,
                        pattern: StrokePattern.dashed(segments: const [10, 8]),
                      ),
                    ],
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
                                BoxShadow(blurRadius: 4, color: Colors.black38),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Marker(
                      point: dest,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: Semantics(
                        label: 'Tujuan: ${source.name}',
                        child: Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            Icon(Icons.location_on,
                                size: 44, color: source.availability.color),
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Icon(source.availability.icon,
                                  size: 16, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 6,
                    color: Colors.black12,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (dist != null && bearing != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Jarak ${formatDistance(dist)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          'Arah ${compassLabel(bearing)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Garis lurus, bukan rute jalan'),
                  ] else if (_locating) ...[
                    const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Mengambil lokasi saat ini…'),
                      ],
                    ),
                  ] else if (_errorStatus != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_off,
                            size: 20,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(locationErrorText(_errorStatus!))),
                      ],
                    ),
                    if (_errorStatus == LocationStatus.serviceOff ||
                        _errorStatus == LocationStatus.deniedForever) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _errorStatus == LocationStatus.serviceOff
                              ? loc.openLocationSettings
                              : loc.openAppSettings,
                          child: const Text('Pengaturan'),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _locating ? null : _fetchLocation,
                    icon: const Icon(Icons.my_location),
                    label: const Text('Perbarui lokasi'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
