import 'package:flutter_test/flutter_test.dart';
import 'package:aquaconnect/config.dart';
import 'package:aquaconnect/models/app_user.dart';
import 'package:aquaconnect/models/provider_application.dart';
import 'package:aquaconnect/models/water_report.dart';
import 'package:aquaconnect/models/water_source.dart';

Map<String, dynamic> _map([Map<String, dynamic> over = const {}]) => {
      'name': 'Sumur Uji',
      'address': 'Cengkareng',
      'latitude': -6.14,
      'longitude': 106.73,
      'sourceType': 'publicWell',
      'availability': 'available',
      'intendedUse': 'Belum diverifikasi',
      'openingHours': '24 jam',
      ...over,
    };

void main() {
  group('asDateTime', () {
    test('null tetap null (tidak dipalsukan menjadi sekarang)', () {
      expect(asDateTime(null), isNull);
    });
    test('menerima DateTime dan string ISO', () {
      final d = DateTime(2026, 1, 2);
      expect(asDateTime(d), d);
      expect(asDateTime('2026-01-02T00:00:00.000'), d);
    });
    test('nilai asing menjadi null', () {
      expect(asDateTime(123), isNull);
    });
  });

  group('WaterSource.fromMap', () {
    test('field baru punya nilai bawaan aman', () {
      final s = WaterSource.fromMap('a', _map());
      expect(s.isActive, isTrue);
      expect(s.qualityFlag, isFalse);
      expect(s.updatedAt, isNull);
      expect(s.verifiedAt, isNull);
    });

    test('jenis asing menjadi SourceType.other', () {
      final s = WaterSource.fromMap('a', _map({'sourceType': 'jenisBaru'}));
      expect(s.type, SourceType.other);
    });

    test('ketersediaan asing melempar agar dokumen dilewati dan dihitung', () {
      expect(() => WaterSource.fromMap('a', _map({'availability': 'entah'})),
          throwsFormatException);
    });
  });

  group('staleLabel', () {
    WaterSource withVerified(DateTime? v) => WaterSource(
          id: 'a',
          name: 'x',
          address: 'y',
          latitude: 0,
          longitude: 0,
          type: SourceType.publicWell,
          availability: Availability.available,
          intendedUse: '',
          openingHours: '-',
          verifiedAt: v,
        );

    test('belum pernah dikonfirmasi', () {
      expect(withVerified(null).staleLabel, contains('belum pernah'));
    });
    test('segar tidak berlabel', () {
      expect(
          withVerified(DateTime.now().subtract(const Duration(hours: 1))).staleLabel,
          isNull);
    });
    test('kedaluwarsa berlabel hari', () {
      expect(
          withVerified(DateTime.now().subtract(const Duration(days: 5))).staleLabel,
          contains('5 hari'));
    });
  });

  group('WaterSource: siklus hidup dan kepemilikan (Fase 2)', () {
    WaterSource src({
      ListingStatus status = ListingStatus.published,
      String? ownerId,
      String? ownerName,
      VerifiedBy? verifiedBy,
      String? reviewNote,
      String? closedReason,
      DateTime? closedAt,
      DateTime? verifiedAt,
    }) =>
        WaterSource(
          id: 'a',
          name: 'Sumur Uji',
          address: 'Cengkareng',
          latitude: -6.14,
          longitude: 106.73,
          type: SourceType.publicWell,
          availability: Availability.available,
          intendedUse: 'Belum diverifikasi',
          openingHours: '24 jam',
          verifiedAt: verifiedAt,
          listingStatus: status,
          ownerId: ownerId,
          ownerName: ownerName,
          verifiedBy: verifiedBy,
          reviewNote: reviewNote,
          closedReason: closedReason,
          closedAt: closedAt,
        );

    test('dokumen lama tanpa field baru dan isActive true menjadi published', () {
      final s = WaterSource.fromMap('a', _map({'isActive': true}));
      expect(s.listingStatus, ListingStatus.published);
      expect(s.isActive, isTrue);
      expect(s.ownerId, isNull);
      expect(s.hasOwner, isFalse);
      expect(s.verifiedBy, isNull);
    });

    test('dokumen lama tanpa isActive dianggap published', () {
      expect(WaterSource.fromMap('a', _map()).isActive, isTrue);
    });

    test('dokumen lama dengan isActive false menjadi closed (tersembunyi)', () {
      final s = WaterSource.fromMap('a', _map({'isActive': false}));
      expect(s.listingStatus, ListingStatus.closed);
      expect(s.isActive, isFalse);
    });

    test('listingStatus asing diperlakukan suspended (aman: tersembunyi)', () {
      final s = WaterSource.fromMap('a', _map({'listingStatus': 'entah', 'isActive': true}));
      expect(s.listingStatus, ListingStatus.suspended);
      expect(s.isActive, isFalse);
    });

    test('listingStatus eksplisit mengalahkan isActive lama', () {
      final s = WaterSource.fromMap('a', _map({'listingStatus': 'pending', 'isActive': true}));
      expect(s.listingStatus, ListingStatus.pending);
      expect(s.isActive, isFalse);
    });

    test('field kepemilikan dibaca; verifiedBy asing menjadi null', () {
      final s = WaterSource.fromMap(
          'a',
          _map({
            'ownerId': 'p1',
            'ownerName': 'Pos Air Mawar',
            'verifiedBy': 'provider',
            'reviewNote': 'Pin kurang tepat',
          }));
      expect(s.hasOwner, isTrue);
      expect(s.ownerName, 'Pos Air Mawar');
      expect(s.verifiedBy, VerifiedBy.provider);
      expect(s.reviewNote, 'Pin kurang tepat');
      expect(WaterSource.fromMap('a', _map({'verifiedBy': 'siapa'})).verifiedBy, isNull);
    });

    test('toMap SELALU menulis isActive konsisten dengan listingStatus', () {
      for (final st in ListingStatus.values) {
        final m = src(status: st).toMap();
        expect(m['listingStatus'], st.name);
        expect(m['isActive'], st == ListingStatus.published, reason: st.name);
      }
    });

    test('toMap menghilangkan kolom opsional yang kosong (bukan menulis null)', () {
      final m = src().toMap();
      for (final k in [
        'ownerId', 'ownerName', 'verifiedBy', 'reviewNote', 'closedReason', 'closedAt'
      ]) {
        expect(m.containsKey(k), isFalse, reason: k);
      }
      expect(m.values.any((v) => v == null), isFalse);
      expect(src(reviewNote: '').toMap().containsKey('reviewNote'), isFalse);
    });

    test('toMap memuat kolom kepemilikan bila ada, dan bisa dibaca kembali', () {
      final closed = DateTime(2026, 11, 3);
      final original = src(
        status: ListingStatus.closed,
        ownerId: 'p1',
        ownerName: 'Pos Air Mawar',
        verifiedBy: VerifiedBy.provider,
        closedReason: 'tidak lagi menyediakan',
        closedAt: closed,
      );
      final back = WaterSource.fromMap('a', original.toMap());
      expect(back.listingStatus, ListingStatus.closed);
      expect(back.ownerId, 'p1');
      expect(back.verifiedBy, VerifiedBy.provider);
      expect(back.closedReason, 'tidak lagi menyediakan');
      expect(back.closedAt, closed);
    });

    test('copyWith dan withId mempertahankan kepemilikan', () {
      final s = src(ownerId: 'p1', ownerName: 'Pos Air Mawar', verifiedBy: VerifiedBy.admin);
      final c = s.copyWith(availability: Availability.limited).withId('b');
      expect(c.id, 'b');
      expect(c.ownerId, 'p1');
      expect(c.ownerName, 'Pos Air Mawar');
      expect(c.verifiedBy, VerifiedBy.admin);
      expect(c.availability, Availability.limited);
    });

    test('copyWith tanpa bendera tidak bisa mengosongkan; dengan bendera bisa', () {
      final s = src(
        reviewNote: 'Pin kurang tepat',
        closedReason: 'tutup',
        closedAt: DateTime(2026, 11, 3),
      );
      expect(s.copyWith(reviewNote: null, closedReason: null).reviewNote, 'Pin kurang tepat');

      final cleared = s.copyWith(clearReviewNote: true, clearClosed: true);
      expect(cleared.reviewNote, isNull);
      expect(cleared.closedReason, isNull);
      expect(cleared.closedAt, isNull);

      // Tidak menyentuh bagian lain.
      expect(cleared.name, s.name);
      expect(cleared.listingStatus, s.listingStatus);
    });

    test('bendera clear mengalahkan nilai baru pada field yang sama', () {
      final s = src(reviewNote: 'lama');
      expect(s.copyWith(reviewNote: 'baru', clearReviewNote: true).reviewNote, isNull);
    });

    test('setiap ListingStatus punya label dan ikon', () {
      for (final st in ListingStatus.values) {
        expect(st.label, isNotEmpty);
        expect(st.icon, isNotNull);
      }
    });

    group('freshness', () {
      final base = DateTime(2026, 11, 1, 12);
      WaterSource at(DateTime? v) => src(verifiedAt: v);

      test('kurang dari 3 hari: fresh', () {
        final now = base.add(const Duration(days: 2, hours: 23));
        expect(at(base).freshness(now), Freshness.fresh);
      });
      test('3 hari lewat 1 menit: stale', () {
        final now = base.add(const Duration(days: 3, minutes: 1));
        expect(at(base).freshness(now), Freshness.stale);
      });
      test('tepat sebelum 7 hari tetap stale', () {
        final now = base.add(const Duration(days: 6, hours: 23));
        expect(at(base).freshness(now), Freshness.stale);
      });
      test('7 hari lewat 1 menit: expired', () {
        final now = base.add(const Duration(days: 7, minutes: 1));
        expect(at(base).freshness(now), Freshness.expired);
      });
      test('verifiedAt null: expired', () {
        expect(at(null).freshness(base), Freshness.expired);
      });
      test('ambang sesuai konstanta konfigurasi', () {
        expect(kStaleAfter, const Duration(hours: 72));
        expect(kHideAfter, const Duration(days: 7));
        expect(kReconfirmReminderAfter, const Duration(hours: 48));
      });
    });
  });

  group('AppUser: status penyedia', () {
    test('bawaan none dan bukan penyedia', () {
      const u = AppUser(uid: 'u', name: 'N', email: 'e@x.id');
      expect(u.providerStatus, ProviderStatus.none);
      expect(u.isProvider, isFalse);
    });
    test('hanya active yang dihitung penyedia', () {
      AppUser u(ProviderStatus s) =>
          AppUser(uid: 'u', name: 'N', email: 'e@x.id', providerStatus: s);
      expect(u(ProviderStatus.active).isProvider, isTrue);
      expect(u(ProviderStatus.terminated).isProvider, isFalse);
      expect(u(ProviderStatus.none).isProvider, isFalse);
    });
  });

  group('ProviderApplication', () {
    test('validasi nomor telepon sama dengan rules', () {
      expect(ProviderApplication.isValidPhone('0812 3456 7890'), isTrue);
      expect(ProviderApplication.isValidPhone('+62812345678'), isTrue);
      expect(ProviderApplication.isValidPhone('12345'), isFalse); // terlalu pendek
      expect(ProviderApplication.isValidPhone('0812-3456'), isFalse); // tanda hubung
      expect(ProviderApplication.isValidPhone('abc12345'), isFalse);
      expect(ProviderApplication.isValidPhone('1' * 21), isFalse);
    });

    test('status asing tidak memberi hak: ditampilkan sebagai menunggu', () {
      final a = ProviderApplication.fromMap('u', {
        'organizationName': 'Pos Air',
        'contactPhone': '081234567',
        'description': 'Sumur warga RW 03',
        'termsVersion': 1,
        'status': 'superadmin',
      });
      expect(a.status, ApplicationStatus.pending);
    });

    test('toSubmitMap memaksa pending, catatan kosong, dan memangkas spasi', () {
      const a = ProviderApplication(
        uid: 'u',
        organizationName: '  Pos Air Mawar ',
        contactPhone: ' 0812 3456 ',
        description: ' Sumur warga RW 03 ',
        termsVersion: 1,
        status: ApplicationStatus.approved,
        adminNote: 'jangan ikut',
      );
      final m = a.toSubmitMap();
      expect(m['status'], 'pending');
      expect(m['adminNote'], '');
      expect(m['organizationName'], 'Pos Air Mawar');
      expect(m['termsVersion'], kProviderTermsVersion);
      expect(m.containsKey('createdAt'), isFalse); // diisi service (serverTimestamp)
    });
  });

  group('ReportType', () {
    test('setiap jenis punya label dan ikon', () {
      for (final t in ReportType.values) {
        expect(t.label, isNotEmpty);
        expect(t.icon, isNotNull);
      }
      expect(ReportType.noLongerOperating.label, 'Sudah tidak beroperasi');
    });
  });
}
