import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/water_source.dart';
import 'auth_service.dart';
import 'firestore_source_service.dart';
import 'profile_session.dart';
import 'source_service.dart';

/// Sumber profil dari Firestore: `users/{uid}` dipantau dengan snapshots().
/// `includeMetadataChanges` agar peralihan cache -> server terlihat (dokumen
/// yang belum ada di cache bukan berarti tidak ada di server).
class FirestoreProfileSource implements ProfileSource {
  final FirebaseFirestore _db;
  FirestoreProfileSource(this._db);

  DocumentReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid);

  @override
  Stream<ProfileDoc> watch(String uid) =>
      _ref(uid).snapshots(includeMetadataChanges: true).map((s) => ProfileDoc(
            data: s.data(),
            fromCache: s.metadata.isFromCache,
            hasPendingWrites: s.metadata.hasPendingWrites,
          ));

  /// Peran SELALU "user". Rules menolak peran lain.
  @override
  Future<void> createBasic(AuthIdentity id) {
    final dn = id.displayName?.trim() ?? '';
    var name = dn.length >= 2 ? dn : id.email.split('@').first;
    if (name.length < 2) name = 'Pengguna';
    if (name.length > 60) name = name.substring(0, 60);
    return _ref(id.uid).set({
      'uid': id.uid,
      'name': name,
      'email': id.email.toLowerCase(),
      'role': 'user',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Auth + profil peran. Peran dibaca dari `users/{uid}.role` dan DIPANTAU langsung
/// ([ProfileSession]): perubahan peran atau status penyedia oleh admin terlihat
/// tanpa keluar-masuk. Peran "admin" HANYA bisa diatur lewat Firebase Console.
class FirebaseAuthService implements AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final SourceService _sources;
  late final ProfileSession _session;

  FirebaseAuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    SourceService? sources,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _sources = sources ?? FirestoreSourceService(db: db) {
    _session = ProfileSession(
      identityChanges: _auth.authStateChanges().map(_identityOf),
      currentIdentity: () => _identityOf(_auth.currentUser),
      source: FirestoreProfileSource(_db),
    );
  }

  static AuthIdentity? _identityOf(User? u) => u == null
      ? null
      : AuthIdentity(
          uid: u.uid,
          email: u.email ?? '',
          displayName: u.displayName,
          emailVerified: u.emailVerified,
        );

  @override
  AppUser? get currentUser => _session.current;

  @override
  Stream<AppUser?> get authChanges => _session.changes;

  AuthException _map(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return const AuthException('Email atau kata sandi salah.');
      case 'invalid-email':
        return const AuthException('Format email tidak valid.');
      case 'user-disabled':
        return const AuthException('Akun ini dinonaktifkan.');
      case 'too-many-requests':
        return const AuthException(
            'Terlalu banyak percobaan. Coba lagi beberapa saat.');
      case 'network-request-failed':
        return const AuthException('Tidak ada koneksi internet.');
      case 'email-already-in-use':
        return const AuthException('Email sudah terdaftar.');
      case 'weak-password':
        return const AuthException('Kata sandi terlalu lemah.');
      case 'requires-recent-login':
        return const AuthException('Sesi sudah lama. Masuk ulang lalu coba lagi.');
      default:
        return AuthException('Autentikasi gagal (${e.code}).');
    }
  }

  /// authStateChanges memulai pemantauan profil; signIn cukup menunggu emisinya.
  @override
  Future<AppUser> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return await _session.awaitUser(cred.user!.uid);
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    } on TimeoutException {
      throw const AuthException('Gagal memuat profil. Periksa koneksi lalu coba lagi.');
    }
  }

  @override
  Future<AppUser> register(String name, String email, String password) async {
    final uid = await _session.runRegistration(() => _createAccount(name, email, password));
    try {
      // Pemantauan profil sudah dimulai oleh runRegistration; tunggu emisinya.
      return await _session.awaitUser(uid);
    } on TimeoutException {
      throw const AuthException('Akun dibuat, tetapi profil belum termuat. Coba muat ulang.');
    }
  }

  /// Membuat akun dan profilnya. Dipanggil di dalam runRegistration, jadi tidak
  /// perlu (dan tidak boleh) mengurus siklus pemantauan sendiri.
  Future<String> _createAccount(String name, String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      final u = cred.user!;

      // Langkah-langkah ini tidak fatal: akun Auth sudah terbentuk.
      try {
        await u.updateDisplayName(name.trim());
      } catch (e) {
        debugPrint('updateDisplayName gagal: $e');
      }
      try {
        // Peran SELALU "user". Rules menolak peran lain.
        await _db.collection('users').doc(u.uid).set({
          'uid': u.uid,
          'name': name.trim(),
          'email': email.trim().toLowerCase(),
          'role': 'user',
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Menulis profil gagal (akan dibuat ulang saat dipantau): $e');
      }
      try {
        await u.sendEmailVerification();
      } catch (e) {
        debugPrint('Kirim email verifikasi gagal: $e');
      }
      return u.uid;
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Jangan membocorkan apakah email terdaftar.
      if (e.code == 'user-not-found') return;
      throw _map(e);
    }
  }

  @override
  Future<void> sendEmailVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    }
  }

  /// Memuat ulang status verifikasi email (berasal dari Auth, bukan dari dokumen)
  /// lalu memulai ulang pemantauan profil, yang sekaligus memulihkan diri dari
  /// galat langganan.
  @override
  Future<void> refresh() async {
    final u = _auth.currentUser;
    if (u == null) return;
    try {
      await u.reload();
      await u.getIdToken(true); // agar klaim email_verified ikut diperbarui
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    }
    _session.restart();
  }

  @override
  Future<void> deleteAccount(String password) async {
    final u = _auth.currentUser;
    if (u == null) return;
    // Selama penghapusan, dokumen profil yang hilang tidak boleh dibuat ulang.
    _session.beginDeletion();
    try {
      final cred =
          EmailAuthProvider.credential(email: u.email ?? '', password: password);
      await u.reauthenticateWithCredential(cred);

      final snap = await _db.collection('users').doc(u.uid).get();
      final status = snap.exists
          ? (byNameOrNull(ProviderStatus.values, snap.data()?['providerStatus']) ??
              ProviderStatus.none)
          : (_session.current?.providerStatus ?? ProviderStatus.none);

      await executeAccountDeletion(
        status: status,
        closeAllOwned: () => _sources.closeAllOwned(u.uid, 'akun dihapus'),
        deleteApplication: () =>
            _db.collection('provider_applications').doc(u.uid).delete(),
        deleteProfile: () => _db.collection('users').doc(u.uid).delete(),
        deleteAuth: () => u.delete(),
      );
    } on AuthException {
      _session.abortDeletion();
      rethrow;
    } on FirebaseAuthException catch (e) {
      _session.abortDeletion();
      throw _map(e);
    } on FirebaseException catch (e) {
      _session.abortDeletion();
      throw AuthException('Gagal menghapus data profil (${e.code}).');
    } catch (_) {
      _session.abortDeletion();
      rethrow;
    }
  }
}
