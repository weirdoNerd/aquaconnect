import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// Jarak dua titik dalam meter (rumus haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Membaca "-6.1480, 106.7370". Desimal pakai titik.
LatLng? parseLatLng(String input) {
  final parts = input
      .replaceAll(';', ',')
      .split(RegExp(r'[,\s]+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0]);
  final lng = double.tryParse(parts[1]);
  if (lat == null || lng == null) return null;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  return LatLng(lat, lng);
}

/// 450 -> "450 m", 1500 -> "1.5 km", 250000 -> "250 km".
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  if (meters < 100000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${(meters / 1000).round()} km';
}

/// Arah dari [from] ke [to] dalam derajat 0-360 (0 = utara, 90 = timur).
double bearingDegrees(LatLng from, LatLng to) {
  double rad(double d) => d * math.pi / 180;
  final dLng = rad(to.longitude - from.longitude);
  final y = math.sin(dLng) * math.cos(rad(to.latitude));
  final x = math.cos(rad(from.latitude)) * math.sin(rad(to.latitude)) -
      math.sin(rad(from.latitude)) *
          math.cos(rad(to.latitude)) *
          math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// 0 -> "utara", 45 -> "timur laut", dst. (delapan arah).
String compassLabel(double degrees) {
  const names = [
    'utara',
    'timur laut',
    'timur',
    'tenggara',
    'selatan',
    'barat daya',
    'barat',
    'barat laut',
  ];
  final i = ((degrees % 360 + 22.5) / 45).floor() % 8;
  return names[i];
}
