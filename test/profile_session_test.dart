import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/services/profile_session.dart';

class _Watch {
  final String uid;
  bool cancelled = false;
  late final StreamController<ProfileDoc> ctrl;
  _Watch(this.uid) {
    ctrl = StreamController<ProfileDoc>(onCancel: () => cancelled = true);
  }
}

class _FakeProfiles implements ProfileSource {
  final watches = <_Watch>[];
  final created = <String>[];
  Object? createError;

  @override
  Stream<ProfileDoc> watch(String uid) {
    final w = _Watch(uid);
    watches.add(w);
    return w.ctrl.stream;
  }

  @override
  Future<void> createBasic(AuthIdentity id) async {
    created.add(id.uid);
    if (createError != null) throw createError!;
  }

  List<String> get active => [for (final w in watches) if (!w.cancelled) w.uid];
  _Watch get last => watches.last;
}

class _Harness {
  final identities = StreamController<AuthIdentity?>.broadcast();
  final source = _FakeProfiles();
  AuthIdentity? identity; // "pengguna Firebase saat ini"
  late final ProfileSession session;

  _Harness() {
    session = ProfileSession(
      identityChanges: identities.stream,
      currentIdentity: () => identity,
      source: source,
    );
  }

  Future<void> signIn(AuthIdentity id) async {
    identity = id;
    identities.add(id);
    await pumpEventQueue();
  }

  Future<void> signOut() async {
    identity = null;
    identities.add(null);
    await pumpEventQueue();
  }

  Future<void> emit(ProfileDoc doc, {_Watch? on}) async {
    (on ?? source.last).ctrl.add(doc);
    await pumpEventQueue();
  }
}

AuthIdentity _id(String uid, {bool verified = true}) =>
    AuthIdentity(uid: uid, email: '$uid@x.id', displayName: 'Nama $uid', emailVerified: verified);

ProfileDoc _doc(Map<String, dynamic> data) => ProfileDoc(data: data);

Map<String, dynamic> _user(String uid, {String? providerStatus, String? providerNote, String role = 'user'}) => {
      'uid': uid,
      'name': 'Nama $uid',
      'email': '$uid@x.id',
      'role': role,
      if (providerStatus != null) 'providerStatus': providerStatus,
      if (providerNote != null) 'providerNote': providerNote,
    };

