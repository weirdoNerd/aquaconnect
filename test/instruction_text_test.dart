import 'package:flutter_test/flutter_test.dart';
import 'package:aquaconnect/models/route_plan.dart';
import 'package:aquaconnect/utils/instruction_text.dart';

void main() {
  test('setiap manuver menghasilkan teks bernama jalan', () {
    const street = 'Jl. Kamal Raya';
    expect(instructionText(Maneuver.left, street), 'Belok kiri ke Jl. Kamal Raya');
    expect(instructionText(Maneuver.right, street), 'Belok kanan ke Jl. Kamal Raya');
    expect(instructionText(Maneuver.sharpLeft, street), 'Belok kiri tajam ke Jl. Kamal Raya');
    expect(instructionText(Maneuver.sharpRight, street), 'Belok kanan tajam ke Jl. Kamal Raya');
    expect(instructionText(Maneuver.slightLeft, street), 'Serong kiri ke Jl. Kamal Raya');
    expect(instructionText(Maneuver.slightRight, street), 'Serong kanan ke Jl. Kamal Raya');
    expect(instructionText(Maneuver.straight, street), 'Lurus di Jl. Kamal Raya');
    expect(instructionText(Maneuver.keepLeft, street), 'Tetap di kiri menuju Jl. Kamal Raya');
    expect(instructionText(Maneuver.keepRight, street), 'Tetap di kanan menuju Jl. Kamal Raya');
    expect(instructionText(Maneuver.roundaboutExit, street), 'Keluar dari bundaran ke Jl. Kamal Raya');
    expect(instructionText(Maneuver.depart, street), 'Mulai menuju Jl. Kamal Raya');
  });

  test('manuver tanpa nama jalan tidak memuat kata "ke"', () {
    expect(instructionText(Maneuver.left, ''), 'Belok kiri');
    expect(instructionText(Maneuver.right, '-'), 'Belok kanan');
    expect(instructionText(Maneuver.straight, '-'), 'Lurus');
    expect(instructionText(Maneuver.roundaboutExit, ' '), 'Keluar dari bundaran');
    expect(instructionText(Maneuver.keepLeft, '-'), 'Tetap di kiri');
    expect(instructionText(Maneuver.keepRight, ''), 'Tetap di kanan');
  });

  test('manuver tetap', () {
    expect(instructionText(Maneuver.uTurn, 'X'), 'Putar balik');
    expect(instructionText(Maneuver.arrive, 'X'), 'Anda telah tiba di tujuan');
    expect(instructionText(Maneuver.roundaboutEnter, ''), 'Masuk bundaran');
  });

  test('bundaran memuat nomor jalan keluar bila ada', () {
    expect(instructionText(Maneuver.roundaboutEnter, '', exitNumber: 2),
        'Masuk bundaran, ambil jalan keluar ke-2');
  });

  test('awal perjalanan mengikuti moda', () {
    expect(instructionText(Maneuver.depart, '-'), 'Mulai berjalan');
    expect(instructionText(Maneuver.depart, '', mode: TravelMode.bike), 'Mulai bersepeda');
    expect(instructionText(Maneuver.depart, '', mode: TravelMode.motor), 'Mulai berkendara');
  });

  test('unknown memakai teks asli penyedia, atau "Lanjutkan"', () {
    expect(instructionText(Maneuver.unknown, 'X', raw: 'Naik angkutan'), 'Naik angkutan');
    expect(instructionText(Maneuver.unknown, 'X'), 'Lanjutkan');
    expect(instructionText(Maneuver.unknown, 'X', raw: '  '), 'Lanjutkan');
  });

  test('semua nilai Maneuver punya teks (tidak ada yang terlewat)', () {
    for (final m in Maneuver.values) {
      expect(instructionText(m, 'Jl. A'), isNotEmpty);
    }
  });
}
