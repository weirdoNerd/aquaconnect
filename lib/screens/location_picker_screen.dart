import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config.dart';
import '../utils/geo.dart';

/// Layar layar-penuh untuk menandai lokasi. Mengembalikan LatLng lewat pop.
class LocationPickerScreen extends StatefulWidget {
  final LatLng? initial;
  const LocationPickerScreen({super.key, this.initial});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Pusat awal bila belum ada titik: Cengkareng, Jakarta Barat
  static const _defaultCenter = LatLng(-6.1480, 106.7370);

  final _controller = MapController();
  LatLng? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  Future<void> _paste() async {
    final p = await showDialog<LatLng>(
        context: context, builder: (_) => const _CoordinateDialog());
    if (p != null) {
      setState(() => _selected = p);
      _controller.move(p, 17);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih lokasi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: 'Tempel koordinat',
            onPressed: _paste,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: widget.initial ?? _defaultCenter,
                initialZoom: widget.initial == null ? 14 : 17,
                onTap: (_, point) => setState(() => _selected = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: kAppPackage,
                ),
                if (sel != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: sel,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on,
                          size: 48, color: Theme.of(context).colorScheme.error),
                    ),
                  ]),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors')
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sel == null
                        ? 'Ketuk peta untuk menandai lokasi, atau tempel koordinat.'
                        : 'Lat ${sel.latitude.toStringAsFixed(6)}, Lng ${sel.longitude.toStringAsFixed(6)}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: sel == null ? null : () => Navigator.pop(context, sel),
                    child: const Text('Gunakan lokasi ini'),
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

class _CoordinateDialog extends StatefulWidget {
  const _CoordinateDialog();

  @override
  State<_CoordinateDialog> createState() => _CoordinateDialogState();
}

class _CoordinateDialogState extends State<_CoordinateDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final p = parseLatLng(_ctrl.text);
    if (p == null) {
      setState(() => _error = 'Format tidak valid. Contoh: -6.1480, 106.7370');
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tempel koordinat'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(
          hintText: '-6.1480, 106.7370',
          helperText: 'Format: -6.1480, 106.7370',
          helperMaxLines: 2,
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _apply(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _apply, child: const Text('Terapkan')),
      ],
    );
  }
}
