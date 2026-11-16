import '../config.dart';
import '../models/provider_application.dart';
import '../models/provider_profile.dart';

class ProviderException implements Exception {
  final String message;

  /// Bila pemutusan kemitraan selesai tetapi penangguhan sumber belum tuntas:
  /// jumlah sumber yang belum ditangguhkan (null = tidak diketahui).
  final int? remaining;

  const ProviderException(this.message, {this.remaining});
  @override
  String toString() => message;
}

/// Validasi pengajuan: batas sama dengan `validApplication()` di firestore.rules.
/// Mengembalikan pesan galat, atau null bila valid.
String? validateApplication(ProviderApplication a) {
  final org = a.organizationName.trim();
  final desc = a.description.trim();
  if (org.length < 3 || org.length > 80) {
    return 'Nama usaha atau komunitas 3-80 karakter.';
  }
  if (!ProviderApplication.isValidPhone(a.contactPhone.trim())) {
    return 'Nomor telepon 6-20 karakter (angka, + dan spasi saja).';
  }
  if (desc.length < 10 || desc.length > 300) {
    return 'Deskripsi 10-300 karakter.';
  }
  if (a.termsVersion != kProviderTermsVersion) {
    return 'Versi ketentuan tidak sesuai. Muat ulang ketentuan terbaru.';
  }
  return null;
}

/// Catatan admin pada tinjauan dan pemutusan: penolakan/pemutusan >= 5, semua <= 200.
String validateAdminNote(String note, {required bool required}) {
  final n = note.trim();
  if (n.length > 200) {
    throw const ProviderException('Catatan maksimal 200 karakter.');
  }
  if (required && n.length < 5) {
    throw const ProviderException('Alasan wajib diisi (min. 5 karakter).');
  }
  return n;
}

abstract class ProviderService {
  /// Pengajuan milik [uid] (realtime); null bila belum pernah mengajukan.
  Stream<ProviderApplication?> watchMyApplication(String uid);

  /// Membuat pengajuan baru, atau mengajukan ulang bila sebelumnya ditolak.
  Future<void> apply(ProviderApplication application);

  // ---------------- admin ----------------

  /// Pengajuan yang menunggu tinjauan (tertua dulu).
  Stream<List<ProviderApplication>> watchPending();

  /// Pengguna berstatus penyedia `active` atau `terminated`.
  Future<List<ProviderProfile>> fetchProviders();

  /// Meninjau pengajuan dalam SATU batch: pengajuan + status penyedia di profil.
  /// Penolakan wajib bercatatan (>= 5 karakter).
  Future<void> review(String uid, {required bool approve, String note = ''});

  /// Memutus kemitraan: (1) tulis providerStatus=terminated DAHULU, (2) baru
  /// tangguhkan semua sumbernya. Bila (2) gagal sebagian, langkah (1) TIDAK
  /// dibatalkan dan [ProviderException.remaining] menyebut sisanya; panggil lagi
  /// untuk menuntaskan (aman diulang).
  Future<void> terminate(String uid, String reason);

  /// Mengaktifkan kembali penyedia (providerStatus=active) dan menghapus
  /// catatan pemutusan lama. Sumber yang sudah ditangguhkan tidak otomatis
  /// tayang; admin menayangkannya satu per satu.
  Future<void> reactivate(String uid);
}
