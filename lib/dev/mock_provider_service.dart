import 'dart:async';
import '../config.dart';
import '../models/app_user.dart';
import '../models/provider_application.dart';
import '../models/provider_profile.dart';
import '../services/provider_service.dart';
import '../services/source_service.dart';
import 'mock_auth_service.dart';

/// Penyimpanan TIRUAN di memori. Jangan dipakai di rilis.
class MockProviderService implements ProviderService {
  final SourceService _sources;
  final MockAuthService? _auth;
  MockProviderService(this._sources, {MockAuthService? auth, bool seedDemo = true})
      : _auth = auth {
    if (seedDemo) {
      _seedDemoData();
    }
  }

  final _ctrl = StreamController<void>.broadcast();
  final Map<String, ProviderApplication> _apps = {};
  final Map<String, ProviderProfile> _profiles = {};

  void _seedDemoData() {
    _apps['mock-calon'] = ProviderApplication(
      uid: 'mock-calon',
      organizationName: '[SIMULASI] Depot Air Sejahtera',
      contactPhone: '+6281234567890',
      description: 'Penyedia depot air isi ulang dan tangki bersih untuk warga.',
      termsVersion: kProviderTermsVersion,
      status: ApplicationStatus.pending,
      createdAt: DateTime.now().subtract(const Duration(hours: 12)),
    );
    _profiles['mock-provider'] = const ProviderProfile(
      uid: 'mock-provider',
      name: 'Penyedia Demo',
      email: 'penyedia@aquaconnect.test',
      status: ProviderStatus.active,
    );
    _profiles['mock-calon'] = const ProviderProfile(
      uid: 'mock-calon',
      name: 'Calon Demo',
      email: 'calon@aquaconnect.test',
      status: ProviderStatus.none,
    );
  }

  /// Menyiapkan pengajuan untuk tes atau demo.
  void seedApplication(ProviderApplication a) => _apps[a.uid] = a;

  /// Urutan operasi penting, untuk tes urutan pemutusan.
  final List<String> callLog = [];

  /// Menyiapkan profil (dokumen `users`) untuk tes.
  void seedProfile(ProviderProfile p) => _profiles[p.uid] = p;

  ProviderProfile? profileOf(String uid) => _profiles[uid];

  ProviderProfile _profile(String uid) =>
      _profiles[uid] ??
      ProviderProfile(uid: uid, name: '', email: '', status: ProviderStatus.none);

  List<ProviderApplication> _pending() => (_apps.values
          .where((a) => a.status == ApplicationStatus.pending)
          .toList()
        ..sort((a, b) => (a.createdAt ?? DateTime.now())
            .compareTo(b.createdAt ?? DateTime.now())));

  @override
  Stream<ProviderApplication?> watchMyApplication(String uid) async* {
    yield _apps[uid];
    yield* _ctrl.stream.map((_) => _apps[uid]);
  }

  @override
  Future<void> apply(ProviderApplication a) async {
    final error = validateApplication(a);
    if (error != null) throw ProviderException(error);
    final existing = _apps[a.uid];
    // Meniru rules: dokumen sudah ada hanya bisa diajukan ulang bila rejected.
    if (existing != null && existing.status != ApplicationStatus.rejected) {
      throw const ProviderException('Tidak ada izin untuk tindakan ini.');
    }
    // Meniru rules: hanya pengguna berstatus `none` yang boleh mengajukan.
    if (_profile(a.uid).status != ProviderStatus.none) {
      throw const ProviderException('Tidak ada izin untuk tindakan ini.');
    }
    _apps[a.uid] = ProviderApplication(
      uid: a.uid,
      organizationName: a.organizationName.trim(),
      contactPhone: a.contactPhone.trim(),
      description: a.description.trim(),
      termsVersion: a.termsVersion,
      createdAt: DateTime.now(),
    );
    _ctrl.add(null);
  }

  @override
  Stream<List<ProviderApplication>> watchPending() async* {
    yield _pending();
    yield* _ctrl.stream.map((_) => _pending());
  }

  @override
  Future<List<ProviderProfile>> fetchProviders() async {
    final list = _profiles.values
        .where((p) =>
            p.status == ProviderStatus.active ||
            p.status == ProviderStatus.terminated)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Future<void> review(String uid, {required bool approve, String note = ''}) async {
    final n = validateAdminNote(note, required: !approve);
    final a = _apps[uid];
    if (a == null) throw const ProviderException('Pengajuan tidak ditemukan.');
    if (a.status != ApplicationStatus.pending) {
      throw const ProviderException('Pengajuan ini sudah ditinjau.');
    }
    final now = DateTime.now();
    _apps[uid] = ProviderApplication(
      uid: a.uid,
      organizationName: a.organizationName,
      contactPhone: a.contactPhone,
      description: a.description,
      termsVersion: a.termsVersion,
      status: approve ? ApplicationStatus.approved : ApplicationStatus.rejected,
      adminNote: n,
      createdAt: a.createdAt,
      reviewedAt: now,
    );
    _profiles[uid] = _profile(uid).copyWith(
        status: approve ? ProviderStatus.active : ProviderStatus.none,
        reviewedAt: now);
    _auth?.updateProfile(
      uid,
      providerStatus: approve ? ProviderStatus.active : ProviderStatus.none,
    );
    _ctrl.add(null);
  }

  @override
  Future<void> terminate(String uid, String reason) async {
    final r = validateAdminNote(reason, required: true);
    // (1) Status DAHULU.
    callLog.add('users:terminated');
    _profiles[uid] = _profile(uid)
        .copyWith(status: ProviderStatus.terminated, note: r, reviewedAt: DateTime.now());
    _auth?.updateProfile(
      uid,
      providerStatus: ProviderStatus.terminated,
      providerNote: r,
    );
    _ctrl.add(null);
    // (2) Lalu penangguhan; kegagalan tidak membatalkan (1).
    callLog.add('suspendAllOwned');
    try {
      await _sources.suspendAllOwned(uid);
    } on SourceBatchException catch (e) {
      throw ProviderException(
          'Kemitraan diputus, tetapi ${e.remaining} sumber belum ditangguhkan '
          '(${e.message}). Ulangi pemutusan untuk menuntaskannya.',
          remaining: e.remaining);
    } on SourceException catch (e) {
      throw ProviderException(
          'Kemitraan diputus, tetapi penangguhan sumber gagal (${e.message}). '
          'Jumlah yang tersisa belum diketahui; ulangi pemutusan.');
    }
  }

  @override
  Future<void> reactivate(String uid) async {
    callLog.add('users:active');
    _profiles[uid] = _profile(uid)
        .copyWith(
            status: ProviderStatus.active,
            reviewedAt: DateTime.now(),
            clearNote: true); // meniru FieldValue.delete() pada providerNote
    _auth?.updateProfile(
      uid,
      providerStatus: ProviderStatus.active,
      clearProviderNote: true,
    );
    _ctrl.add(null);
  }
}
