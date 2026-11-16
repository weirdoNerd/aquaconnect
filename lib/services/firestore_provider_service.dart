import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/provider_application.dart';
import '../models/provider_profile.dart';
import '../models/water_source.dart' show asDateTime, byNameOrNull;
import 'provider_service.dart';
import 'source_service.dart';

class FirestoreProviderService implements ProviderService {
  final FirebaseFirestore _db;
  final SourceService _sources;

  /// [sources] dipakai [terminate] untuk menangguhkan sumber penyedia.
  FirestoreProviderService({FirebaseFirestore? db, required SourceService sources})
      : _db = db ?? FirebaseFirestore.instance,
        _sources = sources;

  CollectionReference<Map<String, dynamic>> get _apps =>
      _db.collection('provider_applications');
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  static FieldValue get _now => FieldValue.serverTimestamp();

  String _message(String code) => switch (code) {
        'permission-denied' => 'Tidak ada izin untuk tindakan ini.',
        'unavailable' || 'deadline-exceeded' =>
          'Tidak ada koneksi ke server. Coba lagi.',
        'not-found' => 'Data penyedia tidak ditemukan.',
        _ => 'Terjadi kesalahan pada server ($code).',
      };

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseException catch (e) {
      throw ProviderException(_message(e.code));
    }
  }

  @override
  Stream<ProviderApplication?> watchMyApplication(String uid) =>
      _apps.doc(uid).snapshots().map((d) {
        final m = d.data();
        return m == null ? null : ProviderApplication.fromMap(d.id, m);
      });

  /// `set` tanpa merge: untuk dokumen baru jatuh ke jalur create, untuk dokumen
  /// berstatus rejected jatuh ke jalur pengajuan ulang, dan MENGGANTI dokumen
  /// (reviewedAt lama hilang), sesuai daftar field yang diizinkan rules.
  @override
  Future<void> apply(ProviderApplication a) => _guard(() async {
        final error = validateApplication(a);
        if (error != null) throw ProviderException(error);
        await _apps.doc(a.uid).set({...a.toSubmitMap(), 'createdAt': _now});
      });

  @override
  Stream<List<ProviderApplication>> watchPending() =>
      _apps.where('status', isEqualTo: 'pending').snapshots().map((snap) {
        final list = <ProviderApplication>[];
        for (final d in snap.docs) {
          try {
            list.add(ProviderApplication.fromMap(d.id, d.data()));
          } catch (e) {
            debugPrint('Melewati pengajuan ${d.id}: $e');
          }
        }
        // Diurutkan di klien agar tidak perlu composite index.
        list.sort((a, b) => (a.createdAt ?? DateTime.now())
            .compareTo(b.createdAt ?? DateTime.now()));
        return list;
      });

  @override
  Future<List<ProviderProfile>> fetchProviders() => _guard(() async {
        final snap =
            await _users.where('providerStatus', whereIn: ['active', 'terminated']).get();
        final list = <ProviderProfile>[];
        for (final d in snap.docs) {
          try {
            final m = d.data();
            list.add(ProviderProfile(
              uid: d.id,
              name: (m['name'] as String?) ?? '',
              email: (m['email'] as String?) ?? '',
              status: byNameOrNull(ProviderStatus.values, m['providerStatus']) ??
                  ProviderStatus.none,
              note: m['providerNote'] as String?,
              reviewedAt: asDateTime(m['providerReviewedAt']),
            ));
          } catch (e) {
            debugPrint('Melewati profil penyedia ${d.id}: $e');
          }
        }
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      });

  @override
  Future<void> review(String uid, {required bool approve, String note = ''}) =>
      _guard(() async {
        final n = validateAdminNote(note, required: !approve);
        final batch = _db.batch();
        batch.update(_apps.doc(uid), {
          'status': approve ? 'approved' : 'rejected',
          'adminNote': n,
          'reviewedAt': _now,
        });
        batch.update(_users.doc(uid), {
          'providerStatus': approve ? 'active' : 'none',
          'providerReviewedAt': _now,
        });
        await batch.commit();
      });

  @override
  Future<void> terminate(String uid, String reason) async {
    final r = validateAdminNote(reason, required: true);
    // (1) Status DAHULU. Mulai saat ini penyedia tidak bisa menulis sumber lagi.
    await _guard(() => _users.doc(uid).update({
          'providerStatus': 'terminated',
          'providerNote': r,
          'providerReviewedAt': _now,
        }));
    // (2) Lalu tangguhkan sumbernya. Kegagalan TIDAK membatalkan langkah (1).
    try {
      await _sources.suspendAllOwned(uid);
    } on SourceBatchException catch (e) {
      throw ProviderException(
          'Kemitraan diputus, tetapi ${e.remaining} sumber belum ditangguhkan '
          '(${e.message}). Ulangi pemutusan untuk menuntaskannya.',
          remaining: e.remaining);
    } on SourceException catch (e) {
      throw ProviderException(
          'Kemitraan diputus, tetapi penangguhan sumber gagal (${e.message}). '
          'Jumlah yang tersisa belum diketahui; ulangi pemutusan.');
    }
  }

  @override
  Future<void> reactivate(String uid) => _guard(() => _users.doc(uid).update({
        'providerStatus': 'active',
        'providerReviewedAt': _now,
        // Alasan pemutusan lama tidak boleh menempel pada penyedia yang aktif lagi.
        'providerNote': FieldValue.delete(),
      }));
}
