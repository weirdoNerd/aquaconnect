import '../models/water_source.dart';

class SourceException implements Exception {
  final String message;
  const SourceException(this.message);
  @override
  String toString() => message;
}

/// Penulisan dalam potongan berhenti di tengah: [done] dokumen sudah tertulis,
/// [remaining] belum. Operasi aman diulang (hanya menyentuh yang belum selesai).
class SourceBatchException extends SourceException {
  final int done;
  final int remaining;
  const SourceBatchException(super.message,
      {required this.done, required this.remaining});
}

/// Hasil satu emisi stream sumber air.
class SourceBatch {
  final List<WaterSource> sources;

  /// Jumlah dokumen yang formatnya rusak dan dilewati.
  final int skipped;

  /// true bila data berasal dari cache lokal (mungkin tidak terbaru).
  final bool fromCache;

  const SourceBatch(this.sources, {this.skipped = 0, this.fromCache = false});
}

/// Perubahan data sumber air akibat laporan yang disetujui.
class SourceUpdate {
  final String sourceId;
  final Availability? availability;
  final bool markQualityConcern;

  /// true = sumber ditangguhkan (listingStatus suspended + isActive false,
  /// ditulis bersamaan). UI-nya baru di S10; di sini cukup datanya.
  final bool suspend;

  const SourceUpdate({
    required this.sourceId,
    this.availability,
    this.markQualityConcern = false,
    this.suspend = false,
  });
}

/// Batas penulisan per batch. Ditentukan oleh batas akses dokumen di rules.
const int kWriteChunk = 8;

/// Status yang boleh ditutup penyedia (jalur (c) di rules). `suspended` TIDAK
/// termasuk: penyedia tidak bisa menutup sumber yang ditangguhkan admin.
const Set<ListingStatus> kProviderClosable = {
  ListingStatus.pending,
  ListingStatus.rejected,
  ListingStatus.published,
};

/// Status yang ditangguhkan saat penyedia diputus.
const Set<ListingStatus> kSuspendable = {
  ListingStatus.published,
  ListingStatus.pending,
};

/// Alasan penutupan: 3-200 karakter (sama dengan rules). Mengembalikan yang sudah dipangkas.
String validateCloseReason(String reason) {
  final r = reason.trim();
  if (r.length < 3) {
    throw const SourceException('Alasan penutupan minimal 3 karakter.');
  }
  if (r.length > 200) {
    throw const SourceException('Alasan penutupan maksimal 200 karakter.');
  }
  return r;
}

/// Catatan admin: wajib >= 5 karakter untuk penolakan, maksimal 200 karakter.
String validateListingNote(ListingStatus status, String note) {
  final n = note.trim();
  if (n.length > 200) {
    throw const SourceException('Catatan maksimal 200 karakter.');
  }
  if (status == ListingStatus.rejected && n.length < 5) {
    throw const SourceException('Alasan penolakan wajib diisi (min. 5 karakter).');
  }
  return n;
}

abstract class SourceService {
  /// HANYA admin: rules menolak query tanpa filter untuk non-admin.
  Stream<SourceBatch> watchAll();

  /// Sumber tayang (`isActive == true`). Untuk tamu, warga, dan penyedia.
  Stream<SourceBatch> watchPublished();

  /// Sumber milik [uid] (`ownerId == uid`), termasuk yang belum tayang.
  Stream<SourceBatch> watchOwned(String uid);

  /// Dipakai saat laporan disetujui: status dikonfirmasi admin
  /// (`verifiedAt` dan `verifiedBy: admin` ditulis bersamaan).
  Future<void> applyUpdate(SourceUpdate update);

  /// Admin menambah sumber baru (id diberikan layanan).
  Future<void> create(WaterSource source);

  /// Admin mengubah data. `verifiedAt` dan `verifiedBy: admin` hanya
  /// diperbarui bila [confirmStatus] true.
  Future<void> update(WaterSource source, {bool confirmStatus = false});

  /// Mengunggah data contoh bila koleksi kosong. Mengembalikan jumlah ditulis.
  Future<int> seed(List<WaterSource> sources);

  // ---------------- penyedia aktif ----------------

  /// Membuat sumber berstatus pending. [ownerName] harus sama dengan nama usaha
  /// pada pengajuan yang disetujui. Bidang sensitif dipaksa: tanpa qualityFlag,
  /// isSimulated, reviewNote, closedReason, closedAt.
  Future<void> createAsProvider(WaterSource source, String uid, String ownerName);

  /// Mengajukan ulang sumber yang belum tayang (`rejected` atau `pending`) dengan
  /// data yang sudah diperbaiki. Catatan penolakan dihapus dan status menjadi
  /// `pending`.
  Future<void> resubmit(WaterSource source);

  /// Hanya data operasional sumber yang SUDAH tayang. Tidak pernah menulis
  /// intendedUse, nama, atau koordinat. Mengubah availability = wajib konfirmasi
  /// (verifiedAt dan verifiedBy: provider).
  Future<void> updateOperational(String id,
      {Availability? availability, String? openingHours});

  /// "Masih beroperasi": memperbarui verifiedAt tanpa mengubah availability.
  Future<void> confirmStillCurrent(String id);

  /// Menutup sumber sendiri. [reason] minimal 3 karakter.
  Future<void> closeOwned(String id, String reason);

  /// Menutup semua sumber milik [uid] yang dapat ditutup penyedia
  /// (pending, rejected, published), per potongan [kWriteChunk]. Mengembalikan
  /// jumlah yang ditutup.
  Future<int> closeAllOwned(String uid, String reason);

  // ---------------- admin ----------------

  /// Mengubah siklus hidup. SELALU menulis listingStatus dan isActive bersamaan.
  Future<void> setListing(String id, ListingStatus status, {String note = ''});

  /// Menangguhkan semua sumber milik [uid] yang published atau pending, per
  /// potongan [kWriteChunk]. Mengembalikan jumlah yang ditangguhkan.
  Future<int> suspendAllOwned(String uid);
}
