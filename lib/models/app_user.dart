enum UserRole { user, admin }

/// Status kemitraan penyedia. Hanya admin yang boleh mengubahnya (rules).
enum ProviderStatus { none, active, terminated }

class AppUser {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final bool emailVerified;

  /// false bila profil gagal dibaca (mis. offline). Peran sementara "user"
  /// dan UI menawarkan muat ulang, jadi admin tidak diturunkan diam-diam.
  final bool profileLoaded;

  final ProviderStatus providerStatus;

  /// Alasan admin (mis. saat pemutusan kemitraan), bila ada.
  final String? providerNote;

  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    this.role = UserRole.user,
    this.emailVerified = true,
    this.profileLoaded = true,
    this.providerStatus = ProviderStatus.none,
    this.providerNote,
  });

  AppUser copyWith({
    UserRole? role,
    bool? emailVerified,
    bool? profileLoaded,
    ProviderStatus? providerStatus,
    String? providerNote,
    bool clearProviderNote = false,
  }) =>
      AppUser(
        uid: uid,
        name: name,
        email: email,
        role: role ?? this.role,
        emailVerified: emailVerified ?? this.emailVerified,
        profileLoaded: profileLoaded ?? this.profileLoaded,
        providerStatus: providerStatus ?? this.providerStatus,
        providerNote: clearProviderNote ? null : (providerNote ?? this.providerNote),
      );

  bool get isAdmin => role == UserRole.admin;
  bool get isProvider => providerStatus == ProviderStatus.active;
}
