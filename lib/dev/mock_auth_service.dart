import 'dart:async';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/source_service.dart';

class _Account {
  String password;
  AppUser user;
  _Account(this.password, this.user);
}

/// Autentikasi TIRUAN untuk pengembangan UI dan tes. Data hilang saat aplikasi
/// ditutup. Build rilis tidak memakai kelas ini (lihat config.dart).
class MockAuthService implements AuthService {
  final SourceService? _sources;
  final void Function(String uid)? _onDeleteApplication;
  final void Function(String uid)? _onDeleteProfile;
  MockAuthService({
    SourceService? sources,
    void Function(String uid)? onDeleteApplication,
    void Function(String uid)? onDeleteProfile,
  })  : _sources = sources,
        _onDeleteApplication = onDeleteApplication,
        _onDeleteProfile = onDeleteProfile;

  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;

  final Map<String, _Account> _accounts = {
    'admin@aquaconnect.test': _Account(
      'admin123',
      const AppUser(
        uid: 'mock-admin',
        name: 'Admin Demo',
        email: 'admin@aquaconnect.test',
        role: UserRole.admin,
      ),
    ),
    'warga@aquaconnect.test': _Account(
      'warga123',
      const AppUser(
        uid: 'mock-user',
        name: 'Warga Demo',
        email: 'warga@aquaconnect.test',
      ),
    ),
    'penyedia@aquaconnect.test': _Account(
      'penyedia123',
      const AppUser(
        uid: 'mock-provider',
        name: 'Penyedia Demo',
        email: 'penyedia@aquaconnect.test',
        providerStatus: ProviderStatus.active,
        emailVerified: true,
      ),
    ),
    'calon@aquaconnect.test': _Account(
      'calon123',
      const AppUser(
        uid: 'mock-calon',
        name: 'Calon Demo',
        email: 'calon@aquaconnect.test',
        emailVerified: true,
      ),
    ),
  };

  @override
  AppUser? get currentUser => _current;

  @override
  Stream<AppUser?> get authChanges async* {
    yield _current;
    yield* _controller.stream;
  }

  Future<void> _latency() => Future.delayed(const Duration(milliseconds: 300));

  // ---------------- profil langsung (meniru users/{uid} yang berubah) ----------------

  _Account? _byUid(String uid) {
    for (final a in _accounts.values) {
      if (a.user.uid == uid) return a;
    }
    return null;
  }

  /// Meniru admin/Console mengubah dokumen profil: memancarkan AppUser baru bila
  /// [uid] adalah pengguna yang sedang masuk. Untuk tes dan pengembangan.
  void updateProfile(
    String uid, {
    UserRole? role,
    ProviderStatus? providerStatus,
    String? providerNote,
    bool clearProviderNote = false,
    bool? emailVerified,
  }) {
    final acc = _byUid(uid);
    if (acc == null) return;
    acc.user = acc.user.copyWith(
      role: role,
      providerStatus: providerStatus,
      providerNote: providerNote,
      clearProviderNote: clearProviderNote,
      emailVerified: emailVerified,
    );
    if (_current?.uid == uid) _set(acc.user);
  }

  /// Meniru dokumen profil yang terhapus: peran terendah (user, bukan penyedia),
  /// tanpa melempar. Pengguna tetap masuk.
  void deleteProfile(String uid) {
    final acc = _byUid(uid);
    if (acc == null) return;
    acc.user = acc.user.copyWith(
      role: UserRole.user,
      providerStatus: ProviderStatus.none,
      clearProviderNote: true,
    );
    if (_current?.uid == uid) _set(acc.user);
  }

  void _set(AppUser? u) {
    _current = u;
    _controller.add(u);
  }

  @override
  Future<AppUser> signIn(String email, String password) async {
    await _latency();
    final acc = _accounts[email.trim().toLowerCase()];
    if (acc == null || acc.password != password) {
      throw const AuthException('Email atau kata sandi salah.');
    }
    _set(acc.user);
    return acc.user;
  }

  @override
  Future<AppUser> register(String name, String email, String password) async {
    await _latency();
    final key = email.trim().toLowerCase();
    if (_accounts.containsKey(key)) {
      throw const AuthException('Email sudah terdaftar.');
    }
    // Peran SELALU "user". Admin tidak bisa dipilih saat mendaftar.
    final user = AppUser(
      uid: 'mock-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      email: key,
    );
    _accounts[key] = _Account(password, user);
    _set(user);
    return user;
  }

  @override
  Future<void> signOut() async => _set(null);

  @override
  Future<void> sendPasswordReset(String email) async => _latency();

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> deleteAccount(String password) async {
    await _latency();
    final u = _current;
    if (u == null) return;
    final acc = _accounts[u.email];
    if (acc == null || acc.password != password) {
      throw const AuthException('Kata sandi salah.');
    }
    await executeAccountDeletion(
      status: u.providerStatus,
      closeAllOwned: () async {
        final svc = _sources;
        if (svc != null) {
          await svc.closeAllOwned(u.uid, 'akun dihapus');
        }
      },
      deleteApplication: () async => _onDeleteApplication?.call(u.uid),
      deleteProfile: () async => _onDeleteProfile?.call(u.uid),
      deleteAuth: () async {
        _accounts.remove(u.email);
        _set(null);
      },
    );
  }
}
