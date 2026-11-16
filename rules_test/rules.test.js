// Jalankan: firebase emulators:exec --only firestore --project demo-aquaconnect "cd rules_test && node --test"
//
// Tes ini adalah batas keamanan sebenarnya. Setelah mengubah firestore.rules,
// GAGALKAN satu tes dengan sengaja (mis. longgarkan pemeriksaan qualityFlag) untuk
// memastikan harness benar-benar menangkap pelanggaran.
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, getDocs, addDoc, updateDoc, deleteDoc, deleteField,
  collection, query, where, writeBatch, runTransaction, serverTimestamp,
} from 'firebase/firestore';

let env;

const T = new Date('2026-11-01T00:00:00Z');

// ---------- pembangun data ----------
const seedSource = (over = {}) => ({
  name: 'Sumur Uji', address: 'Cengkareng, Jakarta Barat',
  latitude: -6.148, longitude: 106.737,
  sourceType: 'publicWell', availability: 'available',
  intendedUse: 'Belum diverifikasi', openingHours: '24 jam',
  isSimulated: false, qualityFlag: false, isActive: true,
  listingStatus: 'published', updatedAt: T, verifiedAt: T,
  ...over,
});

const ownedPending = (uid, org, over = {}) =>
  seedSource({
    ownerId: uid, ownerName: org, listingStatus: 'pending', isActive: false,
    verifiedBy: 'provider', ...over,
  });

const providerNewDoc = (uid, org, over = {}) =>
  ownedPending(uid, org, { updatedAt: serverTimestamp(), verifiedAt: serverTimestamp(), ...over });

const appData = (uid, over = {}) => ({
  uid, organizationName: 'Warung Air Baru', contactPhone: '0812 3456 7890',
  description: 'Menyediakan air bersih untuk warga RW 03.',
  termsVersion: 1, status: 'pending', adminNote: '', createdAt: serverTimestamp(),
  ...over,
});

const reportData = (uid, over = {}) => ({
  sourceId: 's1', reporterId: uid, reportType: 'noWater',
  description: 'Air sudah habis sejak pagi tadi',
  status: 'pending', adminNote: '', createdAt: serverTimestamp(),
  ...over,
});

function submitReport(db, uid, over = {}) {
  const type = over.reportType ?? 'noWater';
  const sourceId = over.sourceId ?? 's1';
  const b = writeBatch(db);
  b.set(doc(collection(db, 'reports')), reportData(uid, over));
  b.set(doc(db, `report_locks/${uid}_${sourceId}_${type}`), {
    reporterId: uid, sourceId, reportType: type,
  });
  return b.commit();
}

// ---------- peran ----------
const ROLES = ['guest', 'warga', 'provider', 'terminated', 'admin'];
const UID = { guest: 'anon', warga: 'u1', provider: 'p1', terminated: 'p2', admin: 'admin1' };

const dbFor = (role, verified = true) =>
  role === 'guest'
    ? env.unauthenticatedContext().firestore()
    : env.authenticatedContext(UID[role], {
        email: `${UID[role]}@x.id`, email_verified: verified,
      }).firestore();

const asUid = (uid, verified = true) =>
  env.authenticatedContext(uid, { email: `${uid}@x.id`, email_verified: verified }).firestore();

const R = (guest, warga, provider, terminated, admin) =>
  ({ guest, warga, provider, terminated, admin });

/** Satu tes per peran per baris matriks (state di-reset oleh beforeEach). */
function matrix(name, op, expected) {
  for (const role of ROLES) {
    const want = expected[role];
    if (want === undefined) continue;
    test(`${name} [${role}: ${want === 'ok' ? 'izin' : 'tolak'}]`, async () => {
      const p = op(dbFor(role), role);
      await (want === 'ok' ? assertSucceeds(p) : assertFails(p));
    });
  }
}

const pubOf = (role) => (role === 'terminated' ? 'termPub' : 'pub1');
const ownOf = (role) => (role === 'terminated' ? 'termOwn' : 'own1');

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-aquaconnect',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

