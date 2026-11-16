import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum LocationStatus { ok, serviceOff, denied, deniedForever, error }

class LocationResult {
  final LocationStatus status;
  final LatLng? point;
  const LocationResult(this.status, [this.point]);
}

abstract class LocationService {
  Future<LocationResult> getCurrent();
  Future<void> openLocationSettings();
  Future<void> openAppSettings();
}

/// Lokasi hanya dipakai di perangkat untuk menghitung jarak.
/// Tidak dikirim ke server dan tidak disimpan.
class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationResult> getCurrent() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult(LocationStatus.serviceOff);
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        return const LocationResult(LocationStatus.denied);
      }
      if (perm == LocationPermission.deniedForever) {
        return const LocationResult(LocationStatus.deniedForever);
      }

      try {
        // Akurasi sedang cukup untuk jarak antar blok dan lebih hemat baterai.
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
        return LocationResult(
            LocationStatus.ok, LatLng(pos.latitude, pos.longitude));
      } catch (e) {
        debugPrint('getCurrentPosition gagal: $e');
        // Sinyal lemah/timeout: pakai posisi terakhir yang diketahui.
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return LocationResult(
              LocationStatus.ok, LatLng(last.latitude, last.longitude));
        }
        return const LocationResult(LocationStatus.error);
      }
    } catch (e) {
      debugPrint('Lokasi gagal: $e');
      return const LocationResult(LocationStatus.error);
    }
  }

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();
}
