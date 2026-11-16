import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/config.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/provider_application.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/providers/provider_application_provider.dart';
import 'package:aquaconnect/screens/provider_apply_screen.dart';
import 'package:aquaconnect/services/auth_service.dart';
import 'package:aquaconnect/services/provider_service.dart';
import 'package:aquaconnect/widgets/account_button.dart';
import 'helpers/fakes.dart';

class _FakeAuthService implements AuthService {
  final _ctrl = StreamController<AppUser?>.broadcast();
  AppUser? _user;
  int verifyCalls = 0;
  int refreshCalls = 0;

  _FakeAuthService([this._user]);

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> get authChanges => _ctrl.stream;

  void emit(AppUser? u) {
    _user = u;
    _ctrl.add(u);
  }

  @override
  Future<void> sendEmailVerification() async => verifyCalls++;

  @override
  Future<void> refresh() async => refreshCalls++;

  @override
  Future<void> signOut() async => emit(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ProviderApplication _sampleApp({
  String uid = 'u1',
  ApplicationStatus status = ApplicationStatus.pending,
  String adminNote = '',
}) =>
    ProviderApplication(
      uid: uid,
      organizationName: 'Depot Air Bersih RW 03',
      contactPhone: '+62 812 3456 7890',
      description: 'Menyediakan air minum isi ulang setiap hari.',
      termsVersion: kProviderTermsVersion,
      status: status,
      adminNote: adminNote,
      createdAt: DateTime(2026, 5, 1, 10, 30),
    );

AppUser _user({
  String uid = 'u1',
  UserRole role = UserRole.user,
  bool emailVerified = true,
  ProviderStatus providerStatus = ProviderStatus.none,
  String? providerNote,
}) =>
    AppUser(
      uid: uid,
      name: 'Budi',
      email: 'budi@test.id',
      role: role,
      emailVerified: emailVerified,
      providerStatus: providerStatus,
      providerNote: providerNote,
    );

void main() async {
  await initializeDateFormatting('id_ID');

  group('ProviderApplicationProvider', () {
    test('syncUser melanggan, reset saat ganti pengguna, dan batal saat keluar/dispose',
        () async {
      final svc = FakeProviderService();
      final p = ProviderApplicationProvider(svc);

      p.syncUser(null);
      expect(svc.taps, isEmpty);

      p.syncUser('u1');
      expect(p.loading, isTrue);
      expect(svc.active, ['u1']);

      final app1 = _sampleApp(uid: 'u1');
      svc.taps.last.ctrl.add(app1);
      await pumpEventQueue();
      expect(p.loading, isFalse);
      expect(p.application?.organizationName, 'Depot Air Bersih RW 03');

      // Ganti ke u2: langganan u1 batal, state lama dibersihkan tanpa sisa.
      p.syncUser('u2');
      expect(p.application, isNull);
      expect(svc.taps.first.cancelled, isTrue);
      expect(svc.active, ['u2']);

      // Keluar: langganan u2 batal.
      p.syncUser(null);
      expect(svc.active, isEmpty);

      // Buka lagi lalu dispose: langganan ikut batal.
      p.syncUser('u3');
      expect(svc.active, ['u3']);
      p.dispose();
      expect(svc.active, isEmpty);
    });

    test('apply sukses mengirim nilai ter-trim dengan kProviderTermsVersion', () async {
      final svc = FakeProviderService();
      final p = ProviderApplicationProvider(svc)..syncUser('u1');

      final ok = await p.apply(
        '  Pos Air Mawar  ',
        '  +62 812 3456 7890  ',
        '  Air bersih untuk warga sekitar RW 03.  ',
      );
      expect(ok, isTrue);
      expect(p.error, isNull);
      expect(p.submitting, isFalse);
      expect(svc.submitted, hasLength(1));
      final s = svc.submitted.single;
      expect(s.uid, 'u1');
      expect(s.organizationName, 'Pos Air Mawar');
      expect(s.contactPhone, '+62 812 3456 7890');
      expect(s.description, 'Air bersih untuk warga sekitar RW 03.');
      expect(s.termsVersion, kProviderTermsVersion);
    });

    test('apply memetakan galat izin ke pesan ramah dan mempertahankan pesan validasi',
        () async {
      final svc = FakeProviderService();
      final p = ProviderApplicationProvider(svc)..syncUser('u1');

      svc.nextApplyError = const ProviderException('Tidak ada izin untuk tindakan ini.');
      expect(await p.apply('Pos Air', '081234567', 'Deskripsi cukup panjang.'), isFalse);
      expect(p.error, contains('Verifikasi email dulu'));

      svc.nextApplyError = const ProviderException('Nama usaha atau komunitas 3-80 karakter.');
      expect(await p.apply('ab', '081234567', 'Deskripsi cukup panjang.'), isFalse);
      expect(p.error, 'Nama usaha atau komunitas 3-80 karakter.');
    });

    test('apply saat belum masuk ditolak', () async {
      final p = ProviderApplicationProvider(FakeProviderService());
      expect(await p.apply('Pos Air', '081234567', 'Deskripsi cukup panjang.'), isFalse);
      expect(p.error, isNotNull);
    });
  });

  group('ProviderApplyScreen (keadaan 3a-3g dan validasi)', () {
    Future<( _FakeAuthService, FakeProviderService)> mountScreen(
      WidgetTester tester, {
      AppUser? initialUser,
      ProviderApplication? initialApp,
    }) async {
      final auth = _FakeAuthService(initialUser);
      final providers = FakeProviderService();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(auth)),
          ChangeNotifierProxyProvider<AuthProvider, ProviderApplicationProvider>(
            create: (ctx) => ProviderApplicationProvider(providers)
              ..syncUser(ctx.read<AuthProvider>().user?.uid),
            update: (_, a, p) => p!..syncUser(a.user?.uid),
          ),
        ],
        child: const MaterialApp(home: ProviderApplyScreen()),
      ));
      await tester.pump();
      if (initialUser != null && providers.taps.isNotEmpty) {
        providers.taps.last.ctrl.add(initialApp);
        await tester.pump();
      }
      return (auth, providers);
    }