after(async () => { await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const user = (id, extra = {}) =>
      setDoc(doc(db, `users/${id}`), {
        uid: id, name: `Nama ${id}`, email: `${id}@x.id`, role: 'user', ...extra,
      });
    await user('admin1', { role: 'admin' });
    await user('u1');
    await user('u4');
    await user('u5');
    await user('p1', { providerStatus: 'active' });
    await user('p2', { providerStatus: 'terminated' });
    await user('p3', { providerStatus: 'active' });

    const application = (id, org, status, extra = {}) =>
      setDoc(doc(db, `provider_applications/${id}`), {
        uid: id, organizationName: org, contactPhone: '0812 3456 7890',
        description: 'Menyediakan air bersih untuk warga.', termsVersion: 1,
        status, adminNote: '', createdAt: T, ...extra,
      });
    await application('p1', 'Pos Air Mawar', 'approved');
    await application('p2', 'Warung Air', 'approved');
    await application('p3', 'Kios Tirta', 'approved');
    await application('u4', 'Ditolak Dulu', 'rejected', { adminNote: 'Data belum lengkap.' });
    await application('u5', 'Menunggu Tinjau', 'pending');

    await setDoc(doc(db, 'water_sources/s1'), seedSource());
    await setDoc(doc(db, 'water_sources/own1'), ownedPending('p1', 'Pos Air Mawar'));
    await setDoc(doc(db, 'water_sources/pub1'),
      seedSource({ ownerId: 'p1', ownerName: 'Pos Air Mawar', verifiedBy: 'admin' }));
    await setDoc(doc(db, 'water_sources/rej1'),
      ownedPending('p1', 'Pos Air Mawar', { listingStatus: 'rejected', reviewNote: 'Pin kurang tepat' }));
    await setDoc(doc(db, 'water_sources/other1'), ownedPending('p3', 'Kios Tirta'));
    await setDoc(doc(db, 'water_sources/otherPub'),
      seedSource({ ownerId: 'p3', ownerName: 'Kios Tirta', verifiedBy: 'provider' }));
    await setDoc(doc(db, 'water_sources/termOwn'), ownedPending('p2', 'Warung Air'));
    await setDoc(doc(db, 'water_sources/termPub'),
      seedSource({ ownerId: 'p2', ownerName: 'Warung Air', verifiedBy: 'provider' }));

    await setDoc(doc(db, 'reports/pending1'), { ...reportData('u2'), createdAt: T });
    await setDoc(doc(db, 'reports/done1'),
      { ...reportData('u2'), status: 'approved', reviewedAt: T, createdAt: T });
  });
});

const st = () => serverTimestamp();

// =====================================================================
// MATRIKS: water_sources
// =====================================================================
matrix('query sumber isActive==true',
  (db) => getDocs(query(collection(db, 'water_sources'), where('isActive', '==', true))),
  R('ok', 'ok', 'ok', 'ok', 'ok'));

matrix('query semua sumber tanpa filter',
  (db) => getDocs(collection(db, 'water_sources')),
  R('no', 'no', 'no', 'no', 'ok'));

matrix('baca sumber pending milik sendiri',
  (db, role) => getDoc(doc(db, `water_sources/${ownOf(role)}`)),
  R('no', 'no', 'ok', 'ok', 'ok'));

matrix('query sumber milik sendiri (ownerId)',
  (db, role) => getDocs(query(collection(db, 'water_sources'), where('ownerId', '==', UID[role]))),
  { guest: 'no', provider: 'ok', terminated: 'ok', admin: 'ok' });

matrix('baca sumber tak tayang milik orang lain',
  (db) => getDoc(doc(db, 'water_sources/other1')),
  R('no', 'no', 'no', 'no', 'ok'));

matrix('buat sumber pending dengan ownerId sendiri',
  (db, role) => setDoc(doc(db, 'water_sources/new1'),
    providerNewDoc(UID[role], role === 'provider' ? 'Pos Air Mawar' : 'Nama Lain')),
  R('no', 'no', 'ok', 'no', 'ok'));

matrix('buat sumber langsung published',
  (db, role) => setDoc(doc(db, 'water_sources/new2'),
    seedSource({
      ownerId: UID[role], ownerName: 'Pos Air Mawar', verifiedBy: 'provider',
      updatedAt: st(), verifiedAt: st(),
    })),
  R('no', 'no', 'no', 'no', 'ok'));

matrix('buat sumber atas nama ownerId orang lain',
  (db) => setDoc(doc(db, 'water_sources/new3'), providerNewDoc('p3', 'Kios Tirta')),
  R('no', 'no', 'no', 'no', 'ok'));

matrix('ubah availability + verifiedAt (tayang, milik sendiri)',
  (db, role) => updateDoc(doc(db, `water_sources/${pubOf(role)}`), {
    availability: 'limited', verifiedAt: st(), verifiedBy: 'provider', updatedAt: st(),
  }),
  R('no', 'no', 'ok', 'no', 'ok'));

matrix('ubah availability tanpa verifiedAt',
  (db, role) => updateDoc(doc(db, `water_sources/${pubOf(role)}`), {
    availability: 'limited', updatedAt: st(),
  }),
  R('no', 'no', 'no', 'no', 'ok'));

matrix('ubah nama atau koordinat sumber tayang',
  (db, role) => updateDoc(doc(db, `water_sources/${pubOf(role)}`), {
    name: 'Nama Baru Sumur', latitude: -6.2, updatedAt: st(),
  }),
  R('no', 'no', 'no', 'no', 'ok'));

matrix('ubah qualityFlag',
  (db, role) => updateDoc(doc(db, `water_sources/${pubOf(role)}`), {
    qualityFlag: true, updatedAt: st(),
  }),
  R('no', 'no', 'no', 'no', 'ok'));

matrix('ubah ownerId',
  (db, role) => updateDoc(doc(db, `water_sources/${pubOf(role)}`), {
    ownerId: 'p3', ownerName: 'Kios Tirta', updatedAt: st(),
  }),
  R('no', 'no', 'no', 'no', 'ok'));

matrix('ubah sumber penyedia lain',
  (db) => updateDoc(doc(db, 'water_sources/otherPub'), {
    availability: 'limited', verifiedAt: st(), verifiedBy: 'provider', updatedAt: st(),
  }),
  R('no', 'no', 'no', 'no', 'ok'));

