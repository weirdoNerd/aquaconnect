import 'package:flutter_test/flutter_test.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/services/source_service.dart';

/// Draf yang SENGAJA memuat field sensitif, untuk membuktikan service memaksanya.
WaterSource _draft({String name = 'Sumur Baru'}) => WaterSource(
      id: '',
      name: name,
      address: 'Cengkareng, Jakarta Barat',
      latitude: -6.15,
      longitude: 106.73,
      type: SourceType.publicWell,
      availability: Availability.available,
      intendedUse: 'Belum diverifikasi',
      openingHours: '24 jam',
      isSimulated: true,
      qualityFlag: true,
      reviewNote: 'sudah diverifikasi admin',
      closedReason: 'x',
      closedAt: DateTime(2026),
      verifiedBy: VerifiedBy.admin,
    );

WaterSource _renamed(WaterSource s, String name) => WaterSource(
      id: s.id,
      name: name,
      address: s.address,
      latitude: s.latitude,
      longitude: s.longitude,
      type: s.type,
      availability: s.availability,
      intendedUse: s.intendedUse,
      openingHours: s.openingHours,
      listingStatus: s.listingStatus,
      ownerId: s.ownerId,
      ownerName: s.ownerName,
    );

Future<List<WaterSource>> _all(MockSourceService s) async =>
    (await s.watchAll().first).sources;

Future<WaterSource> _get(MockSourceService s, String id) async =>
    (await _all(s)).firstWhere((e) => e.id == id);

/// Membuat sumber pending milik [uid] dan mengembalikan id-nya.
Future<String> _owned(MockSourceService svc, String uid, {String name = 'Sumur Baru'}) async {
  svc.actAs(uid);
  await svc.createAsProvider(_draft(name: name), uid, 'Pos Air Mawar');
  return (await _all(svc)).firstWhere((s) => s.ownerId == uid && s.name == name).id;
}

Future<String> _published(MockSourceService svc, String uid, {String name = 'Sumur Tayang'}) async {
  final id = await _owned(svc, uid, name: name);
  await svc.setListing(id, ListingStatus.published);
  return id;
}

const _later = Duration(milliseconds: 2);

