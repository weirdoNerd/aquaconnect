import 'dart:async';
import 'dart:math' as math;
import '../models/water_source.dart';
import '../services/source_service.dart';
import 'dummy_sources.dart';

/// Penyimpanan TIRUAN di memori. Jangan dipakai di rilis.
///
/// Operasi penyedia MENIRU rules, tetapi hanya untuk perilaku yang sudah diuji di
/// emulator (lihat rules_test): penyedia hanya bisa menyentuh sumber miliknya,
/// updateOperational/confirmStillCurrent hanya untuk sumber tayang, closeOwned
/// hanya dari pending/rejected/published, alasan tutup minimal 3 karakter.
/// Identitas pemanggil diatur lewat [actAs]. Di mode tiruan aplikasi, [actAs]
/// tersambung ke MockAuthService.authChanges di Bootstrap (lib/main.dart).
/// Jalur admin tidak dibatasi agar alur admin mode tiruan yang ada tetap jalan.
class MockSourceService implements SourceService {
  final List<WaterSource> _list = List.of(dummySources);
  final Map<String, Map<String, dynamic>> _legacyRaw = {};
  final _ctrl = StreamController<SourceBatch>.broadcast();
  String? _actingUid;
  int _seq = 0;

  /// Ukuran tiap batch yang di-commit, berurutan (untuk tes potongan).
  final List<int> batchSizes = [];

  /// Bila diisi, batch ke-(N+1) dan seterusnya gagal (meniru kegagalan sebagian).
  int? failAfterBatches;

  /// Menambahkan dokumen mentah lama untuk menguji migrasi & pratinjau S11.
  void seedLegacyRaw(String id, Map<String, dynamic> data) =>
      _legacyRaw[id] = Map<String, dynamic>.from(data);

  /// Membaca dokumen mentah lama (untuk verifikasi tes S11).
  Map<String, dynamic>? legacyRawOf(String id) => _legacyRaw[id];

  /// Atur siapa yang "login" untuk operasi penyedia. Null = belum login.
  void actAs(String? uid) => _actingUid = uid;

  SourceBatch _batchOf(bool Function(WaterSource s) test) =>
      SourceBatch(List.unmodifiable(_list.where(test)));

  Stream<SourceBatch> _watch(bool Function(WaterSource s) test) async* {
    yield _batchOf(test);
    yield* _ctrl.stream.map((_) => _batchOf(test));
  }

  void _emit() => _ctrl.add(const SourceBatch([]));

  String _newId() => 'src-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  static const _denied = SourceException('Tidak ada izin untuk operasi ini.');

  /// Indeks sumber milik pemanggil; menolak bila tidak ada atau milik orang lain.
  int _owned(String id) {
    final i = _list.indexWhere((s) => s.id == id);
    if (i < 0) throw const SourceException('Data sumber air tidak ditemukan.');
    if (_actingUid == null || _list[i].ownerId != _actingUid) throw _denied;
    return i;
  }

  WaterSource _patch(
    WaterSource o, {
    Availability? availability,
    String? openingHours,
    DateTime? updatedAt,
    DateTime? verifiedAt,
    VerifiedBy? verifiedBy,
    bool? qualityFlag,
    ListingStatus? listingStatus,
    String? reviewNote,
    bool clearReviewNote = false,
    String? closedReason,
    DateTime? closedAt,
    bool clearClosed = false,
  }) =>
      WaterSource(
        id: o.id,
        name: o.name,
        address: o.address,
        latitude: o.latitude,
        longitude: o.longitude,
        type: o.type,
        availability: availability ?? o.availability,
        intendedUse: o.intendedUse,
        openingHours: openingHours ?? o.openingHours,
        updatedAt: updatedAt ?? o.updatedAt,
        verifiedAt: verifiedAt ?? o.verifiedAt,
        isSimulated: o.isSimulated,
        qualityFlag: qualityFlag ?? o.qualityFlag,
        listingStatus: listingStatus ?? o.listingStatus,
        ownerId: o.ownerId,
        ownerName: o.ownerName,
        verifiedBy: verifiedBy ?? o.verifiedBy,
        reviewNote: clearReviewNote ? null : (reviewNote ?? o.reviewNote),
        closedReason: clearClosed ? null : (closedReason ?? o.closedReason),
        closedAt: clearClosed ? null : (closedAt ?? o.closedAt),
      );

  /// Menerapkan [apply] per batch berisi paling banyak [kWriteChunk] id. Satu batch
  /// atomik; kegagalan terjadi di antara batch (seperti Firestore).
  int _chunked(List<String> ids, void Function(String id) apply) {
    var done = 0;
    var batches = 0;
    for (var i = 0; i < ids.length; i += kWriteChunk) {
      if (failAfterBatches != null && batches >= failAfterBatches!) {
        throw SourceBatchException('Simulasi kegagalan batch.',
            done: done, remaining: ids.length - done);
      }
      final chunk = ids.sublist(i, math.min(i + kWriteChunk, ids.length));
      for (final id in chunk) {
        apply(id);
      }
      batchSizes.add(chunk.length);
      batches++;
      done += chunk.length;
      _emit();
    }
    return done;
  }