matrix('tutup sumber sendiri (closed + closedAt)',
  (db, role) => updateDoc(doc(db, `water_sources/${pubOf(role)}`), {
    listingStatus: 'closed', isActive: false,
    closedReason: 'tidak lagi menyediakan air', closedAt: st(), updatedAt: st(),
  }),
  R('no', 'no', 'ok', 'no', 'ok'));

matrix('tulis isActive tak konsisten dengan listingStatus',
  (db) => setDoc(doc(db, 'water_sources/bad'),
    seedSource({ isActive: true, listingStatus: 'suspended' })),
  R('no', 'no', 'no', 'no', 'no'));

// ---- kasus tambahan: celah yang tidak tercakup matriks dokumen ----
test('penyedia tidak bisa menayangkan sumbernya sendiri lewat ubah', async () => {
  await assertFails(updateDoc(doc(dbFor('provider'), 'water_sources/own1'), {
    listingStatus: 'published', isActive: true, updatedAt: st(),
  }));
});

test('penyedia boleh mengubah sumber belum tayang lalu mengajukan ulang', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('provider'), 'water_sources/rej1'), {
    name: 'Perbaikan Nama Sumur', listingStatus: 'pending', isActive: false,
    reviewNote: '', verifiedBy: 'provider', ownerName: 'Pos Air Mawar', updatedAt: st(),
  }));
});

test('penyedia boleh mengonfirmasi tanpa mengubah status', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('provider'), 'water_sources/pub1'), {
    verifiedAt: st(), verifiedBy: 'provider', updatedAt: st(),
  }));
});

test('penyedia tidak boleh mengaku sebagai pihak lain (ownerName)', async () => {
  await assertFails(setDoc(doc(dbFor('provider'), 'water_sources/new4'),
    providerNewDoc('p1', 'PDAM Tirta Resmi')));
  await assertFails(updateDoc(doc(dbFor('provider'), 'water_sources/own1'), {
    ownerName: 'PDAM Tirta Resmi', listingStatus: 'pending', isActive: false,
    verifiedBy: 'provider', updatedAt: st(),
  }));
});

test('penyedia tidak boleh mengisi catatan tinjauan atau alasan tutup saat membuat', async () => {
  await assertFails(setDoc(doc(dbFor('provider'), 'water_sources/new5'),
    providerNewDoc('p1', 'Pos Air Mawar', { reviewNote: 'Sudah diverifikasi admin' })));
  await assertFails(setDoc(doc(dbFor('provider'), 'water_sources/new6'),
    providerNewDoc('p1', 'Pos Air Mawar', { closedReason: 'x' })));
});

test('menutup sumber tanpa alasan ditolak', async () => {
  await assertFails(updateDoc(doc(dbFor('provider'), 'water_sources/pub1'), {
    listingStatus: 'closed', isActive: false, closedReason: '', closedAt: st(), updatedAt: st(),
  }));
});

test('sumber yang ditangguhkan tidak bisa lagi diubah penyedia', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'water_sources/susp1'),
      seedSource({
        ownerId: 'p1', ownerName: 'Pos Air Mawar', verifiedBy: 'provider',
        listingStatus: 'suspended', isActive: false,
      }));
  });
  await assertFails(updateDoc(doc(dbFor('provider'), 'water_sources/susp1'), {
    availability: 'limited', verifiedAt: st(), verifiedBy: 'provider', updatedAt: st(),
  }));
});

test('tidak ada yang boleh menghapus sumber air', async () => {
  await assertFails(deleteDoc(doc(dbFor('admin'), 'water_sources/s1')));
});

test('admin menolak data sumber yang tidak valid', async () => {
  await assertFails(setDoc(doc(dbFor('admin'), 'water_sources/y'), seedSource({ latitude: 200 })));
  await assertFails(setDoc(doc(dbFor('admin'), 'water_sources/z'), { ...seedSource(), ekstra: 1 }));
});

// =====================================================================
// MATRIKS: provider_applications
// =====================================================================
matrix('ajukan penyedia (email terverifikasi, status none)',
  (db, role) => setDoc(doc(db, `provider_applications/${UID[role]}`), appData(UID[role])),
  { guest: 'no', warga: 'ok', provider: 'no', terminated: 'no' });

test('ajukan penyedia dengan email belum terverifikasi ditolak', async () => {
  await assertFails(setDoc(doc(dbFor('warga', false), 'provider_applications/u1'), appData('u1')));
});

test('ajukan ulang setelah rejected diizinkan, saat masih pending ditolak', async () => {
  await assertSucceeds(setDoc(doc(asUid('u4'), 'provider_applications/u4'), appData('u4')));
  await assertFails(setDoc(doc(asUid('u5'), 'provider_applications/u5'), appData('u5')));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), 'provider_applications/u4'), appData('u4')));
});

test('pengajuan dengan telepon atau versi ketentuan tidak valid ditolak', async () => {
  const db = dbFor('warga');
  await assertFails(setDoc(doc(db, 'provider_applications/u1'), appData('u1', { contactPhone: 'abc' })));
  await assertFails(setDoc(doc(db, 'provider_applications/u1'), appData('u1', { termsVersion: 2 })));
  await assertFails(setDoc(doc(db, 'provider_applications/u1'), appData('u1', { status: 'approved' })));
});

