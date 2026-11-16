import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:aquaconnect/app_providers.dart';
import 'package:aquaconnect/config.dart';
import 'package:aquaconnect/dev/mock_auth_service.dart';
import 'package:aquaconnect/dev/mock_provider_service.dart';
import 'package:aquaconnect/dev/mock_report_service.dart';
import 'package:aquaconnect/dev/mock_source_service.dart';
import 'package:aquaconnect/models/provider_application.dart';
import 'package:aquaconnect/models/water_source.dart';
import 'package:aquaconnect/providers/auth_provider.dart';
import 'package:aquaconnect/providers/my_sources_provider.dart';
import 'package:aquaconnect/providers/source_provider.dart';
import 'package:aquaconnect/screens/admin_screen.dart';
import 'package:aquaconnect/screens/location_picker_screen.dart';
import 'package:aquaconnect/screens/my_sources_screen.dart';
import 'package:aquaconnect/screens/source_form_screen.dart';
import 'helpers/fakes.dart';

WaterSource _draft({
  String id = '',
  String name = 'Depot S7',
  ListingStatus status = ListingStatus.pending,
  String? ownerId = 'mock-provider',
  String? ownerName = 'Penyedia Demo',
  String? reviewNote,
}) =>
    WaterSource(
      id: id,
      name: name,
      address: 'Jl. Daan Mogot No. 12, Cengkareng',
      latitude: -6.148,
      longitude: 106.737,
      type: SourceType.refillStation,
      availability: Availability.available,
      intendedUse: 'Air minum isi ulang',
      openingHours: '08:00-17:00',
      listingStatus: status,
      ownerId: ownerId,
      ownerName: ownerName,
      verifiedBy: VerifiedBy.provider,
      reviewNote: reviewNote,
    );

Widget _harness({
  required MockAuthService auth,
  required MockSourceService sources,
  required MockProviderService providers,
  required Widget home,
}) {
  return MultiProvider(
    key: UniqueKey(),
    providers: appProviders(
      authService: auth,
      reportService: MockReportService(sources),
      sourceService: sources,
      providerService: providers,
      locationService: NoLocation(),
    ),
    child: MaterialApp(home: home),
  );
}

Future<void> _signInProvider(
  WidgetTester tester,
  MockAuthService auth,
  MockSourceService sources,
) async {
  await tester.runAsync(
      () => auth.signIn('penyedia@aquaconnect.test', 'penyedia123'));
  sources.actAs('mock-provider');
}

Future<void> _signInAdmin(WidgetTester tester, MockAuthService auth) async {
  await tester.runAsync(() => auth.signIn('admin@aquaconnect.test', 'admin123'));
}

