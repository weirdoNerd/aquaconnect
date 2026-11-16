import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/water_report.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/admin_provider.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/providers/report_provider.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'package:aquaconnect/services/location_service.dart';
import 'package:aquaconnect/services/source_service.dart';

class FakeLocation implements LocationService {
  final LocationResult result;
  FakeLocation(this.result);
  @override
  Future<LocationResult> getCurrent() async => result;
  @override
  Future<void> openLocationSettings() async {}
  @override
  Future<void> openAppSettings() async {}
}

final _noLocation = FakeLocation(const LocationResult(LocationStatus.error));

/// SourceProvider tidak membuka langganan sendiri; syncUser yang membukanya.
SourceProvider _guest(SourceService s, LocationService l) =>
    SourceProvider(s, l)..syncUser(null, isAdmin: false, isProvider: false);

SourceProvider _admin(SourceService s, LocationService l) =>
    SourceProvider(s, l)..syncUser('admin', isAdmin: true, isProvider: false);

WaterSource _newSource({String name = 'Sumur Baru', double lat = -6.2, double lng = 106.8}) =>
    WaterSource(
      id: '',
      name: name,
      address: 'Cengkareng',
      latitude: lat,
      longitude: lng,
      type: SourceType.publicWell,
      availability: Availability.available,
      intendedUse: 'Belum diverifikasi',
      openingHours: '-',
    );