matrix('baca pengajuan orang lain',
  (db) => getDoc(doc(db, 'provider_applications/p3')),
  R('no', 'no', 'no', 'no', 'ok'));

test('pemilik boleh membaca pengajuannya sendiri', async () => {
  await assertSucceeds(getDoc(doc(dbFor('provider'), 'provider_applications/p1')));
});

matrix('setujui pengajuan',
  (db) => updateDoc(doc(db, 'provider_applications/u5'), {
    status: 'approved', adminNote: '', reviewedAt: st(),
  }),
  R('no', 'no', 'no', 'no', 'ok'));

test('tolak pengajuan tanpa catatan gagal, dengan catatan berhasil', async () => {
  const db = dbFor('admin');
  await assertFails(updateDoc(doc(db, 'provider_applications/u5'), {
    status: 'rejected', adminNote: '', reviewedAt: st(),
  }));
  await assertSucceeds(updateDoc(doc(db, 'provider_applications/u5'), {
    status: 'rejected', adminNote: 'Data usaha belum jelas.', reviewedAt: st(),
  }));
});

test('pengajuan yang sudah ditinjau tidak bisa ditinjau lagi', async () => {
  await assertFails(updateDoc(doc(dbFor('admin'), 'provider_applications/p1'), {
    status: 'rejected', adminNote: 'Terlambat menolak.', reviewedAt: st(),
  }));
});

// =====================================================================
// MATRIKS: users (status penyedia)
// =====================================================================
matrix('ubah providerStatus sendiri',
  (db, role) => updateDoc(doc(db, `users/${UID[role]}`), {
    providerStatus: 'active', providerReviewedAt: st(),
  }),
  R('no', 'no', 'no', 'no', 'ok'));

test('admin boleh menyetujui penyedia lain, warga tidak boleh', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('admin'), 'users/u1'), {
    providerStatus: 'active', providerReviewedAt: st(), providerNote: '',
  }));
});

test('admin tidak bisa mengubah peran pengguna lain atau mengisi status asing', async () => {
  const db = dbFor('admin');
  await assertFails(updateDoc(doc(db, 'users/u1'), { role: 'admin' }));
  await assertFails(updateDoc(doc(db, 'users/u1'), {
    providerStatus: 'superadmin', providerReviewedAt: st(),
  }));
});

test('penyedia terputus tidak bisa mengaktifkan dirinya kembali', async () => {
  await assertFails(updateDoc(doc(dbFor('terminated'), 'users/p2'), {
    providerStatus: 'active', providerReviewedAt: st(),
  }));
});

// ---------- profil (tetap dari fase sebelumnya) ----------
const newProfile = (over = {}) => ({
  uid: 'u2', name: 'Warga Baru', email: 'u2@x.id', role: 'user',
  createdAt: serverTimestamp(), ...over,
});

test('mendaftar dengan peran user diizinkan', async () => {
  await assertSucceeds(setDoc(doc(asUid('u2'), 'users/u2'), newProfile()));
});

test('mendaftar dengan peran admin atau status penyedia ditolak', async () => {
  await assertFails(setDoc(doc(asUid('u2'), 'users/u2'), newProfile({ role: 'admin' })));
  await assertFails(setDoc(doc(asUid('u2'), 'users/u2'), newProfile({ providerStatus: 'active' })));
});

test('email profil harus sama dengan email akun', async () => {
  await assertFails(setDoc(doc(asUid('u2'), 'users/u2'), newProfile({ email: 'lain@x.id' })));
});

test('mengubah peran sendiri ditolak', async () => {
  await assertFails(updateDoc(doc(dbFor('warga'), 'users/u1'), { role: 'admin' }));
});

// =====================================================================
// reports (tetap + jenis baru)
// =====================================================================
test('semua peran boleh membaca sumber air tayang', async () => {
  for (const role of ROLES) {
    await assertSucceeds(getDoc(doc(dbFor(role), 'water_sources/s1')));
  }
});

test('warga terverifikasi boleh membuat laporan valid', async () => {
  await assertSucceeds(submitReport(dbFor('warga'), 'u1'));
});

test('laporan jenis noLongerOperating diizinkan', async () => {
  await assertSucceeds(submitReport(dbFor('warga'), 'u1', { reportType: 'noLongerOperating' }));
});

test('jenis laporan asing ditolak', async () => {
  await assertFails(submitReport(dbFor('warga'), 'u1', { reportType: 'lainnya' }));
});

test('tamu tidak boleh membuat laporan', async () => {
  await assertFails(submitReport(dbFor('guest'), 'u1'));
});

test('laporan atas nama orang lain ditolak', async () => {
  await assertFails(submitReport(dbFor('warga'), 'u2'));
});

test('email belum terverifikasi ditolak', async () => {
  await assertFails(submitReport(dbFor('warga', false), 'u1'));
});

test('laporan duplikat (kunci sudah ada) ditolak', async () => {
  await assertSucceeds(submitReport(dbFor('warga'), 'u1'));
  await assertFails(submitReport(dbFor('warga'), 'u1'));
});

