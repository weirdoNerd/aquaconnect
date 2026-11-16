import 'package:flutter_test/flutter_test.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'package:aquaconnect/services/source_service.dart';
import 'helpers/fakes.dart';

WaterSource _s(String id, {String? owner, ListingStatus status = ListingStatus.published}) =>
    WaterSource(
      id: id,
      name: 'Sumur $id',
      address: 'Cengkareng',
      latitude: -6.14,
      longitude: 106.73,
      type: SourceType.publicWell,
      availability: Availability.available,
      intendedUse: 'Belum diverifikasi',
      openingHours: '24 jam',
      verifiedAt: DateTime.now(),
      listingStatus: status,
      ownerId: owner,
    );

SourceProvider _make(FakeSourceService f) => SourceProvider(f, NoLocation());

void main() {
  group('pemilihan aliran per peran', () {
    test('konstruktor TIDAK membuka langganan; syncUser pertama yang membukanya', () {
      final f = FakeSourceService();
      final p = _make(f);
      expect(f.taps, isEmpty);
      p.syncUser(null, isAdmin: false, isProvider: false);
      expect(f.active, ['published']);
    });

    test('tamu dan warga: hanya sumber tayang', () {
      final f = FakeSourceService();
      _make(f).syncUser(null, isAdmin: false, isProvider: false);
      expect(f.active, ['published']);

      final g = FakeSourceService();
      _make(g).syncUser('warga1', isAdmin: false, isProvider: false);
      expect(g.active, ['published']);
    });

    test('penyedia aktif: tayang + milik sendiri (ownerId = uid)', () {
      final f = FakeSourceService();
      _make(f).syncUser('p1', isAdmin: false, isProvider: true);
      expect(f.active, ['published', 'owned']);
      expect(f.taps[1].arg, 'p1');
    });

    test('admin: watchAll saja, walau juga bertanda penyedia', () {
      final f = FakeSourceService();
      _make(f).syncUser('a1', isAdmin: true, isProvider: true);
      expect(f.active, ['all']);
    });

    test('bendera penyedia tanpa uid diperlakukan sebagai tamu', () {
      final f = FakeSourceService();
      _make(f).syncUser(null, isAdmin: false, isProvider: true);
      expect(f.active, ['published']);
    });
  });

  group('syncUser', () {
    test('tupel sama: tidak membuka ulang', () {
      final f = FakeSourceService();
      final p = _make(f);
      p.syncUser('p1', isAdmin: false, isProvider: true);
      p.syncUser('p1', isAdmin: false, isProvider: true);
      p.syncUser('p1', isAdmin: false, isProvider: true);
      expect(f.taps.length, 2);
      expect(f.active, ['published', 'owned']);
    });

    test('tupel berubah: langganan lama dibatalkan, yang baru dibuka', () {
      final f = FakeSourceService();
      final p = _make(f);
      p.syncUser(null, isAdmin: false, isProvider: false);
      final guestTap = f.taps.first;

      p.syncUser('p1', isAdmin: false, isProvider: true);
      expect(guestTap.cancelled, isTrue);
      expect(f.active, ['published', 'owned']);

      final providerTaps = List.of(f.taps.skip(1));
      p.syncUser(null, isAdmin: false, isProvider: false); // keluar
      expect(providerTaps.every((t) => t.cancelled), isTrue);
      expect(f.active, ['published']);
    });

    test('bendera penyedia saja yang berubah (uid sama) membuka ulang', () {
      final f = FakeSourceService();
      final p = _make(f);
      p.syncUser('u1', isAdmin: false, isProvider: false);
      p.syncUser('u1', isAdmin: false, isProvider: true);
      expect(f.active, ['published', 'owned']);
    });

    test('pergantian pengguna mengosongkan daftar lama dan tidak menerima event lama', () async {
      final f = FakeSourceService();
      final p = _make(f);
      p.syncUser('p1', isAdmin: false, isProvider: true);
      f.taps[0].ctrl.add(SourceBatch([_s('a')]));
      f.taps[1].ctrl.add(SourceBatch([_s('b', owner: 'p1')]));
      await pumpEventQueue();
      expect(p.all.length, 2);

      final oldTaps = List.of(f.taps);
      p.syncUser('p2', isAdmin: false, isProvider: true);
      expect(p.all, isEmpty);
      expect(p.loading, isTrue);
      expect(p.byId('b'), isNull);

      oldTaps[0].ctrl.add(SourceBatch([_s('bocor')]));
      await pumpEventQueue();
      expect(p.byId('bocor'), isNull);
    });
  });

  group('penggabungan aliran penyedia', () {
    test('dedup per id, skipped dijumlah, fromCache = salah satu, menunggu kedua aliran', () async {
      final f = FakeSourceService();
      final p = _make(f)..syncUser('p1', isAdmin: false, isProvider: true);
      final published = f.taps[0], owned = f.taps[1];

      published.ctrl.add(SourceBatch([_s('a', owner: 'p1'), _s('b')], skipped: 1));
      await pumpEventQueue();
      expect(p.loading, isTrue, reason: 'masih menunggu aliran milik sendiri');
      expect(p.all, isEmpty);

      owned.ctrl.add(SourceBatch([
        _s('a', owner: 'p1'),
        _s('c', owner: 'p1', status: ListingStatus.pending),
      ], skipped: 2, fromCache: true));
      await pumpEventQueue();

      expect(p.loading, isFalse);
      expect(p.all.length, 3);
      expect(p.all.map((s) => s.id).toSet(), {'a', 'b', 'c'});
      expect(p.items.map((s) => s.id).toSet(), {'a', 'b'}, reason: 'pending tidak tampil untuk warga');
      expect(p.skippedSources, 3);
      expect(p.fromCache, isTrue);
    });

    test('fromCache salah bila keduanya dari server', () async {
      final f = FakeSourceService();
      final p = _make(f)..syncUser('p1', isAdmin: false, isProvider: true);
      f.taps[0].ctrl.add(SourceBatch([_s('a')]));
      f.taps[1].ctrl.add(SourceBatch([_s('b', owner: 'p1')]));
      await pumpEventQueue();
      expect(p.fromCache, isFalse);
    });

    test('pembaruan berikutnya pada salah satu aliran memperbarui hasil gabungan', () async {
      final f = FakeSourceService();
      final p = _make(f)..syncUser('p1', isAdmin: false, isProvider: true);
      f.taps[0].ctrl.add(SourceBatch([_s('a')]));
      f.taps[1].ctrl.add(const SourceBatch([]));
      await pumpEventQueue();
      expect(p.all.map((s) => s.id), ['a']);

      f.taps[1].ctrl.add(SourceBatch([_s('c', owner: 'p1', status: ListingStatus.pending)]));
      await pumpEventQueue();
      expect(p.all.map((s) => s.id).toSet(), {'a', 'c'});
    });
  });

  group('galat dan coba lagi', () {
    test('galat aliran menampilkan pesan; retry membuka ulang aliran yang sama', () async {
      final f = FakeSourceService();
      final p = _make(f)..syncUser(null, isAdmin: false, isProvider: false);
      f.taps[0].ctrl.addError('permission-denied');
      await pumpEventQueue();
      expect(p.error, isNotNull);
      expect(p.loading, isFalse);

      p.retry();
      expect(f.taps.first.cancelled, isTrue);
      expect(f.active, ['published']);
      expect(p.loading, isTrue);
      expect(p.error, isNull);
    });
  });

  test('dispose membatalkan semua langganan', () {
    final f = FakeSourceService();
    final p = _make(f)..syncUser('p1', isAdmin: false, isProvider: true);
    p.dispose();
    expect(f.active, isEmpty);
  });
}
