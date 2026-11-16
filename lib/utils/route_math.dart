import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'geo.dart';

class RouteSnap {
  final int segment; // indeks titik awal segmen terdekat
  final LatLng point; // titik terdekat pada jalur
  final double offRouteM; // jarak tegak lurus dari jalur
  final double alongM; // jarak dari awal rute sampai titik ini
  const RouteSnap(this.segment, this.point, this.offRouteM, this.alongM);
}

/// cum[0] = 0, cum[i] = cum[i-1] + jarak(titik i-1, titik i).
List<double> cumulativeDistances(List<LatLng> pts) {
  final cum = <double>[];
  for (var i = 0; i < pts.length; i++) {
    cum.add(i == 0
        ? 0.0
        : cum[i - 1] +
            distanceMeters(pts[i - 1].latitude, pts[i - 1].longitude,
                pts[i].latitude, pts[i].longitude));
  }
  return cum;
}

/// Memproyeksikan [p] ke jalur [pts]. Pencarian dimulai dari
/// `max(0, fromSegment - 1)` dan, bila [maxSegments] diberikan, hanya memeriksa
/// sebanyak itu segmen. Pada rute yang memotong dirinya sendiri (mis. lewat
/// jembatan penyeberangan), pemanggil memakai jendela agar snap tidak melompat
/// ke ruas yang salah, dan kembali ke pencarian global (tanpa [maxSegments])
/// hanya saat pengguna menyimpang.
RouteSnap snapToRoute(
  LatLng p,
  List<LatLng> pts,
  List<double> cum, {
  int fromSegment = 0,
  int? maxSegments,
}) {
  if (pts.isEmpty) throw ArgumentError('Jalur kosong');
  if (pts.length == 1) {
    return RouteSnap(
        0,
        pts[0],
        distanceMeters(p.latitude, p.longitude, pts[0].latitude, pts[0].longitude),
        0);
  }

  // Bidang lokal (meter) di sekitar p, jadi p berada di titik asal (0, 0).
  final cosLat = math.cos(p.latitude * math.pi / 180);
  double x(LatLng q) => (q.longitude - p.longitude) * 111320 * cosLat;
  double y(LatLng q) => (q.latitude - p.latitude) * 110540;

  final start = math.max(0, math.min(fromSegment - 1, pts.length - 2));
  var bestDist = double.infinity;
  var bestSeg = start;
  var bestT = 0.0;

  final end = maxSegments == null
      ? pts.length - 1
      : math.min(pts.length - 1, start + math.max(1, maxSegments));

  for (var i = start; i < end; i++) {
    final ax = x(pts[i]), ay = y(pts[i]);
    final dx = x(pts[i + 1]) - ax, dy = y(pts[i + 1]) - ay;
    final len2 = dx * dx + dy * dy;
    // Segmen berpanjang nol (titik identik): jangan membagi nol.
    final t = len2 == 0
        ? 0.0
        : ((-ax * dx - ay * dy) / len2).clamp(0.0, 1.0).toDouble();
    final px = ax + t * dx, py = ay + t * dy;
    final d = math.sqrt(px * px + py * py);
    if (d < bestDist) {
      bestDist = d;
      bestSeg = i;
      bestT = t;
    }
  }

  final a = pts[bestSeg], b = pts[bestSeg + 1];
  final segLen = cum[bestSeg + 1] - cum[bestSeg];
  return RouteSnap(
    bestSeg,
    LatLng(a.latitude + bestT * (b.latitude - a.latitude),
        a.longitude + bestT * (b.longitude - a.longitude)),
    bestDist,
    cum[bestSeg] + bestT * segLen,
  );
}
