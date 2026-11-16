import 'app_user.dart';

/// Ringkasan penyedia untuk admin (dari dokumen `users`). Tidak memuat telepon.
class ProviderProfile {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final ProviderStatus status;
  final String? note;
  final DateTime? reviewedAt;

  const ProviderProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.role = UserRole.user,
    required this.status,
    this.note,
    this.reviewedAt,
  });

  bool get isAdmin => role == UserRole.admin;

  ProviderProfile copyWith({
    UserRole? role,
    ProviderStatus? status,
    String? note,
    bool clearNote = false,
    DateTime? reviewedAt,
  }) =>
      ProviderProfile(
        uid: uid,
        name: name,
        email: email,
        role: role ?? this.role,
        status: status ?? this.status,
        note: clearNote ? null : (note ?? this.note),
        reviewedAt: reviewedAt ?? this.reviewedAt,
      );
}
