import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'package:aquaconnect/screens/location_picker_screen.dart';
import 'package:aquaconnect/screens/source_detail_screen.dart';
import 'package:aquaconnect/screens/source_route_screen.dart';
import 'package:aquaconnect/services/auth_service.dart';
import 'package:aquaconnect/services/location_service.dart';
import 'package:aquaconnect/services/source_service.dart';
import 'package:aquaconnect/utils/geo.dart';

class _FakeLocation implements LocationService {
  LocationResult result;
  int getCalls = 0;
  int openLocationCalls = 0;
  int openAppCalls = 0;

  _FakeLocation(this.result);

  @override
  Future<LocationResult> getCurrent() async {
    getCalls++;
    return result;
  }

  @override
  Future<void> openLocationSettings() async => openLocationCalls++;

  @override
  Future<void> openAppSettings() async => openAppCalls++;
}

class _StubAuth implements AuthService {
  final _ctrl = StreamController<AppUser?>.broadcast();
  final AppUser? _user;
  _StubAuth([this._user]);

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> get authChanges => _ctrl.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StaticSourceService implements SourceService {
  final List<WaterSource> sources;
  _StaticSourceService(this.sources);

  @override
  Stream<SourceBatch> watchAll() => Stream.value(SourceBatch(sources));

  @override
  Stream<SourceBatch> watchPublished() =>
      Stream.value(SourceBatch(sources.where((s) => s.isActive).toList()));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

WaterSource _source({
  ListingStatus listingStatus = ListingStatus.published,
}) =>
    WaterSource(
      id: 'src-1',
      name: 'Sumur RW 01',
      address: 'Cengkareng',
      latitude: -6.1400,
      longitude: 106.7300,
      type: SourceType.publicWell,
      availability: Availability.available,
      intendedUse: 'Rumah tangga',
      openingHours: '06:00-18:00',
      verifiedAt: DateTime.now().subtract(const Duration(hours: 2)),
      verifiedBy: VerifiedBy.admin,
      listingStatus: listingStatus,
    );

void main() async {
  await initializeDateFormatting('id_ID');

  group('P-lite: SourceRouteScreen', () {
    Future<void> mountRoute(
      WidgetTester tester, {
      required _FakeLocation loc,
      WaterSource? src,
    }) async {
      final s = src ?? _source();
      final sp = SourceProvider(_StaticSourceService([s]), loc)
        ..syncUser(null, isAdmin: false, isProvider: false);

      await tester.pumpWidget(MultiProvider(
        key: UniqueKey(),
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(_StubAuth(null))),
          ChangeNotifierProvider(create: (_) => sp),
        ],
        child: MaterialApp(home: SourceRouteScreen(sourceId: s.id)),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('menampilkan jarak, arah kompas, garis lurus, dan tanpa perkiraan waktu',
        (tester) async {
      const userPos = LatLng(-6.1500, 106.7300);
      final loc = _FakeLocation(const LocationResult(LocationStatus.ok, userPos));
      await mountRoute(tester, loc: loc);

      final dest = LatLng(_source().latitude, _source().longitude);
      final expectedDist =
          formatDistance(distanceMeters(userPos.latitude, userPos.longitude, dest.latitude, dest.longitude));
      final expectedCompass = compassLabel(bearingDegrees(userPos, dest));

      expect(loc.getCalls, 1);
      expect(find.text('Jarak $expectedDist'), findsOneWidget);
      expect(find.text('Arah $expectedCompass'), findsOneWidget);
      expect(find.text('Jarak 1.1 km'), findsOneWidget);
      expect(find.text('Arah utara'), findsOneWidget);
      expect(find.text('Garis lurus, bukan rute jalan'), findsOneWidget);
      expect(find.textContaining('menit'), findsNothing);
      expect(find.byType(PolylineLayer), findsOneWidget);
    });

    testWidgets('tombol Perbarui lokasi mengambil ulang lokasi dan memperbarui jarak/arah',
        (tester) async {
      final loc = _FakeLocation(
        const LocationResult(LocationStatus.ok, LatLng(-6.1500, 106.7300)),
      );
      await mountRoute(tester, loc: loc);
      expect(find.text('Arah utara'), findsOneWidget);

      // Pindah ke barat tujuan (-6.1400, 106.7200) -> arah ke tujuan menjadi timur.
      loc.result =
          const LocationResult(LocationStatus.ok, LatLng(-6.1400, 106.7200));
      await tester.tap(find.widgetWithText(FilledButton, 'Perbarui lokasi'));
      await tester.pump();
      await tester.pump();

      expect(loc.getCalls, 2);
      expect(find.text('Arah timur'), findsOneWidget);
    });

    testWidgets('keadaan tanpa lokasi menampilkan tujuan saja, pesan jelas, dan tombol pengaturan',
        (tester) async {
      final deniedLoc =
          _FakeLocation(const LocationResult(LocationStatus.denied));
      await mountRoute(tester, loc: deniedLoc);
      expect(find.textContaining('Izin lokasi ditolak'), findsOneWidget);
      expect(find.byType(PolylineLayer), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Perbarui lokasi'), findsOneWidget);

      final serviceOffLoc =
          _FakeLocation(const LocationResult(LocationStatus.serviceOff));
      await mountRoute(tester, loc: serviceOffLoc);
      expect(find.textContaining('Layanan lokasi (GPS) mati'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Pengaturan'));
      await tester.pump();
      expect(serviceOffLoc.openLocationCalls, 1);

      final deniedForeverLoc =
          _FakeLocation(const LocationResult(LocationStatus.deniedForever));
      await mountRoute(tester, loc: deniedForeverLoc);
      expect(find.textContaining('Izin lokasi diblokir'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Pengaturan'));
      await tester.pump();
      expect(deniedForeverLoc.openAppCalls, 1);
    });
  });

  group('P-lite: SourceDetailScreen dan LocationPickerScreen bebas Google Maps', () {
    testWidgets(
        'SourceDetailScreen memakai Lihat di peta, nonaktif saat !isActive, tanpa teks Google Maps',
        (tester) async {
      final loc = _FakeLocation(
        const LocationResult(LocationStatus.ok, LatLng(-6.1500, 106.7300)),
      );
      final activeSp = SourceProvider(_StaticSourceService([_source()]), loc)
        ..syncUser(null, isAdmin: false, isProvider: false);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(_StubAuth(null))),
          ChangeNotifierProvider(create: (_) => activeSp),
        ],
        child: const MaterialApp(home: SourceDetailScreen(sourceId: 'src-1')),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Google'), findsNothing);
      expect(find.text('Buka petunjuk arah'), findsNothing);
      expect(find.text('Lihat di peta'), findsOneWidget);

      await tester.tap(find.text('Lihat di peta'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(SourceRouteScreen), findsOneWidget);

      // Nonaktif: tombol Lihat di peta nonaktif.
      final inactiveSrc = _source(listingStatus: ListingStatus.suspended);
      final adminSp = SourceProvider(_StaticSourceService([inactiveSrc]), loc)
        ..syncUser('adm', isAdmin: true, isProvider: false);

      await tester.pumpWidget(MultiProvider(
        key: UniqueKey(),
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthProvider(_StubAuth(const AppUser(
              uid: 'adm',
              name: 'Admin',
              email: 'a@x.id',
              role: UserRole.admin,
            ))),
          ),
          ChangeNotifierProvider(create: (_) => adminSp),
        ],
        child: const MaterialApp(home: SourceDetailScreen(sourceId: 'src-1')),
      ));
      await tester.pumpAndSettle();

      final btn = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Lihat di peta'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('LocationPickerScreen tidak memuat teks Google Maps',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: LocationPickerScreen()),
      );
      await tester.pump();
      expect(find.textContaining('Google'), findsNothing);

      await tester.tap(find.byTooltip('Tempel koordinat'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Google'), findsNothing);
      expect(find.text('Format: -6.1480, 106.7370'), findsOneWidget);
    });
  });
}
