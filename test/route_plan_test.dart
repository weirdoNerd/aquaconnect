import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:aquaconnect/models/route_plan.dart';

RoutePlan _plan({List<RouteStep>? steps}) => RoutePlan(
      points: List.generate(5, (i) => LatLng(0, 0.001 * i)),
      steps: steps ??
          const [
            RouteStep(maneuver: Maneuver.depart, street: 'A', distanceM: 222, firstPoint: 0, lastPoint: 2),
            RouteStep(maneuver: Maneuver.left, street: 'B', distanceM: 222, firstPoint: 2, lastPoint: 4),
            RouteStep(maneuver: Maneuver.arrive, street: '-', distanceM: 0, firstPoint: 4, lastPoint: 4),
          ],
      distanceM: 444,
      durationS: 300,
      mode: TravelMode.walk,
    );

void main() {
  group('Maneuver.fromOrsType', () {
    test('kode 0-13 dipetakan sesuai dokumentasi ORS', () {
      const expected = [
        Maneuver.left,
        Maneuver.right,
        Maneuver.sharpLeft,
        Maneuver.sharpRight,
        Maneuver.slightLeft,
        Maneuver.slightRight,
        Maneuver.straight,
        Maneuver.roundaboutEnter,
        Maneuver.roundaboutExit,
        Maneuver.uTurn,
        Maneuver.arrive,
        Maneuver.depart,
        Maneuver.keepLeft,
        Maneuver.keepRight,
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(Maneuver.fromOrsType(i), expected[i], reason: 'type $i');
      }
    });

    test('kode asing, angkutan umum, dan null menjadi unknown', () {
      expect(Maneuver.fromOrsType(14), Maneuver.unknown);
      expect(Maneuver.fromOrsType(17), Maneuver.unknown);
      expect(Maneuver.fromOrsType(99), Maneuver.unknown);
      expect(Maneuver.fromOrsType(-1), Maneuver.unknown);
      expect(Maneuver.fromOrsType(null), Maneuver.unknown);
    });
  });

  group('TravelMode', () {
    test('profil ORS dan penanda perkiraan', () {
      expect(TravelMode.walk.orsProfile, 'foot-walking');
      expect(TravelMode.bike.orsProfile, 'cycling-regular');
      expect(TravelMode.motor.orsProfile, 'driving-car');
      expect(TravelMode.walk.approximate, isFalse);
      expect(TravelMode.motor.approximate, isTrue);
      expect(TravelMode.motor.label, contains('perkiraan'));
    });
  });

  group('RoutePlan', () {
    test('cum dihitung sekali dan sepanjang points', () {
      final p = _plan();
      expect(p.cum.length, p.points.length);
      expect(p.cum.first, 0);
      expect(p.cum.last, closeTo(444.8, 2));
    });

    test('stepIndexAt memilih langkah yang memuat segmen', () {
      final p = _plan();
      expect(p.stepIndexAt(0), 0);
      expect(p.stepIndexAt(1), 0);
      expect(p.stepIndexAt(2), 1);
      expect(p.stepIndexAt(3), 1);
    });

    test('stepIndexAt aman untuk segmen negatif dan tanpa langkah', () {
      expect(_plan().stepIndexAt(-5), 0);
      expect(_plan(steps: const []).stepIndexAt(1), -1);
    });
  });
}
