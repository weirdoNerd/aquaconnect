import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'providers/admin_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/my_sources_provider.dart';
import 'providers/provider_application_provider.dart';
import 'providers/report_provider.dart';
import 'providers/source_provider.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'services/provider_service.dart';
import 'services/report_service.dart';
import 'services/source_service.dart';

/// Daftar provider aplikasi. Dipisah dari main.dart agar rangkaian
/// AuthProvider -> SourceProvider (dan lainnya) bisa dites apa adanya.
List<SingleChildWidget> appProviders({
  required AuthService authService,
  required ReportService reportService,
  required SourceService sourceService,
  required ProviderService providerService,
  required LocationService locationService,
}) =>
    [
      ChangeNotifierProvider(create: (_) => AuthProvider(authService)),
      // Aliran sumber air mengikuti peran. `create` sudah membuka langganan untuk
      // keadaan saat ini (tamu sejak awal), jadi sumber tayang tampil sebelum login.
      // Profil dipantau langsung (S4): perubahan peran atau status penyedia memicu
      // `update` ini dan membuka aliran yang sesuai TANPA keluar-masuk.
      ChangeNotifierProxyProvider<AuthProvider, SourceProvider>(
        create: (ctx) {
          final a = ctx.read<AuthProvider>();
          return SourceProvider(sourceService, locationService)
            ..syncUser(a.user?.uid, isAdmin: a.isAdmin, isProvider: a.isProvider);
        },
        update: (_, a, sp) => sp!
          ..syncUser(a.user?.uid, isAdmin: a.isAdmin, isProvider: a.isProvider),
      ),
      // Data per-pengguna dikosongkan saat akun berganti (mencegah kebocoran).
      ChangeNotifierProxyProvider<AuthProvider, ReportProvider>(
        create: (_) => ReportProvider(reportService),
        update: (_, auth, rp) => rp!..syncUser(auth.user?.uid),
      ),
      ChangeNotifierProxyProvider<AuthProvider, AdminProvider>(
        create: (_) => AdminProvider(reportService),
        update: (_, auth, ap) => ap!..syncUser(auth.user?.uid),
      ),
      ChangeNotifierProxyProvider<AuthProvider, ProviderApplicationProvider>(
        create: (ctx) => ProviderApplicationProvider(providerService)
          ..syncUser(ctx.read<AuthProvider>().user?.uid),
        update: (_, auth, app) => app!..syncUser(auth.user?.uid),
      ),
      ChangeNotifierProxyProvider<AuthProvider, MySourcesProvider>(
        create: (ctx) {
          final a = ctx.read<AuthProvider>();
          return MySourcesProvider(sourceService)
            ..syncUser(a.user?.uid, isProvider: a.isProvider);
        },
        update: (_, auth, mp) =>
            mp!..syncUser(auth.user?.uid, isProvider: auth.isProvider),
      ),
    ];
