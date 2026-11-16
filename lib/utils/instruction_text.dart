import '../models/route_plan.dart';

/// Teks instruksi bahasa Indonesia, dibuat di aplikasi (ORS tidak menyediakan
/// bahasa Indonesia), sehingga tes tidak bergantung bahasa server.
String instructionText(
  Maneuver m,
  String street, {
  String? raw,
  int? exitNumber,
  TravelMode mode = TravelMode.walk,
}) {
  final s = (street.trim().isEmpty || street.trim() == '-') ? '' : street.trim();
  String to() => s.isEmpty ? '' : ' ke $s';
  String toward() => s.isEmpty ? '' : ' menuju $s';
  String start() => switch (mode) {
        TravelMode.walk => 'Mulai berjalan',
        TravelMode.bike => 'Mulai bersepeda',
        TravelMode.motor => 'Mulai berkendara',
      };

  return switch (m) {
    Maneuver.depart => s.isEmpty ? start() : 'Mulai menuju $s',
    Maneuver.left => 'Belok kiri${to()}',
    Maneuver.right => 'Belok kanan${to()}',
    Maneuver.sharpLeft => 'Belok kiri tajam${to()}',
    Maneuver.sharpRight => 'Belok kanan tajam${to()}',
    Maneuver.slightLeft => 'Serong kiri${to()}',
    Maneuver.slightRight => 'Serong kanan${to()}',
    Maneuver.straight => s.isEmpty ? 'Lurus' : 'Lurus di $s',
    Maneuver.keepLeft => 'Tetap di kiri${toward()}',
    Maneuver.keepRight => 'Tetap di kanan${toward()}',
    Maneuver.roundaboutEnter => exitNumber == null
        ? 'Masuk bundaran'
        : 'Masuk bundaran, ambil jalan keluar ke-$exitNumber',
    Maneuver.roundaboutExit => 'Keluar dari bundaran${to()}',
    Maneuver.uTurn => 'Putar balik',
    Maneuver.arrive => 'Anda telah tiba di tujuan',
    Maneuver.unknown => (raw == null || raw.trim().isEmpty) ? 'Lanjutkan' : raw,
  };
}