void main() async {
  await initializeDateFormatting('id_ID');

  group('Provider & layanan S7', () {
    test('MySourcesProvider: createAsProvider & resubmit sesuai izin dan status',
        () async {
      final sources = MockSourceService();
      final p = MySourcesProvider(sources);

      // Non-provider ditolak.
      p.syncUser('u1', isProvider: false);
      expect(await p.createAsProvider(_draft(), 'Pos'), isNotNull);
      expect(await p.resubmit(_draft(id: 'x')), isNotNull);

      // Provider aktif menambah -> status pending, ownerName diisi, tidak tayang.
      sources.actAs('mock-provider');
      p.syncUser('mock-provider', isProvider: true);
      expect(await p.createAsProvider(_draft(name: 'Sumber S7'), 'Penyedia Demo'),
          isNull);

      final owned = (await sources.watchOwned('mock-provider').first).sources;
      final created = owned.firstWhere((s) => s.name == 'Sumber S7');
      expect(created.listingStatus, ListingStatus.pending);
      expect(created.isActive, isFalse);
      expect(created.ownerName, 'Penyedia Demo');

      final published =
          (await sources.watchPublished().first).sources.map((s) => s.id);
      expect(published, isNot(contains(created.id)));

      // Pending boleh diedit lewat resubmit.
      expect(
        await p.resubmit(WaterSource(
          id: created.id,
          name: 'Sumber S7 Revisi',
          address: created.address,
          latitude: created.latitude,
          longitude: created.longitude,
          type: created.type,
          availability: created.availability,
          intendedUse: created.intendedUse,
          openingHours: created.openingHours,
          listingStatus: created.listingStatus,
          ownerId: created.ownerId,
          ownerName: created.ownerName,
        )),
        isNull,
      );

      // Setelah tayang, resubmit ditolak (hanya jalur operasional).
      await sources.setListing(created.id, ListingStatus.published);
      final tayang = (await sources.watchOwned('mock-provider').first)
          .sources
          .firstWhere((s) => s.id == created.id);
      expect(
        await p.resubmit(WaterSource(
          id: tayang.id,
          name: 'Coba Ubah Nama',
          address: tayang.address,
          latitude: tayang.latitude,
          longitude: tayang.longitude,
          type: tayang.type,
          availability: tayang.availability,
          intendedUse: 'Coba ubah klaim air',
          openingHours: tayang.openingHours,
          listingStatus: tayang.listingStatus,
          ownerId: tayang.ownerId,
          ownerName: tayang.ownerName,
        )),
        isNotNull,
      );
    });

    test('SourceProvider.setListingStatus memvalidasi catatan tolak & menayangkan',
        () async {
      final sources = MockSourceService();
      sources.actAs('mock-provider');
      await sources.createAsProvider(
          _draft(name: 'Menunggu Admin'), 'mock-provider', 'Penyedia Demo');
      final pending = (await sources.watchOwned('mock-provider').first)
          .sources
          .firstWhere((s) => s.name == 'Menunggu Admin');

      final sp = SourceProvider(sources, NoLocation())
        ..syncUser('admin1', isAdmin: true, isProvider: false);

      expect(
        await sp.setListingStatus(pending.id, ListingStatus.rejected, note: 'abc'),
        contains('Alasan penolakan'),
      );
      expect(
        await sp.setListingStatus(pending.id, ListingStatus.rejected,
            note: 'Pin lokasi salah'),
        isNull,
      );
      final rej = (await sources.watchAll().first)
          .sources
          .firstWhere((s) => s.id == pending.id);
      expect(rej.listingStatus, ListingStatus.rejected);
      expect(rej.reviewNote, 'Pin lokasi salah');

      expect(
        await sp.setListingStatus(pending.id, ListingStatus.published),
        isNull,
      );
      final pub = (await sources.watchAll().first)
          .sources
          .firstWhere((s) => s.id == pending.id);
      expect(pub.listingStatus, ListingStatus.published);
      expect(pub.isActive, isTrue);
      expect(pub.reviewNote, isNull);
    });
  });

  group('Widget S7 penyedia & admin', () {
    testWidgets(
        'MySourcesScreen -> Tambah sumber (mode providerNew) menyembunyikan kontrol admin, '
        'memakai organizationName, dan sumber baru belum muncul di publik',
        (tester) async {
      final sources = MockSourceService();
      final auth = MockAuthService();
      final providers = MockProviderService(sources, auth: auth);
      await _signInProvider(tester, auth, sources);

      await tester.pumpWidget(_harness(
        auth: auth,
        sources: sources,
        providers: providers,
        home: const MySourcesScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tambah sumber'));
      await tester.pumpAndSettle();

      // Mode penyedia: kontrol khusus admin tidak tampil, ownerName otomatis tampil.
      expect(find.text('Tambah Sumber Penyedia'), findsOneWidget);
      expect(find.text('Penyedia Demo'), findsOneWidget);
      expect(find.text('Data simulasi'), findsNothing);
      expect(find.text('Tampilkan di aplikasi'), findsNothing);
      expect(find.text('Konfirmasi status sekarang'), findsNothing);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Depot Baru Warga');
      await tester.enterText(fields.at(1), 'Jl. Kapuk Raya No. 8');
      await tester.enterText(fields.at(2), 'Air bersih kebutuhan memasak');
      await tester.enterText(fields.at(3), '07:00-19:00');

      // Pilih lokasi lewat LocationPickerScreen (tempel koordinat).
      await tester.ensureVisible(find.text('Pilih lokasi di peta'));
      await tester.tap(find.text('Pilih lokasi di peta'));
      await tester.pumpAndSettle();
      expect(find.byType(LocationPickerScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Tempel koordinat'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '-6.1480, 106.7370');
      await tester.tap(find.text('Terapkan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gunakan lokasi ini'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Kirim untuk verifikasi'));
      await tester.tap(find.text('Kirim untuk verifikasi'));
      await tester.pumpAndSettle();

      expect(find.text('Sumber dikirim, menunggu verifikasi admin'),
          findsOneWidget);
      final owned = (await sources.watchOwned('mock-provider').first).sources;
      final created = owned.firstWhere((s) => s.name == 'Depot Baru Warga');
      expect(created.ownerName, 'Penyedia Demo');
      expect(created.listingStatus, ListingStatus.pending);
      expect(created.isActive, isFalse);

      final sp = tester
          .element(find.byType(MySourcesScreen))
          .read<SourceProvider>();
      expect(sp.items.any((s) => s.id == created.id), isFalse);
    });

    testWidgets(
        'Sumber ditolak menampilkan alasan di Sumber Saya -> Edit -> Ajukan ulang',
        (tester) async {
      final sources = MockSourceService();
      final auth = MockAuthService();
      final providers = MockProviderService(sources, auth: auth);
      await _signInProvider(tester, auth, sources);

      sources.actAs('mock-provider');
      await sources.createAsProvider(
          _draft(name: 'Sumber Ditolak Uji'), 'mock-provider', 'Penyedia Demo');
      final created = (await sources.watchOwned('mock-provider').first)
          .sources
          .firstWhere((s) => s.name == 'Sumber Ditolak Uji');
      await sources.setListing(created.id, ListingStatus.rejected,
          note: 'Alamat kurang lengkap');

      await tester.pumpWidget(_harness(
        auth: auth,
        sources: sources,
        providers: providers,
        home: const MySourcesScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Alasan ditolak: Alamat kurang lengkap'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Alasan ditolak: Alamat kurang lengkap'), findsOneWidget);

      // Cari kartu sumber ditolak lalu ketuk Edit di kartu itu.
      final rejectedCard = find.ancestor(
        of: find.text('Sumber Ditolak Uji'),
        matching: find.byType(Card),
      );
      final editBtn =
          find.descendant(of: rejectedCard, matching: find.text('Edit'));
      await tester.ensureVisible(editBtn);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      expect(find.text('Ubah Sumber Saya'), findsOneWidget);
      expect(find.textContaining('Alasan ditolak: Alamat kurang lengkap'),
          findsOneWidget);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'Jl. Cengkareng Barat Blok B2');
      await tester.ensureVisible(find.text('Ajukan ulang'));
      await tester.tap(find.text('Ajukan ulang'));
      await tester.pumpAndSettle();

      final updated = (await sources.watchOwned('mock-provider').first)
          .sources
          .firstWhere((s) => s.id == created.id);
      expect(updated.listingStatus, ListingStatus.pending);
      expect(updated.address, 'Jl. Cengkareng Barat Blok B2');
      expect(updated.reviewNote, isNull);
    });

    testWidgets(
        'Edit sumber tayang di mode penyedia mengunci nama, alamat, jenis, tujuan, dan lokasi; '
        'hanya ubah jam layanan & ketersediaan lewat updateOperational',
        (tester) async {
      final sources = MockSourceService();
      final auth = MockAuthService();
      final providers = MockProviderService(sources, auth: auth);
      await _signInProvider(tester, auth, sources);

      final published = (await sources.watchOwned('mock-provider').first)
          .sources
          .firstWhere((s) => s.listingStatus == ListingStatus.published);

      await tester.pumpWidget(_harness(
        auth: auth,
        sources: sources,
        providers: providers,
        home: SourceFormScreen(
          source: published,
          mode: SourceFormMode.providerEdit,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Sumber sudah tayang. Nama, alamat, jenis sumber, tujuan penggunaan, dan lokasi dikunci'),
        findsOneWidget,
      );

      // Name, address, dan intendedUse terkunci (enabled == false).
      final nameField = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
      final addrField = tester.widget<TextFormField>(find.byType(TextFormField).at(1));
      final useField = tester.widget<TextFormField>(find.byType(TextFormField).at(2));
      final hoursField = tester.widget<TextFormField>(find.byType(TextFormField).at(3));
      expect(nameField.enabled, isFalse);
      expect(addrField.enabled, isFalse);
      expect(useField.enabled, isFalse);
      expect(hoursField.enabled, isTrue);

      // Chip SourceType terkunci.
      final sumurChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, SourceType.publicWell.label),
      );
      expect(sumurChip.onSelected, isNull);

      // Ketuk peta tidak membuka LocationPickerScreen.
      await tester.ensureVisible(find.textContaining('• lokasi dikunci'));
      await tester.tap(find.byType(FlutterMap));
      await tester.pumpAndSettle();
      expect(find.byType(LocationPickerScreen), findsNothing);

      // Ubah status ke Terbatas dan jam layanan, lalu simpan.
      final limitedChip =
          find.widgetWithText(ChoiceChip, Availability.limited.label).first;
      await tester.ensureVisible(limitedChip);
      await tester.tap(limitedChip);
      await tester.enterText(find.byType(TextFormField).at(3), '09:00-15:00');
      await tester.ensureVisible(find.text('Simpan perubahan'));
      await tester.tap(find.text('Simpan perubahan'));
      await tester.pumpAndSettle();

      final after = (await sources.watchOwned('mock-provider').first)
          .sources
          .firstWhere((s) => s.id == published.id);
      expect(after.name, published.name);
      expect(after.intendedUse, published.intendedUse);
      expect(after.availability, Availability.limited);
      expect(after.openingHours, '09:00-15:00');
    });

    testWidgets(
        'Admin: tab Sumber air menyaring Menunggu verifikasi (n) dan meninjau lewat ListingReviewSheet (tolak wajib catatan & setujui menayangkan)',
        (tester) async {
      final sources = MockSourceService();
      final auth = MockAuthService();
      final providers = MockProviderService(sources, auth: auth);

      sources.actAs('mock-provider');
      await sources.createAsProvider(
          _draft(name: 'Sumber Antre Pertama'), 'mock-provider', 'Penyedia Demo');
      await _signInAdmin(tester, auth);

      await tester.pumpWidget(_harness(
        auth: auth,
        sources: sources,
        providers: providers,
        home: const AdminScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sumber air'));
      await tester.pumpAndSettle();

      final pendingChip = find.textContaining('Menunggu verifikasi (');
      expect(pendingChip, findsOneWidget);
      await tester.tap(pendingChip);
      await tester.pumpAndSettle();

      expect(find.text('Sumber Antre Pertama'), findsOneWidget);
      await tester.tap(find.text('Sumber Antre Pertama'));
      await tester.pumpAndSettle();

      expect(find.text('Tinjau sumber penyedia'), findsOneWidget);
      expect(
        find.textContaining('Periksa posisi pin pada peta'),
        findsOneWidget,
      );

      // Tolak tanpa catatan wajib ditahan oleh validasi.
      await tester.ensureVisible(find.text('Tolak'));
      await tester.tap(find.text('Tolak'));
      await tester.pumpAndSettle();
      expect(find.text('Alasan penolakan wajib diisi (min. 5 karakter).'),
          findsOneWidget);

      // Setujui -> menjadi published & isActive = true.
      await tester.ensureVisible(find.text('Setujui'));
      await tester.tap(find.text('Setujui'));
      await tester.pumpAndSettle();

      expect(find.text('Sumber disetujui dan ditayangkan.'), findsOneWidget);
      final approved = (await sources.watchAll().first)
          .sources
          .firstWhere((s) => s.name == 'Sumber Antre Pertama');
      expect(approved.listingStatus, ListingStatus.published);
      expect(approved.isActive, isTrue);
      expect(approved.verifiedBy, VerifiedBy.admin);
    });
  });

  group('Keselarasan kontrak dasar', () {
    test('providerNew memakai kProviderTermsVersion di aplikasi demo', () async {
      final sources = MockSourceService();
      final providers = MockProviderService(sources);
      final app = await providers.watchMyApplication('mock-provider').first;
      expect(app, isNotNull);
      expect(app!.status, ApplicationStatus.approved);
      expect(app.organizationName, 'Penyedia Demo');
      expect(app.termsVersion, kProviderTermsVersion);
      final auth = MockAuthService();
      await auth.signIn('penyedia@aquaconnect.test', 'penyedia123');
      final ap = AuthProvider(auth);
      expect(ap.isProvider, isTrue);
    });
  });
}
