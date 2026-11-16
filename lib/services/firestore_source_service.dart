import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/water_source.dart';
import 'source_service.dart';

class FirestoreSourceService implements SourceService {
  final FirebaseFirestore _db;
  FirestoreSourceService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('water_sources');

  static FieldValue get _now => FieldValue.serverTimestamp();

  String _message(String code) => switch (code) {
        'permission-denied' =>
          'Tidak ada izin. Pastikan akunmu berhak dan data valid.',
        'unavailable' || 'deadline-exceeded' =>
          'Tidak ada koneksi ke server. Coba lagi.',
        'not-found' => 'Data sumber air tidak ditemukan.',
        _ => 'Terjadi kesalahan pada server ($code).',
      };

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw SourceException(_message(e.code));
    }
  }

  SourceBatch _toBatch(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = <WaterSource>[];
    var skipped = 0;
    for (final d in snap.docs) {
      try {
        list.add(WaterSource.fromMap(d.id, d.data()));
      } catch (e) {
        skipped++;
        debugPrint('Melewati sumber air ${d.id}: $e');
      }
    }
    return SourceBatch(list,
        skipped: skipped, fromCache: snap.metadata.isFromCache);
  }

  // ---------------- baca ----------------

  @override
  Stream<SourceBatch> watchAll() =>
      _col.snapshots(includeMetadataChanges: true).map(_toBatch);

  @override
  Stream<SourceBatch> watchPublished() => _col
      .where('isActive', isEqualTo: true)
      .snapshots(includeMetadataChanges: true)
      .map(_toBatch);

  @override
  Stream<SourceBatch> watchOwned(String uid) => _col
      .where('ownerId', isEqualTo: uid)
      .snapshots(includeMetadataChanges: true)
      .map(_toBatch);

  // ---------------- admin (jalur lama) ----------------
  // SEMUA jalur admin yang menulis verifiedAt juga menulis verifiedBy: admin.

  @override
  Future<void> applyUpdate(SourceUpdate u) => _guard(() => _col.doc(u.sourceId).update({
        if (u.availability != null) 'availability': u.availability!.name,
        if (u.markQualityConcern) 'qualityFlag': true,
        if (u.suspend) ...{'listingStatus': 'suspended', 'isActive': false},
        'updatedAt': _now,
        'verifiedAt': _now,
        'verifiedBy': 'admin',
      }));

  @override
  Future<void> create(WaterSource source) => _guard(() => _col.add({
        ...source.toMap(),
        'updatedAt': _now,
        'verifiedAt': _now,
        'verifiedBy': 'admin',
      }));

  @override
  Future<void> update(WaterSource source, {bool confirmStatus = false}) =>
      _guard(() => _col.doc(source.id).update({
            ...source.toMap(),
            'updatedAt': _now,
            if (confirmStatus) ...{'verifiedAt': _now, 'verifiedBy': 'admin'},
          }));

  @override
  Future<int> seed(List<WaterSource> sources) => _guard(() async {
        final existing = await _col.limit(1).get();
        if (existing.docs.isNotEmpty) return 0;
        final batch = _db.batch();
        for (final s in sources) {
          batch.set(_col.doc(s.id), {
            ...s.toMap(),
            if (s.updatedAt != null) 'updatedAt': s.updatedAt,
            if (s.verifiedAt != null) 'verifiedAt': s.verifiedAt,
          });
        }
        await batch.commit();
        return sources.length;
      });

  // ---------------- penyedia ----------------

  @override
  Future<void> createAsProvider(
          WaterSource source, String uid, String ownerName) =>
      _guard(() async {
        if (ownerName.trim().isEmpty) {
          throw const SourceException('Nama usaha penyedia belum tersedia.');
        }
        // Dasar dari toMap(), lalu field sensitif DIPAKSA agar lolos providerNew().
        final data = Map<String, dynamic>.from(source.toMap())
          ..remove('reviewNote')
          ..remove('closedReason')
          ..remove('closedAt');
        await _col.add({
          ...data,
          'isSimulated': false,
          'qualityFlag': false,
          'listingStatus': 'pending',
          'isActive': false,
          'ownerId': uid,
          'ownerName': ownerName,
          'verifiedBy': 'provider',
          'updatedAt': _now,
          'verifiedAt': _now,
        });
      });

  @override
  Future<void> resubmit(WaterSource s) => _guard(() async {
        if (s.listingStatus != ListingStatus.rejected &&
            s.listingStatus != ListingStatus.pending) {
          throw const SourceException(
              'Hanya sumber menunggu verifikasi atau ditolak yang bisa diubah di jalur ini.');
        }
        // Hanya field pada daftar jalur (a) di rules. ownerId, qualityFlag, dan
        // isSimulated sengaja tidak ditulis.
        await _col.doc(s.id).update({
          'name': s.name,
          'address': s.address,
          'latitude': s.latitude,
          'longitude': s.longitude,
          'sourceType': s.type.name,
          'availability': s.availability.name,
          'intendedUse': s.intendedUse,
          'openingHours': s.openingHours,
          'listingStatus': 'pending',
          'isActive': false,
          'verifiedBy': 'provider',
          'verifiedAt': _now,
          'reviewNote': FieldValue.delete(),
          'updatedAt': _now,
        });
      });

  @override
  Future<void> updateOperational(String id,
          {Availability? availability, String? openingHours}) =>
      _guard(() async {
        if (availability == null && openingHours == null) {
          throw const SourceException('Tidak ada perubahan untuk disimpan.');
        }
        final hours = openingHours?.trim();
        if (hours != null && hours.length > 50) {
          throw const SourceException('Jam layanan maksimal 50 karakter.');
        }
        final ref = _col.doc(id);
        // Perlu membaca nilai sekarang: konfirmasi hanya wajib bila availability BERUBAH.
        await _db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          final data = snap.data();
          if (data == null) {
            throw const SourceException('Data sumber air tidak ditemukan.');
          }
          final changed =
              availability != null && data['availability'] != availability.name;
          tx.update(ref, {
            if (availability != null) 'availability': availability.name,
            if (hours != null) 'openingHours': hours.isEmpty ? '-' : hours,
            'updatedAt': _now,
            if (changed) ...{'verifiedAt': _now, 'verifiedBy': 'provider'},
          });
        });
      });

  @override
  Future<void> confirmStillCurrent(String id) => _guard(() => _col.doc(id).update({
        'updatedAt': _now,
        'verifiedAt': _now,
        'verifiedBy': 'provider',
      }));

  Map<String, dynamic> _closeFields(String reason) => {
        'listingStatus': 'closed',
        'isActive': false,
        'closedReason': reason,
        'closedAt': _now,
        'updatedAt': _now,
      };

  @override
  Future<void> closeOwned(String id, String reason) => _guard(() async {
        final r = validateCloseReason(reason);
        await _col.doc(id).update(_closeFields(r));
      });

  @override
  Future<int> closeAllOwned(String uid, String reason) => _guard(() async {
        final r = validateCloseReason(reason);
        final ids = await _idsOwnedWith(uid, kProviderClosable);
        return _chunked(ids, (b, ref) => b.update(ref, _closeFields(r)));
      });

  // ---------------- admin (baru) ----------------

  @override
  Future<void> setListing(String id, ListingStatus status, {String note = ''}) =>
      _guard(() async {
        final n = validateListingNote(status, note);
        final data = <String, dynamic>{
          'listingStatus': status.name,
          'isActive': status == ListingStatus.published,
          'updatedAt': _now,
        };
        switch (status) {
          case ListingStatus.published:
            // Tayang: admin mengonfirmasi; bersihkan jejak penolakan/penutupan.
            data['verifiedBy'] = 'admin';
            data['verifiedAt'] = _now;
            data['reviewNote'] = FieldValue.delete();
            data['closedReason'] = FieldValue.delete();
            data['closedAt'] = FieldValue.delete();
          case ListingStatus.pending:
            data['closedReason'] = FieldValue.delete();
            data['closedAt'] = FieldValue.delete();
          case ListingStatus.rejected:
            data['reviewNote'] = n;
          case ListingStatus.suspended:
          case ListingStatus.closed:
            if (n.isNotEmpty) data['reviewNote'] = n;
        }
        await _col.doc(id).update(data);
      });

  @override
  Future<int> suspendAllOwned(String uid) => _guard(() async {
        final ids = await _idsOwnedWith(uid, kSuspendable);
        return _chunked(
            ids,
            (b, ref) => b.update(ref, {
                  'listingStatus': 'suspended',
                  'isActive': false,
                  'updatedAt': _now,
                }));
      });

  @override
  Future<int> countLegacySources() => _guard(() async {
        final snap = await _col.get();
        var count = 0;
        for (final d in snap.docs) {
          if (legacyMigrationPatch(d.data()) != null) count++;
        }
        return count;
      });

  @override
  Future<int> migrateLegacySources() => _guard(() async {
        final snap = await _col.get();
        final patches = <String, Map<String, dynamic>>{};
        for (final d in snap.docs) {
          final p = legacyMigrationPatch(d.data());
          if (p != null) patches[d.id] = p;
        }
        if (patches.isEmpty) return 0;
        return _chunked(
          patches.keys.toList(),
          (b, ref) => b.update(ref, patches[ref.id]!),
        );
      });

  // ---------------- pembantu ----------------

  Future<List<String>> _idsOwnedWith(String uid, Set<ListingStatus> allowed) async {
    final snap = await _col.where('ownerId', isEqualTo: uid).get();
    return [
      for (final d in snap.docs)
        if (allowed
            .contains(byNameOrNull(ListingStatus.values, d.data()['listingStatus'])))
          d.id,
    ];
  }

  /// Menulis dalam batch berisi paling banyak [kWriteChunk] dokumen. Bila sebuah
  /// batch gagal, batch sebelumnya TIDAK dibatalkan: pemanggil diberi tahu berapa
  /// yang tersisa lewat [SourceBatchException].
  Future<int> _chunked(
    List<String> ids,
    void Function(WriteBatch b, DocumentReference<Map<String, dynamic>> ref) write,
  ) async {
    var done = 0;
    for (var i = 0; i < ids.length; i += kWriteChunk) {
      final chunk = ids.sublist(i, math.min(i + kWriteChunk, ids.length));
      final batch = _db.batch();
      for (final id in chunk) {
        write(batch, _col.doc(id));
      }
      try {
        await batch.commit();
      } on FirebaseException catch (e) {
        throw SourceBatchException(_message(e.code),
            done: done, remaining: ids.length - done);
      }
      done += chunk.length;
    }
    return done;
  }
}
