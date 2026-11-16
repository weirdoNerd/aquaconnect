import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/app_providers.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/providers/provider_application_provider.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'helpers/fakes.dart';

/// Memasang appProviders APA ADANYA (yang dipakai main.dart) dan memastikan
/// perubahan profil di AuthProvider membuka aliran sumber yang sesuai.
void main() {
  Future<(MockAuthService, FakeSourceService, FakeProviderService, BuildContext)> mount(
      WidgetTester tester) async {
    final auth = MockAuthService();
    final sources = FakeSourceService();
    final providers = FakeProviderService();
    await tester.pumpWidget(MultiProvider(
      providers: appProviders(
        authService: auth,
        reportService: MockReportService(MockSourceService()),
        sourceService: sources,
        providerService: providers,
        locationService: NoLocation(),
      ),
      child: const SizedBox(),
    ));
    final ctx = tester.element(find.byType(SizedBox));
    ctx.read<SourceProvider>(); // provider dibuat malas; baca agar terbentuk (seperti layar daftar)
    return (auth, sources, providers, ctx);
  }

  testWidgets('tamu: satu langganan "published" aktif sejak awal', (tester) async {
    final (_, sources, _, _) = await mount(tester);
    expect(sources.active, ['published']);
  });

  testWidgets('providerStatus none -> active membuka aliran "milik sendiri" TANPA keluar-masuk', (tester) async {
    final (auth, sources, _, ctx) = await mount(tester);

    await tester.runAsync(() => ctx.read<AuthProvider>().signIn('warga@aquaconnect.test', 'warga123'));
    await tester.pump();
    await tester.pump();
    expect(sources.active, ['published'], reason: 'warga biasa: hanya sumber tayang');
    expect(ctx.read<AuthProvider>().user!.uid, 'mock-user');

    // Admin menyetujui pengajuan: profil berubah, TANPA signOut/signIn.
    auth.updateProfile('mock-user', providerStatus: ProviderStatus.active);
    await tester.pump();
    await tester.pump();
    expect(sources.active, ['published', 'owned']);
    final owned = sources.taps.lastWhere((t) => t.name == 'owned' && !t.cancelled);
    expect(owned.arg, 'mock-user');
    expect(ctx.read<AuthProvider>().isLoggedIn, isTrue);

    // Pemutusan kemitraan: aliran "milik sendiri" ditutup lagi.
    auth.updateProfile('mock-user',
        providerStatus: ProviderStatus.terminated, providerNote: 'Melanggar ketentuan');
    await tester.pump();
    await tester.pump();
    expect(sources.active, ['published']);
    expect(sources.taps.where((t) => t.name == 'owned').every((t) => t.cancelled), isTrue);
  });

  testWidgets('perubahan profil yang tidak memengaruhi tupel tidak membuka ulang aliran', (tester) async {
    final (auth, sources, _, ctx) = await mount(tester);
    await tester.runAsync(() => ctx.read<AuthProvider>().signIn('warga@aquaconnect.test', 'warga123'));
    await tester.pump();
    await tester.pump();
    final before = sources.taps.length;

    auth.updateProfile('mock-user', emailVerified: false); // bukan peran/penyedia
    await tester.pump();
    await tester.pump();
    expect(sources.taps.length, before);
  });

  testWidgets('admin dipromosikan: aliran berganti ke "all"; profil dihapus: kembali ke tayang', (tester) async {
    final (auth, sources, _, ctx) = await mount(tester);
    await tester.runAsync(() => ctx.read<AuthProvider>().signIn('admin@aquaconnect.test', 'admin123'));
    await tester.pump();
    await tester.pump();
    expect(sources.active, ['all']);

    auth.deleteProfile('mock-admin'); // peran terendah, tidak crash
    await tester.pump();
    await tester.pump();
    expect(sources.active, ['published']);
    expect(ctx.read<AuthProvider>().isAdmin, isFalse);
  });

  testWidgets('ProviderApplicationProvider melanggan saat masuk dan batal saat keluar',
      (tester) async {
    final (_, _, providers, ctx) = await mount(tester);
    ctx.read<ProviderApplicationProvider>();
    expect(providers.active, isEmpty);

    await tester.runAsync(() => ctx.read<AuthProvider>().signIn('warga@aquaconnect.test', 'warga123'));
    await tester.pump();
    await tester.pump();
    expect(providers.active, ['mock-user']);

    await tester.runAsync(() => ctx.read<AuthProvider>().signOut());
    await tester.pump();
    await tester.pump();
    expect(providers.active, isEmpty);
  });
}
