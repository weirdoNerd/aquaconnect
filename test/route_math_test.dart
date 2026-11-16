import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:aquaconnect/utils/route_math.dart';

// Jalur lurus ke timur di khatulistiwa, sekitar 222 m.
final _route = [
  const LatLng(0, 0),
  const LatLng(0, 0.001),
  const LatLng(0, 0.002),
];
// 30 m ke utara dalam satuan derajat lintang (sesuai bidang lokal 110540 m/derajat).
const _lat30m = 30 / 110540;

void main() {
  final cum = cumulativeDistances(_route);

  test('jarak kumulatif dimulai dari 0 dan bertambah', () {
    expect(cum.first, 0);
    expect(cum[1], closeTo(111.19, 0.5));
    expect(cum[2], closeTo(222.39, 1));
  });

  test('titik tepat di jalur: offRouteM mendekati 0', () {
    final s = snapToRoute(const LatLng(0, 0.0005), _route, cum);
    expect(s.offRouteM, closeTo(0, 0.01));
  });

  test('titik 30 m tegak lurus: offRouteM sekitar 30, alongM di tengah', () {
    final s = snapToRoute(const LatLng(_lat30m, 0.001), _route, cum);
    expect(s.offRouteM, closeTo(30, 0.5));
    expect(s.alongM, closeTo(cum.last / 2, 1));
  });

  test('alongM tidak pernah berkurang saat bergerak sepanjang jalur', () {
    var prev = -1.0;
    for (var k = 0; k <= 20; k++) {
      final s = snapToRoute(LatLng(_lat30m * 0.2, 0.0001 * k), _route, cum);
      expect(s.alongM, greaterThanOrEqualTo(prev));
      prev = s.alongM;
    }
  });

  test('titik sebelum awal dijepit ke awal', () {
    final s = snapToRoute(const LatLng(0, -0.001), _route, cum);
    expect(s.alongM, 0);
    expect(s.point.longitude, 0);
    expect(s.offRouteM, closeTo(111.3, 1));
  });

  test('titik sesudah akhir dijepit ke akhir', () {
    final s = snapToRoute(const LatLng(0, 0.003), _route, cum);
    expect(s.alongM, closeTo(cum.last, 0.01));
    expect(s.point.longitude, closeTo(0.002, 1e-9));
  });

  test('jalur satu segmen berfungsi', () {
    final pts = [const LatLng(0, 0), const LatLng(0, 0.001)];
    final s = snapToRoute(const LatLng(0.0001, 0.0005), pts, cumulativeDistances(pts));
    expect(s.segment, 0);
    expect(s.offRouteM, closeTo(11.05, 0.2));
  });

  test('dua titik identik tidak membagi nol', () {
    final pts = [const LatLng(0, 0), const LatLng(0, 0)];
    final s = snapToRoute(const LatLng(0.0001, 0.0001), pts, cumulativeDistances(pts));
    expect(s.alongM, 0);
    expect(s.offRouteM.isFinite, isTrue);
  });

  test('titik duplikat di tengah jalur tidak merusak hasil', () {
    final pts = [
      const LatLng(0, 0),
      const LatLng(0, 0.001),
      const LatLng(0, 0.001),
      const LatLng(0, 0.002),
    ];
    final c = cumulativeDistances(pts);
    final s = snapToRoute(const LatLng(0.0001, 0.0015), pts, c);
    expect(s.alongM.isFinite, isTrue);
    expect(s.alongM, closeTo(c.last * 0.75, 1));
  });

  test('jalur satu titik dan jalur kosong ditangani', () {
    final one = [const LatLng(1, 1)];
    expect(snapToRoute(const LatLng(1, 1), one, cumulativeDistances(one)).alongM, 0);
    expect(() => snapToRoute(const LatLng(0, 0), [], []), throwsArgumentError);
  });

  test('jendela maxSegments mencegah lompat ke ruas yang memotong dirinya', () {
    // A -> B ke timur, lalu memutar dan kembali memotong A-B di (0, 0.001).
    final loop = [
      const LatLng(0, 0),
      const LatLng(0, 0.002),
      const LatLng(0.001, 0.002),
      const LatLng(0.001, 0.001),
      const LatLng(-0.001, 0.001),
    ];
    final c = cumulativeDistances(loop);
    const p = LatLng(-0.0005, 0.001); // tepat di segmen terakhir

    final global = snapToRoute(p, loop, c);
    expect(global.segment, 3);
    expect(global.offRouteM, closeTo(0, 0.5));

    final windowed = snapToRoute(p, loop, c, fromSegment: 0, maxSegments: 2);
    expect(windowed.segment, 0);
    expect(windowed.offRouteM, closeTo(55.27, 0.5));
  });

  test('maxSegments kurang dari 1 tetap memeriksa satu segmen', () {
    final s = snapToRoute(const LatLng(0, 0.0005), _route, cum, maxSegments: 0);
    expect(s.segment, 0);
  });

  test('fromSegment membatasi pencarian ke segmen setelahnya', () {
    final s = snapToRoute(const LatLng(0, 0.0002), _route, cum, fromSegment: 2);
    // fromSegment 2 -> mulai dari segmen 1 (max(0, 2-1)); segmen 0 diabaikan.
    expect(s.segment, 1);
  });
}
