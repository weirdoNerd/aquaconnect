import 'app_user.dart';

/// Ringkasan penyedia untuk admin (dari dokumen `users`). Tidak memuat telepon.
class ProviderProfile {
  final String uid;
  final String name;
  final String email;
  final ProviderStatus status;
  final String? note;
  final DateTime? reviewedAt;

  const ProviderProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.status,
    this.note,
    this.reviewedAt,
  });

  ProviderProfile copyWith({
    ProviderStatus? status,
    String? note,
    bool clearNote = false,
    DateTime? reviewedAt,
  }) =>
      ProviderProfile(
        uid: uid,
        name: name,
        email: email,
        status: status ?? this.status,
        note: clearNote ? null : (note ?? this.note),
        reviewedAt: reviewedAt ?? this.reviewedAt,
      );
}