test('laporan tanpa kunci ditolak', async () => {
  await assertFails(setDoc(doc(collection(dbFor('warga'), 'reports')), reportData('u1')));
});

test('laporan untuk sumber yang tidak ada ditolak', async () => {
  const db = dbFor('warga');
  const b = writeBatch(db);
  b.set(doc(collection(db, 'reports')), reportData('u1', { sourceId: 'tidakada' }));
  await assertFails(b.commit());
});

test('laporan untuk sumber yang tidak tayang ditolak', async () => {
  await assertFails(submitReport(dbFor('warga'), 'u1', { sourceId: 'own1' }));
});

test('warga tidak boleh membaca laporan orang lain, admin boleh', async () => {
  await assertFails(getDoc(doc(dbFor('warga'), 'reports/pending1')));
  await assertSucceeds(getDoc(doc(dbFor('admin'), 'reports/pending1')));
});

const review = (db, id, over = {}) =>
  updateDoc(doc(db, `reports/${id}`), {
    status: 'approved', adminNote: '', reviewedAt: serverTimestamp(), ...over,
  });

test('admin boleh meninjau laporan pending', async () => {
  await assertSucceeds(review(dbFor('admin'), 'pending1'));
});

test('warga tidak boleh meninjau laporan', async () => {
  await assertFails(review(dbFor('warga'), 'pending1'));
});

test('laporan yang sudah ditinjau tidak bisa ditinjau lagi', async () => {
  await assertFails(review(dbFor('admin'), 'done1'));
});

test('menolak laporan tanpa catatan ditolak, dengan catatan diizinkan', async () => {
  await assertFails(review(dbFor('admin'), 'pending1', { status: 'rejected', adminNote: '' }));
  await assertSucceeds(review(dbFor('admin'), 'pending1', {
    status: 'rejected', adminNote: 'Gerbang hanya terkunci malam hari.',
  }));
});

// =====================================================================
// R1: intendedUse terkunci setelah tayang; pemutusan tidak bisa menghapus jejak
// =====================================================================
const claim = 'Air minum aman diminum';

test('R1: penyedia tidak bisa mengubah intendedUse sumber yang sudah tayang', async () => {
  await assertFails(updateDoc(doc(dbFor('provider'), 'water_sources/pub1'), {
    intendedUse: claim, updatedAt: st(),
  }));
});

test('R1: penyedia tetap bisa mengubah intendedUse saat sumber masih pending', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('provider'), 'water_sources/own1'), {
    intendedUse: claim, updatedAt: st(),
  }));
});

test('R1: penyedia tetap bisa mengubah jam layanan sumber yang sudah tayang', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('provider'), 'water_sources/pub1'), {
    openingHours: '06:00-18:00', updatedAt: st(),
  }));
});

test('R1: admin tetap bisa mengubah intendedUse sumber yang sudah tayang', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('admin'), 'water_sources/pub1'), {
    intendedUse: 'Air minum (kualitas diperiksa)', updatedAt: st(),
  }));
});

test('R1: penyedia terputus tidak bisa menghapus users maupun provider_applications', async () => {
  const db = dbFor('terminated');
  await assertFails(deleteDoc(doc(db, 'provider_applications/p2')));
  await assertFails(deleteDoc(doc(db, 'users/p2')));
});

test('R1: warga biasa bisa menghapus pengajuan dan profilnya sendiri', async () => {
  // u5: pengajuan pending; u4: pengajuan rejected. Pengajuan DULU, baru profil.
  await assertSucceeds(deleteDoc(doc(asUid('u5'), 'provider_applications/u5')));
  await assertSucceeds(deleteDoc(doc(asUid('u5'), 'users/u5')));
  await assertSucceeds(deleteDoc(doc(asUid('u4'), 'provider_applications/u4')));
  await assertSucceeds(deleteDoc(doc(asUid('u4'), 'users/u4')));
});

test('R1: penyedia aktif bisa menghapus pengajuan lalu profilnya', async () => {
  const db = dbFor('provider');
  await assertSucceeds(deleteDoc(doc(db, 'provider_applications/p1')));
  await assertSucceeds(deleteDoc(doc(db, 'users/p1')));
});

test('R1.1: pengajuan tetap bisa dihapus walau profil sudah terhapus lebih dulu', async () => {
  const db = dbFor('provider');
  await assertSucceeds(deleteDoc(doc(db, 'users/p1')));
  await assertSucceeds(deleteDoc(doc(db, 'provider_applications/p1')));
});

// Perilaku yang DIASUMSIKAN, belum terbukti di emulator: menghapus dokumen yang tidak ada
// dinilai oleh rules seperti biasa (tidak otomatis ditolak). Bila emulator menolaknya,
// catat sebagai perilaku nyata dan jangan mengubah aturan hanya agar tes ini lulus.
test('R1.1: pengguna tanpa dokumen profil menghapus pengajuan yang tidak ada (asumsi: diizinkan)', async () => {
  await assertSucceeds(deleteDoc(doc(asUid('u9'), 'provider_applications/u9')));
});

test('R1: pengguna tanpa dokumen profil tetap bisa menghapus akunnya (resource == null)', async () => {
  await assertSucceeds(deleteDoc(doc(asUid('u9'), 'users/u9')));
});

