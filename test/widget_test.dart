import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/providers/admin_provider.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'package:aquaconnect/screens/admin_screen.dart';
import 'package:aquaconnect/screens/login_screen.dart';
import 'package:aquaconnect/services/location_service.dart';

class _NoLocation implements LocationService {
  @override
  Future<LocationResult> getCurrent() async =>
      const LocationResult(LocationStatus.error);
  @override
  Future<void> openLocationSettings() async {}
  @override
  Future<void> openAppSettings() async {}
}

void main() {
  testWidgets('login menolak email kosong dan sandi kosong', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => AuthProvider(MockAuthService()),
        child: const LoginScreen(),
      ),
    ));

    final button = find.widgetWithText(FilledButton, 'Masuk');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.text('Email wajib diisi'), findsOneWidget);
    expect(find.text('Kata sandi wajib diisi'), findsOneWidget);
  });

  testWidgets('login tidak memaksa panjang sandi (hanya wajib terisi)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => AuthProvider(MockAuthService()),
        child: const LoginScreen(),
      ),
    ));

    await tester.enterText(find.byType(TextFormField).first, 'a@b.id');
    await tester.enterText(find.byType(TextFormField).last, '123');
    final button = find.widgetWithText(FilledButton, 'Masuk');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.text('Minimal 6 karakter'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });

  testWidgets('panel admin menolak akses untuk warga', (tester) async {
    final sources = MockSourceService();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(MockAuthService())),
        ChangeNotifierProvider(
            create: (_) => SourceProvider(sources, _NoLocation())),
        ChangeNotifierProvider(
            create: (_) => AdminProvider(MockReportService(sources))),
      ],
      child: const MaterialApp(home: AdminScreen()),
    ));
    await tester.pump();

    expect(find.text('Akses ditolak. Khusus pengelola.'), findsOneWidget);
  });
}
