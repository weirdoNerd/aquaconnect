import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/report_provider.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'package:aquaconnect/screens/my_reports_screen.dart';
import 'helpers/fakes.dart';

Widget _host(SourceProvider sp, ReportProvider rp) => MultiProvider(
      providers: [
        ChangeNotifierProvider<SourceProvider>.value(value: sp),
        ChangeNotifierProvider<ReportProvider>.value(value: rp),
      ],
      child: const MaterialApp(home: MyReportsScreen()),
    );

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  // Laporan contoh milik 'mock-user': seed-1 -> sim-2, seed-2 -> sim-4.
  testWidgets('sumber yang tidak lagi tayang diberi label "Sumber tidak lagi tayang"', (tester) async {
    final sources = MockSourceService();
    await sources.setListing('sim-2', ListingStatus.suspended, note: 'Dalam pemeriksaan');
    final sp = SourceProvider(sources, NoLocation())
      ..syncUser(null, isAdmin: false, isProvider: false);
    final rp = ReportProvider(MockReportService(sources))..syncUser('mock-user');

    await tester.pumpWidget(_host(sp, rp));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sumber tidak lagi tayang'), findsOneWidget, reason: 'sim-2 ditangguhkan');
    expect(find.text('[SIMULASI] Sumur Umum Taman Warga'), findsOneWidget, reason: 'sim-4 masih tayang');
    expect(find.text('Sumber air tidak ditemukan'), findsNothing);
  });

  testWidgets('sumber yang ditutup juga diberi label yang sama', (tester) async {
    final sources = MockSourceService();
    sources.actAs('p1');
    await sources.setListing('sim-4', ListingStatus.closed);
    final sp = SourceProvider(sources, NoLocation())
      ..syncUser(null, isAdmin: false, isProvider: false);
    final rp = ReportProvider(MockReportService(sources))..syncUser('mock-user');

    await tester.pumpWidget(_host(sp, rp));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sumber tidak lagi tayang'), findsOneWidget, reason: 'sim-4 ditutup');
    expect(find.text('[SIMULASI] Pos Distribusi Air Kelurahan'), findsOneWidget, reason: 'sim-2 masih tayang');
  });

  testWidgets('selama daftar sumber masih dimuat TIDAK menyatakan "tidak lagi tayang"', (tester) async {
    final sources = MockSourceService();
    final sp = SourceProvider(sources, NoLocation()); // belum syncUser: masih loading
    final rp = ReportProvider(MockReportService(sources))..syncUser('mock-user');

    await tester.pumpWidget(_host(sp, rp));
    await tester.pump();
    await tester.pump();

    expect(sp.loading, isTrue);
    expect(find.text('Memuat nama sumber…'), findsNWidgets(2));
    expect(find.text('Sumber tidak lagi tayang'), findsNothing);
  });

  testWidgets('nama sumber muncul setelah daftar selesai dimuat', (tester) async {
    final sources = MockSourceService();
    final sp = SourceProvider(sources, NoLocation());
    final rp = ReportProvider(MockReportService(sources))..syncUser('mock-user');

    await tester.pumpWidget(_host(sp, rp));
    await tester.pump();
    expect(find.text('Memuat nama sumber…'), findsNWidgets(2));

    sp.syncUser(null, isAdmin: false, isProvider: false);
    await tester.pump();
    await tester.pump();
    expect(find.text('Memuat nama sumber…'), findsNothing);
    expect(find.text('[SIMULASI] Pos Distribusi Air Kelurahan'), findsOneWidget);
    expect(find.text('[SIMULASI] Sumur Umum Taman Warga'), findsOneWidget);
  });
}
