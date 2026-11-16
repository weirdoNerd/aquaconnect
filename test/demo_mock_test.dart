import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/dev/dummy_sources.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/dev/mock_provider_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/provider_application.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/screens/login_screen.dart';
import 'package:aquaconnect/services/source_service.dart';

WaterSource _draftSource() => const WaterSource(
      id: '',
      name: '[SIMULASI] Sumur Uji Demo',
      address: 'Cengkareng, Jakarta Barat',
      latitude: -6.1450,
      longitude: 106.7350,
      type: SourceType.publicWell,
      availability: Availability.available,
      intendedUse: 'Kebutuhan rumah tangga',
      openingHours: '07:00-17:00',
    );

void main() {
  group('D1: identitas & izin operasi penyedia di mode tiruan', () {
    test('login penyedia mengizinkan operasi penyedia; keluar lalu ditolak', () async {
      final auth = MockAuthService();
      final sources = MockSourceService();
      final sub = auth.authChanges.listen((u) => sources.actAs(u?.uid));
      addTearDown(sub.cancel);

      // Sebelum login: ditolak.
      await expectLater(
        sources.confirmStillCurrent('sim-prov-1'),
        throwsA(isA<SourceException>()),
      );

      // Login sebagai penyedia demo.
      final user = await auth.signIn('penyedia@aquaconnect.test', 'penyedia123');
      await pumpEventQueue();
      expect(user.uid, 'mock-provider');
      expect(user.name, 'Penyedia Demo');
      expect(user.providerStatus, ProviderStatus.active);
      expect(user.emailVerified, isTrue);

      // Operasi penyedia diizinkan.
      await sources.confirmStillCurrent('sim-prov-1');
      await sources.createAsProvider(
          _draftSource(), user.uid, user.name);

      // Keluar: operasi penyedia kembali ditolak.
      await auth.signOut();
      await pumpEventQueue();
      await expectLater(
        sources.confirmStillCurrent('sim-prov-1'),
        throwsA(isA<SourceException>()),
      );
    });
  });

  group('D1: persetujuan MockProviderService mengubah profil MockAuthService', () {
    test('review(approve: true), terminate, dan reactivate langsung memancarkan profil baru',
        () async {
      final auth = MockAuthService();
      final sources = MockSourceService();
      final providers = MockProviderService(sources, auth: auth);

      // Calon sudah login dan memiliki 1 pengajuan pending bawaan.
      final calon = await auth.signIn('calon@aquaconnect.test', 'calon123');
      expect(calon.uid, 'mock-calon');
      expect(calon.providerStatus, ProviderStatus.none);
      expect(calon.emailVerified, isTrue);

      final emitted = <ProviderStatus>[];
      final sub = auth.authChanges.listen((u) {
        if (u != null) emitted.add(u.providerStatus);
      });
      addTearDown(sub.cancel);
      await pumpEventQueue();

      // Admin menyetujui -> langsung active tanpa keluar-masuk.
      await providers.review('mock-calon', approve: true);
      await pumpEventQueue();
      expect(auth.currentUser!.providerStatus, ProviderStatus.active);
      expect(emitted.last, ProviderStatus.active);

      // Admin memutus kemitraan -> langsung terminated + providerNote.
      await providers.terminate('mock-calon', 'Melanggar ketentuan penyedia.');
      await pumpEventQueue();
      expect(auth.currentUser!.providerStatus, ProviderStatus.terminated);
      expect(auth.currentUser!.providerNote, 'Melanggar ketentuan penyedia.');
      expect(emitted.last, ProviderStatus.terminated);

      // Admin mengaktifkan kembali -> langsung active + providerNote terhapus.
      await providers.reactivate('mock-calon');
      await pumpEventQueue();
      expect(auth.currentUser!.providerStatus, ProviderStatus.active);
      expect(auth.currentUser!.providerNote, isNull);
      expect(emitted.last, ProviderStatus.active);
    });

    test('review(approve: false) menjaga providerStatus tetap none', () async {
      final auth = MockAuthService();
      final sources = MockSourceService();
      final providers = MockProviderService(sources, auth: auth);

      await auth.signIn('warga@aquaconnect.test', 'warga123');
      await providers.apply(const ProviderApplication(
        uid: 'mock-user',
        organizationName: 'Pos Air Warga',
        contactPhone: '08123456789',
        description: 'Menyediakan air bersih untuk warga sekitar.',
        termsVersion: 1,
      ));

      await providers.review('mock-user', approve: false, note: 'Dokumen belum lengkap.');
      await pumpEventQueue();
      expect(auth.currentUser!.providerStatus, ProviderStatus.none);
    });
  });

  group('D1: data seed demo', () {
    test('seed pengajuan pending untuk mock-calon tersedia', () async {
      final providers = MockProviderService(MockSourceService());
      final pending = await providers.watchPending().first;
      expect(pending.any((a) => a.uid == 'mock-calon'), isTrue);
      final calonApp = pending.firstWhere((a) => a.uid == 'mock-calon');
      expect(calonApp.status, ApplicationStatus.pending);
    });

    test('seed dummySources memiliki umur 2 jam, 4 hari, 8 hari, pending, dan admin 5 hari',
        () {
      expect(dummySources.every((s) => s.isSimulated), isTrue);
      expect(dummySources.every((s) => s.name.startsWith('[SIMULASI]')), isTrue);

      final owned = dummySources.where((s) => s.ownerId == 'mock-provider').toList();
      expect(owned.length, 4);
      expect(owned.every((s) => s.ownerName == 'Penyedia Demo'), isTrue);
      expect(owned.every((s) => s.verifiedBy == VerifiedBy.provider), isTrue);

      final now = DateTime.now();

      final fresh = owned.firstWhere((s) => s.id == 'sim-prov-1');
      expect(fresh.availability, Availability.available);
      expect(fresh.listingStatus, ListingStatus.published);
      expect(now.difference(fresh.verifiedAt!).inHours, inInclusiveRange(1, 3));
      expect(fresh.freshness(now), Freshness.fresh);

      final stale = owned.firstWhere((s) => s.id == 'sim-prov-2');
      expect(stale.availability, Availability.limited);
      expect(stale.listingStatus, ListingStatus.published);
      expect(now.difference(stale.verifiedAt!).inDays, 4);
      expect(stale.freshness(now), Freshness.stale);

      final expired = owned.firstWhere((s) => s.id == 'sim-prov-3');
      expect(expired.availability, Availability.available);
      expect(expired.listingStatus, ListingStatus.published);
      expect(now.difference(expired.verifiedAt!).inDays, 8);
      expect(expired.freshness(now), Freshness.expired);

      final pending = owned.firstWhere((s) => s.id == 'sim-prov-4');
      expect(pending.listingStatus, ListingStatus.pending);
      expect(pending.isActive, isFalse);

      // Sumber kelolaan admin 5 hari lalu tetap ada dan menampilkan label.
      final adminStale = dummySources.firstWhere((s) => s.id == 'sim-4');
      expect(adminStale.ownerId, isNull);
      expect(now.difference(adminStale.verifiedAt!).inDays, 5);
      expect(adminStale.staleLabel, 'Belum dikonfirmasi 5 hari');
    });

    testWidgets('LoginScreen menampilkan 4 akun demo pada mode debug non-Firebase',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => AuthProvider(MockAuthService()),
          child: const LoginScreen(),
        ),
      ));

      expect(find.textContaining('admin@aquaconnect.test'), findsOneWidget);
      expect(find.textContaining('warga@aquaconnect.test'), findsOneWidget);
      expect(find.textContaining('penyedia@aquaconnect.test'), findsOneWidget);
      expect(find.textContaining('calon@aquaconnect.test'), findsOneWidget);
    });
  });
}
