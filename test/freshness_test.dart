import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'package:aquaconnect/screens/source_detail_screen.dart';
import 'package:aquaconnect/screens/source_list_screen.dart';
import 'package:aquaconnect/screens/source_map_screen.dart';
import 'package:aquaconnect/services/auth_service.dart';
import 'package:aquaconnect/services/location_service.dart';
import 'package:aquaconnect/services/source_service.dart';
import 'package:aquaconnect/widgets/availability_badge.dart';
import 'package:aquaconnect/widgets/source_card.dart';
import 'helpers/fakes.dart';

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

class _FixedLocation implements LocationService {
  final LatLng point;
  _FixedLocation(this.point);

  @override
  Future<LocationResult> getCurrent() async =>
      LocationResult(LocationStatus.ok, point);

  @override
  Future<void> openLocationSettings() async {}

  @override
  Future<void> openAppSettings() async {}
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
  Stream<SourceBatch> watchOwned(String uid) =>
      Stream.value(SourceBatch(sources.where((s) => s.ownerId == uid).toList()));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

WaterSource _src(
  String id, {
  String name = 'Sumber Uji',
  DateTime? verifiedAt,
  VerifiedBy? verifiedBy = VerifiedBy.admin,
  String? ownerId,
  String? ownerName,
  double lat = -6.15,
  double lng = 106.73,
}) =>
    WaterSource(
      id: id,
      name: name,
      address: 'Cengkareng',
      latitude: lat,
      longitude: lng,
      type: SourceType.publicWell,
      availability: Availability.available,
      intendedUse: 'Rumah tangga',
      openingHours: '07:00-17:00',
      updatedAt: verifiedAt,
      verifiedAt: verifiedAt,
      verifiedBy: verifiedBy,
      ownerId: ownerId,
      ownerName: ownerName,
    );

void main() async {
  await initializeDateFormatting('id_ID');

  group('S9: batas waktu, penyembunyian, sakelar, dan urutan terdekat', () {
    final base = DateTime(2026, 6, 10, 12, 0);

    test('batas 3 dan 7 hari (2h23j, 3h1m, 7h1m, verifiedAt null)', () async {
      final list = [
        _src('fresh', verifiedAt: base.subtract(const Duration(days: 2, hours: 23))),
        _src('stale', verifiedAt: base.subtract(const Duration(days: 3, minutes: 1))),
        _src('expired', verifiedAt: base.subtract(const Duration(days: 7, minutes: 1))),
        _src('null_v', verifiedAt: null),
      ];
      final sp = SourceProvider(_StaticSourceService(list), NoLocation(),
          clock: () => base)
        ..syncUser(null, isAdmin: false, isProvider: false);
      addTearDown(sp.dispose);
      await pumpEventQueue();

      expect(sp.freshnessOf(sp.byId('fresh')!), Freshness.fresh);
      expect(sp.staleLabelOf(sp.byId('fresh')!), isNull);

      expect(sp.freshnessOf(sp.byId('stale')!), Freshness.stale);
      expect(sp.staleLabelOf(sp.byId('stale')!), 'Belum dikonfirmasi 3 hari');

      expect(sp.freshnessOf(sp.byId('expired')!), Freshness.expired);
      expect(sp.staleLabelOf(sp.byId('expired')!), 'Belum dikonfirmasi 7 hari');

      expect(sp.freshnessOf(sp.byId('null_v')!), Freshness.expired);
      expect(sp.staleLabelOf(sp.byId('null_v')!),
          'Status belum pernah dikonfirmasi');
    });

    test(
        'expired berpemilik tersembunyi untuk warga, tampil untuk admin & saat sakelar aktif; kelolaan admin tetap tampil',
        () async {
      final list = [
        _src('adm-exp',
            name: 'Admin Expired',
            verifiedAt: base.subtract(const Duration(days: 8))),
        _src('own-exp',
            name: 'Milik Penyedia Expired',
            ownerId: 'p1',
            ownerName: 'Pos Air',
            verifiedAt: base.subtract(const Duration(days: 8))),
        _src('own-fresh',
            name: 'Milik Penyedia Segar',
            ownerId: 'p1',
            ownerName: 'Pos Air',
            verifiedAt: base.subtract(const Duration(hours: 2))),
      ];

      // Warga: own-exp tersembunyi, adm-exp tetap tampil.
      final citizen = SourceProvider(_StaticSourceService(list), NoLocation(),
          clock: () => base)
        ..syncUser('u1', isAdmin: false, isProvider: false);
      addTearDown(citizen.dispose);
      await pumpEventQueue();

      expect(citizen.items.map((s) => s.id).toSet(), {'adm-exp', 'own-fresh'});
      expect(citizen.hiddenUnconfirmedCount, 1);

      // Nyalakan sakelar -> own-exp tampil.
      citizen.setShowUnconfirmed(true);
      expect(citizen.items.map((s) => s.id).toSet(),
          {'adm-exp', 'own-exp', 'own-fresh'});
      expect(citizen.hiddenUnconfirmedCount, 0);

      // Admin: melihat semua tanpa perlu sakelar.
      final admin = SourceProvider(_StaticSourceService(list), NoLocation(),
          clock: () => base)
        ..syncUser('adm', isAdmin: true, isProvider: false);
      addTearDown(admin.dispose);
      await pumpEventQueue();

      expect(admin.items.map((s) => s.id).toSet(),
          {'adm-exp', 'own-exp', 'own-fresh'});
      expect(admin.hiddenUnconfirmedCount, 0);
    });

    test('urutan Terdekat meletakkan stale dan expired di akhir', () async {
      // Lokasi pengguna di (-6.1500, 106.7300).
      final list = [
        // Jarak ~0 m, tetapi expired (kelolaan admin agar tampil)
        _src('A-expired',
            name: 'Expired Terdekat',
            lat: -6.1500,
            lng: 106.7300,
            verifiedAt: base.subtract(const Duration(days: 9))),
        // Jarak ~111 m, tetapi stale
        _src('B-stale',
            name: 'Stale Dekat',
            lat: -6.1510,
            lng: 106.7300,
            verifiedAt: base.subtract(const Duration(days: 4))),
        // Jarak ~555 m, segar
        _src('C-fresh',
            name: 'Fresh Jauh',
            lat: -6.1550,
            lng: 106.7300,
            verifiedAt: base.subtract(const Duration(hours: 1))),
      ];

      final sp = SourceProvider(
        _StaticSourceService(list),
        _FixedLocation(const LatLng(-6.1500, 106.7300)),
        clock: () => base,
      )..syncUser(null, isAdmin: false, isProvider: false);
      addTearDown(sp.dispose);
      await pumpEventQueue();

      await sp.locate();
      // Fresh paling depan; stale & expired di akhir (diurutkan jarak di tier akhir).
      expect(sp.items.map((s) => s.id).toList(),
          ['C-fresh', 'A-expired', 'B-stale']);
    });

    testWidgets('timer 1 menit hanya memanggil notifyListeners saat kategori berubah',
        (tester) async {
      var now = DateTime(2026, 6, 10, 12, 0);
      final list = [
        _src('s1',
            verifiedAt: now.subtract(const Duration(days: 2, hours: 23, minutes: 59))),
      ];

      final sp = SourceProvider(_StaticSourceService(list), NoLocation(),
          clock: () => now)
        ..syncUser(null, isAdmin: false, isProvider: false);
      await tester.pump();

      var notifications = 0;
      sp.addListener(() => notifications++);

      // Lewat 30 detik (masih fresh) -> tick 1 menit TIDAK memicu notifyListeners.
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(minutes: 1));
      expect(notifications, 0);

      // Lewat batas 3 hari (+1 menit) -> fresh berubah ke stale -> notifyListeners terpanggil!
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(notifications, 1);
      expect(sp.freshnessOf(sp.byId('s1')!), Freshness.stale);

      // Tick berikutnya masih stale -> tidak ada notifikasi tambahan.
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      expect(notifications, 1);
      sp.dispose();
    });
  });

