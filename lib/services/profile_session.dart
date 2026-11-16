import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/water_source.dart' show byNameOrNull;

/// Identitas dari Auth, tanpa tipe Firebase agar logika di bawah bisa dites.
class AuthIdentity {
  final String uid;
  final String email;
  final String? displayName;
  final bool emailVerified;
  const AuthIdentity({
    required this.uid,
    required this.email,
    this.displayName,
    this.emailVerified = true,
  });
}

/// Satu snapshot dokumen `users/{uid}`.
class ProfileDoc {
  /// Null = dokumen tidak ada.
  final Map<String, dynamic>? data;

  /// true = berasal dari cache lokal (belum dikonfirmasi server).
  final bool fromCache;

  /// true = mencerminkan tulisan lokal yang belum diterima server.
  final bool hasPendingWrites;

  const ProfileDoc({this.data, this.fromCache = false, this.hasPendingWrites = false});
}

abstract class ProfileSource {
  /// Memantau dokumen profil (realtime).
  Stream<ProfileDoc> watch(String uid);

  /// Membuat dokumen profil dasar (peran SELALU `user`).
  Future<void> createBasic(AuthIdentity id);
}

/// Memantau `users/{uid}` selama pengguna masuk dan memancarkan [AppUser] baru
/// setiap dokumen berubah (peran, status penyedia, catatan). Menggantikan
/// pembacaan sekali.
///
/// Aturan yang dijaga:
/// - hasil usang diabaikan (sesi berganti selama menunggu);
/// - langganan lama dibatalkan saat keluar, ganti akun, atau dimulai ulang;
/// - dokumen tidak ada: peran terendah, tidak pernah melempar;
/// - dokumen tidak ada HANYA dari cache: `profileLoaded: false` (belum bisa
///   memastikan; admin tidak diturunkan diam-diam);
/// - profil hanya dibuat ulang bila server mengonfirmasi dokumen memang tidak
///   ada, tidak ada tulisan lokal tertunda, tidak sedang menghapus akun, dan
///   sekali per sesi.
class ProfileSession {
  final AuthIdentity? Function() _currentIdentity;
  final ProfileSource _source;
  final _ctrl = StreamController<AppUser?>.broadcast();

  StreamSubscription<AuthIdentity?>? _identitySub;
  StreamSubscription<ProfileDoc>? _profileSub;
  final Set<String> _healed = {};

  AppUser? _current;
  int _gen = 0;
  bool _registering = false;
  bool _deleting = false;

  ProfileSession({
    required Stream<AuthIdentity?> identityChanges,
    required AuthIdentity? Function() currentIdentity,
    required ProfileSource source,
  })  : _currentIdentity = currentIdentity,
        _source = source {
    _identitySub = identityChanges.listen(_onIdentity);
  }

  AppUser? get current => _current;

  Stream<AppUser?> get changes async* {
    yield _current;
    yield* _ctrl.stream;
  }

  // ---------------- siklus pendaftaran dan penghapusan ----------------

  /// Menjalankan [body] sebagai pendaftaran: pemantauan profil ditahan selama
  /// [body] berjalan dan SELALU dilanjutkan sesudahnya, tepat sekali, apa pun
  /// hasilnya (sukses, galat Firebase, atau galat jenis lain seperti
  /// PlatformException). Tanpa jaminan ini satu galat tak terduga membuat
  /// pemantauan macet sampai aplikasi dimulai ulang.
  Future<T> runRegistration<T>(Future<T> Function() body) async {
    beginRegistration();
    try {
      return await body();
    } finally {
      endRegistration();
    }
  }

  /// Selama pendaftaran, profil ditulis oleh register(); pemantauan baru dimulai
  /// setelah [endRegistration]. Pakai [runRegistration] agar pasangan ini tidak
  /// bisa terlewat.
  void beginRegistration() => _registering = true;

  void endRegistration() {
    _registering = false;
    final id = _currentIdentity();
    if (id != null) _start(id);
  }

  /// Selama penghapusan akun, dokumen profil yang hilang TIDAK dibuat ulang.
  void beginDeletion() => _deleting = true;
  void abortDeletion() => _deleting = false;

  // ---------------- kendali ----------------

