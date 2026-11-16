import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:aquaconnect/utils/geo.dart';

void main() {
  group('distanceMeters', () {
    test('titik yang sama berjarak 0', () {
      expect(distanceMeters(-6.148, 106.737, -6.148, 106.737), closeTo(0, 0.01));
    });

    test('1 derajat bujur di khatulistiwa sekitar 111 km', () {
      expect(distanceMeters(0, 0, 0, 1), closeTo(111195, 200));
    });

    test('simetris', () {
      final a = distanceMeters(-6.14, 106.73, -6.16, 106.75);
      final b = distanceMeters(-6.16, 106.75, -6.14, 106.73);
      expect(a, closeTo(b, 0.001));
    });
  });

  group('parseLatLng', () {
    test('format salinan Google Maps', () {
      final p = parseLatLng('-6.1480, 106.7370');
      expect(p?.latitude, -6.1480);
      expect(p?.longitude, 106.7370);
    });

    test('dipisah spasi', () {
      expect(parseLatLng('-6.1 106.7'), isNotNull);
    });

    test('menolak input tidak valid', () {
      expect(parseLatLng(''), isNull);
      expect(parseLatLng('abc, def'), isNull);
      expect(parseLatLng('-6.1'), isNull);
      expect(parseLatLng('95, 106'), isNull);
      expect(parseLatLng('-6, 200'), isNull);
    });
  });

  group('formatDistance', () {
    test('meter, kilometer, dan jauh', () {
      expect(formatDistance(450), '450 m');
      expect(formatDistance(1500), '1.5 km');
      expect(formatDistance(250000), '250 km');
    });
  });

  group('bearingDegrees', () {
    const o = LatLng(0, 0);
    test('utara, timur, selatan, barat', () {
      expect(bearingDegrees(o, const LatLng(1, 0)), closeTo(0, 0.01));
      expect(bearingDegrees(o, const LatLng(0, 1)), closeTo(90, 0.01));
      expect(bearingDegrees(o, const LatLng(-1, 0)), closeTo(180, 0.01));
      expect(bearingDegrees(o, const LatLng(0, -1)), closeTo(270, 0.01));
    });
    test('selalu di rentang 0-360', () {
      for (final to in const [LatLng(1, 1), LatLng(-1, -1), LatLng(1, -1), LatLng(-1, 1)]) {
        final b = bearingDegrees(o, to);
        expect(b, inInclusiveRange(0, 360));
      }
    });
  });

  group('compassLabel', () {
    test('delapan arah dan batasnya', () {
      expect(compassLabel(0), 'utara');
      expect(compassLabel(22), 'utara');
      expect(compassLabel(23), 'timur laut');
      expect(compassLabel(45), 'timur laut');
      expect(compassLabel(90), 'timur');
      expect(compassLabel(135), 'tenggara');
      expect(compassLabel(180), 'selatan');
      expect(compassLabel(225), 'barat daya');
      expect(compassLabel(270), 'barat');
      expect(compassLabel(315), 'barat laut');
      expect(compassLabel(359), 'utara');
    });
  });
}