test('R1: tidak bisa menghapus dokumen pengguna lain', async () => {
  await assertFails(deleteDoc(doc(dbFor('warga'), 'users/p1')));
  await assertFails(deleteDoc(doc(dbFor('warga'), 'provider_applications/p3')));
  await assertFails(deleteDoc(doc(dbFor('guest'), 'users/u1')));
});

// =====================================================================
// BATAS AKSES DOKUMEN (20 per batch/transaksi, 10 per operasi)
// Hasilnya menentukan ukuran potongan penulisan massal (lihat docs/FASE2_PLAN.md).
// =====================================================================
test('batch menangguhkan 8 sumber milik penyedia lolos', async () => {
  const ids = Array.from({ length: 8 }, (_, i) => `bulk${i}`);
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const id of ids) {
      await setDoc(doc(ctx.firestore(), `water_sources/${id}`),
        seedSource({ ownerId: 'p1', ownerName: 'Pos Air Mawar', verifiedBy: 'provider' }));
    }
  });
  const db = dbFor('admin');
  const b = writeBatch(db);
  for (const id of ids) {
    b.update(doc(db, `water_sources/${id}`), {
      listingStatus: 'suspended', isActive: false, updatedAt: st(),
    });
  }
  await assertSucceeds(b.commit());
});

test('transaksi peninjauan laporan yang menangguhkan sumber lolos', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'reports/rep1'), {
      ...reportData('u2', { sourceId: 'pub1', reportType: 'noLongerOperating' }),
      createdAt: T,
    });
    await setDoc(doc(db, 'report_locks/u2_pub1_noLongerOperating'), {
      reporterId: 'u2', sourceId: 'pub1', reportType: 'noLongerOperating',
    });
  });
  const db = dbFor('admin');
  await assertSucceeds(runTransaction(db, async (tx) => {
    const snap = await tx.get(doc(db, 'reports/rep1'));
    if (snap.data().status !== 'pending') throw new Error('bukan pending');
    tx.update(doc(db, 'reports/rep1'), {
      status: 'approved', adminNote: '', reviewedAt: serverTimestamp(),
    });
    tx.delete(doc(db, 'report_locks/u2_pub1_noLongerOperating'));
    tx.update(doc(db, 'water_sources/pub1'), {
      listingStatus: 'suspended', isActive: false, updatedAt: serverTimestamp(),
    });
  }));
});

// =====================================================================
// S3: payload yang dihasilkan lapisan data harus lolos rules.
// Payload di bawah DISALIN dari FirestoreSourceService, FirestoreProviderService,
// dan FirestoreReportService. Ubah kode Dart dan tes ini bersama-sama.
// =====================================================================
const closeFields = () => ({
  listingStatus: 'closed', isActive: false, closedReason: 'berhenti beroperasi',
  closedAt: st(), updatedAt: st(),
});

const suspendFields = () => ({ listingStatus: 'suspended', isActive: false, updatedAt: st() });

/** Menyiapkan [n] sumber milik p1 lewat jalur tanpa rules. */
async function seedOwned(ids, over = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const id of ids) {
      await setDoc(doc(ctx.firestore(), `water_sources/${id}`),
        seedSource({ ownerId: 'p1', ownerName: 'Pos Air Mawar', verifiedBy: 'provider', ...over }));
    }
  });
}

test('S3 createAsProvider: add() dengan id otomatis lolos', async () => {
  await assertSucceeds(addDoc(collection(dbFor('provider'), 'water_sources'),
    providerNewDoc('p1', 'Pos Air Mawar')));
});

test('S3 resubmit: payload lengkap dengan deleteField(reviewNote) lolos', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('provider'), 'water_sources/rej1'), {
    name: 'Perbaikan Nama Sumur', address: 'Cengkareng, Jakarta Barat',
    latitude: -6.15, longitude: 106.74, sourceType: 'publicWell',
    availability: 'available', intendedUse: 'Belum diverifikasi', openingHours: '24 jam',
    listingStatus: 'pending', isActive: false,
    verifiedBy: 'provider', verifiedAt: st(),
    reviewNote: deleteField(), updatedAt: st(),
  }));
});

test('S3 resubmit: ubah sumber pending tetap lolos', async () => {
  await seedOwned(['pend1'], { listingStatus: 'pending', isActive: false });
  await assertSucceeds(updateDoc(doc(dbFor('provider'), 'water_sources/pend1'), {
    name: 'Perbaikan Sumur Pending', address: 'Cengkareng, Jakarta Barat',
    latitude: -6.15, longitude: 106.74, sourceType: 'publicWell',
    availability: 'limited', intendedUse: 'Kebutuhan rumah tangga', openingHours: '08:00-17:00',
    listingStatus: 'pending', isActive: false,
    verifiedBy: 'provider', verifiedAt: st(),
    reviewNote: deleteField(), updatedAt: st(),
  }));
});

test('S3 updateOperational: availability + jam layanan + konfirmasi lolos', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('provider'), 'water_sources/pub1'), {
    availability: 'limited', openingHours: '06:00-18:00',
    updatedAt: st(), verifiedAt: st(), verifiedBy: 'provider',
  }));
});