void main() {
  late _Harness h;
  setUp(() => h = _Harness());

  group('memantau users/{uid}', () {
    test('masuk memulai pemantauan dan memancarkan AppUser dari dokumen', () async {
      await h.signIn(_id('u1'));
      expect(h.source.active, ['u1']);
      expect(h.session.current, isNull, reason: 'belum ada snapshot');

      await h.emit(_doc(_user('u1')));
      final u = h.session.current!;
      expect(u.uid, 'u1');
      expect(u.name, 'Nama u1');
      expect(u.role, UserRole.user);
      expect(u.providerStatus, ProviderStatus.none);
      expect(u.profileLoaded, isTrue);
    });

    test('perubahan providerStatus none -> active -> terminated memancarkan AppUser baru', () async {
      final seen = <AppUser?>[];
      h.session.changes.listen(seen.add);
      await h.signIn(_id('u1'));

      await h.emit(_doc(_user('u1')));
      expect(h.session.current!.isProvider, isFalse);

      await h.emit(_doc(_user('u1', providerStatus: 'active')));
      expect(h.session.current!.providerStatus, ProviderStatus.active);
      expect(h.session.current!.isProvider, isTrue);

      await h.emit(_doc(_user('u1', providerStatus: 'terminated', providerNote: 'Melanggar ketentuan')));
      final u = h.session.current!;
      expect(u.providerStatus, ProviderStatus.terminated);
      expect(u.isProvider, isFalse);
      expect(u.providerNote, 'Melanggar ketentuan');

      final statuses = seen.whereType<AppUser>().map((e) => e.providerStatus).toList();
      expect(statuses, [ProviderStatus.none, ProviderStatus.active, ProviderStatus.terminated]);
    });

    test('catatan dihapus (reactivate) memancarkan AppUser tanpa providerNote', () async {
      await h.signIn(_id('u1'));
      await h.emit(_doc(_user('u1', providerStatus: 'terminated', providerNote: 'Melanggar')));
      expect(h.session.current!.providerNote, 'Melanggar');
      await h.emit(_doc(_user('u1', providerStatus: 'active')));
      expect(h.session.current!.providerNote, isNull);
      expect(h.session.current!.isProvider, isTrue);
    });

    test('perubahan peran dipancarkan', () async {
      await h.signIn(_id('a1'));
      await h.emit(_doc(_user('a1')));
      expect(h.session.current!.isAdmin, isFalse);
      await h.emit(_doc(_user('a1', role: 'admin')));
      expect(h.session.current!.isAdmin, isTrue);
    });

    test('snapshot identik tidak dipancarkan ulang', () async {
      var count = 0;
      h.session.changes.skip(1).listen((_) => count++);
      await h.signIn(_id('u1'));
      await h.emit(_doc(_user('u1')));
      await h.emit(ProfileDoc(data: _user('u1'), hasPendingWrites: true)); // hanya metadata
      await h.emit(_doc(_user('u1')));
      expect(count, 1);
    });

    test('field bertipe salah dalam dokumen tidak membuat crash', () async {
      await h.signIn(_id('u1'));
      await h.emit(_doc({'name': 123, 'email': null, 'role': 'user', 'providerNote': 5, 'providerStatus': 'entah'}));
      final u = h.session.current!;
      expect(u.name, 'Nama u1', reason: 'jatuh ke nama Auth');
      expect(u.providerStatus, ProviderStatus.none);
      expect(u.providerNote, isNull);
    });
  });

  group('emailVerified (berasal dari Auth, bukan dokumen)', () {
    test('memakai identitas TERBARU saat emisi; restart() memancarkan ulang yang diperbarui', () async {
      await h.signIn(_id('u1', verified: false));
      await h.emit(_doc(_user('u1')));
      expect(h.session.current!.emailVerified, isFalse);

      h.identity = _id('u1', verified: true); // pengguna memverifikasi lalu reload()
      h.session.restart();
      expect(h.source.watches.length, 2);
      expect(h.source.watches.first.cancelled, isTrue);

      await h.emit(_doc(_user('u1'))); // snapshot pertama dari langganan baru
      expect(h.session.current!.emailVerified, isTrue);
    });
  });

  group('siklus langganan', () {
    test('keluar membatalkan langganan dan mengosongkan pengguna', () async {
      await h.signIn(_id('u1'));
      await h.emit(_doc(_user('u1')));
      expect(h.session.current, isNotNull);

      await h.signOut();
      expect(h.source.active, isEmpty);
      expect(h.session.current, isNull);
    });

    test('ganti akun membatalkan langganan lama dan mengabaikan event lamanya', () async {
      await h.signIn(_id('u1'));
      final old = h.source.last;
      await h.signIn(_id('u2'));

      expect(old.cancelled, isTrue);
      expect(h.source.active, ['u2']);

      await h.emit(_doc(_user('u1', role: 'admin')), on: old);
      expect(h.session.current, isNull, reason: 'event akun lama tidak boleh bocor');

      await h.emit(_doc(_user('u2')));
      expect(h.session.current!.uid, 'u2');
    });

    test('penjagaan usang: event u1 tiba setelah sesi berganti (sebelum event identitas)', () async {
      await h.signIn(_id('u1'));
      h.identity = _id('u2'); // Auth sudah berganti, event identitas belum sampai
      await h.emit(_doc(_user('u1', role: 'admin')));
      expect(h.session.current, isNull);
    });

    test('galat dari langganan usang diabaikan', () async {
      await h.signIn(_id('u1'));
      final old = h.source.last;
      await h.signIn(_id('u2'));
      old.ctrl.addError('permission-denied');
      await pumpEventQueue();
      expect(h.session.current, isNull);
    });

    test('dispose menutup semua langganan', () async {
      await h.signIn(_id('u1'));
      h.session.dispose();
      expect(h.source.active, isEmpty);
    });
  });

  group('dokumen profil tidak ada atau galat (tanpa crash)', () {
    test('terhapus (dikonfirmasi server): peran terendah, profil dasar dibuat SEKALI', () async {
      await h.signIn(_id('u1'));
      await h.emit(_doc(_user('u1', role: 'admin', providerStatus: 'active')));
      expect(h.session.current!.isAdmin, isTrue);

      await h.emit(const ProfileDoc(data: null));
      final u = h.session.current!;
      expect(u.role, UserRole.user);
      expect(u.providerStatus, ProviderStatus.none);
      expect(u.isProvider, isFalse);
      expect(u.profileLoaded, isTrue);
      expect(h.source.created, ['u1']);

      await h.emit(const ProfileDoc(data: null));
      expect(h.source.created, ['u1'], reason: 'sekali per sesi');
    });

    test('tidak ada HANYA di cache: profileLoaded false dan TIDAK dibuat; lalu server menimpa', () async {
      await h.signIn(_id('a1'));
      await h.emit(const ProfileDoc(data: null, fromCache: true));
      expect(h.session.current!.profileLoaded, isFalse);
      expect(h.session.current!.role, UserRole.user);
      expect(h.source.created, isEmpty, reason: 'jangan menimpa profil yang mungkin ada di server');

      await h.emit(_doc(_user('a1', role: 'admin')));
      expect(h.session.current!.isAdmin, isTrue);
      expect(h.session.current!.profileLoaded, isTrue);
    });

    test('tulisan lokal tertunda tidak memicu pembuatan profil', () async {
      await h.signIn(_id('u1'));
      await h.emit(const ProfileDoc(data: null, hasPendingWrites: true));
      expect(h.source.created, isEmpty);
    });

    test('selama penghapusan akun profil TIDAK dibuat ulang; setelah dibatalkan boleh', () async {
      await h.signIn(_id('u1'));
      h.session.beginDeletion();
      await h.emit(const ProfileDoc(data: null));
      expect(h.source.created, isEmpty);

      h.session.abortDeletion();
      await h.emit(const ProfileDoc(data: null, hasPendingWrites: false));
      expect(h.source.created, ['u1']);
    });

    test('gagal membuat profil dasar tidak menjatuhkan sesi', () async {
      h.source.createError = Exception('permission-denied');
      await h.signIn(_id('u1'));
      await h.emit(const ProfileDoc(data: null));
      await pumpEventQueue();
      expect(h.session.current!.profileLoaded, isTrue);
    });

    test('galat langganan: profileLoaded false; restart() memulihkan', () async {
      await h.signIn(_id('u1'));
      await h.emit(_doc(_user('u1', role: 'admin')));
      h.source.last.ctrl.addError('unavailable');
      await pumpEventQueue();
      final u = h.session.current!;
      expect(u.profileLoaded, isFalse);
      expect(u.role, UserRole.user);

      h.session.restart();
      await h.emit(_doc(_user('u1', role: 'admin')));
      expect(h.session.current!.isAdmin, isTrue);
      expect(h.session.current!.profileLoaded, isTrue);
    });
  });

  group('pendaftaran', () {
    test('tidak memantau sampai endRegistration', () async {
      h.session.beginRegistration();
      await h.signIn(_id('u1'));
      expect(h.source.watches, isEmpty);

      h.session.endRegistration();
      expect(h.source.active, ['u1']);
    });

    test('endRegistration tanpa pengguna tidak membuka apa pun', () async {
      h.session.beginRegistration();
      h.session.endRegistration();
      expect(h.source.watches, isEmpty);
    });
  });

  group('awaitUser', () {
    test('segera bila sudah ada, menunggu emisi bila belum, timeout bila tak kunjung ada', () async {
      await h.signIn(_id('u1'));
      final pending = h.session.awaitUser('u1');
      var done = false;
      unawaited(pending.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse);

      await h.emit(_doc(_user('u1')));
      expect((await pending).uid, 'u1');
      expect((await h.session.awaitUser('u1')).uid, 'u1');

      await expectLater(
          h.session.awaitUser('lain', timeout: const Duration(milliseconds: 20)),
          throwsA(isA<TimeoutException>()));
    });
  });

  group('runRegistration (S4.1): endRegistration SELALU terpanggil, tepat sekali', () {
    test('galat NON-Firebase: dilempar apa adanya, dan masuk berikutnya tidak menunggu sampai timeout', () async {
      final err = StateError('PlatformException tiruan');
      await expectLater(
          h.session.runRegistration<void>(() async => throw err), throwsA(same(err)));

      // Tanpa perbaikan, _registering macet dan pemantauan tidak pernah dimulai di sini.
      await h.signIn(_id('u1'));
      expect(h.source.active, ['u1']);

      final pending = h.session.awaitUser('u1', timeout: const Duration(seconds: 1));
      await h.emit(_doc(_user('u1')));
      expect((await pending).uid, 'u1');
    });

    test('akun sudah terbentuk lalu galat: pemantauan profil dimulai untuk akun itu', () async {
      h.identity = _id('u1'); // Firebase sudah punya pengguna
      await expectLater(
        h.session.runRegistration<void>(() async {
          h.identities.add(h.identity); // authStateChanges menyala SELAMA pendaftaran
          await pumpEventQueue();
          expect(h.source.watches, isEmpty, reason: 'ditahan selama pendaftaran');
          throw StateError('gagal setelah akun dibuat');
        }),
        throwsA(isA<StateError>()),
      );
      expect(h.source.active, ['u1']);
      expect(h.source.watches.length, 1, reason: 'sekali, bukan ganda');
    });

    test('sukses: nilai dikembalikan dan pemantauan dimulai tepat sekali', () async {
      final uid = await h.session.runRegistration<String>(() async {
        h.identity = _id('u1');
        h.identities.add(h.identity);
        await pumpEventQueue();
        return 'u1';
      });
      expect(uid, 'u1');
      expect(h.source.watches.length, 1);
      expect(h.source.active, ['u1']);
    });

    test('pembuatan akun gagal (tanpa pengguna): tidak membuka apa pun dan tidak macet', () async {
      await expectLater(
          h.session.runRegistration<void>(() async => throw Exception('email-already-in-use')),
          throwsA(isA<Exception>()));
      expect(h.source.watches, isEmpty);

      await h.signIn(_id('u2'));
      expect(h.source.active, ['u2']);
    });

    test('dua pendaftaran berurutan: masing-masing menutup dan membuka sendiri', () async {
      await h.session.runRegistration<void>(() async {
        h.identity = _id('u1');
        h.identities.add(h.identity);
        await pumpEventQueue();
      });
      expect(h.source.active, ['u1']);

      await h.session.runRegistration<void>(() async {
        h.identity = _id('u2');
        h.identities.add(h.identity);
        await pumpEventQueue();
      });
      expect(h.source.active, ['u2']);
      expect(h.source.watches.first.cancelled, isTrue);
    });
  });
}
