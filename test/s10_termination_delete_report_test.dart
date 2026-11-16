import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/app_providers.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/dev/mock_provider_service.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/water_report.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/admin_provider.dart';
import 'package:aquaconnect/screens/report_form_screen.dart';
import 'package:aquaconnect/screens/review_sheet.dart';
import 'package:aquaconnect/services/auth_service.dart';
import 'package:aquaconnect/services/source_service.dart';
import 'package:aquaconnect/widgets/account_button.dart';
import 'helpers/fakes.dart';

Widget _harness({
  required MockAuthService auth,
  required MockSourceService sources,
  required MockReportService reports,
  required MockProviderService providers,
  required Widget home,
}) {
  return MultiProvider(
    key: UniqueKey(),
    providers: appProviders(
      authService: auth,
      reportService: reports,
      sourceService: sources,
      providerService: providers,
      locationService: NoLocation(),
    ),
    child: MaterialApp(home: home),
  );
}

void main() {
  group('S10(b) executeAccountDeletion & MockAuthService.deleteAccount', () {
    test('penyedia aktif: closeAllOwned -> deleteApplication -> deleteProfile -> deleteAuth',
        () async {
      final log = <String>[];
      await executeAccountDeletion(
        status: ProviderStatus.active,
        closeAllOwned: () async => log.add('closeAllOwned'),
        deleteApplication: () async => log.add('deleteApplication'),
        deleteProfile: () async => log.add('deleteProfile'),
        deleteAuth: () async => log.add('deleteAuth'),
      );
      expect(
          log, ['closeAllOwned', 'deleteApplication', 'deleteProfile', 'deleteAuth']);
    });

    test('penyedia aktif: kegagalan closeAllOwned membatalkan sebelum menghapus apapun',
        () async {
      final log = <String>[];
      await expectLater(
        () => executeAccountDeletion(
          status: ProviderStatus.active,
          closeAllOwned: () async {
            log.add('closeAllOwned');
            throw const SourceBatchException(
              'Koneksi putus.',
              done: 8,
              remaining: 4,
            );
          },
          deleteApplication: () async => log.add('deleteApplication'),
          deleteProfile: () async => log.add('deleteProfile'),
          deleteAuth: () async => log.add('deleteAuth'),
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          allOf(contains('8 ditutup'), contains('4 tersisa'), contains('belum dihapus')),
        )),
      );
      expect(log, ['closeAllOwned']);
    });

    test('penyedia terputus: melewati deleteApplication & deleteProfile, hanya deleteAuth',
        () async {
      final log = <String>[];
      await executeAccountDeletion(
        status: ProviderStatus.terminated,
        closeAllOwned: () async => log.add('closeAllOwned'),
        deleteApplication: () async => log.add('deleteApplication'),
        deleteProfile: () async => log.add('deleteProfile'),
        deleteAuth: () async => log.add('deleteAuth'),
      );
      expect(log, ['deleteAuth']);
    });

    test('pengguna tanpa pengajuan: gagal hapus pengajuan bukan galat fatal',
        () async {
      final log = <String>[];
      await executeAccountDeletion(
        status: ProviderStatus.none,
        closeAllOwned: () async => log.add('closeAllOwned'),
        deleteApplication: () async {
          log.add('deleteApplication');
          throw Exception('permission-denied');
        },
        deleteProfile: () async => log.add('deleteProfile'),
        deleteAuth: () async => log.add('deleteAuth'),
      );
      expect(log, ['deleteApplication', 'deleteProfile', 'deleteAuth']);
    });

    test('MockAuthService.deleteAccount: sandi salah tidak menutup sumber; penyedia aktif menutup sumber & membersihkan data',
        () async {
      final sources = MockSourceService();
      late final MockProviderService providers;
      final auth = MockAuthService(
        sources: sources,
        onDeleteApplication: (uid) => providers.removeApplication(uid),
        onDeleteProfile: (uid) => providers.removeProfile(uid),
      );
      providers = MockProviderService(sources, auth: auth);

      await auth.signIn('penyedia@aquaconnect.test', 'penyedia123');
      sources.actAs('mock-provider');

      // Sandi salah gagal sebelum menyentuh sumber milik penyedia.
      await expectLater(
        () => auth.deleteAccount('salah'),
        throwsA(isA<AuthException>()),
      );
      final beforeOwned = (await sources.watchOwned('mock-provider').first).sources;
      expect(
        beforeOwned.any((s) => s.listingStatus == ListingStatus.published),
        isTrue,
      );

      // Sandi benar: sumber yang dapat ditutup menjadi closed ('akun dihapus'),
      // aplikasi & profil ikut dihapus, dan akun tidak bisa masuk lagi.
      await auth.deleteAccount('penyedia123');
      expect(auth.currentUser, isNull);
      final afterOwned = (await sources.watchAll().first)
          .sources
          .where((s) => s.ownerId == 'mock-provider')
          .toList();
      expect(
        afterOwned.where((s) => s.listingStatus != ListingStatus.suspended),
        everyElement(
          isA<WaterSource>()
              .having((s) => s.listingStatus, 'listingStatus', ListingStatus.closed)
              .having((s) => s.closedReason, 'closedReason', 'akun dihapus'),
        ),
      );
      expect(await providers.watchMyApplication('mock-provider').first, isNull);
      expect(providers.profileOf('mock-provider'), isNull);
      await expectLater(
        () => auth.signIn('penyedia@aquaconnect.test', 'penyedia123'),
        throwsA(isA<AuthException>()),
      );
    });

    test('MockAuthService.deleteAccount penyedia terputus mempertahankan pengajuan & profil',
        () async {
      final sources = MockSourceService();
      late final MockProviderService providers;
      final auth = MockAuthService(
        sources: sources,
        onDeleteApplication: (uid) => providers.removeApplication(uid),
        onDeleteProfile: (uid) => providers.removeProfile(uid),
      );
      providers = MockProviderService(sources, auth: auth);

      // Setujui lalu putus mock-calon agar berstatus terminated.
      await providers.review('mock-calon', approve: true);
      await providers.terminate('mock-calon', 'Melanggar ketentuan operasional');
      await auth.signIn('calon@aquaconnect.test', 'calon123');
      expect(auth.currentUser?.providerStatus, ProviderStatus.terminated);

      await auth.deleteAccount('calon123');
      expect(auth.currentUser, isNull);
      expect(await providers.watchMyApplication('mock-calon').first, isNotNull);
      expect(providers.profileOf('mock-calon')?.status, ProviderStatus.terminated);
    });
  });

  group('S10 UI: dialog hapus akun, ReportType.noLongerOperating, ReviewSheet suspend',
      () {
    testWidgets(
        'AccountButton dialog hapus akun menampilkan peringatan sesuai status active & terminated',
        (tester) async {
      final sources = MockSourceService();
      final auth = MockAuthService(sources: sources);
      final reports = MockReportService(sources);
      final providers = MockProviderService(sources, auth: auth);

      await tester.runAsync(
          () => auth.signIn('penyedia@aquaconnect.test', 'penyedia123'));
      await tester.pumpWidget(_harness(
        auth: auth,
        sources: sources,
        reports: reports,
        providers: providers,
        home: const Scaffold(appBar: null, body: Center(child: AccountButton())),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AccountButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus akun'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Semua sumber air milik Anda akan ditutup terlebih dahulu'),
        findsOneWidget,
      );
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      // Ubah ke terminated lalu buka dialog lagi.
      auth.updateProfile(
        'mock-provider',
        providerStatus: ProviderStatus.terminated,
        providerNote: 'Berhenti',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AccountButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus akun'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Hanya akun masuk yang akan dihapus'),
        findsOneWidget,
      );
    });

    testWidgets(
        'ReportFormScreen menampilkan Sudah tidak beroperasi dan warga bisa mengirimkannya',
        (tester) async {
      final sources = MockSourceService();
      final auth = MockAuthService(sources: sources);
      final reports = MockReportService(sources);
      final providers = MockProviderService(sources, auth: auth);

      await tester.runAsync(
          () => auth.signIn('warga@aquaconnect.test', 'warga123'));

      await tester.pumpWidget(_harness(
        auth: auth,
        sources: sources,
        reports: reports,
        providers: providers,
        home: const ReportFormScreen(sourceId: 'sim-1'),
      ));
      await tester.pumpAndSettle();

      final chip = find.text(ReportType.noLongerOperating.label);
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('sudah berhenti beroperasi secara permanen'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextFormField),
        'Depot sudah tutup permanen dan alatnya dibongkar.',
      );
      await tester.ensureVisible(find.text('Kirim laporan'));
      await tester.tap(find.text('Kirim laporan'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final pending = await reports.watchPending().first;
      expect(
        pending.any((r) =>
            r.sourceId == 'sim-1' && r.type == ReportType.noLongerOperating),
        isTrue,
      );
    });

    testWidgets(
        'ReviewSheet untuk Sudah tidak beroperasi menyarankan tangguhkan dengan konfirmasi eksplisit dan menulis suspended + isActive=false',
        (tester) async {
      final sources = MockSourceService();
      final auth = MockAuthService(sources: sources);
      final reports = MockReportService(sources);
      final providers = MockProviderService(sources, auth: auth);

      await tester.runAsync(
          () => auth.signIn('admin@aquaconnect.test', 'admin123'));
      await tester.runAsync(() => reports.submit(
            sourceId: 'sim-1',
            reporterId: 'mock-user',
            type: ReportType.noLongerOperating,
            description: 'Lokasi sudah rata tanah dan tutup permanen.',
          ));
      final report = (await reports.watchPending().first)
          .firstWhere((r) => r.type == ReportType.noLongerOperating);

      await tester.pumpWidget(_harness(
        auth: auth,
        sources: sources,
        reports: reports,
        providers: providers,
        home: Scaffold(body: ReviewSheet(report: report)),
      ));
      await tester.pumpAndSettle();

      // Mulai AdminProvider supaya review() menyegarkan daftar pending.
      tester.element(find.byType(ReviewSheet)).read<AdminProvider>().start();
      await tester.pumpAndSettle();

      expect(find.text('Tangguhkan sumber air (disarankan)'), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.value, isTrue);

      // Klik Setujui memunculkan dialog konfirmasi eksplisit.
      await tester.ensureVisible(find.text('Setujui'));
      await tester.tap(find.text('Setujui'));
      await tester.pumpAndSettle();

      expect(find.text('Tangguhkan sumber air?'), findsOneWidget);
      // Batal -> tidak menangguhkan.
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      final stillActive = (await sources.watchAll().first)
          .sources
          .firstWhere((s) => s.id == 'sim-1');
      expect(stillActive.isActive, isTrue);
      expect(stillActive.listingStatus, ListingStatus.published);

      // Setujui lalu konfirmasi Ya, tangguhkan -> sumber ditangguhkan & tidak aktif.
      await tester.ensureVisible(find.text('Setujui'));
      await tester.tap(find.text('Setujui'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya, tangguhkan'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final suspended = (await sources.watchAll().first)
          .sources
          .firstWhere((s) => s.id == 'sim-1');
      expect(suspended.listingStatus, ListingStatus.suspended);
      expect(suspended.isActive, isFalse);
      final published = (await sources.watchPublished().first).sources;
      expect(published.any((s) => s.id == 'sim-1'), isFalse);
    });
  });
}
