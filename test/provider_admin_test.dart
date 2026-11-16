import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/config.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/dev/mock_provider_service.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/provider_application.dart';
import 'package:aquaconnect/models/provider_profile.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/admin_provider.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/providers/provider_admin_provider.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'package:aquaconnect/screens/admin_screen.dart';
import 'package:aquaconnect/services/auth_service.dart';
import 'package:aquaconnect/services/provider_service.dart';
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

class _TrackingProviderService implements ProviderService {
  int watchCalls = 0;
  int fetchCalls = 0;
  bool cancelled = false;
  final ctrl = StreamController<List<ProviderApplication>>.broadcast();
  List<ProviderProfile> profiles = const [];
  Object? nextFetchError;

  @override
  Stream<List<ProviderApplication>> watchPending() {
    watchCalls++;
    late StreamController<List<ProviderApplication>> wrapper;
    StreamSubscription<List<ProviderApplication>>? sub;
    wrapper = StreamController<List<ProviderApplication>>(
      onListen: () {
        sub = ctrl.stream.listen(wrapper.add, onError: wrapper.addError);
      },
      onCancel: () {
        cancelled = true;
        sub?.cancel();
      },
    );
    return wrapper.stream;
  }

  @override
  Future<List<ProviderProfile>> fetchProviders() async {
    fetchCalls++;
    if (nextFetchError != null) throw nextFetchError!;
    return profiles;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ProviderApplication _app(String uid, {String org = 'Depot Air Bersih'}) =>
    ProviderApplication(
      uid: uid,
      organizationName: org,
      contactPhone: '+6281234567890',
      description: 'Menyediakan air minum isi ulang bagi warga sekitar.',
      termsVersion: kProviderTermsVersion,
      createdAt: DateTime(2026, 6, 1, 9, 0),
    );

WaterSource _ownedDraft(String name) => WaterSource(
      id: '',
      name: name,
      address: 'Cengkareng',
      latitude: -6.15,
      longitude: 106.73,
      type: SourceType.publicWell,
      availability: Availability.available,
      intendedUse: 'Rumah tangga',
      openingHours: '08:00-17:00',
    );

void main() async {
  await initializeDateFormatting('id_ID');

  group('ProviderAdminProvider', () {
    test('non-admin tidak melanggan; ganti pengguna dan dispose membatalkan & mereset',
        () async {
      final svc = _TrackingProviderService();
      final p = ProviderAdminProvider(svc);

      p.syncUser(null, isAdmin: false);
      p.syncUser('u1', isAdmin: false);
      expect(svc.watchCalls, 0);
      expect(svc.fetchCalls, 0);
      expect(await p.review('x', approve: true), isFalse);
      expect(p.error, isNotNull);

      p.syncUser('admin1', isAdmin: true);
      expect(svc.watchCalls, 1);
      expect(svc.fetchCalls, 1);
      svc.ctrl.add([_app('u1')]);
      await pumpEventQueue();
      expect(p.pendingCount, 1);

      // Ganti ke non-admin: reset data dan batalkan langganan.
      p.syncUser('u2', isAdmin: false);
      expect(svc.cancelled, isTrue);
      expect(p.pending, isEmpty);
      expect(p.providers, isEmpty);
      expect(p.error, isNull);

      // Buka lagi lalu dispose.
      svc.cancelled = false;
      p.syncUser('admin2', isAdmin: true);
      p.dispose();
      expect(svc.cancelled, isTrue);
    });

    test('review setuju/tolak memperbarui daftar; tolak tanpa catatan ditolak',
        () async {
      final sources = MockSourceService();
      final svc = MockProviderService(sources, seedDemo: false);
      await svc.apply(_app('u1', org: 'Depot Satu'));
      await svc.apply(_app('u2', org: 'Depot Dua'));

      final p = ProviderAdminProvider(svc)..syncUser('admin', isAdmin: true);
      await pumpEventQueue();
      expect(p.pendingCount, 2);

      // Tolak tanpa catatan -> gagal, tetap pending.
      expect(await p.review('u1', approve: false, note: 'abc'), isFalse);
      expect(p.error, contains('Alasan wajib diisi'));
      expect(p.pendingCount, 2);

      // Setujui u1 -> keluar dari pending, masuk ke daftar providers active.
      expect(await p.review('u1', approve: true), isTrue);
      await pumpEventQueue();
      expect(p.pendingCount, 1);
      expect(p.providers.any((x) => x.uid == 'u1' && x.status == ProviderStatus.active),
          isTrue);

      // Tolak u2 dengan catatan valid -> keluar dari pending, tidak jadi active.
      expect(
          await p.review('u2', approve: false, note: 'Data lokasi kurang jelas.'),
          isTrue);
      await pumpEventQueue();
      expect(p.pendingCount, 0);
      expect(p.providers.any((x) => x.uid == 'u2'), isFalse);
    });

    test('urutan terminate, pesan sisa sumber saat gagal sebagian, dan reactivate',
        () async {
      final sources = MockSourceService();
      final svc = MockProviderService(sources, seedDemo: false);
      svc.seedProfile(const ProviderProfile(
        uid: 'p1',
        name: 'Pos Air Mawar',
        email: 'p1@test.id',
        status: ProviderStatus.active,
      ));
      sources.actAs('p1');
      for (var i = 0; i < 12; i++) {
        await sources.createAsProvider(_ownedDraft('Sumur $i'), 'p1', 'Pos Air Mawar');
      }
      sources.failAfterBatches = 1;

      final p = ProviderAdminProvider(svc)..syncUser('admin', isAdmin: true);
      await pumpEventQueue();

      // Terminate gagal sebagian -> ProviderException melaporkan sisa (4 sumber) & profil sudah terminated.
      expect(await p.terminate('p1', 'Melanggar ketentuan'), isFalse);
      expect(svc.callLog, ['users:terminated', 'suspendAllOwned']);
      expect(p.error, contains('4 sumber belum ditangguhkan'));
      expect(
          p.providers.firstWhere((x) => x.uid == 'p1').status,
          ProviderStatus.terminated);

      // Ulangi tanpa gangguan -> sukses tuntas.
      sources.failAfterBatches = null;
      expect(await p.terminate('p1', 'Melanggar ketentuan'), isTrue);
      expect(p.error, isNull);

      // Reactivate -> kembali active dan alasan lama hilang.
      expect(await p.reactivate('p1'), isTrue);
      final reactivated = p.providers.firstWhere((x) => x.uid == 'p1');
      expect(reactivated.status, ProviderStatus.active);
      expect(reactivated.note, isNull);
    });

    test('galat fetchProviders dipetakan ke loadError', () async {
      final svc = _TrackingProviderService()
        ..nextFetchError = const ProviderException('Gagal membaca penyedia.');
      final p = ProviderAdminProvider(svc)..syncUser('admin', isAdmin: true);
      await pumpEventQueue();
      expect(p.loadError, 'Gagal membaca penyedia.');
      expect(p.error, 'Gagal membaca penyedia.');
    });
  });

  group('AdminScreen tab Penyedia', () {
    Future<(MockSourceService, MockProviderService)> mountAdmin(
      WidgetTester tester, {
      bool seedDemo = false,
      List<ProviderProfile> extraProfiles = const [],
    }) async {
      final sources = MockSourceService();
      final mockAuth = MockAuthService();
      final providers = MockProviderService(sources, auth: mockAuth, seedDemo: seedDemo);
      for (final pr in extraProfiles) {
        providers.seedProfile(pr);
      }

      const adminUser = AppUser(
        uid: 'mock-admin',
        name: 'Admin',
        email: 'admin@aquaconnect.test',
        role: UserRole.admin,
      );

      final sp = SourceProvider(sources, NoLocation())
        ..syncUser(adminUser.uid, isAdmin: true, isProvider: false);
      final pa = ProviderAdminProvider(providers)
        ..syncUser(adminUser.uid, isAdmin: true);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(_StubAuth(adminUser))),
          ChangeNotifierProvider.value(value: sp),
          ChangeNotifierProvider(
              create: (_) => AdminProvider(MockReportService(sources))
                ..syncUser(adminUser.uid)),
          ChangeNotifierProvider.value(value: pa),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ));
      await tester.pumpAndSettle();
      return (sources, providers);
    }

    testWidgets('kosong menampilkan Tidak ada pengajuan yang menunggu',
        (tester) async {
      await mountAdmin(tester, seedDemo: false);
      expect(find.text('Penyedia'), findsOneWidget);
      await tester.tap(find.text('Penyedia'));
      await tester.pumpAndSettle();

      expect(find.text('Tidak ada pengajuan yang menunggu'), findsOneWidget);
      expect(find.text('Belum ada penyedia terdaftar'), findsOneWidget);
    });

    testWidgets('tinjau pengajuan: tolak butuh catatan, setujui memindahkan ke daftar penyedia',
        (tester) async {
      final (_, providers) = await mountAdmin(tester, seedDemo: true);
      // Tab label memuat jumlah pengajuan pending dari seedDemo (1).
      expect(find.text('Penyedia (1)'), findsOneWidget);

      await tester.tap(find.text('Penyedia (1)'));
      await tester.pumpAndSettle();

      expect(find.text('[SIMULASI] Depot Air Sejahtera'), findsOneWidget);
      expect(find.text('+6281234567890'), findsOneWidget);

      // Buka lembar tinjau.
      await tester.tap(find.text('Tinjau'));
      await tester.pumpAndSettle();

      // Tolak tanpa catatan -> tampil galat validasi, lembar tetap terbuka.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Tolak'));
      await tester.pump();
      expect(find.text('Alasan wajib diisi (min. 5 karakter).'), findsOneWidget);

      // Setujui -> lembar menutup, jumlah pending menjadi 0, label tab menjadi 'Penyedia'.
      await tester.tap(find.widgetWithText(FilledButton, 'Setujui'));
      await tester.pumpAndSettle();

      expect(find.text('Penyedia'), findsWidgets);
      expect(find.text('Tidak ada pengajuan yang menunggu'), findsOneWidget);
      expect((await providers.fetchProviders()).any((x) => x.uid == 'mock-calon'),
          isTrue);
    });

    testWidgets(
        'putuskan kemitraan & aktifkan kembali; tindakan disembunyikan untuk admin',
        (tester) async {
      await mountAdmin(
        tester,
        seedDemo: true,
        extraProfiles: const [
          ProviderProfile(
            uid: 'admin-prov',
            name: 'Admin Merangkap',
            email: 'admin2@test.id',
            role: UserRole.admin,
            status: ProviderStatus.active,
          ),
        ],
      );

      await tester.tap(find.text('Penyedia (1)'));
      await tester.pumpAndSettle();

      // Penyedia Demo (4 sumber di dummySources) tampil beserta jumlah sumbernya.
      expect(find.text('Penyedia Demo'), findsOneWidget);
      expect(find.text('Jumlah sumber: 4'), findsOneWidget);

      // Admin Merangkap (role admin) TIDAK memiliki tombol Putuskan kemitraan.
      final adminCard = find.ancestor(
        of: find.text('Admin Merangkap'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: adminCard, matching: find.text('Putuskan kemitraan')),
        findsNothing,
      );

      // Putuskan kemitraan Penyedia Demo.
      final providerCard = find.ancestor(
        of: find.text('Penyedia Demo'),
        matching: find.byType(Card),
      );
      await tester.ensureVisible(
        find.descendant(of: providerCard, matching: find.text('Putuskan kemitraan')),
      );
      await tester.tap(
        find.descendant(of: providerCard, matching: find.text('Putuskan kemitraan')),
      );
      await tester.pumpAndSettle();

      // Dialog menjelaskan penangguhan sumber dan wajib alasan >= 5 karakter.
      expect(find.textContaining('ditangguhkan'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Putuskan'));
      await tester.pump();
      expect(find.text('Alasan wajib diisi (min. 5 karakter).'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'Berhenti beroperasi');
      await tester.tap(find.widgetWithText(FilledButton, 'Putuskan'));
      await tester.pumpAndSettle();

      expect(find.text('Diputus'), findsOneWidget);
      expect(find.text('Alasan pemutusan: Berhenti beroperasi'), findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.byType(AdminScreen)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();

      // Aktifkan kembali -> dialog menegaskan sumber ditangguhkan TIDAK otomatis tayang lagi.
      await tester.ensureVisible(find.text('Aktifkan kembali'));
      await tester.tap(find.text('Aktifkan kembali'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('TIDAK otomatis tayang lagi dan harus ditayangkan satu per satu'),
        findsOneWidget,
      );
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Aktifkan kembali'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Aktif'), findsNWidgets(2));
    });
  });
}
