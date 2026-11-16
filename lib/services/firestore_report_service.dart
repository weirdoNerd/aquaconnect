import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/water_report.dart';
import '../models/water_source.dart';
import 'report_service.dart';
import 'source_service.dart';

class FirestoreReportService implements ReportService {
  final FirebaseFirestore _db;
  FirestoreReportService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('reports');
  CollectionReference<Map<String, dynamic>> get _locks =>
      _db.collection('report_locks');

  /// Kunci anti-duplikat. Harus sama dengan pola di firestore.rules.
  static String lockId(String uid, String sourceId, String type) =>
      '${uid}_${sourceId}_$type';

  WaterReport _fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    final type = byNameOrNull(ReportType.values, m['reportType']);
    if (type == null) {
      throw FormatException('reportType tidak dikenal: ${m['reportType']}');
    }
    return WaterReport(
      id: d.id,
      sourceId: m['sourceId'] as String,
      reporterId: m['reporterId'] as String,
      type: type,
      description: (m['description'] as String?) ?? '',
      status: byNameOrNull(ReportStatus.values, m['status']) ?? ReportStatus.pending,
      adminNote: (m['adminNote'] as String?) ?? '',
      createdAt: asDateTime(m['createdAt']),
      reviewedAt: asDateTime(m['reviewedAt']),
    );
  }

  List<WaterReport> _parse(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = <WaterReport>[];
    for (final d in snap.docs) {
      try {
        list.add(_fromDoc(d));
      } catch (e) {
        debugPrint('Melewati laporan ${d.id}: $e');
      }
    }
    return list;
  }

  String _message(String code) => switch (code) {
        'permission-denied' => 'Kamu tidak memiliki izin untuk tindakan ini.',
        'unavailable' || 'deadline-exceeded' =>
          'Tidak ada koneksi ke server. Coba lagi.',
        _ => 'Terjadi kesalahan pada server ($code).',
      };

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw ReportException(_message(e.code));
    }
  }

  @override
  Stream<List<WaterReport>> watchByReporter(String uid) =>
      _col.where('reporterId', isEqualTo: uid).snapshots().map((snap) {
        // Diurutkan di klien agar tidak perlu composite index.
        final list = _parse(snap);
        list.sort((a, b) => (b.createdAt ?? DateTime.now())
            .compareTo(a.createdAt ?? DateTime.now()));
        return list;
      });

  /// Butuh indeks (status, createdAt) -> firestore.indexes.json.
  @override
  Stream<List<WaterReport>> watchPending({int limit = 50}) => _col
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(_parse);

  /// Butuh indeks (status, reviewedAt) -> firestore.indexes.json.
  @override
  Future<List<WaterReport>> fetchByStatus(ReportStatus status,
          {int limit = 50}) =>
      _guard(() async => _parse(await _col
          .where('status', isEqualTo: status.name)
          .orderBy(status == ReportStatus.pending ? 'createdAt' : 'reviewedAt',
              descending: true)
          .limit(limit)
          .get()));

  @override
  Future<void> submit({
    required String sourceId,
    required String reporterId,
    required ReportType type,
    required String description,
  }) =>
      _guard(() async {
        final lockRef = _locks.doc(lockId(reporterId, sourceId, type.name));
        if ((await lockRef.get()).exists) {
          throw const ReportException(
              'Kamu sudah mengirim laporan serupa untuk sumber ini dan masih menunggu verifikasi.');
        }
        // Laporan + kunci ditulis dalam satu batch; rules mensyaratkan keduanya.
        final batch = _db.batch();
        batch.set(_col.doc(), {
          'sourceId': sourceId,
          'reporterId': reporterId,
          'reportType': type.name,
          'description': description.trim(),
          'status': 'pending',
          'adminNote': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        batch.set(lockRef, {
          'reporterId': reporterId,
          'sourceId': sourceId,
          'reportType': type.name,
        });
        await batch.commit();
      });

  /// Laporan + sumber air + kunci diperbarui dalam SATU transaksi.
  @override
  Future<void> review({
    required String id,
    required bool approve,
    required String adminNote,
    SourceUpdate? sourceUpdate,
  }) =>
      _guard(() => _db.runTransaction((tx) async {
            final ref = _col.doc(id);
            final snap = await tx.get(ref);
            if (!snap.exists) {
              throw const ReportException('Laporan tidak ditemukan.');
            }
            final data = snap.data()!;
            if (data['status'] != 'pending') {
              throw const ReportException('Laporan ini sudah ditinjau.');
            }

            tx.update(ref, {
              'status': approve ? 'approved' : 'rejected',
              'adminNote': adminNote,
              'reviewedAt': FieldValue.serverTimestamp(),
            });

            // Lepas kunci agar warga bisa melapor lagi di kemudian hari.
            final reporter = data['reporterId'] as String?;
            final sourceId = data['sourceId'] as String?;
            final type = data['reportType'] as String?;
            if (reporter != null && sourceId != null && type != null) {
              tx.delete(_locks.doc(lockId(reporter, sourceId, type)));
            }

            if (approve && sourceUpdate != null) {
              tx.update(_db.collection('water_sources').doc(sourceUpdate.sourceId), {
                if (sourceUpdate.availability != null)
                  'availability': sourceUpdate.availability!.name,
                if (sourceUpdate.markQualityConcern) 'qualityFlag': true,
                // Penangguhan menulis listingStatus dan isActive BERSAMAAN (invarian rules).
                if (sourceUpdate.suspend)
                  ...{'listingStatus': 'suspended', 'isActive': false},
                'updatedAt': FieldValue.serverTimestamp(),
                // Jalur admin yang menulis verifiedAt juga menulis verifiedBy.
                'verifiedAt': FieldValue.serverTimestamp(),
                'verifiedBy': 'admin',
              });
            }
          }));
}
