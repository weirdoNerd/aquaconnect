import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/water_source.dart';
import '../providers/auth_provider.dart';
import '../providers/source_provider.dart';
import 'location_picker_screen.dart';

/// Tambah (source == null) atau ubah sumber air. Khusus admin.
class SourceFormScreen extends StatefulWidget {
  final WaterSource? source;
  const SourceFormScreen({super.key, this.source});

  @override
  State<SourceFormScreen> createState() => _SourceFormScreenState();
}

class _SourceFormScreenState extends State<SourceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _use;
  late final TextEditingController _hours;
  late SourceType _type;
  late Availability _availability;
  late bool _simulated;
  late bool _active;
  late bool _qualityFlag;
  late bool _confirm;
  LatLng? _point;
  bool _pointError = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.source != null;

  /// Sumber berpemilik yang belum tayang (pending/rejected): penayangannya lewat
  /// setListing (S7), bukan sakelar ini.
  bool get _hideListingSwitch {
    final s = widget.source;
    return s != null &&
        s.hasOwner &&
        (s.listingStatus == ListingStatus.pending ||
            s.listingStatus == ListingStatus.rejected);
  }

  @override
  void initState() {
    super.initState();
    final s = widget.source;
    _name = TextEditingController(text: s?.name ?? '');
    _address = TextEditingController(text: s?.address ?? '');
    _use = TextEditingController(
        text: s?.intendedUse ?? 'Belum diverifikasi untuk air minum');
    _hours = TextEditingController(text: s?.openingHours ?? '');
    _type = s?.type ?? SourceType.publicWell;
    _availability = s?.availability ?? Availability.available;
    _simulated = s?.isSimulated ?? false;
    _active = s?.isActive ?? true;
    _qualityFlag = s?.qualityFlag ?? false;
    _confirm = false; // sumber baru otomatis dikonfirmasi oleh service
    _point = s == null ? null : LatLng(s.latitude, s.longitude);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _use.dispose();
    _hours.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final r = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(builder: (_) => LocationPickerScreen(initial: _point)),
    );
    if (r != null) {
      setState(() {
        _point = r;
        _pointError = false;
      });
    }
  }

  Future<void> _save() async {
    final okForm = _formKey.currentState!.validate();
    setState(() => _pointError = _point == null);
    if (!okForm || _point == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final hours = _hours.text.trim();
    final original = widget.source?.listingStatus;
    final data = WaterSource(
      id: widget.source?.id ?? '',
      name: _name.text.trim(),
      address: _address.text.trim(),
      latitude: _point!.latitude,
      longitude: _point!.longitude,
      type: _type,
      availability: _availability,
      intendedUse: _use.text.trim(),
      openingHours: hours.isEmpty ? '-' : hours,
      isSimulated: _simulated,
      qualityFlag: _qualityFlag,
      // Mematikan sakelar = ditangguhkan, kecuali sumber sudah berstatus tak tayang
      // lain (pending/ditolak/ditutup) yang tidak boleh diubah diam-diam.
      listingStatus: _active
          ? ListingStatus.published
          : (original != null && original != ListingStatus.published
              ? original
              : ListingStatus.suspended),
      ownerId: widget.source?.ownerId,
      ownerName: widget.source?.ownerName,
      verifiedBy: _confirm ? VerifiedBy.admin : widget.source?.verifiedBy,
      reviewNote: widget.source?.reviewNote,
      closedReason: widget.source?.closedReason,
      closedAt: widget.source?.closedAt,
    );

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final err = await context
        .read<SourceProvider>()
        .saveSource(data, isNew: !_isEdit, confirmStatus: _confirm);
    if (!mounted) return;

    if (err == null) {
      nav.pop();
      messenger.showSnackBar(SnackBar(
          content: Text(_isEdit
              ? 'Data sumber air diperbarui.'
              : 'Sumber air baru ditambahkan.')));
    } else {
      setState(() {
        _saving = false;
        _error = err;
      });
    }
  }

  Widget _preview(ColorScheme scheme) {
    final p = _point;
    if (p == null) {
      return InkWell(
        onTap: _pickLocation,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 140,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _pointError ? scheme.error : scheme.outline),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_location_alt_outlined,
                  color: _pointError ? scheme.error : null),
              const SizedBox(height: 4),
              Text(
                _pointError ? 'Lokasi wajib dipilih' : 'Pilih lokasi di peta',
                style: TextStyle(color: _pointError ? scheme.error : null),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              key: ValueKey(p),
              options: MapOptions(
                initialCenter: p,
                initialZoom: 16,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: kAppPackage,
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: p,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_on, size: 40, color: scheme.error),
                  ),
                ]),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors')
                  ],
                ),
              ],
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: _pickLocation),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pengecekan UI saja. Pembatasan sebenarnya ada di Security Rules.
    if (!context.watch<AuthProvider>().isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sumber Air')),
        body: const Center(child: Text('Akses ditolak. Khusus pengelola.')),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Ubah Sumber Air' : 'Tambah Sumber Air')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Nama sumber air',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.length < 3) return 'Nama minimal 3 karakter';
                    if (!_simulated && t.contains('[SIMULASI]')) {
                      return 'Hapus label [SIMULASI] atau aktifkan "Data simulasi"';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _address,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Alamat / wilayah',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().length < 5)
                      ? 'Alamat minimal 5 karakter'
                      : null,
                ),
                const SizedBox(height: 8),
                Text('Jenis sumber', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in SourceType.values)
                    ChoiceChip(
                      avatar: Icon(t.icon, size: 18),
                      label: Text(t.label),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                    ),
                ]),
                const SizedBox(height: 16),
                Text('Status ketersediaan',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final a in Availability.values)
                    ChoiceChip(
                      label: Text(a.label),
                      selected: _availability == a,
                      onSelected: (_) => setState(() => _availability = a),
                    ),
                ]),
                if (_isEdit)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Konfirmasi status sekarang'),
                    subtitle: const Text(
                        'Aktifkan hanya jika kamu benar-benar memeriksa ketersediaan air. '
                        'Mengubah alamat atau jam layanan tidak menandai status sebagai terverifikasi.'),
                    value: _confirm,
                    onChanged: (v) => setState(() => _confirm = v),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _use,
                  textInputAction: TextInputAction.next,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    labelText: 'Tujuan penggunaan air',
                    helperText:
                        'Jangan tulis "aman diminum" kecuali sudah ada pemeriksaan kualitas.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _hours,
                  textInputAction: TextInputAction.done,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    labelText: 'Jam layanan',
                    hintText: 'Contoh: 08:00-17:00 atau 24 jam',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Lokasi', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _preview(scheme),
                if (_point != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Lat ${_point!.latitude.toStringAsFixed(6)}, Lng ${_point!.longitude.toStringAsFixed(6)} • ketuk peta untuk mengubah',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                if (!_hideListingSwitch)
                  SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tampilkan di aplikasi'),
                  subtitle: const Text(
                      'Matikan untuk menonaktifkan sumber (data dan riwayat laporan tetap tersimpan).'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                if (_isEdit && widget.source!.qualityFlag)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Penanda dugaan masalah kualitas aktif'),
                    subtitle: const Text(
                        'Matikan setelah kualitas air diperiksa dan dinyatakan baik.'),
                    value: _qualityFlag,
                    onChanged: (v) => setState(() => _qualityFlag = v),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data simulasi'),
                  subtitle: const Text('Ditandai di aplikasi sebagai bukan lokasi nyata.'),
                  value: _simulated,
                  onChanged: (v) => setState(() => _simulated = v),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_isEdit ? 'Simpan perubahan' : 'Tambah sumber air'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
