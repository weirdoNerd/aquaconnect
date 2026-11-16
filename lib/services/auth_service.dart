import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import 'source_service.dart';

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

  /// Reautentikasi, tutup sumber penyedia aktif (bila ada), hapus pengajuan
  /// dan profil (kecuali penyedia terputus), lalu hapus akun.
  Future<void> deleteAccount(String password);
}

/// Menjalankan urutan penghapusan akun yang aman sesuai [status] penyedia dan
/// aturan Firestore:
/// - `active`: tutup semua sumber (`closeAllOwned`) dahulu; bila gagal batalkan
///   sebelum menghapus dokumen/akun.
/// - `terminated`: lewati penghapusan pengajuan dan profil (dilarang rules),
///   hapus hanya akun Auth.
/// - lainnya: hapus pengajuan (kegagalan karena belum ada/ditolak non-fatal),
///   hapus profil, lalu hapus akun Auth.
Future<void> executeAccountDeletion({
  required ProviderStatus status,
  required Future<void> Function() closeAllOwned,
  required Future<void> Function() deleteApplication,
  required Future<void> Function() deleteProfile,
  required Future<void> Function() deleteAuth,
}) async {
  if (status == ProviderStatus.terminated) {
    await deleteAuth();
    return;
  }
  if (status == ProviderStatus.active) {
    try {
      await closeAllOwned();
    } on SourceBatchException catch (e) {
      throw AuthException(
        'Gagal menutup semua sumber air (${e.done} ditutup, ${e.remaining} tersisa). '
        'Akun belum dihapus, silakan coba lagi.',
      );
    } on SourceException catch (e) {
      throw AuthException(
        'Gagal menutup sumber air: ${e.message} Akun belum dihapus.',
      );
    }
  }
  try {
    await deleteApplication();
  } catch (e) {
    debugPrint('deleteApplication diabaikan (non-fatal): $e');
  }
  await deleteProfile();
  await deleteAuth();
}
