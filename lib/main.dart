import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'app_providers.dart';
import 'config.dart';
import 'dev/mock_auth_service.dart';
import 'dev/mock_report_service.dart';
import 'dev/mock_source_service.dart';
import 'firebase_options.dart';
import 'screens/config_error_screen.dart';
import 'screens/source_list_screen.dart';
import 'services/auth_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/firestore_report_service.dart';
import 'services/firestore_source_service.dart';
import 'services/location_service.dart';
import 'services/report_service.dart';
import 'services/source_service.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kReleaseMode && !useFirebase) {
    throw StateError('Build rilis wajib memakai Firebase.');
  }
  await initializeDateFormatting('id_ID');
  runApp(const Bootstrap());
}

class _Deps {
  final AuthService auth;
  final ReportService reports;
  final SourceService sources;
  const _Deps(this.auth, this.reports, this.sources);
}

/// Menyiapkan layanan; bila Firebase gagal diinisialisasi, tampilkan layar
/// galat dengan tombol coba lagi (bukan aplikasi mati tanpa pesan).
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<_Deps> _future = _init();
  StreamSubscription<dynamic>? _authSub;

  Future<_Deps> _init() async {
    if (useFirebase) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      return _Deps(FirebaseAuthService(), FirestoreReportService(),
          FirestoreSourceService());
    }
    final auth = MockAuthService();
    final sources = MockSourceService();
    _authSub?.cancel();
    _authSub = auth.authChanges.listen((u) => sources.actAs(u?.uid));
    return _Deps(auth, MockReportService(sources), sources);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Deps>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return MaterialApp(
            theme: AppTheme.light,
            home: ConfigErrorScreen(
              error: snap.error!,
              onRetry: () => setState(() => _future = _init()),
            ),
          );
        }
        final deps = snap.data;
        if (deps == null) {
          return MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return AquaConnectApp(
          authService: deps.auth,
          reportService: deps.reports,
          sourceService: deps.sources,
          locationService: GeolocatorLocationService(),
        );
      },
    );
  }
}

class AquaConnectApp extends StatelessWidget {
  final AuthService authService;
  final ReportService reportService;
  final SourceService sourceService;
  final LocationService locationService;
  const AquaConnectApp({
    super.key,
    required this.authService,
    required this.reportService,
    required this.sourceService,
    required this.locationService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders(
        authService: authService,
        reportService: reportService,
        sourceService: sourceService,
        locationService: locationService,
      ),
      child: MaterialApp(
        title: 'AquaConnect',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('id'),
        supportedLocales: const [Locale('id'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const SourceListScreen(),
      ),
    );
  }
}
