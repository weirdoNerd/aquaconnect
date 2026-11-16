import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/app_providers.dart';
import 'package:aquaconnect/config.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/dev/mock_provider_service.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/provider_application.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/providers/my_sources_provider.dart';
import 'package:aquaconnect/providers/provider_application_provider.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'package:aquaconnect/screens/my_sources_screen.dart';
import 'package:aquaconnect/services/auth_service.dart';
import 'package:aquaconnect/services/provider_service.dart';
import 'package:aquaconnect/services/source_service.dart';
import 'package:aquaconnect/widgets/account_button.dart';
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

class _StubProviderService implements ProviderService {
  @override
  Stream<ProviderApplication?> watchMyApplication(String uid) =>
      Stream.value(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _SpySourceService implements SourceService {
  final List<String> calls = [];
  final Map<String, Completer<void>> pending = {};
  final Map<String, Object> errors = {};
  final StreamController<SourceBatch> _pubCtrl =
      StreamController<SourceBatch>.broadcast();
  final StreamController<SourceBatch> _ownCtrl =
      StreamController<SourceBatch>.broadcast();
  List<WaterSource> initialOwned = const [];
  Object? closeAllError;
  int closeAllResult = 0;

  void emitOwned(List<WaterSource> list) {
    initialOwned = list;
    _ownCtrl.add(SourceBatch(list));
  }

  @override
  Stream<SourceBatch> watchPublished() async* {
    yield SourceBatch(initialOwned.where((s) => s.isActive).toList());
    yield* _pubCtrl.stream;
  }

  @override
  Stream<SourceBatch> watchOwned(String uid) async* {
    yield SourceBatch(initialOwned);
    yield* _ownCtrl.stream;
  }

  @override
  Stream<SourceBatch> watchAll() => Stream.value(const SourceBatch([]));

  Future<void> _maybeWaitOrThrow(String key) async {
    final err = errors[key];
    if (err != null) throw err;
    final c = pending[key];
    if (c != null) await c.future;
  }

  @override
  Future<void> updateOperational(String id,
      {Availability? availability, String? openingHours}) async {
    calls.add('updateOperational:$id:${availability?.name}:$openingHours');
    await _maybeWaitOrThrow(id);
  }

  @override
  Future<void> confirmStillCurrent(String id) async {
    calls.add('confirmStillCurrent:$id');
    await _maybeWaitOrThrow(id);
  }

  @override
  Future<void> closeOwned(String id, String reason) async {
    calls.add('closeOwned:$id:$reason');
    await _maybeWaitOrThrow(id);
  }

  @override
  Future<int> closeAllOwned(String uid, String reason) async {
    calls.add('closeAllOwned:$uid:$reason');
    if (closeAllError != null) throw closeAllError!;
    return closeAllResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

WaterSource _ownedSource(
  String id, {
  String name = 'Sumber A',
  ListingStatus status = ListingStatus.published,
  Availability availability = Availability.available,
  DateTime? verifiedAt,
  VerifiedBy? verifiedBy = VerifiedBy.provider,
  String? reviewNote,
  String? closedReason,
  String ownerId = 'p1',
}) =>
    WaterSource(
      id: id,
      name: name,
      address: 'Cengkareng',
      latitude: -6.15,
      longitude: 106.73,
      type: SourceType.publicWell,
      availability: availability,
      intendedUse: 'Rumah tangga',
      openingHours: '08:00-17:00',
      verifiedAt: verifiedAt ?? DateTime.now().subtract(const Duration(hours: 2)),
      verifiedBy: verifiedBy,
      listingStatus: status,
      ownerId: ownerId,
      ownerName: 'Penyedia Uji',
      reviewNote: reviewNote,
      closedReason: closedReason,
    );

AppUser _providerUser({
  String uid = 'p1',
  ProviderStatus status = ProviderStatus.active,
  UserRole role = UserRole.user,
  String? note,
}) =>
    AppUser(
      uid: uid,
      name: 'Penyedia',
      email: 'p@test.id',
      role: role,
      providerStatus: status,
      providerNote: note,
    );

void main() {
  group('MySourcesProvider', () {
    test('tiap aksi memanggil service dengan argumen benar', () async {
      final svc = _SpySourceService()..closeAllResult = 3;
      final p = MySourcesProvider(svc)..syncUser('p1', isProvider: true);

      expect(
          await p.updateOperational('s1',
              availability: Availability.limited, openingHours: '09:00-15:00'),
          isTrue);
      expect(await p.confirmStillCurrent('s1'), isTrue);
      expect(await p.closeOwned('s1', 'Sumber kering'), isTrue);
      expect(await p.closeAllOwned('Tutup semua'), 3);

      expect(svc.calls, [
        'updateOperational:s1:limited:09:00-15:00',
        'confirmStillCurrent:s1',
        'closeOwned:s1:Sumber kering',
        'closeAllOwned:p1:Tutup semua',
      ]);
    });

    test('busy dan error berlaku per sumber', () async {
      final svc = _SpySourceService();
      final c1 = Completer<void>();
      svc.pending['s1'] = c1;
      svc.errors['s2'] = const SourceException('Gagal ubah s2.');
      final p = MySourcesProvider(svc)..syncUser('p1', isProvider: true);

      final f1 = p.confirmStillCurrent('s1');
      expect(p.isBusy('s1'), isTrue);
      expect(p.isBusy('s2'), isFalse);

      expect(await p.confirmStillCurrent('s2'), isFalse);
      expect(p.errorFor('s2'), 'Gagal ubah s2.');
      expect(p.errorFor('s1'), isNull);
      expect(p.isBusy('s1'), isTrue);

      c1.complete();
      expect(await f1, isTrue);
      expect(p.isBusy('s1'), isFalse);
    });

    test('syncUser mereset busy/error saat ganti pengguna dan menolak non-penyedia',
        () async {
      final svc = _SpySourceService()
        ..errors['s1'] = const SourceException('Galat lama.');
      final p = MySourcesProvider(svc)..syncUser('p1', isProvider: true);

      await p.confirmStillCurrent('s1');
      expect(p.errorFor('s1'), 'Galat lama.');

      p.syncUser('p2', isProvider: false);
      expect(p.errorFor('s1'), isNull);
      expect(await p.confirmStillCurrent('s1'), isFalse);
      expect(p.errorFor('s1'), contains('penyedia aktif'));
    });

    test('confirmAll berjalan berurutan dan tidak berhenti saat sebagian gagal',
        () async {
      final svc = _SpySourceService()
        ..errors['s2'] = const SourceException('Izin ditolak pada s2');
      final p = MySourcesProvider(svc)..syncUser('p1', isProvider: true);

      final targets = [
        _ownedSource('s1', name: 'Sumber Satu'),
        _ownedSource('s2', name: 'Sumber Dua'),
        _ownedSource('s3', name: 'Sumber Tiga'),
      ];
      final res = await p.confirmAll(targets);

      expect(svc.calls, [
        'confirmStillCurrent:s1',
        'confirmStillCurrent:s2',
        'confirmStillCurrent:s3',
      ]);
      expect(res.succeeded, 2);
      expect(res.failedNames, ['Sumber Dua']);
      expect(p.errorFor('s2'), 'Izin ditolak pada s2');
      expect(p.bulkError, contains('Sumber Dua'));
    });

    test('closeAllOwned menangkap SourceBatchException dan melaporkan sisa',
        () async {
      final svc = _SpySourceService()
        ..closeAllError = const SourceBatchException('Putus jaringan',
            done: 8, remaining: 4);
      final p = MySourcesProvider(svc)..syncUser('p1', isProvider: true);

      expect(await p.closeAllOwned('Pindah lokasi'), isNull);
      expect(p.bulkError, contains('8 sumber ditutup'));
      expect(p.bulkError, contains('4 sumber belum selesai'));
    });
  });

  group('MySourcesScreen & lencana AccountButton', () {
    Future<(_SpySourceService, MySourcesProvider)> mountMySources(
      WidgetTester tester, {
      required AppUser? user,
      required List<WaterSource> owned,
    }) async {
      final auth = _StubAuth(user);
      final svc = _SpySourceService()..initialOwned = owned;
      final mySources = MySourcesProvider(svc)
        ..syncUser(user?.uid, isProvider: user?.isProvider ?? false);
      final sp = SourceProvider(svc, NoLocation())
        ..syncUser(user?.uid,
            isAdmin: user?.isAdmin ?? false,
            isProvider: user?.isProvider ?? false);

      await tester.pumpWidget(MultiProvider(
        key: UniqueKey(),
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(auth)),
          ChangeNotifierProvider(lazy: false, create: (_) => sp),
          ChangeNotifierProvider(create: (_) => mySources),
        ],
        child: const MaterialApp(home: MySourcesScreen()),
      ));
      await tester.pumpAndSettle();
      return (svc, mySources);
    }

    testWidgets('kosong menampilkan Kamu belum punya sumber air', (tester) async {
      await mountMySources(tester, user: _providerUser(), owned: const []);
      expect(find.text('Kamu belum punya sumber air'), findsOneWidget);
    });

    testWidgets('non-penyedia dan terminated hanya melihat penjelasan',
        (tester) async {
      await mountMySources(
        tester,
        user: _providerUser(
          status: ProviderStatus.terminated,
          note: 'Tidak memperbarui data',
        ),
        owned: [_ownedSource('s1')],
      );
      expect(find.text('Kemitraan penyedia diputus'), findsOneWidget);
      expect(find.textContaining('Tidak memperbarui data'), findsOneWidget);
      expect(find.text('Konfirmasi masih tersedia'), findsNothing);
      expect(find.text('Tutup sumber'), findsNothing);

      await mountMySources(
        tester,
        user: _providerUser(status: ProviderStatus.none),
        owned: const [],
      );
      expect(find.text('Khusus penyedia air aktif'), findsOneWidget);
    });

    testWidgets(
        'aksi hanya pada published; pending/rejected hanya tutup; suspended/closed tanpa aksi',
        (tester) async {
      final (svc, _) = await mountMySources(
        tester,
        user: _providerUser(),
        owned: [
          _ownedSource('pub', name: 'Sumber Tayang', status: ListingStatus.published),
          _ownedSource('pen', name: 'Sumber Menunggu', status: ListingStatus.pending),
          _ownedSource('rej',
              name: 'Sumber Ditolak',
              status: ListingStatus.rejected,
              reviewNote: 'Pin kurang tepat'),
          _ownedSource('sus',
              name: 'Sumber Ditangguhkan', status: ListingStatus.suspended),
          _ownedSource('cls',
              name: 'Sumber Ditutup',
              status: ListingStatus.closed,
              closedReason: 'Pindah'),
        ],
      );

      // Hanya 1 kartu published yang punya tombol konfirmasi & ubah ketersediaan.
      expect(find.text('Konfirmasi masih tersedia'), findsOneWidget);
      expect(find.text('Tersedia'), findsWidgets);
      expect(find.text('Terbatas'), findsOneWidget);
      expect(find.text('Habis'), findsOneWidget);
      // 3 kartu closable: published, pending, rejected.
      expect(find.text('Tutup sumber'), findsNWidgets(3));
      expect(find.textContaining('Pin kurang tepat'), findsOneWidget);

      await tester.tap(find.text('Terbatas'));
      await tester.pump();
      expect(svc.calls, contains('updateOperational:pub:limited:null'));

      await tester.scrollUntilVisible(
          find.text('Ditangguhkan admin, hubungi admin'), 200);
      expect(find.text('Ditangguhkan admin, hubungi admin'), findsOneWidget);
      final susCard = find.ancestor(
        of: find.text('Sumber Ditangguhkan'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: susCard, matching: find.text('Tutup sumber')),
        findsNothing,
      );

      await tester.scrollUntilVisible(find.text('Sumber Ditutup'), 200);
      expect(find.textContaining('Pindah'), findsOneWidget);
      final clsCard = find.ancestor(
        of: find.text('Sumber Ditutup'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: clsCard, matching: find.text('Tutup sumber')),
        findsNothing,
      );
    });

    testWidgets('dialog tutup sumber mewajibkan alasan >= 3 karakter',
        (tester) async {
      final (svc, _) = await mountMySources(
        tester,
        user: _providerUser(),
        owned: [_ownedSource('s1', name: 'Sumber Tayang')],
      );

      await tester.ensureVisible(find.text('Tutup sumber'));
      await tester.tap(find.text('Tutup sumber'));
      await tester.pumpAndSettle();

      // Pilih 'Lainnya' dan coba konfirmasi tanpa alasan -> gagal validasi.
      await tester.tap(find.text('Lainnya'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Tutup sumber'));
      await tester.pump();
      expect(find.text('Alasan penutupan minimal 3 karakter.'), findsOneWidget);
      expect(svc.calls, isEmpty);

      // Isi alasan >= 3 karakter -> berhasil memanggil closeOwned.
      await tester.enterText(find.byType(TextField), 'Pindah ke tempat baru');
      await tester.tap(find.widgetWithText(FilledButton, 'Tutup sumber'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['closeOwned:s1:Pindah ke tempat baru']);
    });

    testWidgets(
        'dialog hentikan semua menyebut sumber ditangguhkan tidak ikut tertutup',
        (tester) async {
      final (svc, _) = await mountMySources(
        tester,
        user: _providerUser(),
        owned: [_ownedSource('s1', name: 'Sumber Tayang')],
      );

      await tester.ensureVisible(find.text('Hentikan semua sumber saya'));
      await tester.tap(find.text('Hentikan semua sumber saya'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('sumber yang ditangguhkan admin tidak ikut tertutup'),
        findsWidgets,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Hentikan semua'));
      await tester.pumpAndSettle();
      expect(svc.calls, ['closeAllOwned:p1:Tidak lagi menyediakan air']);
    });

    testWidgets('spanduk pengingat dan lencana AccountButton muncul saat > 48 jam',
        (tester) async {
      final oldTime = DateTime.now()
          .subtract(kReconfirmReminderAfter + const Duration(hours: 2));
      final freshTime = DateTime.now().subtract(const Duration(hours: 2));

      final (svc, _) = await mountMySources(
        tester,
        user: _providerUser(),
        owned: [
          _ownedSource('s1', name: 'Lama 1', verifiedAt: oldTime),
          _ownedSource('s2', name: 'Lama 2', verifiedAt: oldTime),
          _ownedSource('s3', name: 'Baru', verifiedAt: freshTime),
        ],
      );

      expect(find.text('2 sumber perlu dikonfirmasi'), findsOneWidget);
      await tester.tap(find.text('Konfirmasi semua'));
      await tester.pumpAndSettle();
      expect(svc.calls, [
        'confirmStillCurrent:s1',
        'confirmStillCurrent:s2',
      ]);

      // Verifikasi lencana pada AccountButton.
      final auth = _StubAuth(_providerUser());
      final sp = SourceProvider(
        _SpySourceService()
          ..initialOwned = [
            _ownedSource('s1', verifiedAt: oldTime),
            _ownedSource('s2', verifiedAt: oldTime),
            _ownedSource('s3', verifiedAt: freshTime),
          ],
        NoLocation(),
      )..syncUser('p1', isAdmin: false, isProvider: true);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(auth)),
          ChangeNotifierProvider(
              create: (_) => ProviderApplicationProvider(_StubProviderService())),
          ChangeNotifierProvider(lazy: false, create: (_) => sp),
          ChangeNotifierProvider(
              create: (_) =>
                  MySourcesProvider(_SpySourceService())..syncUser('p1', isProvider: true)),
        ],
        child: const MaterialApp(home: Scaffold(body: AccountButton())),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Akun'));
      await tester.pumpAndSettle();
      expect(find.text('Sumber saya'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('Integrasi mode tiruan', () {
    testWidgets(
        'penyedia demo memperbarui status sumber, warga melihat perubahan',
        (tester) async {
      final auth = MockAuthService();
      final sources = MockSourceService();
      final sub = auth.authChanges.listen((u) => sources.actAs(u?.uid));
      addTearDown(() {
        sub.cancel();
      });
      final providers = MockProviderService(sources, auth: auth);

      await tester.pumpWidget(MultiProvider(
        providers: appProviders(
          authService: auth,
          reportService: MockReportService(sources),
          sourceService: sources,
          providerService: providers,
          locationService: NoLocation(),
        ),
        child: const MaterialApp(home: MySourcesScreen()),
      ));
      await tester.pump();
      await tester.pump();

      final ctx = tester.element(find.byType(MySourcesScreen));
      ctx.read<SourceProvider>(); // bentuk provider sejak awal (seperti layar daftar)
      await tester.pump();
      await tester.pump();

      // Login sebagai penyedia demo.
      await tester.runAsync(() => ctx
          .read<AuthProvider>()
          .signIn('penyedia@aquaconnect.test', 'penyedia123'));
      await tester.pump();
      await tester.pump();

      // Awalnya sim-prov-1 berstatus available ('Tersedia').
      expect(ctx.read<SourceProvider>().byId('sim-prov-1')!.availability,
          Availability.available);

      // Penyedia mengubah sim-prov-1 menjadi 'Habis' lewat MySourcesProvider.
      final ok = await ctx
          .read<MySourcesProvider>()
          .updateOperational('sim-prov-1', availability: Availability.unavailable);
      expect(ok, isTrue);
      await tester.pump();
      await tester.pump();

      // Keluar -> kembali sebagai tamu/warga dan verifikasi perubahan terlihat di daftar warga.
      await tester.runAsync(() => ctx.read<AuthProvider>().signOut());
      await tester.pump();
      await tester.pump();

      final citizenView = ctx
          .read<SourceProvider>()
          .items
          .firstWhere((s) => s.id == 'sim-prov-1');
      expect(citizenView.availability, Availability.unavailable);
    });
  });
}
