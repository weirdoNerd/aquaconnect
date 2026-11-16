import 'package:flutter_test/flutter_test.dart';
import 'package:aquaconnect/config.dart';
import 'package:aquaconnect/dev/mock_provider_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/provider_application.dart';
import 'package:aquaconnect/models/provider_profile.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/services/provider_service.dart';

ProviderApplication _app(String uid,
        {String org = 'Pos Air Mawar',
        String phone = '0812 3456 7890',
        String desc = 'Menyediakan air bersih untuk warga RW 03.',
        int? terms}) =>
    ProviderApplication(
      uid: uid,
      organizationName: org,
      contactPhone: phone,
      description: desc,
      termsVersion: terms ?? kProviderTermsVersion,
    );

WaterSource _draft(String name) => WaterSource(
      id: '',
      name: name,
      address: 'Cengkareng',
      latitude: -6.15,
      longitude: 106.73,
      type: SourceType.publicWell,
      availability: Availability.available,
      intendedUse: 'Belum diverifikasi',
      openingHours: '24 jam',
    );

Future<List<WaterSource>> _owned(MockSourceService s, String uid) async =>
    (await s.watchOwned(uid).first).sources;

/// Membuat [n] sumber tayang milik [uid].
Future<void> _seedPublished(MockSourceService s, String uid, int n) async {
  s.actAs(uid);
  for (var i = 0; i < n; i++) {
    await s.createAsProvider(_draft('Sumur $i'), uid, 'Pos Air Mawar');
  }
  for (final src in await _owned(s, uid)) {
    await s.setListing(src.id, ListingStatus.published);
  }
}