    testWidgets('3a: belum login menampilkan ajakan masuk', (tester) async {
      await mountScreen(tester, initialUser: null);
      expect(find.text('Masuk terlebih dahulu'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Masuk'), findsOneWidget);
    });

    testWidgets('3b: email belum terverifikasi menyembunyikan form dan memanggil aksi verifikasi',
        (tester) async {
      final (auth, _) = await mountScreen(
        tester,
        initialUser: _user(emailVerified: false),
      );
      expect(find.text('Verifikasi email diperlukan'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Kirim ulang email verifikasi'));
      await tester.pump();
      expect(auth.verifyCalls, 1);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Saya sudah verifikasi'));
      await tester.pump();
      expect(auth.refreshCalls, 1);
    });

    testWidgets('3c: validasi batas panjang, telepon, spasi tepi, kotak persetujuan, dan kirim',
        (tester) async {
      final (_, providers) = await mountScreen(
        tester,
        initialUser: _user(),
        initialApp: null,
      );

      // Teks ketentuan DRAF 5 butir tampil.
      expect(find.textContaining('DRAF'), findsWidgets);
      for (var i = 1; i <= 5; i++) {
        expect(find.textContaining('$i. '), findsOneWidget);
      }

      FilledButton submitBtn() =>
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Kirim pengajuan'));

      expect(submitBtn().onPressed, isNull);

      final orgField = find.widgetWithText(TextFormField, 'Nama usaha / pengelola');
      final phoneField = find.widgetWithText(TextFormField, 'Nomor telepon');
      final descField = find.widgetWithText(TextFormField, 'Deskripsi singkat');

      // Spasi di tepi: '  ab  ' trim-nya hanya 2 karakter -> tidak valid.
      await tester.enterText(orgField, '  ab  ');
      await tester.enterText(phoneField, '08123456789');
      await tester.enterText(descField, 'Deskripsi yang cukup panjang.');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(submitBtn().onPressed, isNull);
      expect(find.text('Nama usaha/pengelola harus 3-80 karakter.'), findsOneWidget);

      // Telepon tidak valid (mengandung huruf / tanda hubung).
      await tester.enterText(orgField, 'Pos Air RW 03');
      await tester.enterText(phoneField, '0812-3456');
      await tester.pump();
      expect(submitBtn().onPressed, isNull);

      // Deskripsi terlalu pendek setelah trim.
      await tester.enterText(phoneField, '+62 812 3456 7890');
      await tester.enterText(descField, '   pendek   ');
      await tester.pump();
      expect(submitBtn().onPressed, isNull);

      // Semua valid tetapi kotak persetujuan tidak dicentang -> tetap nonaktif.
      await tester.enterText(descField, '  Menyediakan air bersih setiap hari.  ');
      await tester.pump();
      expect(submitBtn().onPressed, isNotNull);

      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Kirim pengajuan'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(submitBtn().onPressed, isNull);

      // Centang kembali lalu kirim.
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Kirim pengajuan'));
      await tester.tap(find.widgetWithText(FilledButton, 'Kirim pengajuan'));
      await tester.pump();

      expect(providers.submitted, hasLength(1));
      expect(providers.submitted.single.organizationName, 'Pos Air RW 03');
      expect(providers.submitted.single.description, 'Menyediakan air bersih setiap hari.');
      expect(providers.submitted.single.termsVersion, kProviderTermsVersion);
    });

    testWidgets('3d: pending menampilkan ringkasan tanpa tombol ubah', (tester) async {
      await mountScreen(
        tester,
        initialUser: _user(),
        initialApp: _sampleApp(status: ApplicationStatus.pending),
      );
      expect(find.text('Menunggu peninjauan admin'), findsOneWidget);
      expect(find.text('Depot Air Bersih RW 03'), findsOneWidget);
      expect(find.text('+62 812 3456 7890'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('3e: rejected menampilkan catatan admin dan ajukan ulang mengisi data lama',
        (tester) async {
      await mountScreen(
        tester,
        initialUser: _user(),
        initialApp: _sampleApp(
          status: ApplicationStatus.rejected,
          adminNote: 'Nomor telepon tidak dapat dihubungi.',
        ),
      );
      expect(find.text('Pengajuan ditolak'), findsOneWidget);
      expect(find.textContaining('Nomor telepon tidak dapat dihubungi.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Ajukan ulang'));
      await tester.pump();

      expect(find.text('Depot Air Bersih RW 03'), findsOneWidget);
      expect(find.text('+62 812 3456 7890'), findsOneWidget);
      expect(find.text('Menyediakan air minum isi ulang setiap hari.'), findsOneWidget);
    });

    testWidgets('3f: active menampilkan status penyedia dan info Sumber Saya', (tester) async {
      await mountScreen(
        tester,
        initialUser: _user(providerStatus: ProviderStatus.active),
      );
      expect(find.text('Kamu sudah menjadi penyedia'), findsOneWidget);
      expect(find.text('Halaman Sumber Saya hadir di pembaruan berikutnya.'), findsOneWidget);
    });

    testWidgets('3g: terminated menampilkan alasan pemutusan tanpa tombol ajukan',
        (tester) async {
      await mountScreen(
        tester,
        initialUser: _user(
          providerStatus: ProviderStatus.terminated,
          providerNote: 'Melanggar ketentuan konfirmasi.',
        ),
      );
      expect(find.text('Kemitraan penyedia diputus'), findsOneWidget);
      expect(find.textContaining('Melanggar ketentuan konfirmasi.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('AccountButton: item menu penyedia & label peran', () {
    Future<void> openMenu(
      WidgetTester tester, {
      required AppUser user,
      ProviderApplication? app,
    }) async {
      final auth = _FakeAuthService(user);
      final providers = FakeProviderService();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(auth)),
          ChangeNotifierProxyProvider<AuthProvider, ProviderApplicationProvider>(
            create: (ctx) => ProviderApplicationProvider(providers)
              ..syncUser(ctx.read<AuthProvider>().user?.uid),
            update: (_, a, p) => p!..syncUser(a.user?.uid),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AccountButton())),
      ));
      await tester.pump();
      if (providers.taps.isNotEmpty) {
        providers.taps.last.ctrl.add(app);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Akun'));
      await tester.pumpAndSettle();
    }

    testWidgets('warga belum mengajukan: label Warga dan menu Jadi penyedia', (tester) async {
      await openMenu(tester, user: _user(), app: null);
      expect(find.text('Warga'), findsOneWidget);
      expect(find.text('Jadi penyedia'), findsOneWidget);

      await tester.tap(find.text('Jadi penyedia'));
      await tester.pumpAndSettle();
      expect(find.byType(ProviderApplyScreen), findsOneWidget);
    });

    testWidgets('pengajuan pending: menu Status pengajuan', (tester) async {
      await openMenu(
        tester,
        user: _user(),
        app: _sampleApp(status: ApplicationStatus.pending),
      );
      expect(find.text('Status pengajuan'), findsOneWidget);
    });

    testWidgets('pengajuan rejected: menu Status pengajuan', (tester) async {
      await openMenu(
        tester,
        user: _user(),
        app: _sampleApp(status: ApplicationStatus.rejected, adminNote: 'Kurang'),
      );
      expect(find.text('Status pengajuan'), findsOneWidget);
    });

    testWidgets('penyedia active: menu Status penyedia dan label Penyedia', (tester) async {
      await openMenu(
        tester,
        user: _user(providerStatus: ProviderStatus.active),
      );
      expect(find.text('Penyedia'), findsOneWidget);
      expect(find.text('Status penyedia'), findsOneWidget);
    });

    testWidgets('penyedia terminated: menu Status penyedia dan label Warga', (tester) async {
      await openMenu(
        tester,
        user: _user(providerStatus: ProviderStatus.terminated),
      );
      expect(find.text('Warga'), findsOneWidget);
      expect(find.text('Status penyedia'), findsOneWidget);
    });

    testWidgets('admin: label Pengelola dan tidak melihat item pengajuan', (tester) async {
      await openMenu(tester, user: _user(role: UserRole.admin));
      expect(find.text('Pengelola'), findsOneWidget);
      expect(find.text('Panel pengelola'), findsOneWidget);
      expect(find.text('Jadi penyedia'), findsNothing);
      expect(find.text('Status pengajuan'), findsNothing);
      expect(find.text('Status penyedia'), findsNothing);
    });
  });
}