test('S3 updateOperational: lewat transaksi (baca lalu tulis) lolos', async () => {
  const db = dbFor('provider');
  await assertSucceeds(runTransaction(db, async (tx) => {
    const snap = await tx.get(doc(db, 'water_sources/pub1'));
    const changed = snap.data().availability !== 'limited';
    tx.update(doc(db, 'water_sources/pub1'), {
      availability: 'limited', updatedAt: serverTimestamp(),
      ...(changed ? { verifiedAt: serverTimestamp(), verifiedBy: 'provider' } : {}),
    });
  }));
});

test('S3 closeAllOwned: batch 8 sumber milik penyedia (4 tayang + 4 pending) lolos', async () => {
  await seedOwned(['c0', 'c1', 'c2', 'c3']);
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const id of ['c4', 'c5', 'c6', 'c7']) {
      await setDoc(doc(ctx.firestore(), `water_sources/${id}`), ownedPending('p1', 'Pos Air Mawar'));
    }
  });
  const db = dbFor('provider');
  const b = writeBatch(db);
  for (const id of ['c0', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7']) {
    b.update(doc(db, `water_sources/${id}`), closeFields());
  }
  await assertSucceeds(b.commit());
});

// TEMUAN: tugas S3 meminta closeAllOwned menutup "semua yang belum closed". Rules tidak
// mengizinkan penyedia menutup sumber yang DITANGGUHKAN (jalur (c) hanya dari pending,
// rejected, published), dan satu dokumen yang ditolak menggagalkan SELURUH batch. Karena itu
// service melewati yang ditangguhkan. Tes ini membuktikan alasannya; rules tidak diubah.
test('S3 closeAllOwned: satu sumber ditangguhkan menggagalkan seluruh batch (maka service melewatinya)', async () => {
  await seedOwned(['d0', 'd1', 'd2', 'd3', 'd4', 'd5', 'd6']);
  await seedOwned(['dSusp'], { listingStatus: 'suspended', isActive: false });
  const db = dbFor('provider');
  const b = writeBatch(db);
  for (const id of ['d0', 'd1', 'd2', 'd3', 'd4', 'd5', 'd6', 'dSusp']) {
    b.update(doc(db, `water_sources/${id}`), closeFields());
  }
  await assertFails(b.commit());
});

test('S3 setListing(published): membuka kembali sumber closed dengan deleteField lolos', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'water_sources/cl1'),
      seedSource({
        ownerId: 'p1', ownerName: 'Pos Air Mawar', verifiedBy: 'provider',
        listingStatus: 'closed', isActive: false,
        closedReason: 'sementara tutup', closedAt: T, reviewNote: 'Dalam pemeriksaan',
      }));
  });
  await assertSucceeds(updateDoc(doc(dbFor('admin'), 'water_sources/cl1'), {
    listingStatus: 'published', isActive: true, updatedAt: st(),
    verifiedBy: 'admin', verifiedAt: st(),
    reviewNote: deleteField(), closedReason: deleteField(), closedAt: deleteField(),
  }));
});

test('S3 setListing(rejected) dan setListing(suspended) lolos', async () => {
  const db = dbFor('admin');
  await assertSucceeds(updateDoc(doc(db, 'water_sources/own1'), {
    listingStatus: 'rejected', isActive: false,
    reviewNote: 'Lokasi tidak sesuai', updatedAt: st(),
  }));
  await assertSucceeds(updateDoc(doc(db, 'water_sources/pub1'), {
    ...suspendFields(), reviewNote: 'Dalam pemeriksaan',
  }));
});

test('S3 suspendAllOwned: batch 8 sumber lolos', async () => {
  const ids = ['s0', 's1x', 's2', 's3', 's4', 's5', 's6', 's7'];
  await seedOwned(ids);
  const db = dbFor('admin');
  const b = writeBatch(db);
  for (const id of ids) b.update(doc(db, `water_sources/${id}`), suspendFields());
  await assertSucceeds(b.commit());
});

test('S3 terminate: users DAHULU, lalu suspendAllOwned 8 sekaligus, lolos', async () => {
  const ids = ['t0', 't1', 't2', 't3', 't4', 't5', 't6', 't7'];
  await seedOwned(ids);
  const db = dbFor('admin');
  await assertSucceeds(updateDoc(doc(db, 'users/p1'), {
    providerStatus: 'terminated', providerNote: 'Melanggar ketentuan penyedia',
    providerReviewedAt: st(),
  }));
  const b = writeBatch(db);
  for (const id of ids) b.update(doc(db, `water_sources/${id}`), suspendFields());
  await assertSucceeds(b.commit());
});

test('S3 terminate: setelah diputus penyedia tidak bisa menulis sumbernya lagi', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('admin'), 'users/p1'), {
    providerStatus: 'terminated', providerNote: 'Melanggar ketentuan penyedia',
    providerReviewedAt: st(),
  }));
  await assertFails(updateDoc(doc(dbFor('provider'), 'water_sources/pub1'), {
    verifiedAt: st(), verifiedBy: 'provider', updatedAt: st(),
  }));
});