void main() {
  late MockSourceService svc;
  setUp(() => svc = MockSourceService());

  group('aliran baca', () {
    test('watchPublished hanya sumber tayang; watchOwned hanya milik uid', () async {
      final id = await _owned(svc, 'p1');

      final pub = (await svc.watchPublished().first).sources.map((s) => s.id);
      expect(pub, isNot(contains(id)));
      expect(pub, contains('sim-1'));

      expect((await svc.watchOwned('p1').first).sources.map((s) => s.id), [id]);
      expect((await svc.watchOwned('p2').first).sources, isEmpty);
      expect((await svc.watchAll().first).sources.map((s) => s.id), contains(id));
    });
  });

  group('createAsProvider', () {
    test('memaksa pending dan menghapus field sensitif', () async {
      final id = await _owned(svc, 'p1');
      final s = await _get(svc, id);
      expect(s.listingStatus, ListingStatus.pending);
      expect(s.isActive, isFalse);
      expect(s.ownerId, 'p1');
      expect(s.ownerName, 'Pos Air Mawar');
      expect(s.verifiedBy, VerifiedBy.provider);
      expect(s.verifiedAt, isNotNull);
      expect(s.updatedAt, isNotNull);
      expect(s.isSimulated, isFalse);
      expect(s.qualityFlag, isFalse);
      expect(s.reviewNote, isNull);
      expect(s.closedReason, isNull);
      expect(s.closedAt, isNull);
    });

    test('ditolak bila belum login, atau uid berbeda dari pemanggil, atau nama usaha kosong', () async {
      svc.actAs(null);
      expect(() => svc.createAsProvider(_draft(), 'p1', 'Pos'), throwsA(isA<SourceException>()));
      svc.actAs('p2');
      expect(() => svc.createAsProvider(_draft(), 'p1', 'Pos'), throwsA(isA<SourceException>()));
      svc.actAs('p1');
      expect(() => svc.createAsProvider(_draft(), 'p1', '  '), throwsA(isA<SourceException>()));
    });
  });

  group('resubmit', () {
    test('rejected -> pending, menghapus reviewNote, memperbarui data', () async {
      final id = await _owned(svc, 'p1');
      await svc.setListing(id, ListingStatus.rejected, note: 'Pin kurang tepat');
      final rejected = await _get(svc, id);
      expect(rejected.reviewNote, 'Pin kurang tepat');

      await Future<void>.delayed(_later);
      await svc.resubmit(_renamed(rejected, 'Sumur Diperbaiki'));
      final s = await _get(svc, id);
      expect(s.listingStatus, ListingStatus.pending);
      expect(s.name, 'Sumur Diperbaiki');
      expect(s.reviewNote, isNull);
      expect(s.updatedAt!.isAfter(rejected.updatedAt!), isTrue);
      expect(s.ownerId, 'p1');
    });

    test('pending -> pending, memperbarui data', () async {
      final id = await _owned(svc, 'p1');
      final pending = await _get(svc, id);

      await Future<void>.delayed(_later);
      await svc.resubmit(_renamed(pending, 'Sumur Pending Diubah'));
      final s = await _get(svc, id);
      expect(s.listingStatus, ListingStatus.pending);
      expect(s.name, 'Sumur Pending Diubah');
      expect(s.verifiedBy, VerifiedBy.provider);
      expect(s.updatedAt!.isAfter(pending.updatedAt!), isTrue);
    });

    test('ditolak untuk sumber tayang/ditangguhkan dan milik orang lain', () async {
      final pubId = await _published(svc, 'p1');
      final pub = await _get(svc, pubId);
      expect(() => svc.resubmit(pub), throwsA(isA<SourceException>()));

      final suspId = await _owned(svc, 'p1', name: 'Sumur Ditangguhkan');
      await svc.setListing(suspId, ListingStatus.suspended, note: 'Ditahan');
      final susp = await _get(svc, suspId);
      expect(() => svc.resubmit(susp), throwsA(isA<SourceException>()));

      final id = await _owned(svc, 'p1', name: 'Sumur Ditolak');
      await svc.setListing(id, ListingStatus.rejected, note: 'Pin kurang tepat');
      final rejected = await _get(svc, id);
      svc.actAs('p2');
      expect(() => svc.resubmit(rejected), throwsA(isA<SourceException>()));
    });
  });

  group('updateOperational', () {
    test('mengubah availability = wajib konfirmasi; data lain tidak tersentuh', () async {
      final id = await _published(svc, 'p1');
      final before = await _get(svc, id);
      await Future<void>.delayed(_later);

      await svc.updateOperational(id, availability: Availability.limited);
      final s = await _get(svc, id);
      expect(s.availability, Availability.limited);
      expect(s.verifiedAt!.isAfter(before.verifiedAt!), isTrue);
      expect(s.verifiedBy, VerifiedBy.provider);
      expect(s.name, before.name);
      expect(s.intendedUse, before.intendedUse);
      expect(s.latitude, before.latitude);
      expect(s.longitude, before.longitude);
    });

    test('hanya jam layanan (availability sama): verifiedAt tidak berubah', () async {
      final id = await _published(svc, 'p1');
      final before = await _get(svc, id);
      await Future<void>.delayed(_later);

      await svc.updateOperational(id,
          availability: before.availability, openingHours: '06:00-18:00');
      final s = await _get(svc, id);
      expect(s.openingHours, '06:00-18:00');
      expect(s.verifiedAt, before.verifiedAt);
      expect(s.updatedAt!.isAfter(before.updatedAt!), isTrue);
    });

    test('jam layanan kosong menjadi "-"', () async {
      final id = await _published(svc, 'p1');
      await svc.updateOperational(id, openingHours: '   ');
      expect((await _get(svc, id)).openingHours, '-');
    });

    test('ditolak: tanpa perubahan, jam > 50, belum tayang, milik orang lain, belum login', () async {
      final id = await _published(svc, 'p1');
      expect(() => svc.updateOperational(id), throwsA(isA<SourceException>()));
      expect(() => svc.updateOperational(id, openingHours: 'x' * 51), throwsA(isA<SourceException>()));

      final pendingId = await _owned(svc, 'p1', name: 'Masih Pending');
      expect(() => svc.updateOperational(pendingId, availability: Availability.limited),
          throwsA(isA<SourceException>()));

      svc.actAs('p2');
      expect(() => svc.updateOperational(id, availability: Availability.limited),
          throwsA(isA<SourceException>()));
      svc.actAs(null);
      expect(() => svc.updateOperational(id, availability: Availability.limited),
          throwsA(isA<SourceException>()));
    });
  });

  group('confirmStillCurrent', () {
    test('memperbarui verifiedAt tanpa mengubah availability', () async {
      final id = await _published(svc, 'p1');
      final before = await _get(svc, id);
      await Future<void>.delayed(_later);

      await svc.confirmStillCurrent(id);
      final s = await _get(svc, id);
      expect(s.availability, before.availability);
      expect(s.verifiedAt!.isAfter(before.verifiedAt!), isTrue);
      expect(s.verifiedBy, VerifiedBy.provider);
    });

    test('ditolak untuk sumber belum tayang atau milik orang lain', () async {
      final pendingId = await _owned(svc, 'p1', name: 'Masih Pending');
      expect(() => svc.confirmStillCurrent(pendingId), throwsA(isA<SourceException>()));

      final id = await _published(svc, 'p1');
      svc.actAs('p2');
      expect(() => svc.confirmStillCurrent(id), throwsA(isA<SourceException>()));
    });
  });

  group('closeOwned', () {
    test('menutup dengan alasan: closed, nonaktif, closedReason dan closedAt', () async {
      final id = await _published(svc, 'p1');
      await svc.closeOwned(id, '  tidak lagi menyediakan air  ');
      final s = await _get(svc, id);
      expect(s.listingStatus, ListingStatus.closed);
      expect(s.isActive, isFalse);
      expect(s.closedReason, 'tidak lagi menyediakan air');
      expect(s.closedAt, isNotNull);
    });

    test('ditolak: alasan < 3 karakter, milik orang lain, sudah closed, ditangguhkan admin', () async {
      final id = await _published(svc, 'p1');
      expect(() => svc.closeOwned(id, 'ab'), throwsA(isA<SourceException>()));
      expect((await _get(svc, id)).listingStatus, ListingStatus.published);

      svc.actAs('p2');
      expect(() => svc.closeOwned(id, 'alasan sah'), throwsA(isA<SourceException>()));

      svc.actAs('p1');
      await svc.closeOwned(id, 'alasan sah');
      expect(() => svc.closeOwned(id, 'alasan sah'), throwsA(isA<SourceException>()));

      final other = await _published(svc, 'p1', name: 'Sumur Lain');
      await svc.setListing(other, ListingStatus.suspended, note: 'Dalam pemeriksaan');
      expect(() => svc.closeOwned(other, 'alasan sah'), throwsA(isA<SourceException>()));
    });
  });

  group('closeAllOwned', () {
    test('20 sumber ditutup dalam 3 batch (8, 8, 4)', () async {
      for (var i = 0; i < 20; i++) {
        await _owned(svc, 'p1', name: 'Sumur $i');
      }
      expect(await svc.closeAllOwned('p1', 'berhenti beroperasi'), 20);
      expect(svc.batchSizes, [8, 8, 4]);
      final mine = (await _all(svc)).where((s) => s.ownerId == 'p1');
      expect(mine.every((s) => s.listingStatus == ListingStatus.closed), isTrue);
    });

    test('yang ditangguhkan atau sudah ditutup dilewati (rules tidak mengizinkan penyedia menyentuhnya)', () async {
      final a = await _owned(svc, 'p1', name: 'A');
      final b = await _owned(svc, 'p1', name: 'B');
      final c = await _owned(svc, 'p1', name: 'C');
      final d = await _owned(svc, 'p1', name: 'D');
      await svc.setListing(a, ListingStatus.suspended, note: 'Dalam pemeriksaan');
      await svc.closeOwned(b, 'sudah tutup');

      expect(await svc.closeAllOwned('p1', 'berhenti beroperasi'), 2);
      expect((await _get(svc, a)).listingStatus, ListingStatus.suspended);
      expect((await _get(svc, c)).listingStatus, ListingStatus.closed);
      expect((await _get(svc, d)).listingStatus, ListingStatus.closed);
    });

    test('ditolak: uid orang lain atau alasan pendek; tidak ada yang berubah', () async {
      final id = await _owned(svc, 'p1');
      expect(() => svc.closeAllOwned('p2', 'berhenti beroperasi'), throwsA(isA<SourceException>()));
      expect(() => svc.closeAllOwned('p1', 'ab'), throwsA(isA<SourceException>()));
      expect((await _get(svc, id)).listingStatus, ListingStatus.pending);
      expect(svc.batchSizes, isEmpty);
    });

    test('gagal di tengah: batch sebelumnya tetap berlaku dan sisa dilaporkan', () async {
      for (var i = 0; i < 20; i++) {
        await _owned(svc, 'p1', name: 'Sumur $i');
      }
      svc.failAfterBatches = 1;
      try {
        await svc.closeAllOwned('p1', 'berhenti beroperasi');
        fail('seharusnya melempar SourceBatchException');
      } on SourceBatchException catch (e) {
        expect(e.done, 8);
        expect(e.remaining, 12);
      }
      final closed = (await _all(svc))
          .where((s) => s.ownerId == 'p1' && s.listingStatus == ListingStatus.closed);
      expect(closed.length, 8);
    });
  });

  group('setListing', () {
    test('published: verifiedBy admin, verifiedAt baru, jejak penolakan dihapus', () async {
      final id = await _owned(svc, 'p1');
      await svc.setListing(id, ListingStatus.rejected, note: 'Pin kurang tepat');
      await Future<void>.delayed(_later);
      final before = await _get(svc, id);

      await svc.setListing(id, ListingStatus.published);
      final s = await _get(svc, id);
      expect(s.listingStatus, ListingStatus.published);
      expect(s.isActive, isTrue);
      expect(s.verifiedBy, VerifiedBy.admin);
      expect(s.verifiedAt!.isAfter(before.verifiedAt!), isTrue);
      expect(s.reviewNote, isNull);
    });

    test('rejected wajib catatan >= 5 karakter dan menyimpannya di reviewNote', () async {
      final id = await _owned(svc, 'p1');
      expect(() => svc.setListing(id, ListingStatus.rejected), throwsA(isA<SourceException>()));
      expect(() => svc.setListing(id, ListingStatus.rejected, note: 'abc'), throwsA(isA<SourceException>()));
      await svc.setListing(id, ListingStatus.rejected, note: 'Lokasi tidak sesuai');
      expect((await _get(svc, id)).reviewNote, 'Lokasi tidak sesuai');
    });

    test('membuka kembali dari closed menghapus closedReason dan closedAt', () async {
      final id = await _published(svc, 'p1');
      await svc.closeOwned(id, 'sementara tutup');
      expect((await _get(svc, id)).closedReason, isNotNull);

      await svc.setListing(id, ListingStatus.published);
      final s = await _get(svc, id);
      expect(s.closedReason, isNull);
      expect(s.closedAt, isNull);
      expect(s.isActive, isTrue);
    });

    test('isActive SELALU konsisten dengan listingStatus', () async {
      final id = await _owned(svc, 'p1');
      for (final st in ListingStatus.values) {
        await svc.setListing(id, st, note: 'Catatan admin lengkap');
        final s = await _get(svc, id);
        expect(s.listingStatus, st);
        expect(s.isActive, st == ListingStatus.published, reason: st.name);
      }
    });

    test('suspended dengan catatan menyimpannya; catatan > 200 dan id tak dikenal ditolak', () async {
      final id = await _published(svc, 'p1');
      await svc.setListing(id, ListingStatus.suspended, note: 'Dalam pemeriksaan');
      expect((await _get(svc, id)).reviewNote, 'Dalam pemeriksaan');
      expect(() => svc.setListing(id, ListingStatus.suspended, note: 'x' * 201), throwsA(isA<SourceException>()));
      expect(() => svc.setListing('tidak-ada', ListingStatus.published), throwsA(isA<SourceException>()));
    });
  });

  group('suspendAllOwned', () {
    test('hanya published dan pending; 15 sumber dalam batch 8 dan 7', () async {
      final ids = <String, ListingStatus>{};
      for (var i = 0; i < 10; i++) {
        ids[await _published(svc, 'p1', name: 'Tayang $i')] = ListingStatus.published;
      }
      for (var i = 0; i < 5; i++) {
        ids[await _owned(svc, 'p1', name: 'Pending $i')] = ListingStatus.pending;
      }
      final closed = <String>[];
      for (var i = 0; i < 3; i++) {
        final id = await _published(svc, 'p1', name: 'Tutup $i');
        await svc.closeOwned(id, 'sudah tutup');
        closed.add(id);
      }
      final rejected = <String>[];
      for (var i = 0; i < 2; i++) {
        final id = await _owned(svc, 'p1', name: 'Ditolak $i');
        await svc.setListing(id, ListingStatus.rejected, note: 'Lokasi tidak sesuai');
        rejected.add(id);
      }

      expect(await svc.suspendAllOwned('p1'), 15);
      expect(svc.batchSizes, [8, 7]);
      for (final id in ids.keys) {
        final s = await _get(svc, id);
        expect(s.listingStatus, ListingStatus.suspended);
        expect(s.isActive, isFalse);
      }
      for (final id in closed) {
        expect((await _get(svc, id)).listingStatus, ListingStatus.closed);
      }
      for (final id in rejected) {
        expect((await _get(svc, id)).listingStatus, ListingStatus.rejected);
      }
    });

    test('tidak menyentuh sumber penyedia lain', () async {
      await _published(svc, 'p1', name: 'Milik P1');
      final other = await _published(svc, 'p2', name: 'Milik P2');
      await svc.suspendAllOwned('p1');
      expect((await _get(svc, other)).listingStatus, ListingStatus.published);
    });
  });

  group('SEMUA jalur admin yang menulis verifiedAt juga menulis verifiedBy: admin', () {
    test('applyUpdate (dan dengan suspend)', () async {
      await svc.applyUpdate(const SourceUpdate(
          sourceId: 'sim-1', availability: Availability.unavailable));
      var s = await _get(svc, 'sim-1');
      expect(s.verifiedBy, VerifiedBy.admin);
      expect(s.verifiedAt, isNotNull);
      expect(s.availability, Availability.unavailable);

      await svc.applyUpdate(const SourceUpdate(sourceId: 'sim-2', suspend: true));
      s = await _get(svc, 'sim-2');
      expect(s.listingStatus, ListingStatus.suspended);
      expect(s.isActive, isFalse);
      expect(s.verifiedBy, VerifiedBy.admin);
    });

    test('create', () async {
      await svc.create(_draft(name: 'Dibuat Admin'));
      final s = (await _all(svc)).firstWhere((e) => e.name == 'Dibuat Admin');
      expect(s.verifiedBy, VerifiedBy.admin);
      expect(s.verifiedAt, isNotNull);
    });

    test('update: confirmStatus true menulis admin; false tidak menyentuhnya', () async {
      final before = await _get(svc, 'sim-1');
      await svc.update(before);
      var s = await _get(svc, 'sim-1');
      expect(s.verifiedAt, before.verifiedAt);
      expect(s.verifiedBy, before.verifiedBy);

      await Future<void>.delayed(_later);
      await svc.update(before, confirmStatus: true);
      s = await _get(svc, 'sim-1');
      expect(s.verifiedAt!.isAfter(before.verifiedAt!), isTrue);
      expect(s.verifiedBy, VerifiedBy.admin);
    });

    test('setListing(published)', () async {
      final id = await _owned(svc, 'p1');
      await svc.setListing(id, ListingStatus.published);
      expect((await _get(svc, id)).verifiedBy, VerifiedBy.admin);
    });

    test('peninjauan laporan (MockReportService.review -> applyUpdate)', () async {
      final reports = MockReportService(svc);
      await reports.review(
        id: 'seed-3',
        approve: true,
        adminNote: '',
        sourceUpdate: const SourceUpdate(
            sourceId: 'sim-1', availability: Availability.unavailable),
      );
      final s = await _get(svc, 'sim-1');
      expect(s.verifiedBy, VerifiedBy.admin);
      expect(s.availability, Availability.unavailable);

      await reports.review(
        id: 'seed-5',
        approve: true,
        adminNote: '',
        sourceUpdate: const SourceUpdate(sourceId: 'sim-5', suspend: true),
      );
      final t = await _get(svc, 'sim-5');
      expect(t.listingStatus, ListingStatus.suspended);
      expect(t.isActive, isFalse);
    });
  });
}
