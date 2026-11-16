import 'water_source.dart';

enum ApplicationStatus { pending, approved, rejected }

extension ApplicationStatusX on ApplicationStatus {
  String get label => switch (this) {
        ApplicationStatus.pending => 'Menunggu peninjauan admin',
        ApplicationStatus.approved => 'Disetujui',
        ApplicationStatus.rejected => 'Ditolak',
      };
}

/// Pengajuan menjadi penyedia (satu per pengguna, id dokumen = uid).
/// Hanya pemilik dan admin yang dapat membacanya (rules).
class ProviderApplication {
  final String uid;
  final String organizationName;
  final String contactPhone;
  final String description;
  final int termsVersion;
  final ApplicationStatus status;
  final String adminNote;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  const ProviderApplication({
    required this.uid,
    required this.organizationName,
    required this.contactPhone,
    required this.description,
    required this.termsVersion,
    this.status = ApplicationStatus.pending,
    this.adminNote = '',
    this.createdAt,
    this.reviewedAt,
  });

  /// Harus sama dengan `validApplication()` di firestore.rules.
  static final _phone = RegExp(r'^[0-9+ ]{6,20}$');
  static bool isValidPhone(String s) => _phone.hasMatch(s);

  factory ProviderApplication.fromMap(String uid, Map<String, dynamic> m) =>
      ProviderApplication(
        uid: uid,
        organizationName: (m['organizationName'] as String?) ?? '',
        contactPhone: (m['contactPhone'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        termsVersion: (m['termsVersion'] as num?)?.toInt() ?? 0,
        // Nilai asing tidak memberi hak apa pun; tampilkan sebagai menunggu.
        status: byNameOrNull(ApplicationStatus.values, m['status']) ??
            ApplicationStatus.pending,
        adminNote: (m['adminNote'] as String?) ?? '',
        createdAt: asDateTime(m['createdAt']),
        reviewedAt: asDateTime(m['reviewedAt']),
      );

  /// Untuk membuat/mengajukan ulang. `createdAt` ditambahkan service
  /// (serverTimestamp); status selalu pending dan catatan kosong.
  Map<String, dynamic> toSubmitMap() => {
        'uid': uid,
        'organizationName': organizationName.trim(),
        'contactPhone': contactPhone.trim(),
        'description': description.trim(),
        'termsVersion': termsVersion,
        'status': 'pending',
        'adminNote': '',
      };
}
