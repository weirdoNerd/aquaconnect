import 'package:flutter/material.dart';
import '../providers/source_provider.dart';
import '../services/location_service.dart';

/// Menampilkan snackbar yang sesuai untuk kegagalan lokasi.
/// Panggil hanya bila `context.mounted`.
void showLocationError(
    BuildContext context, SourceProvider sp, LocationStatus status) {
  final text = switch (status) {
    LocationStatus.serviceOff =>
      'Layanan lokasi (GPS) mati. Aktifkan di pengaturan perangkat.',
    LocationStatus.denied =>
      'Izin lokasi ditolak, jadi jarak tidak bisa dihitung.',
    LocationStatus.deniedForever =>
      'Izin lokasi diblokir. Aktifkan di pengaturan aplikasi.',
    _ => 'Gagal mendapatkan lokasi. Pastikan sinyal GPS baik lalu coba lagi.',
  };
  final action = switch (status) {
    LocationStatus.serviceOff =>
      SnackBarAction(label: 'Pengaturan', onPressed: sp.openLocationSettings),
    LocationStatus.deniedForever =>
      SnackBarAction(label: 'Pengaturan', onPressed: sp.openAppSettings),
    _ => null,
  };
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text), action: action));
}
