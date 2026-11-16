import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../utils/route_math.dart';

enum TravelMode {
  walk('Jalan kaki', Icons.directions_walk, 'foot-walking', false),
  bike('Sepeda', Icons.directions_bike, 'cycling-regular', false),

  /// ORS tidak punya profil motor: `driving-car` hanya pendekatan. Motor bisa
  /// lewat gang yang tidak dilalui mobil, sehingga rute dan waktunya berbeda.
  motor('Motor/mobil (perkiraan)', Icons.two_wheeler, 'driving-car', true);

  final String label;
  final IconData icon;
  final String orsProfile;
  final bool approximate;
  const TravelMode(this.label, this.icon, this.orsProfile, this.approximate);
}

enum Maneuver {
  depart,
  left,
  right,
  sharpLeft,
  sharpRight,
  slightLeft,
  slightRight,
  straight,
  roundaboutEnter,
  roundaboutExit,
  uTurn,
  keepLeft,
  keepRight,
  arrive,
  unknown;

  /// Kode `type` instruksi ORS (0-13 sesuai dokumentasi resmi; 14-17 untuk
  /// angkutan umum dan tidak dikenal menjadi [unknown]). Dicocokkan lagi dengan
  /// respons nyata di tes fixture.
  static Maneuver fromOrsType(int? type) => switch (type) {
        0 => Maneuver.left,
        1 => Maneuver.right,
        2 => Maneuver.sharpLeft,
        3 => Maneuver.sharpRight,
        4 => Maneuver.slightLeft,
        5 => Maneuver.slightRight,
        6 => Maneuver.straight,
        7 => Maneuver.roundaboutEnter,
        8 => Maneuver.roundaboutExit,
        9 => Maneuver.uTurn,
        10 => Maneuver.arrive,
        11 => Maneuver.depart,
        12 => Maneuver.keepLeft,
        13 => Maneuver.keepRight,
        _ => Maneuver.unknown,
      };
}

class RouteStep {
  final Maneuver maneuver;

  /// Nama jalan; kosong atau "-" bila jalan tanpa nama.
  final String street;
  final double distanceM;

  /// Indeks titik awal dan akhir langkah pada [RoutePlan.points].
  final int firstPoint;
  final int lastPoint;

  /// Teks asli dari penyedia (cadangan untuk [Maneuver.unknown]).
  final String? rawInstruction;

  /// Nomor jalan keluar bundaran, bila ada.
  final int? exitNumber;

  const RouteStep({
    required this.maneuver,
    required this.street,
    required this.distanceM,
    required this.firstPoint,
    required this.lastPoint,
    this.rawInstruction,
    this.exitNumber,
  });
}

class RoutePlan {
  final List<LatLng> points;
  final List<RouteStep> steps;
  final double distanceM;
  final double durationS;
  final TravelMode mode;

  /// true bila rute hanya perkiraan (garis lurus atau profil pendekatan).
  final bool approximate;

  /// Alasan bila memakai cadangan, mis. "Tanpa kunci API" atau "Tidak ada internet".
  final String? fallbackReason;

  /// Jarak kumulatif per titik, dihitung sekali.
  final List<double> cum;

  RoutePlan({
    required this.points,
    required this.steps,
    required this.distanceM,
    required this.durationS,
    required this.mode,
    this.approximate = false,
    this.fallbackReason,
  })  : assert(points.length >= 2, 'Rute minimal punya dua titik'),
        cum = cumulativeDistances(points);

  /// Indeks langkah yang memuat segmen [segment] (segmen i = titik i ke i+1),
  /// atau -1 bila tidak ada langkah.
  int stepIndexAt(int segment) {
    if (steps.isEmpty) return -1;
    for (var i = steps.length - 1; i >= 0; i--) {
      if (steps[i].firstPoint <= segment) return i;
    }
    return 0;
  }
}