  /// Memulai ulang pemantauan (mis. setelah memuat ulang status verifikasi email,
  /// atau memulihkan diri dari galat langganan).
  void restart() {
    final id = _currentIdentity();
    if (id != null && !_registering) _start(id);
  }

  /// Menunggu pengguna [uid] tersedia (segera bila sudah ada).
  Future<AppUser> awaitUser(String uid,
      {Duration timeout = const Duration(seconds: 20)}) {
    final now = _current;
    if (now != null && now.uid == uid) return Future.value(now);
    return _ctrl.stream
        .firstWhere((u) => u?.uid == uid)
        .then((u) => u!)
        .timeout(timeout);
  }

  void dispose() {
    _identitySub?.cancel();
    _stop();
    _ctrl.close();
  }

  // ---------------- internal ----------------

  void _onIdentity(AuthIdentity? id) {
    if (_registering) return;
    if (id == null) {
      _deleting = false;
      _healed.clear();
      _stop();
      _set(null);
      return;
    }
    _start(id);
  }

  void _start(AuthIdentity id) {
    _stop();
    final gen = ++_gen;
    _profileSub = _source.watch(id.uid).listen(
          (doc) => _onDoc(gen, id.uid, doc),
          onError: (Object e) => _onError(gen, id.uid, e),
        );
  }

  void _stop() {
    _gen++; // membatalkan semua callback yang masih tertunda
    _profileSub?.cancel();
    _profileSub = null;
  }

  bool _stale(int gen, String uid) => gen != _gen || _currentIdentity()?.uid != uid;

  void _onDoc(int gen, String uid, ProfileDoc doc) {
    if (_stale(gen, uid)) return;
    final id = _currentIdentity()!; // identitas TERBARU (emailVerified, nama)
    final data = doc.data;
    if (data != null) {
      _set(_fromData(id, data));
      return;
    }
    if (doc.fromCache) {
      // Tidak ada di cache bukan berarti tidak ada di server.
      _set(_basic(id, loaded: false));
      return;
    }
    // Server mengonfirmasi dokumen tidak ada (mis. terhapus): peran terendah.
    _set(_basic(id, loaded: true));
    _maybeHeal(id, doc);
  }

  void _onError(int gen, String uid, Object e) {
    if (_stale(gen, uid)) return;
    debugPrint('Pemantauan profil $uid gagal: $e');
    _set(_basic(_currentIdentity()!, loaded: false));
  }

  void _maybeHeal(AuthIdentity id, ProfileDoc doc) {
    if (_deleting || doc.hasPendingWrites) return;
    if (!_healed.add(id.uid)) return; // sekali per sesi
    _source.createBasic(id).catchError((Object e) {
      debugPrint('Membuat profil dasar gagal: $e');
    });
  }

  AppUser _basic(AuthIdentity id, {required bool loaded}) => AppUser(
        uid: id.uid,
        name: id.displayName ?? '',
        email: id.email,
        emailVerified: id.emailVerified,
        profileLoaded: loaded,
      );

  AppUser _fromData(AuthIdentity id, Map<String, dynamic> m) {
    final name = m['name'];
    final email = m['email'];
    final note = m['providerNote'];
    return AppUser(
      uid: id.uid,
      name: name is String ? name : (id.displayName ?? ''),
      email: email is String ? email : id.email,
      role: m['role'] == 'admin' ? UserRole.admin : UserRole.user,
      // Status verifikasi email berasal dari Auth, bukan dari dokumen.
      emailVerified: id.emailVerified,
      providerStatus:
          byNameOrNull(ProviderStatus.values, m['providerStatus']) ?? ProviderStatus.none,
      providerNote: note is String ? note : null,
    );
  }

  static bool _same(AppUser? a, AppUser? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.uid == b.uid &&
        a.name == b.name &&
        a.email == b.email &&
        a.role == b.role &&
        a.emailVerified == b.emailVerified &&
        a.profileLoaded == b.profileLoaded &&
        a.providerStatus == b.providerStatus &&
        a.providerNote == b.providerNote;
  }

  void _set(AppUser? u) {
    if (_same(_current, u)) return; // snapshot yang sama tidak dipancarkan ulang
    _current = u;
    _ctrl.add(u);
  }
}
