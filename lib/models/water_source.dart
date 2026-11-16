import 'package:flutter/material.dart';
import '../config.dart';

const kQualityWarning =
    'Dugaan masalah kualitas. Hindari konsumsi sampai diperiksa.';

/// Mencari enum berdasarkan nama; null bila nilai asing (tidak melempar).
T? byNameOrNull<T extends Enum>(List<T> values, Object? name) =>
    name is String ? values.asNameMap()[name] : null;

/// Menerima DateTime, String ISO, atau Timestamp Firestore (tanpa mengimpor
/// cloud_firestore). Null tetap null; tidak dipalsukan menjadi "sekarang".
DateTime? asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  try {
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

enum Availability { available, limited, unavailable }

enum SourceType { publicWell, distributionPost, refillStation, other }

/// Siklus hidup sumber. Hanya `published` yang terlihat publik.
enum ListingStatus { pending, published, suspended, closed, rejected }

/// Siapa yang terakhir mengonfirmasi status ketersediaan.
enum VerifiedBy { admin, provider }

/// Kesegaran data, dihitung di klien dari `verifiedAt` (tanpa server).
enum Freshness { fresh, stale, expired }

extension AvailabilityX on Availability {
  String get label => switch (this) {
        Availability.available => 'Tersedia',
        Availability.limited => 'Terbatas',
        Availability.unavailable => 'Habis',
      };

  Color get color => switch (this) {
        Availability.available => Colors.green,
        Availability.limited => Colors.orange,
        Availability.unavailable => Colors.red,
      };

  /// Warna teks/garis yang kontrasnya memadai di atas latar terang.
  Color get darkColor => switch (this) {
        Availability.available => Colors.green.shade800,
        Availability.limited => Colors.orange.shade900,
        Availability.unavailable => Colors.red.shade800,
      };

  /// Penanda selain warna (ramah buta warna).
  IconData get icon => switch (this) {
        Availability.available => Icons.check_circle,
        Availability.limited => Icons.error,
        Availability.unavailable => Icons.cancel,
      };
}

extension SourceTypeX on SourceType {
  String get label => switch (this) {
        SourceType.publicWell => 'Sumur umum',
        SourceType.distributionPost => 'Pos distribusi',
        SourceType.refillStation => 'Titik isi ulang',
        SourceType.other => 'Lainnya',
      };

  IconData get icon => switch (this) {
        SourceType.publicWell => Icons.water_drop,
        SourceType.distributionPost => Icons.local_shipping,
        SourceType.refillStation => Icons.local_drink,
        SourceType.other => Icons.place,
      };
}

extension ListingStatusX on ListingStatus {
  String get label => switch (this) {
        ListingStatus.pending => 'Menunggu verifikasi',
        ListingStatus.published => 'Tayang',
        ListingStatus.suspended => 'Ditangguhkan',
        ListingStatus.closed => 'Ditutup',
        ListingStatus.rejected => 'Ditolak',
      };

  Color get darkColor => switch (this) {
        ListingStatus.pending => Colors.orange.shade900,
        ListingStatus.published => Colors.green.shade800,
        ListingStatus.suspended => Colors.blueGrey.shade700,
        ListingStatus.closed => Colors.grey.shade700,
        ListingStatus.rejected => Colors.red.shade800,
      };

  IconData get icon => switch (this) {
        ListingStatus.pending => Icons.hourglass_top,
        ListingStatus.published => Icons.check_circle,
        ListingStatus.suspended => Icons.pause_circle,
        ListingStatus.closed => Icons.lock,
        ListingStatus.rejected => Icons.cancel,
      };
}

class WaterSource {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final SourceType type;
  final Availability availability;
  final String intendedUse;
  final String openingHours;

  /// Kapan DATA diubah. Null = tidak diketahui.
  final DateTime? updatedAt;

  /// Kapan STATUS ketersediaan terakhir dikonfirmasi. Null = belum pernah.
  final DateTime? verifiedAt;

  final bool isSimulated;

  /// Ada dugaan masalah kualitas air (dari laporan yang disetujui).
  final bool qualityFlag;

  /// Siklus hidup. `isActive` diturunkan dari sini dan keduanya SELALU ditulis
  /// bersamaan (rules memaksa `isActive == (listingStatus == 'published')`).
  final ListingStatus listingStatus;

  /// Tanpa [ownerId] = dikelola admin.
  final String? ownerId;
  final String? ownerName;
  final VerifiedBy? verifiedBy;

  /// Alasan penolakan/penangguhan dari admin.
  final String? reviewNote;

  /// Alasan dan waktu penutupan oleh penyedia.
  final String? closedReason;
  final DateTime? closedAt;

  const WaterSource({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.availability,
    required this.intendedUse,
    required this.openingHours,
    this.updatedAt,
    this.verifiedAt,
    this.isSimulated = false,
    this.qualityFlag = false,
    this.listingStatus = ListingStatus.published,
    this.ownerId,
    this.ownerName,
    this.verifiedBy,
    this.reviewNote,
    this.closedReason,
    this.closedAt,
  });

  /// false = disembunyikan dari warga.
  bool get isActive => listingStatus == ListingStatus.published;

  bool get hasOwner => ownerId != null;

  /// Kesegaran status ketersediaan. `verifiedAt == null` dihitung kedaluwarsa.
  /// [now] bisa diberikan agar dapat dites tanpa menunggu waktu.
  Freshness freshness([DateTime? now]) {
    final v = verifiedAt;
    if (v == null) return Freshness.expired;
    final age = (now ?? DateTime.now()).difference(v);
    if (age > kHideAfter) return Freshness.expired;
    if (age >= kStaleAfter) return Freshness.stale;
    return Freshness.fresh;
  }

  /// Label bila status sudah lama tidak dikonfirmasi, atau null bila masih segar.
  String? staleLabelAt([DateTime? now]) {
    final v = verifiedAt;
    if (v == null) return 'Status belum pernah dikonfirmasi';
    final age = (now ?? DateTime.now()).difference(v);
    if (age >= kStaleAfter) return 'Belum dikonfirmasi ${age.inDays} hari';
    return null;
  }

  /// Label bila status sudah lama tidak dikonfirmasi (memakai jam perangkat).
  String? get staleLabel => staleLabelAt();

  WaterSource copyWith({
    String? id,
    Availability? availability,
    String? intendedUse,
    DateTime? updatedAt,
    DateTime? verifiedAt,
    bool? qualityFlag,
    ListingStatus? listingStatus,
    VerifiedBy? verifiedBy,
    String? reviewNote,
    String? closedReason,
    DateTime? closedAt,
    // Parameter bernilai null tidak bisa mengosongkan field. Dua bendera ini
    // hanya untuk model dan tes; service Firestore memakai FieldValue.delete().
    bool clearReviewNote = false,
    bool clearClosed = false,
  }) =>
      WaterSource(
        id: id ?? this.id,
        name: name,
        address: address,
        latitude: latitude,
        longitude: longitude,
        type: type,
        availability: availability ?? this.availability,
        intendedUse: intendedUse ?? this.intendedUse,
        openingHours: openingHours,
        updatedAt: updatedAt ?? this.updatedAt,
        verifiedAt: verifiedAt ?? this.verifiedAt,
        isSimulated: isSimulated,
        qualityFlag: qualityFlag ?? this.qualityFlag,
        listingStatus: listingStatus ?? this.listingStatus,
        ownerId: ownerId,
        ownerName: ownerName,
        verifiedBy: verifiedBy ?? this.verifiedBy,
        reviewNote: clearReviewNote ? null : (reviewNote ?? this.reviewNote),
        closedReason: clearClosed ? null : (closedReason ?? this.closedReason),
        closedAt: clearClosed ? null : (closedAt ?? this.closedAt),
      );

  WaterSource withId(String newId) => copyWith(id: newId);

  /// Melempar FormatException bila `availability` tidak dikenal, agar dokumen
  /// rusak dilewati DAN dihitung (bukan ditampilkan dengan status keliru).
  ///
  /// `listingStatus` yang tidak ada diturunkan dari `isActive` (dokumen lama);
  /// nilai asing diperlakukan `suspended` (aman: tersembunyi).
  factory WaterSource.fromMap(String id, Map<String, dynamic> m) {
    final availability = byNameOrNull(Availability.values, m['availability']);
    if (availability == null) {
      throw FormatException('availability tidak dikenal: ${m['availability']}');
    }

    final rawListing = m['listingStatus'];
    final listing = rawListing == null
        ? ((m['isActive'] as bool? ?? true)
            ? ListingStatus.published
            : ListingStatus.closed)
        : (byNameOrNull(ListingStatus.values, rawListing) ??
            ListingStatus.suspended);

    return WaterSource(
      id: id,
      name: m['name'] as String,
      address: (m['address'] as String?) ?? '',
      latitude: (m['latitude'] as num).toDouble(),
      longitude: (m['longitude'] as num).toDouble(),
      type: byNameOrNull(SourceType.values, m['sourceType']) ?? SourceType.other,
      availability: availability,
      intendedUse: (m['intendedUse'] as String?) ?? '',
      openingHours: (m['openingHours'] as String?) ?? '-',
      updatedAt: asDateTime(m['updatedAt']),
      verifiedAt: asDateTime(m['verifiedAt']),
      isSimulated: m['isSimulated'] as bool? ?? false,
      qualityFlag: m['qualityFlag'] as bool? ?? false,
      listingStatus: listing,
      ownerId: m['ownerId'] as String?,
      ownerName: m['ownerName'] as String?,
      verifiedBy: byNameOrNull(VerifiedBy.values, m['verifiedBy']),
      reviewNote: m['reviewNote'] as String?,
      closedReason: m['closedReason'] as String?,
      closedAt: asDateTime(m['closedAt']),
    );
  }

  /// Tanpa stempel waktu (ditentukan service lewat serverTimestamp). Kolom
  /// opsional yang kosong DIHILANGKAN, bukan ditulis null: rules memeriksa
  /// tipe field dan null akan ditolak. `listingStatus` dan `isActive` selalu
  /// ditulis bersamaan.
  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'sourceType': type.name,
        'availability': availability.name,
        'intendedUse': intendedUse,
        'openingHours': openingHours,
        'isSimulated': isSimulated,
        'qualityFlag': qualityFlag,
        'listingStatus': listingStatus.name,
        'isActive': isActive,
        if (ownerId != null) 'ownerId': ownerId,
        if (ownerName != null) 'ownerName': ownerName,
        if (verifiedBy != null) 'verifiedBy': verifiedBy!.name,
        if (reviewNote != null && reviewNote!.isNotEmpty) 'reviewNote': reviewNote,
        if (closedReason != null && closedReason!.isNotEmpty)
          'closedReason': closedReason,
        if (closedAt != null) 'closedAt': closedAt,
      };
}