  // ---------------- baca ----------------

  @override
  Stream<SourceBatch> watchAll() => _watch((_) => true);

  @override
  Stream<SourceBatch> watchPublished() => _watch((s) => s.isActive);

  @override
  Stream<SourceBatch> watchOwned(String uid) => _watch((s) => s.ownerId == uid);

  // ---------------- admin (jalur lama) ----------------

  @override
  Future<void> applyUpdate(SourceUpdate u) async {
    final i = _list.indexWhere((s) => s.id == u.sourceId);
    if (i < 0) return;
    final now = DateTime.now();
    _list[i] = _patch(
      _list[i],
      availability: u.availability,
      qualityFlag: u.markQualityConcern ? true : null,
      listingStatus: u.suspend ? ListingStatus.suspended : null,
      updatedAt: now,
      verifiedAt: now,
      verifiedBy: VerifiedBy.admin,
    );
    _emit();
  }

  @override
  Future<void> create(WaterSource source) async {
    final now = DateTime.now();
    _list.add(source.withId(_newId()).copyWith(
          updatedAt: now,
          verifiedAt: now,
          verifiedBy: VerifiedBy.admin,
        ));
    _emit();
  }

  @override
  Future<void> update(WaterSource source, {bool confirmStatus = false}) async {
    final i = _list.indexWhere((s) => s.id == source.id);
    if (i < 0) return;
    final now = DateTime.now();
    final old = _list[i];
    // Kepemilikan dan catatan tinjauan tidak diubah lewat form admin.
    _list[i] = WaterSource(
      id: source.id,
      name: source.name,
      address: source.address,
      latitude: source.latitude,
      longitude: source.longitude,
      type: source.type,
      availability: source.availability,
      intendedUse: source.intendedUse,
      openingHours: source.openingHours,
      updatedAt: now,
      verifiedAt: confirmStatus ? now : old.verifiedAt,
      isSimulated: source.isSimulated,
      qualityFlag: source.qualityFlag,
      listingStatus: source.listingStatus,
      ownerId: old.ownerId,
      ownerName: old.ownerName,
      verifiedBy: confirmStatus ? VerifiedBy.admin : old.verifiedBy,
      reviewNote: old.reviewNote,
      closedReason: old.closedReason,
      closedAt: old.closedAt,
    );
    _emit();
  }

  @override
  Future<int> seed(List<WaterSource> sources) async => 0;

  // ---------------- penyedia ----------------

  @override
  Future<void> createAsProvider(
      WaterSource source, String uid, String ownerName) async {
    if (_actingUid == null || _actingUid != uid) throw _denied;
    if (ownerName.trim().isEmpty) {
      throw const SourceException('Nama usaha penyedia belum tersedia.');
    }
    final now = DateTime.now();
    _list.add(WaterSource(
      id: _newId(),
      name: source.name,
      address: source.address,
      latitude: source.latitude,
      longitude: source.longitude,
      type: source.type,
      availability: source.availability,
      intendedUse: source.intendedUse,
      openingHours: source.openingHours,
      updatedAt: now,
      verifiedAt: now,
      // Dipaksa seperti di service Firestore: tidak bisa memalsukan tanda ini.
      isSimulated: false,
      qualityFlag: false,
      listingStatus: ListingStatus.pending,
      ownerId: uid,
      ownerName: ownerName,
      verifiedBy: VerifiedBy.provider,
    ));
    _emit();
  }

  @override
  Future<void> resubmit(WaterSource source) async {
    final i = _owned(source.id);
    final old = _list[i];
    final canResubmit = old.listingStatus == ListingStatus.rejected ||
        old.listingStatus == ListingStatus.pending;
    final srcAllowed = source.listingStatus == ListingStatus.rejected ||
        source.listingStatus == ListingStatus.pending;
    if (!canResubmit || !srcAllowed) {
      throw const SourceException(
          'Hanya sumber menunggu verifikasi atau ditolak yang bisa diubah di jalur ini.');
    }
    final now = DateTime.now();
    _list[i] = WaterSource(
      id: old.id,
      name: source.name,
      address: source.address,
      latitude: source.latitude,
      longitude: source.longitude,
      type: source.type,
      availability: source.availability,
      intendedUse: source.intendedUse,
      openingHours: source.openingHours,
      updatedAt: now,
      verifiedAt: now,
      isSimulated: old.isSimulated,
      qualityFlag: old.qualityFlag,
      listingStatus: ListingStatus.pending,
      ownerId: old.ownerId,
      ownerName: old.ownerName,
      verifiedBy: VerifiedBy.provider,
      // reviewNote dihapus
      closedReason: old.closedReason,
      closedAt: old.closedAt,
    );
    _emit();
  }