void main() {
  group('SourceProvider', () {
    test('filter jenis dan pencarian', () async {
      final p = _guest(MockSourceService(), _noLocation);
      await pumpEventQueue();
      expect(p.items.length, 7);
      expect(p.hiddenUnconfirmedCount, 1);

      p.setType(SourceType.publicWell);
      expect(p.items.every((s) => s.type == SourceType.publicWell), isTrue);

      p.setType(null);
      p.setQuery('masjid');
      expect(p.items.length, 1);
    });

    test('urutan terdekat dari lokasi pengguna', () async {
      final loc = FakeLocation(
          const LocationResult(LocationStatus.ok, LatLng(-6.1380, 106.7440)));
      final p = _guest(MockSourceService(), loc);
      await pumpEventQueue();

      expect(await p.locate(), LocationStatus.ok);
      expect(p.sortNearest, isTrue);
      expect(p.items.first.id, 'sim-3');

      p.clearNearest();
      expect(p.sortNearest, isFalse);
      expect(p.userLocation, isNull);
    });

    test('gagal lokasi tidak mengaktifkan urutan terdekat', () async {
      final p = _guest(MockSourceService(), _noLocation);
      await pumpEventQueue();
      expect(await p.locate(), LocationStatus.error);
      expect(p.sortNearest, isFalse);
    });

    test('saveSource menolak duplikat nama dalam 50 m', () async {
      final p = _guest(MockSourceService(), _noLocation);
      await pumpEventQueue();
      final dup = _newSource(
          name: '[SIMULASI] Sumur Umum RW 01', lat: -6.1450, lng: 106.7340);
      expect(await p.saveSource(dup, isNew: true), isNotNull);
      expect(p.all.length, 8);
    });

    test('saveSource menambah sumber baru', () async {
      final p = _guest(MockSourceService(), _noLocation);
      await pumpEventQueue();
      expect(await p.saveSource(_newSource(), isNew: true), isNull);
      await pumpEventQueue();
      expect(p.all.length, 9);
    });

    test('sumber nonaktif disembunyikan dari warga tetapi ada di all', () async {
      final svc = MockSourceService();
      final p = _admin(svc, _noLocation);
      await pumpEventQueue();
      final s = p.byId('sim-1')!;
      final inactive = WaterSource(
        id: s.id,
        name: s.name,
        address: s.address,
        latitude: s.latitude,
        longitude: s.longitude,
        type: s.type,
        availability: s.availability,
        intendedUse: s.intendedUse,
        openingHours: s.openingHours,
        listingStatus: ListingStatus.suspended,
      );
      await p.saveSource(inactive, isNew: false);
      await pumpEventQueue();
      expect(p.items.any((e) => e.id == 'sim-1'), isFalse);
      expect(p.all.any((e) => e.id == 'sim-1'), isTrue);
    });
  });

  group('ReportProvider', () {
    test('syncUser mengosongkan data saat pemilik berganti (T1.2)', () async {
      final p = ReportProvider(MockReportService(MockSourceService()));
      p.syncUser('mock-user');
      await pumpEventQueue();
      expect(p.mine.length, 2);

      p.syncUser('mock-lain');
      expect(p.mine, isEmpty);
      await pumpEventQueue();
      expect(p.mine, isEmpty);

      p.syncUser(null);
      expect(p.mine, isEmpty);
    });

    test('submit sukses lalu duplikat ditolak', () async {
      final p = ReportProvider(MockReportService(MockSourceService()));
      p.syncUser('mock-baru');
      Future<SubmitOutcome> send() => p.submit(
            sourceId: 'sim-1',
            reporterId: 'mock-baru',
            type: ReportType.noWater,
            description: 'Air sudah habis sejak pagi.',
          );

      expect(await send(), SubmitOutcome.sent);
      await pumpEventQueue();
      expect(p.mine.length, 1);

      expect(await send(), SubmitOutcome.failed);
      expect(p.submitError, contains('sudah mengirim'));
      p.clearSubmitError();
      expect(p.submitError, isNull);
    });
  });

  group('AdminProvider', () {
    test('menyetujui memperbarui status sumber; peninjauan kedua gagal', () async {
      final sources = MockSourceService();
      final admin = AdminProvider(MockReportService(sources));
      final sp = _guest(sources, _noLocation);
      admin.start();
      await pumpEventQueue();
      expect(admin.pendingCount, 3);

      final r = admin.items.firstWhere((e) => e.id == 'seed-3');
      expect(
          await admin.review(r, approve: true, newAvailability: Availability.unavailable),
          isTrue);
      await pumpEventQueue();

      expect(sp.byId('sim-1')!.availability, Availability.unavailable);
      expect(sp.byId('sim-1')!.verifiedAt, isNotNull);
      expect(admin.pendingCount, 2);

      expect(await admin.review(r, approve: true), isFalse);
      expect(admin.reviewError, contains('sudah ditinjau'));
    });

    test('laporan kualitas disetujui memasang qualityFlag tanpa menimpa intendedUse', () async {
      final sources = MockSourceService();
      final admin = AdminProvider(MockReportService(sources));
      final sp = _guest(sources, _noLocation);
      admin.start();
      await pumpEventQueue();

      final before = sp.byId('sim-3')!.intendedUse;
      final r = admin.items.firstWhere((e) => e.id == 'seed-4');
      expect(await admin.review(r, approve: true), isTrue);
      await pumpEventQueue();

      expect(sp.byId('sim-3')!.qualityFlag, isTrue);
      expect(sp.byId('sim-3')!.intendedUse, before);
    });

    test('menolak tanpa catatan ditolak', () async {
      final admin = AdminProvider(MockReportService(MockSourceService()));
      admin.start();
      await pumpEventQueue();
      final r = admin.items.first;
      expect(await admin.review(r, approve: false, note: '  '), isFalse);
      expect(admin.reviewError, isNotNull);
      expect(await admin.review(r, approve: false, note: 'Gerbang hanya terkunci malam hari.'), isTrue);
    });

    test('syncUser mereset data admin saat akun berganti', () async {
      final admin = AdminProvider(MockReportService(MockSourceService()));
      admin.syncUser('mock-admin');
      admin.start();
      await pumpEventQueue();
      expect(admin.pendingCount, 3);

      admin.syncUser('mock-lain');
      expect(admin.pendingCount, 0);
    });
  });

  group('AuthProvider', () {
    test('mendaftar selalu berperan user', () async {
      final p = AuthProvider(MockAuthService());
      expect(await p.register('Budi', 'budi@x.id', 'rahasia1'), isTrue);
      await pumpEventQueue();
      expect(p.user?.role, UserRole.user);
      expect(p.isAdmin, isFalse);
    });

    test('error tampil lalu terhapus', () async {
      final p = AuthProvider(MockAuthService());
      expect(await p.signIn('warga@aquaconnect.test', 'salah'), isFalse);
      expect(p.error, isNotNull);
      p.clearError();
      expect(p.error, isNull);
    });

    test('admin tiruan dikenali dan bisa keluar', () async {
      final p = AuthProvider(MockAuthService());
      expect(await p.signIn('admin@aquaconnect.test', 'admin123'), isTrue);
      await pumpEventQueue();
      expect(p.isAdmin, isTrue);
      await p.signOut();
      await pumpEventQueue();
      expect(p.isLoggedIn, isFalse);
    });

    test('hapus akun butuh kata sandi yang benar', () async {
      final p = AuthProvider(MockAuthService());
      await p.register('Sari', 'sari@x.id', 'rahasia1');
      await pumpEventQueue();
      expect(await p.deleteAccount('salah'), isFalse);
      expect(await p.deleteAccount('rahasia1'), isTrue);
      await pumpEventQueue();
      expect(p.isLoggedIn, isFalse);
    });
  });
}
