import 'package:flutter/foundation.dart';

/// Build rilis SELALU memakai Firebase. Mode tiruan hanya untuk debug.
/// Paksa dengan: flutter run --dart-define=USE_FIREBASE=true
const bool useFirebase =
    bool.fromEnvironment('USE_FIREBASE', defaultValue: kReleaseMode);

/// Samakan dengan applicationId (tool/bootstrap.sh mengaturnya otomatis).
/// Dipakai sebagai User-Agent permintaan tile peta.
const String kAppPackage = 'id.ac.kampus.aquaconnect';

/// Status ketersediaan yang tidak dikonfirmasi lebih lama dari ini diberi label.
const Duration kStaleAfter = Duration(hours: 72);

/// Wajibkan email terverifikasi untuk mengirim laporan.
/// Harus selaras dengan baris `email_verified` di firestore.rules.
const bool kRequireVerifiedEmail = true;

// ---------------- Fase 1: rute dan navigasi ----------------

/// Kunci ORS. JANGAN di-commit. Isi lewat: --dart-define-from-file=dart_defines.json
/// Kunci ikut terkemas di APK; batasi dan pantau kuotanya di account.heigit.org.
const String kOrsApiKey = String.fromEnvironment('ORS_API_KEY');
const bool kRoutingAvailable = kOrsApiKey != '';

/// Alamat dasar layanan (tanpa garis miring di akhir). `api.openrouteservice.org`
/// sudah dimatikan; alamat resmi sekarang `api.heigit.org`. Directions dan
/// geocoding memakai base yang BERBEDA.
const String kOrsBaseUrl = String.fromEnvironment('ORS_BASE_URL',
    defaultValue: 'https://api.heigit.org/openrouteservice');
const String kOrsGeocodeBaseUrl = String.fromEnvironment(
    'ORS_GEOCODE_BASE_URL',
    defaultValue: 'https://api.heigit.org/pelias/v1');

/// Build demo: posisi disimulasikan di sepanjang rute. Spanduk "SIMULASI"
/// tidak bisa dimatikan. Hanya untuk demo, bukan rilis ke pengguna.
const bool kDemoSimulation = bool.fromEnvironment('DEMO_SIM');

/// Tombol simulasi tersedia di debug atau di build demo.
const bool kSimulationEnabled = kDebugMode || kDemoSimulation;

const double kOffRouteMeters = 40; // jarak dari jalur yang dianggap menyimpang
const int kOffRouteFixes = 3; // berturut-turut, agar tidak terpancing GPS melompat
const Duration kRerouteMinGap = Duration(seconds: 15);
const int kMaxReroutes = 10; // per sesi, menjaga kuota API
const double kArriveMeters = 25;
const double kMaxUsableAccuracyM = 50; // fix kurang akurat tidak menilai penyimpangan

// ---------------- Fase 2: penyedia dan siklus hidup sumber ----------------

/// Sumber berpemilik yang tidak dikonfirmasi selama ini disembunyikan dari warga
/// (kecuali sakelar "Tampilkan yang belum dikonfirmasi" aktif). `kStaleAfter`
/// (3 hari) adalah ambang "tidak pasti".
const Duration kHideAfter = Duration(days: 7);

/// Penyedia diingatkan mengonfirmasi bila lebih dari ini belum dikonfirmasi.
const Duration kReconfirmReminderAfter = Duration(hours: 48);

/// Naikkan bersama teks Ketentuan Penyedia dan batas `termsVersion` di rules.
const int kProviderTermsVersion = 1;