  @override
  Future<void> updateOperational(String id,
      {Availability? availability, String? openingHours}) async {
    if (availability == null && openingHours == null) {
      throw const SourceException('Tidak ada perubahan untuk disimpan.');
    }
    final hours = openingHours?.trim();
    if (hours != null && hours.length > 50) {
      throw const SourceException('Jam layanan maksimal 50 karakter.');
    }
    final i = _owned(id);
    final old = _list[i];
    // Meniru rules: jalur (b) hanya untuk sumber yang sudah tayang.
    if (old.listingStatus != ListingStatus.published) throw _denied;
    final now = DateTime.now();
    final changed = availability != null && availability != old.availability;
    _list[i] = _patch(
      old,
      availability: availability,
      openingHours: hours == null ? null : (hours.isEmpty ? '-' : hours),
      updatedAt: now,
      verifiedAt: changed ? now : null,
      verifiedBy: changed ? VerifiedBy.provider : null,
    );
    _emit();
  }

  @override
  Future<void> confirmStillCurrent(String id) async {
    final i = _owned(id);
    final old = _list[i];
    if (old.listingStatus != ListingStatus.published) throw _denied;
    final now = DateTime.now();
    _list[i] = _patch(old,
        updatedAt: now, verifiedAt: now, verifiedBy: VerifiedBy.provider);
    _emit();
  }

  WaterSource _closed(WaterSource o, String reason, DateTime now) => _patch(
        o,
        listingStatus: ListingStatus.closed,
        closedReason: reason,
        closedAt: now,
        updatedAt: now,
      );

  @override
  Future<void> closeOwned(String id, String reason) async {
    final r = validateCloseReason(reason);
    final i = _owned(id);
    // Meniru rules: hanya dari pending, rejected, atau published.
    if (!kProviderClosable.contains(_list[i].listingStatus)) throw _denied;
    _list[i] = _closed(_list[i], r, DateTime.now());
    _emit();
  }

  @override
  Future<int> closeAllOwned(String uid, String reason) async {
    if (_actingUid == null || _actingUid != uid) throw _denied;
    final r = validateCloseReason(reason);
    final ids = [
      for (final s in _list)
        if (s.ownerId == uid && kProviderClosable.contains(s.listingStatus)) s.id,
    ];
    return _chunked(ids, (id) {
      final i = _list.indexWhere((s) => s.id == id);
      _list[i] = _closed(_list[i], r, DateTime.now());
    });
  }

  // ---------------- admin (baru) ----------------

  @override
  Future<void> setListing(String id, ListingStatus status,
      {String note = ''}) async {
    final n = validateListingNote(status, note);
    final i = _list.indexWhere((s) => s.id == id);
    if (i < 0) throw const SourceException('Data sumber air tidak ditemukan.');
    final now = DateTime.now();
    final o = _list[i];
    _list[i] = switch (status) {
      ListingStatus.published => _patch(o,
          listingStatus: status,
          updatedAt: now,
          verifiedAt: now,
          verifiedBy: VerifiedBy.admin,
          clearReviewNote: true,
          clearClosed: true),
      ListingStatus.pending =>
        _patch(o, listingStatus: status, updatedAt: now, clearClosed: true),
      ListingStatus.rejected =>
        _patch(o, listingStatus: status, updatedAt: now, reviewNote: n),
      ListingStatus.suspended || ListingStatus.closed => _patch(o,
          listingStatus: status,
          updatedAt: now,
          reviewNote: n.isEmpty ? null : n),
    };
    _emit();
  }

  @override
  Future<int> suspendAllOwned(String uid) async {
    final ids = [
      for (final s in _list)
        if (s.ownerId == uid && kSuspendable.contains(s.listingStatus)) s.id,
    ];
    return _chunked(ids, (id) {
      final i = _list.indexWhere((s) => s.id == id);
      _list[i] = _patch(_list[i],
          listingStatus: ListingStatus.suspended, updatedAt: DateTime.now());
    });
  }

  @override
  Future<int> countLegacySources() async {
    var count = 0;
    for (final raw in _legacyRaw.values) {
      if (legacyMigrationPatch(raw) != null) count++;
    }
    return count;
  }

  @override
  Future<int> migrateLegacySources() async {
    final patches = <String, Map<String, dynamic>>{};
    _legacyRaw.forEach((id, raw) {
      final p = legacyMigrationPatch(raw);
      if (p != null) patches[id] = p;
    });
    if (patches.isEmpty) return 0;
    return _chunked(patches.keys.toList(), (id) {
      final patch = patches[id];
      if (patch != null && _legacyRaw.containsKey(id)) {
        _legacyRaw[id] = {..._legacyRaw[id]!, ...patch};
      }
    });
  }
}