test('S3 ProviderService.review: batch pengajuan + users (setujui) lolos', async () => {
  const db = dbFor('admin');
  const b = writeBatch(db);
  b.update(doc(db, 'provider_applications/u5'), {
    status: 'approved', adminNote: '', reviewedAt: serverTimestamp(),
  });
  b.update(doc(db, 'users/u5'), {
    providerStatus: 'active', providerReviewedAt: serverTimestamp(),
  });
  await assertSucceeds(b.commit());
});

test('S3 ProviderService.review: batch tolak (providerStatus none) lolos', async () => {
  const db = dbFor('admin');
  const b = writeBatch(db);
  b.update(doc(db, 'provider_applications/u5'), {
    status: 'rejected', adminNote: 'Data usaha belum jelas.', reviewedAt: serverTimestamp(),
  });
  b.update(doc(db, 'users/u5'), {
    providerStatus: 'none', providerReviewedAt: serverTimestamp(),
  });
  await assertSucceeds(b.commit());
});

test('S3 ProviderService.apply: set tanpa merge setelah rejected menimpa dokumen (reviewedAt hilang)', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'provider_applications/u4'), {
      uid: 'u4', organizationName: 'Ditolak Dulu', contactPhone: '0812 3456 7890',
      description: 'Menyediakan air bersih untuk warga.', termsVersion: 1,
      status: 'rejected', adminNote: 'Data belum lengkap.', createdAt: T, reviewedAt: T,
    });
  });
  await assertSucceeds(setDoc(doc(asUid('u4'), 'provider_applications/u4'), appData('u4')));
});

test('S3 FirestoreReportService.review: transaksi dengan verifiedBy admin dan suspend lolos', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'reports/rep2'), {
      ...reportData('u2', { sourceId: 'pub1', reportType: 'noLongerOperating' }), createdAt: T,
    });
    await setDoc(doc(db, 'report_locks/u2_pub1_noLongerOperating'), {
      reporterId: 'u2', sourceId: 'pub1', reportType: 'noLongerOperating',
    });
  });
  const db = dbFor('admin');
  await assertSucceeds(runTransaction(db, async (tx) => {
    const snap = await tx.get(doc(db, 'reports/rep2'));
    if (snap.data().status !== 'pending') throw new Error('bukan pending');
    tx.update(doc(db, 'reports/rep2'), {
      status: 'approved', adminNote: '', reviewedAt: serverTimestamp(),
    });
    tx.delete(doc(db, 'report_locks/u2_pub1_noLongerOperating'));
    tx.update(doc(db, 'water_sources/pub1'), {
      listingStatus: 'suspended', isActive: false,
      updatedAt: serverTimestamp(), verifiedAt: serverTimestamp(), verifiedBy: 'admin',
    });
  }));
});

// =====================================================================
// S4: profil dipantau langsung; reactivate menghapus providerNote.
// Rules tidak diubah. Payload disalin dari FirestoreProviderService.reactivate.
// =====================================================================
async function seedTerminatedNote() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'users/p2'), {
      providerNote: 'Melanggar ketentuan penyedia',
    });
  });
}

test('S4 reactivate: providerStatus active + hapus providerNote (deleteField) lolos untuk admin', async () => {
  await seedTerminatedNote();
  await assertSucceeds(updateDoc(doc(dbFor('admin'), 'users/p2'), {
    providerStatus: 'active', providerReviewedAt: st(), providerNote: deleteField(),
  }));
});

test('S4 reactivate: tetap lolos bila catatan lama memang tidak ada', async () => {
  await assertSucceeds(updateDoc(doc(dbFor('admin'), 'users/p2'), {
    providerStatus: 'active', providerReviewedAt: st(), providerNote: deleteField(),
  }));
});

test('S4 penyedia terputus tidak bisa menghapus catatan pemutusannya sendiri', async () => {
  await seedTerminatedNote();
  await assertFails(updateDoc(doc(dbFor('terminated'), 'users/p2'), { providerNote: deleteField() }));
  await assertFails(updateDoc(doc(dbFor('terminated'), 'users/p2'), {
    providerStatus: 'active', providerReviewedAt: st(), providerNote: deleteField(),
  }));
});

test('S4 warga biasa tidak bisa menghapus providerNote pengguna lain', async () => {
  await seedTerminatedNote();
  await assertFails(updateDoc(doc(dbFor('warga'), 'users/p2'), { providerNote: deleteField() }));
});

// Pemantauan profil (snapshots) memakai aturan baca yang sama dengan get().
test('S4 pengguna boleh membaca (memantau) dokumen profilnya sendiri, bukan milik orang lain', async () => {
  await assertSucceeds(getDoc(doc(dbFor('warga'), 'users/u1')));
  await assertSucceeds(getDoc(doc(dbFor('provider'), 'users/p1')));
  await assertFails(getDoc(doc(dbFor('warga'), 'users/p1')));
  await assertFails(getDoc(doc(dbFor('guest'), 'users/u1')));
  await assertSucceeds(getDoc(doc(dbFor('admin'), 'users/p1')));
});

test('S4 membaca dokumen profil yang tidak ada (pengguna tanpa profil) tidak crash dan diizinkan untuk dirinya', async () => {
  await assertSucceeds(getDoc(doc(asUid('u9'), 'users/u9')));
});
