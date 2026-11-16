import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/water_source.dart';
import '../providers/source_provider.dart';
import '../services/source_service.dart';
import '../widgets/availability_badge.dart';

Future<void> showListingReviewSheet(BuildContext context, WaterSource source) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ListingReviewSheet(source: source),
    ),
  );
}

class ListingReviewSheet extends StatefulWidget {
  final WaterSource source;
  const ListingReviewSheet({super.key, required this.source});

  @override
  State<ListingReviewSheet> createState() => _ListingReviewSheetState();
}

class _ListingReviewSheetState extends State<ListingReviewSheet> {
  final _note = TextEditingController();
  String? _noteError;
  String? _submitError;
  bool _submitting = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    final target = approve ? ListingStatus.published : ListingStatus.rejected;
    String cleanNote;
    try {
      cleanNote = validateListingNote(target, _note.text);
    } on SourceException catch (e) {
      setState(() => _noteError = e.message);
      return;
    }

    setState(() {
      _submitting = true;
      _noteError = null;
      _submitError = null;
    });

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final err = await context
        .read<SourceProvider>()
        .setListingStatus(widget.source.id, target, note: cleanNote);

    if (!mounted) return;
    if (err == null) {
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(approve
            ? 'Sumber disetujui dan ditayangkan.'
            : 'Sumber ditolak dan alasan dicatat.'),
      ));
    } else {
      setState(() {
        _submitting = false;
        _submitError = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final scheme = Theme.of(context).colorScheme;
    final point = LatLng(s.latitude, s.longitude);
    final owner = s.ownerName?.trim() ?? '';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tinjau sumber penyedia',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (owner.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Penyedia: $owner'),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s.type.icon, size: 16),
                    const SizedBox(width: 4),
                    Text(s.type.label),
                  ],
                ),
                AvailabilityBadge(availability: s.availability),
              ],
            ),
            const SizedBox(height: 8),
            Text('Alamat: ${s.address}'),
            const SizedBox(height: 4),
            Text('Tujuan penggunaan: ${s.intendedUse}'),
            const SizedBox(height: 4),
            Text('Jam layanan: ${s.openingHours}'),
            const SizedBox(height: 4),
            Text(
              'Koordinat: ${s.latitude.toStringAsFixed(6)}, ${s.longitude.toStringAsFixed(6)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade800),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.pin_drop_outlined,
                      size: 18, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Periksa posisi pin pada peta agar sesuai dengan alamat sebelum menyetujui.',
                      style: TextStyle(color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 16,
                    interactionOptions:
                        const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: kAppPackage,
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 40,
                          height: 40,
                          alignment: Alignment.topCenter,
                          child: Icon(Icons.location_on,
                              size: 40, color: scheme.error),
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
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLines: 2,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'Catatan peninjau',
                helperText: 'Wajib diisi jika menolak (min. 5 karakter)',
                errorText: _noteError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_noteError != null) setState(() => _noteError = null);
              },
            ),
            if (_submitError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child:
                    Text(_submitError!, style: TextStyle(color: scheme.error)),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => _decide(false),
                    child: const Text('Tolak'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _decide(true),
                    child: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Setujui'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