void main() {
  late MockSourceService sources;
  late MockProviderService svc;

  setUp(() {
    sources = MockSourceService();
    svc = MockProviderService(sources);
  });

  group('pengajuan', () {
    test('apply membuat pengajuan pending dengan catatan kosong', () async {
      expect(await svc.watchMyApplication('u1').first, isNull);
      await svc.apply(_app('u1'));
      final a = (await svc.watchMyApplication('u1').first)!;
      expect(a.status, ApplicationStatus.pending);
      expect(a.adminNote, '');
      expect(a.createdAt, isNotNull);
    });

    test('pengajuan kedua saat masih pending ditolak', () async {
      await svc.apply(_app('u1'));
      expect(() => svc.apply(_app('u1')), throwsA(isA<ProviderException>()));
    });

    test('setelah ditolak boleh mengajukan ulang; status kembali pending, catatan kosong', () async {
      await svc.apply(_app('u1'));
      await svc.review('u1', approve: false, note: 'Data belum lengkap.');
      expect((await svc.watchMyApplication('u1').first)!.status, ApplicationStatus.rejected);

      await svc.apply(_app('u1', org: 'Pos Air Mawar Baru'));
      final a = (await svc.watchMyApplication('u1').first)!;
      expect(a.status, ApplicationStatus.pending);
      expect(a.adminNote, '');
      expect(a.organizationName, 'Pos Air Mawar Baru');
    });

    test('pengajuan yang sudah disetujui tidak bisa diajukan ulang', () async {
      await svc.apply(_app('u1'));
      await svc.review('u1', approve: true);
      expect(() => svc.apply(_app('u1')), throwsA(isA<ProviderException>()));
    });

    test('validasi: nama, telepon, deskripsi, versi ketentuan', () async {
      for (final bad in [
        _app('u1', org: 'ab'),
        _app('u1', org: 'x' * 81),
        _app('u1', phone: 'abc'),
        _app('u1', phone: '0812-3456'),
        _app('u1', desc: 'pendek'),
        _app('u1', desc: 'x' * 301),
        _app('u1', terms: kProviderTermsVersion + 1),
      ]) {
        expect(() => svc.apply(bad), throwsA(isA<ProviderException>()));
      }
      expect(await svc.watchMyApplication('u1').first, isNull);
    });
  });

  group('tinjauan admin', () {
    test('menyetujui: pengajuan approved dan profil active', () async {
      await svc.apply(_app('u1'));
      await svc.review('u1', approve: true);
      final a = (await svc.watchMyApplication('u1').first)!;
      expect(a.status, ApplicationStatus.approved);
      expect(a.reviewedAt, isNotNull);
      expect(svc.profileOf('u1')!.status, ProviderStatus.active);
    });

    test('menolak wajib catatan >= 5 karakter; profil tidak menjadi active', () async {
      await svc.apply(_app('u1'));
      expect(() => svc.review('u1', approve: false), throwsA(isA<ProviderException>()));
      expect(() => svc.review('u1', approve: false, note: 'abc'), throwsA(isA<ProviderException>()));
      await svc.review('u1', approve: false, note: 'Data belum lengkap.');
      final a = (await svc.watchMyApplication('u1').first)!;
      expect(a.status, ApplicationStatus.rejected);
      expect(a.adminNote, 'Data belum lengkap.');
      expect(svc.profileOf('u1')!.status, ProviderStatus.none);
    });

    test('hanya sekali: yang sudah ditinjau atau tidak ada ditolak', () async {
      await svc.apply(_app('u1'));
      await svc.review('u1', approve: true);
      expect(() => svc.review('u1', approve: true), throwsA(isA<ProviderException>()));
      expect(() => svc.review('tidak-ada', approve: true), throwsA(isA<ProviderException>()));
    });

    test('watchPending hanya yang menunggu', () async {
      await svc.apply(_app('u1'));
      await svc.apply(_app('u2'));
      expect((await svc.watchPending().first).map((a) => a.uid).toSet(), {'u1', 'u2'});
      await svc.review('u1', approve: true);
      expect((await svc.watchPending().first).map((a) => a.uid), ['u2']);
    });

    test('fetchProviders hanya active dan terminated, urut nama', () async {
      svc.seedProfile(const ProviderProfile(uid: 'a', name: 'Budi', email: 'b@x.id', status: ProviderStatus.active));
      svc.seedProfile(const ProviderProfile(uid: 'b', name: 'Agus', email: 'a@x.id', status: ProviderStatus.terminated));
      svc.seedProfile(const ProviderProfile(uid: 'c', name: 'Cici', email: 'c@x.id', status: ProviderStatus.none));
      final list = await svc.fetchProviders();
      expect(list.map((p) => p.name), ['Agus', 'Budi']);
    });
  });

  group('terminate', () {
    const reason = 'Melanggar ketentuan penyedia';

    setUp(() => svc.seedProfile(const ProviderProfile(
        uid: 'p1', name: 'Pos Air Mawar', email: 'p1@x.id', status: ProviderStatus.active)));

    test('menulis providerStatus LEBIH DULU, lalu menangguhkan semua sumber (3 batch)', () async {
      await _seedPublished(sources, 'p1', 20);
      sources.batchSizes.clear();

      await svc.terminate('p1', reason);

      expect(svc.callLog, ['users:terminated', 'suspendAllOwned']);
      final p = svc.profileOf('p1')!;
      expect(p.status, ProviderStatus.terminated);
      expect(p.note, reason);
      final mine = await _owned(sources, 'p1');
      expect(mine.every((s) => s.listingStatus == ListingStatus.suspended), isTrue);
      expect(mine.every((s) => !s.isActive), isTrue);
      expect(sources.batchSizes, [8, 8, 4]);
    });

    test('penangguhan gagal sebagian: status TETAP terminated, sisa dilaporkan, bisa diulang', () async {
      await _seedPublished(sources, 'p1', 20);
      sources.batchSizes.clear();
      sources.failAfterBatches = 1;

      try {
        await svc.terminate('p1', reason);
        fail('seharusnya melempar ProviderException');
      } on ProviderException catch (e) {
        expect(e.remaining, 12);
        expect(e.message, contains('12 sumber belum ditangguhkan'));
      }
      expect(svc.callLog, ['users:terminated', 'suspendAllOwned']);
      expect(svc.profileOf('p1')!.status, ProviderStatus.terminated, reason: 'langkah (1) tidak dibatalkan');
      var mine = await _owned(sources, 'p1');
      expect(mine.where((s) => s.listingStatus == ListingStatus.suspended).length, 8);

      // Diulang setelah gangguan hilang: hanya sisa yang disentuh.
      sources.failAfterBatches = null;
      sources.batchSizes.clear();
      await svc.terminate('p1', reason);
      mine = await _owned(sources, 'p1');
      expect(mine.every((s) => s.listingStatus == ListingStatus.suspended), isTrue);
      expect(sources.batchSizes, [8, 4]);
    });

    test('alasan pendek ditolak SEBELUM menulis apa pun', () async {
      expect(() => svc.terminate('p1', 'abc'), throwsA(isA<ProviderException>()));
      expect(svc.callLog, isEmpty);
      expect(svc.profileOf('p1')!.status, ProviderStatus.active);
    });
  });

  test('reactivate mengembalikan status active DAN menghapus catatan pemutusan lama', () async {
    svc.seedProfile(const ProviderProfile(
        uid: 'p1',
        name: 'P',
        email: 'p@x.id',
        status: ProviderStatus.terminated,
        note: 'Melanggar ketentuan penyedia'));
    await svc.reactivate('p1');
    final p = svc.profileOf('p1')!;
    expect(p.status, ProviderStatus.active);
    expect(p.note, isNull);
    expect(p.reviewedAt, isNotNull);
  });

  test('ProviderProfile.copyWith: clearNote mengosongkan, note null tidak', () {
    const p = ProviderProfile(
        uid: 'a', name: 'A', email: 'a@x.id', status: ProviderStatus.terminated, note: 'alasan');
    expect(p.copyWith(note: null).note, 'alasan');
    expect(p.copyWith(clearNote: true).note, isNull);
  });
}
