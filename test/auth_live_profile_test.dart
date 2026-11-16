import 'package:flutter_test/flutter_test.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/providers/auth_provider.dart';

void main() {
  late MockAuthService auth;
  late AuthProvider p;

  setUp(() {
    auth = MockAuthService();
    p = AuthProvider(auth);
  });

  Future<void> signInWarga() async {
    expect(await p.signIn('warga@aquaconnect.test', 'warga123'), isTrue);
    await pumpEventQueue();
  }

  test('perubahan providerStatus memancarkan AppUser baru ke AuthProvider (tanpa keluar-masuk)', () async {
    await signInWarga();
    expect(p.user!.providerStatus, ProviderStatus.none);
    expect(p.isProvider, isFalse);

    var notified = 0;
    p.addListener(() => notified++);

    auth.updateProfile('mock-user', providerStatus: ProviderStatus.active);
    await pumpEventQueue();
    expect(p.user!.providerStatus, ProviderStatus.active);
    expect(p.isProvider, isTrue);
    expect(notified, greaterThan(0));
    expect(p.isLoggedIn, isTrue, reason: 'tetap masuk');

    auth.updateProfile('mock-user',
        providerStatus: ProviderStatus.terminated, providerNote: 'Melanggar ketentuan');
    await pumpEventQueue();
    expect(p.isProvider, isFalse);
    expect(p.user!.providerStatus, ProviderStatus.terminated);
    expect(p.user!.providerNote, 'Melanggar ketentuan');

    auth.updateProfile('mock-user', providerStatus: ProviderStatus.active, clearProviderNote: true);
    await pumpEventQueue();
    expect(p.user!.providerNote, isNull);
  });

  test('perubahan peran dipancarkan; perubahan untuk pengguna lain tidak memengaruhi', () async {
    await signInWarga();
    auth.updateProfile('mock-admin', role: UserRole.admin, providerStatus: ProviderStatus.active);
    await pumpEventQueue();
    expect(p.user!.uid, 'mock-user');
    expect(p.isAdmin, isFalse);
    expect(p.isProvider, isFalse);

    auth.updateProfile('mock-user', role: UserRole.admin);
    await pumpEventQueue();
    expect(p.isAdmin, isTrue);
  });

  test('profil terhapus: peran terendah, tetap masuk, tidak crash', () async {
    expect(await p.signIn('admin@aquaconnect.test', 'admin123'), isTrue);
    await pumpEventQueue();
    expect(p.isAdmin, isTrue);

    auth.deleteProfile('mock-admin');
    await pumpEventQueue();
    expect(p.isLoggedIn, isTrue);
    expect(p.isAdmin, isFalse);
    expect(p.user!.role, UserRole.user);
    expect(p.user!.providerStatus, ProviderStatus.none);
    expect(p.user!.providerNote, isNull);
  });

  test('profil penyedia terhapus: bukan penyedia lagi', () async {
    await signInWarga();
    auth.updateProfile('mock-user', providerStatus: ProviderStatus.active, providerNote: 'x');
    await pumpEventQueue();
    expect(p.isProvider, isTrue);
    auth.deleteProfile('mock-user');
    await pumpEventQueue();
    expect(p.isProvider, isFalse);
    expect(p.user!.providerNote, isNull);
  });

  test('setelah keluar, perubahan profil tidak memunculkan pengguna', () async {
    await signInWarga();
    await p.signOut();
    await pumpEventQueue();
    expect(p.isLoggedIn, isFalse);

    auth.updateProfile('mock-user', providerStatus: ProviderStatus.active);
    auth.deleteProfile('mock-user');
    await pumpEventQueue();
    expect(p.isLoggedIn, isFalse);
  });

  test('AppUser.copyWith: clearProviderNote mengalahkan nilai baru', () {
    const u = AppUser(uid: 'u', name: 'N', email: 'e@x.id', providerNote: 'a');
    expect(u.copyWith(providerNote: null).providerNote, 'a');
    expect(u.copyWith(clearProviderNote: true).providerNote, isNull);
    expect(u.copyWith(providerNote: 'b', clearProviderNote: true).providerNote, isNull);
  });
}
