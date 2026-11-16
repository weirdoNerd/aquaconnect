import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/app_providers.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/dev/mock_provider_service.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/screens/admin_screen.dart';
import 'package:aquaconnect/services/source_service.dart';
import 'helpers/fakes.dart';

void main() async {
  await initializeDateFormatting('id_ID');

  group('S11(a) legacyMigrationPatch & MockSourceService', () {
    test('menghitung patch yang tepat untuk berbagai bentuk dokumen lama dan idempoten',
        () {
      expect(
        legacyMigrationPatch({'name': 'Sumur Lama'}),
        {'isActive': true, 'listingStatus': 'published'},
      );
      expect(
        legacyMigrationPatch({'isActive': true}),
        {'listingStatus': 'published'},
      );
      expect(
        legacyMigrationPatch({'isActive': false}),
        {'listingStatus': 'closed'},
      );
      expect(
        legacyMigrationPatch({'listingStatus': 'pending'}),
        {'isActive': false},
      );
      expect(
        legacyMigrationPatch({'isActive': true, 'listingStatus': 'published'}),
        isNull,
      );
      expect(
        legacyMigrationPatch({'isActive': false, 'listingStatus': 'suspended'}),
        isNull,
      );
    });

    test('migrateLegacySources berjalan per potongan 8, aman diulang, dan idempoten',
        () async {
      final svc = MockSourceService();
      for (var i = 0; i < 18; i++) {
        svc.seedLegacyRaw('old-$i', {
          'name': 'Sumber Lama $i',
          if (i.isEven) 'isActive': i % 4 == 0,
        });
      }
      svc.seedLegacyRaw('modern-1', {
        'isActive': true,
        'listingStatus': 'published',
      });

      expect(await svc.countLegacySources(), 18);
      expect(await svc.migrateLegacySources(), 18);
      expect(svc.batchSizes, [8, 8, 2]);

      expect(svc.legacyRawOf('old-0'), {
        'name': 'Sumber Lama 0',
        'isActive': true,
        'listingStatus': 'published',
      });
      expect(svc.legacyRawOf('old-2'), {
        'name': 'Sumber Lama 2',
        'isActive': false,
        'listingStatus': 'closed',
      });
      expect(svc.legacyRawOf('old-1'), {
        'name': 'Sumber Lama 1',
        'isActive': true,
        'listingStatus': 'published',
      });

      // Panggil ulang: idempoten (0 tulisan baru).
      svc.batchSizes.clear();
      expect(await svc.countLegacySources(), 0);
      expect(await svc.migrateLegacySources(), 0);
      expect(svc.batchSizes, isEmpty);
    });

    test('gagal di tengah melempar SourceBatchException dan ulang hanya memproses sisa',
        () async {
      final svc = MockSourceService();
      for (var i = 0; i < 10; i++) {
        svc.seedLegacyRaw('old-$i', {'isActive': false});
      }
      svc.failAfterBatches = 1;

      await expectLater(
        svc.migrateLegacySources,
        throwsA(isA<SourceBatchException>()
            .having((e) => e.done, 'done', 8)
            .having((e) => e.remaining, 'remaining', 2)),
      );
      expect(await svc.countLegacySources(), 2);

      svc.failAfterBatches = null;
      expect(await svc.migrateLegacySources(), 2);
      expect(await svc.countLegacySources(), 0);
    });
  });

  group('S11(a) UI AdminScreen tombol Perbaiki data lama', () {
    testWidgets('menampilkan pratinjau jumlah, batal, eksekusi, dan cek ulang idempoten',
        (tester) async {
      final sources = MockSourceService();
      final auth = MockAuthService(sources: sources);
      final providers = MockProviderService(sources, auth: auth);
      await tester.runAsync(
          () => auth.signIn('admin@aquaconnect.test', 'admin123'));

      await tester.pumpWidget(MultiProvider(
        key: UniqueKey(),
        providers: appProviders(
          authService: auth,
          reportService: MockReportService(sources),
          sourceService: sources,
          providerService: providers,
          locationService: NoLocation(),
        ),
        child: const MaterialApp(home: AdminScreen()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sumber air'));
      await tester.pumpAndSettle();

      // Belum ada data lama.
      await tester.tap(find.text('Perbaiki data lama'));
      await tester.pumpAndSettle();
      expect(
        find.text(
            'Semua data sumber air sudah sesuai (0 dokumen perlu diperbarui).'),
        findsOneWidget,
      );

      // Tambah 2 dokumen lama -> pratinjau 2, batal tidak memigrasikan, Perbaiki (2) sukses.
      sources.seedLegacyRaw('legacy-1', {'name': 'Lama 1'});
      sources.seedLegacyRaw('legacy-2', {'isActive': false});

      await tester.tap(find.text('Perbaiki data lama'));
      await tester.pumpAndSettle();
      expect(find.text('Perbaiki data lama?'), findsOneWidget);
      expect(find.textContaining('Ditemukan 2 dokumen sumber air lama'),
          findsOneWidget);

      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(await sources.countLegacySources(), 2);

      await tester.tap(find.text('Perbaiki data lama'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Perbaiki (2)'));
      await tester.pumpAndSettle();

      expect(find.text('2 dokumen lama berhasil diperbarui.'), findsOneWidget);
      expect(await sources.countLegacySources(), 0);
      expect(sources.legacyRawOf('legacy-1')?['listingStatus'], 'published');
      expect(sources.legacyRawOf('legacy-2')?['listingStatus'], 'closed');
    });
  });
}