  group('S9: widget AvailabilityBadge, SourceCard, SourceListScreen, SourceDetailScreen',
      () {
    testWidgets('AvailabilityBadge dan SourceCard menampilkan Tidak pasti + ikon + hari',
        (tester) async {
      final now = DateTime(2026, 6, 10, 12, 0);
      final staleSrc = _src(
        's1',
        name: 'Sumur Lama',
        verifiedAt: now.subtract(const Duration(days: 4)),
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const AvailabilityBadge(
                availability: Availability.available,
                stale: true,
              ),
              SourceCard(
                source: staleSrc,
                freshness: staleSrc.freshness(now),
                staleLabel: staleSrc.staleLabelAt(now),
                onTap: () {},
              ),
            ],
          ),
        ),
      ));

      expect(find.text('Tidak pasti'), findsNWidgets(2));
      expect(find.byIcon(Icons.help_outline), findsNWidgets(2));
      expect(find.text('Belum dikonfirmasi 4 hari'), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    testWidgets(
        'SourceListScreen menampilkan FilterChip, banner jumlah tersembunyi, dan tautan Tampilkan',
        (tester) async {
      final now = DateTime(2026, 6, 10, 12, 0);
      final list = [
        _src('fresh', name: 'Sumber Segar', verifiedAt: now.subtract(const Duration(hours: 2))),
        _src(
          'hidden',
          name: 'Sumber Tersembunyi',
          ownerId: 'p1',
          ownerName: 'Penyedia Uji',
          verifiedAt: now.subtract(const Duration(days: 8)),
        ),
      ];

      final sp = SourceProvider(_StaticSourceService(list), NoLocation(),
          clock: () => now)
        ..syncUser(null, isAdmin: false, isProvider: false);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(_StubAuth(null))),
          ChangeNotifierProvider(create: (_) => sp),
        ],
        child: const MaterialApp(home: SourceListScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Tampilkan yang belum dikonfirmasi'), findsOneWidget);
      expect(find.text('1 sumber disembunyikan karena belum dikonfirmasi'),
          findsOneWidget);
      expect(find.text('Sumber Segar'), findsOneWidget);
      expect(find.text('Sumber Tersembunyi'), findsNothing);

      // Ketuk tautan Tampilkan -> sumber kedaluwarsa tampil.
      await tester.tap(find.widgetWithText(TextButton, 'Tampilkan'));
      await tester.pumpAndSettle();

      expect(find.text('Sumber Tersembunyi'), findsOneWidget);
      expect(find.text('1 sumber disembunyikan karena belum dikonfirmasi'),
          findsNothing);
    });

