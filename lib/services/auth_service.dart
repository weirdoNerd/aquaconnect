import 'dart:async';
import '../models/app_user.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Kontrak autentikasi. UI hanya bergantung pada kelas ini.
abstract class AuthService {
  AppUser? get currentUser;
  Stream<AppUser?> get authChanges;
  Future<AppUser> signIn(String email, String password);
  Future<AppUser> register(String name, String email, String password);
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);
  Future<void> sendEmailVerification();

  /// Memuat ulang profil dan status verifikasi email.
  Future<void> refresh();

  /// Reautentikasi, hapus profil, lalu hapus akun.
  Future<void> deleteAccount(String password);
}