    testWidgets('SourceDetailScreen menampilkan pengelola, konfirmasi oleh penyedia, dan peringatan stale',
        (tester) async {
      final now = DateTime(2026, 6, 10, 12, 0);
      final staleOwned = _src(
        's1',
        name: 'Depot Lama',
        ownerId: 'p1',
        ownerName: 'Penyedia Demo',
        verifiedBy: VerifiedBy.provider,
        verifiedAt: now.subtract(const Duration(days: 4)),
      );
      final sp = SourceProvider(_StaticSourceService([staleOwned]), NoLocation(),
          clock: () => now)
        ..syncUser(null, isAdmin: false, isProvider: false);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(_StubAuth(null))),
          ChangeNotifierProvider(create: (_) => sp),
        ],
        child: const MaterialApp(home: SourceDetailScreen(sourceId: 's1')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Dikelola oleh Penyedia Demo'), findsOneWidget);
      expect(find.textContaining('Dikonfirmasi oleh penyedia '), findsOneWidget);
      expect(find.text('Tidak pasti'), findsOneWidget);
      expect(
        find.text('Status mungkin sudah tidak benar. Hubungi pengelola bila perlu.'),
        findsOneWidget,
      );
    });

    testWidgets('SourceMapScreen meredupkan pin stale dan tetap bisa diketuk',
        (tester) async {
      final now = DateTime(2026, 6, 10, 12, 0);
      final staleSrc = _src(
        's1',
        name: 'Pin Lama',
        verifiedAt: now.subtract(const Duration(days: 4)),
      );
      final sp = SourceProvider(_StaticSourceService([staleSrc]), NoLocation(),
          clock: () => now)
        ..syncUser(null, isAdmin: false, isProvider: false);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(_StubAuth(null))),
          ChangeNotifierProvider(create: (_) => sp),
        ],
        child: const MaterialApp(home: SourceMapScreen()),
      ));
      await tester.pump();
      await tester.pump();

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, 0.5);

      await tester.tap(find.byIcon(Icons.location_on).first);
      await tester.pumpAndSettle();
      expect(find.byType(SourceDetailScreen), findsOneWidget);
      expect(find.text('Pin Lama'), findsOneWidget);
    });
  });

  group('S9: integrasi mode tiruan dengan seed D1', () {
    test('seed D1: 2 jam segar, 4 hari tidak pasti, 8 hari tersembunyi, admin 5 hari tampil',
        () async {
      final sp = SourceProvider(MockSourceService(), NoLocation())
        ..syncUser(null, isAdmin: false, isProvider: false);
      addTearDown(sp.dispose);
      await pumpEventQueue();

      // 2 jam lalu: segar dan tampil.
      final fresh = sp.items.firstWhere((s) => s.id == 'sim-prov-1');
      expect(sp.freshnessOf(fresh), Freshness.fresh);

      // 4 hari lalu: tidak pasti dan tampil.
      final stale = sp.items.firstWhere((s) => s.id == 'sim-prov-2');
      expect(sp.freshnessOf(stale), Freshness.stale);
      expect(sp.staleLabelOf(stale), 'Belum dikonfirmasi 4 hari');

      // 8 hari lalu (milik mock-provider): tersembunyi dari warga.
      expect(sp.items.any((s) => s.id == 'sim-prov-3'), isFalse);
      expect(sp.hiddenUnconfirmedCount, 1);

      // Kelolaan admin 5 hari lalu (sim-4): tetap tampil bagi warga dengan label.
      final adminStale = sp.items.firstWhere((s) => s.id == 'sim-4');
      expect(sp.freshnessOf(adminStale), Freshness.stale);
      expect(sp.staleLabelOf(adminStale), 'Belum dikonfirmasi 5 hari');

      // Menyalakan sakelar memunculkan sim-prov-3 (expired).
      sp.setShowUnconfirmed(true);
      final exp = sp.items.firstWhere((s) => s.id == 'sim-prov-3');
      expect(sp.freshnessOf(exp), Freshness.expired);
    });
  });
}
