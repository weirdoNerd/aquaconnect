# Fase 2: Penyedia dan Siklus Hidup Sumber Air: status dan catatan

Dasar: `Fase_2_Penyedia_dan_Siklus_Hidup_Sumber_Air.md`. Dokumen ini mencatat apa yang SUDAH
dikerjakan, penyimpangan dari dokumen sumber beserta alasannya, dan apa yang menunggu.

## Status

| Langkah | Status | Catatan |
| --- | --- | --- |
| S0 Persiapan | menunggu Anda | `flutter analyze`, `flutter test`, dan tes rules di emulator harus dijalankan. Saya tidak punya Flutter maupun emulator Firestore. |
| S1 Model dan tes model | selesai ditulis | Belum dikompilasi. Lihat daftar berkas di bawah. |
| R1 Perbaikan rules | selesai ditulis | `intendedUse` terkunci setelah tayang; penyedia terputus tidak bisa menghapus `users`/`provider_applications`. 10 tes baru. Belum dijalankan di emulator. |
| R1.1 Hapus pengajuan tanpa bergantung urutan | selesai ditulis | Aturan hapus `provider_applications` memakai `!exists(users/{uid}) \|\| status != terminated`. 1 tes diubah menjadi `assertSucceeds`, 1 tes baru. Belum dijalankan di emulator. |
| S2 Rules dan tes rules | selesai ditulis | Belum dijalankan di emulator. 60 tes (matriks + kasus tambahan). |
| S3 Lapisan data | selesai ditulis | `SourceService` (aliran per peran, operasi penyedia dan admin), `ProviderService` baru, `SourceProvider.syncUser`, `verifiedBy` di semua jalur admin. Belum dikompilasi dan belum dijalankan di CI/emulator. Lihat bagian "S3: lapisan data" di bawah. |
| S4 Profil langsung | selesai ditulis | `users/{uid}` dipantau (`ProfileSession`), `reactivate` menghapus `providerNote`, label baru di "Laporan Saya". Belum dikompilasi dan belum dijalankan di CI/emulator. Lihat bagian "S4: profil langsung" di bawah. |
| S4.1 Perbaikan kecil | selesai ditulis | `register()` memakai `ProfileSession.runRegistration` (try/finally) sehingga `endRegistration` selalu terpanggil, tepat sekali; impor tak terpakai diperiksa. Belum dikompilasi dan belum dijalankan di CI/emulator. |
| D1 Mode tiruan siap demo | selesai & teruji | `MockSourceService.actAs` tersambung ke `MockAuthService.authChanges` di `Bootstrap`; `MockProviderService` memperbarui profil `MockAuthService`; akun `penyedia` & `calon`, 4 sumber milik `mock-provider`, petunjuk `LoginScreen`, `docs/DEMO.md`, dan `test/demo_mock_test.dart`. `flutter analyze` (0 masalah) & `flutter test` (193 lulus) sudah dijalankan. |
| S5 Pengajuan penyedia (sisi warga) | selesai & teruji (mock/widget) | `ProviderService` dipasang di `main.dart` (Firebase & mock) dan `app_providers.dart`; `ProviderApplicationProvider`, `ProviderApplyScreen` (3a–3g + Ketentuan Penyedia v1 DRAF), `AccountButton` (item & label peran), serta tes unit/widget baru. `flutter analyze` dan `flutter test` lulus; pengujian terhadap Firebase/emulator sungguhan belum dijalankan. |
| S6 Tinjauan pengajuan penyedia (sisi admin) | selesai & teruji (mock/widget) | `ProviderProfile.role` (`FirestoreProviderService.fetchProviders` membaca `m['role']`), `ProviderAdminProvider` (`appProviders`), tab ketiga `Penyedia (n)` di `AdminScreen` (`ProviderAdminTab`: tinjau pengajuan, putus kemitraan, aktifkan kembali, sembunyikan aksi pada `isAdmin`), serta `test/provider_admin_test.dart`. `flutter analyze` & `flutter test` lulus; Firebase/emulator sungguhan belum dijalankan. |
| S7 Unggah/edit sumber penyedia | selesai & teruji (mock/widget + rules emulator) | `SourceFormScreen` mode (`admin`, `providerNew`, `providerEdit`: sembunyikan kontrol admin, kunci `name`/`address`/`sourceType`/`intendedUse`/lokasi pada sumber tayang dan ubah operasional lewat `updateOperational`, `pending`/`rejected` lewat `resubmit`, `ownerName` dari pengajuan `approved`), tombol Tambah/Edit di `MySourcesScreen`, filter `Menunggu verifikasi (n)` + `ListingReviewSheet` di `AdminScreen`, `MySourcesProvider.createAsProvider`/`resubmit`, `SourceProvider.setListingStatus`, serta `test/s7_provider_source_flow_test.dart`. `flutter analyze` (0 masalah), `flutter test` (252 lulus), dan `rules_test` di emulator Firestore (171/171 lulus) sudah dijalankan; pengujian langsung terhadap Firebase produksi/perangkat fisik belum dijalankan. |
| S8 Sumber Saya | selesai & teruji (mock/widget) | `MySourcesProvider` (busy/galat per sumber, `confirmAll`, `closeAllOwned`), `MySourcesScreen` (aksi hanya pada `published`, tutup dengan alasan & konfirmasi permanen, pengingat > 48 jam, `Hentikan semua`), navigasi & lencana di `AccountButton` dan `ProviderApplyScreen`, serta `test/my_sources_test.dart` (termasuk integrasi mode tiruan). `flutter analyze` & `flutter test` lulus; Firebase/emulator sungguhan belum dijalankan. |
| S9 Kesegaran data (memudar & tersembunyi) | selesai & teruji (mock/widget) | Jam suntik & timer 1 menit di `SourceProvider`, penyembunyian sumber kedaluwarsa berpemilik untuk non-admin + `showUnconfirmed`, `Terdekat` meletakkan `stale`/`expired` di akhir, `FilterChip` & banner jumlah tersembunyi di `SourceListScreen`, lencana abu-abu `Tidak pasti` di `AvailabilityBadge`/`SourceCard`, pengelola/konfirmasi/peringatan di `SourceDetailScreen`, pin redup dapat diketuk di `SourceMapScreen`, serta `test/freshness_test.dart`. `flutter analyze` & `flutter test` lulus; pengujian perangkat nyata belum dijalankan. |
| S10-S11 | ditunda | S10 dan S11 belum dijalankan. |

### Berkas yang berubah di S1/S2
- `lib/config.dart`: `kHideAfter`, `kReconfirmReminderAfter`, `kProviderTermsVersion`.
- `lib/models/app_user.dart`: `ProviderStatus`, `providerStatus`, `providerNote`, `isProvider`.
- `lib/models/water_source.dart`: `ListingStatus`, `VerifiedBy`, `Freshness`; field `ownerId`, `ownerName`,
  `listingStatus`, `verifiedBy`, `reviewNote`, `closedReason`, `closedAt`; `isActive` kini getter.
- `lib/models/water_report.dart`: `ReportType.noLongerOperating`.
- `lib/models/provider_application.dart` (baru).
- Dampak berantai: `source_form_screen.dart`, `review_sheet.dart`, `report_form_screen.dart`,
  `dev/mock_source_service.dart`, `services/firebase_auth_service.dart`, `test/provider_test.dart`.
- `firestore.rules`, `rules_test/rules.test.js`, `test/model_test.dart`.

## S3: lapisan data

**Deploy rules menunggu S11. Klien baru wajib dirilis bersamaan karena query tanpa filter isActive ditolak untuk non-admin.**

Selesai ditulis, belum dijalankan (`flutter analyze`, `flutter test`, dan tes rules di emulator belum ada hasilnya untuk S3).
`firestore.rules` TIDAK diubah di S3.

### Berkas
- `lib/services/source_service.dart` (kontrak, `SourceBatchException`, `SourceUpdate.suspend`, validator bersama),
  `firestore_source_service.dart`, `lib/dev/mock_source_service.dart`.
- `lib/services/provider_service.dart`, `firestore_provider_service.dart`, `lib/dev/mock_provider_service.dart`,
  `lib/models/provider_profile.dart` (baru).
- `lib/providers/source_provider.dart` (`syncUser`, penggabungan aliran), `auth_provider.dart` (`isProvider`),
  `lib/main.dart` (`ChangeNotifierProxyProvider<AuthProvider, SourceProvider>`),
  `lib/services/firestore_report_service.dart` (transaksi review: `verifiedBy: admin` dan `suspend`),
  `lib/models/water_source.dart` (`clearReviewNote`, `clearClosed`), `lib/screens/source_form_screen.dart` (sakelar disembunyikan).
- Tes: `test/source_service_test.dart`, `source_provider_streams_test.dart`, `provider_service_test.dart`;
  `model_test.dart` dan `provider_test.dart` disesuaikan; 15 tes baru di `rules_test/rules.test.js` (bagian "S3").

### Temuan dan keputusan pelaksanaan
1. **`closeAllOwned` melewati sumber yang ditangguhkan** (tugas meminta "semua yang belum closed"). Rules (jalur (c)) hanya
   mengizinkan penutupan dari `pending`, `rejected`, `published`; satu dokumen ditangguhkan menggagalkan SELURUH batch.
   Tes rules `S3 closeAllOwned: satu sumber ditangguhkan menggagalkan seluruh batch` membuktikan alasannya (belum dijalankan).
   Rules tidak dilonggarkan. Akibat untuk S10(b): sumber yang ditangguhkan admin tidak ikut ditutup saat penyedia hapus akun.
2. **`updateOperational` memakai transaksi** (baca nilai sekarang) karena konfirmasi (`verifiedAt`, `verifiedBy`) hanya wajib
   bila `availability` BERUBAH. Parameter `availability` dan `openingHours` keduanya opsional; keduanya kosong ditolak.
3. **`resubmit` hanya menulis field pada daftar jalur (a)** dan menghapus `reviewNote` dengan `FieldValue.delete()`.
   `ownerId`, `qualityFlag`, `isSimulated` tidak ditulis. Objek yang dikirim DAN dokumen tersimpan harus `rejected`.
4. **`apply` memakai `set` tanpa merge**: dokumen baru jatuh ke jalur create, dokumen `rejected` ke jalur pengajuan ulang
   dan DITIMPA (field `reviewedAt` lama hilang, sesuai daftar field yang diizinkan).
5. **Tambahan di luar tugas (kecil, tidak melonggarkan):** `terminate` mewajibkan alasan 5-200 karakter (menyamai penolakan);
   `review` yang menolak menulis `providerStatus: none` di profil; `reactivate` menghapus `providerNote` lama
   (semula TIDAK; diubah di S4 dengan `FieldValue.delete()`).
6. **`SourceProvider` tidak lagi membuka langganan di konstruktor.** Semua pemanggil diperbaiki; pembuatan pertama lewat
   `create` di `main.dart` sudah memanggil `syncUser` untuk keadaan saat ini (tamu sejak awal).
7. `ProviderService` belum dipasang di `main.dart`/UI (tidak ada layar di S3); itu bagian S4+.

### Dampak yang perlu ditangani di langkah berikutnya
- **"Laporan Saya" dan nama sumber (diatasi di S4).** Warga hanya melanggan sumber tayang, jadi laporan atas sumber yang
  kemudian ditangguhkan atau ditutup tidak menemukan namanya (nama tidak lagi disimpan di laporan). Kini ditampilkan
  "Sumber tidak lagi tayang"; admin tidak terdampak dan teks adminnya tidak diubah.
- **Status penyedia tidak langsung terlihat (diatasi di S4).** Profil kini dipantau langsung; setelah admin menyetujui,
  aliran "milik sendiri" terbuka tanpa keluar-masuk (lihat bagian S4 untuk apa yang sudah dan belum terbukti).
- **Mode tiruan (diatasi di D1):** `MockSourceService.actAs` kini tersambung ke `MockAuthService.authChanges` di `Bootstrap`,
  dan `MockProviderService` memperbarui profil di `MockAuthService`. Jalur admin tiruan tetap tidak dibatasi agar alur yang ada tetap jalan.

### Perilaku yang HANYA dibuktikan oleh mock/fake, bukan emulator
- Penolakan yang meniru rules (penyedia hanya miliknya, status yang diizinkan, alasan minimal) di `MockSourceService` dan
  `MockProviderService`. Kecocokannya dengan rules hanya terbukti bila tes rules S3 lulus di emulator.
- Potongan 8 (20 sumber menjadi 3 batch) dan penghentian di tengah (`failAfterBatches`) hanya teruji di mock. Di Firestore,
  batch penyedia berisi 8 tulisan membutuhkan sekitar 16 akses dokumen untuk rules (`isAdmin()` dan `isActiveProvider()` per
  tulisan); batas 20 belum dibuktikan untuk jalur penyedia (tes rules `S3 closeAllOwned: batch 8 ...`).
- Pemilihan aliran, dedup, dan penjumlahan `skipped` diuji dengan `_FakeService`. `includeMetadataChanges` serta urutan
  `create`/`update` pada `ChangeNotifierProxyProvider` belum diuji (tidak ada tes widget untuk itu).
- Seluruh kode `Firestore*Service` baru TIDAK punya tes Flutter otomatis; satu-satunya bukti adalah tes rules yang menyalin payload-nya
  (ubah keduanya bersama-sama). Semantik `FieldValue.delete()` pada update, transaksi `updateOperational`, dan `set` tanpa merge
  pada pengajuan hanya diuji lewat tes rules itu.

## S4: profil langsung

Selesai ditulis. **Yang saya jalankan:** hanya pemeriksaan kasar (kurung seimbang, semua impor lokal ada, sintaks JS tes rules).
**Yang BELUM dijalankan:** `flutter analyze`, `flutter test`, dan tes rules di emulator. `firestore.rules` TIDAK diubah di S4
(md5 sama dengan sebelum S4).

### Berkas
- `lib/services/profile_session.dart` (baru): logika pemantauan profil dalam Dart murni (`AuthIdentity`, `ProfileDoc`,
  `ProfileSource`, `ProfileSession`), dipisah dari Firebase agar bisa dites dengan fake.
- `lib/services/firebase_auth_service.dart`: ditulis ulang menjadi adaptor tipis (`FirestoreProfileSource` + `ProfileSession`).
  Pembacaan sekali (`_loadProfile`) dihapus.
- `lib/dev/mock_auth_service.dart`: `updateProfile(...)` dan `deleteProfile(uid)` meniru dokumen profil yang berubah/terhapus.
- `lib/app_providers.dart` (baru): daftar provider dipindah dari `main.dart` agar rangkaian `AuthProvider -> SourceProvider`
  bisa dites apa adanya. Isinya tidak berubah.
- `lib/models/app_user.dart` (`copyWith`), `lib/models/provider_profile.dart` (`clearNote`),
  `firestore_provider_service.dart` dan `lib/dev/mock_provider_service.dart` (`reactivate` menghapus `providerNote`),
  `lib/screens/my_reports_screen.dart` (label baru).
- Tes: `profile_session_test`, `auth_live_profile_test`, `app_providers_test`, `my_reports_label_test`, `test/helpers/fakes.dart`
  (fake bersama; `source_provider_streams_test` dialihkan memakainya); `provider_service_test` diperluas; 6 tes rules baru.

### Keputusan pelaksanaan
1. **Aturan `ProfileSession`:** hasil usang diabaikan (sesi berganti selama menunggu); langganan lama dibatalkan saat keluar,
   ganti akun, atau `restart()`; snapshot identik tidak dipancarkan ulang.
2. **Dokumen profil tidak ada = peran terendah, tidak pernah melempar.** Bila ketidakadaan HANYA dari cache, hasilnya
   `profileLoaded: false` (belum bisa memastikan), supaya admin tidak diturunkan diam-diam saat offline.
3. **Pembuatan ulang profil dasar dijaga ketat:** hanya bila server mengonfirmasi dokumen tidak ada, tidak ada tulisan lokal
   tertunda, tidak sedang menghapus akun, dan sekali per sesi. Tanpa penjagaan ini, `deleteAccount` bisa "menghidupkan kembali"
   profil yang baru dihapusnya sendiri.
4. **`emailVerified` berasal dari Auth, bukan dari dokumen** (dokumen tidak memuatnya). Emisi memakai identitas Auth terbaru;
   `refresh()` memuat ulang user lalu memanggil `restart()` agar nilainya dipancarkan.
5. **Galat langganan:** hasilnya `profileLoaded: false` (peran terendah). Pemulihan lewat `refresh()` (menu akun
   "Profil belum termuat, coba lagi") yang me-restart pemantauan.
6. **Pendaftaran:** `register()` menahan pemantauan sampai profil ditulis, lalu memulainya (`endRegistration`).
7. **Rangkaian ke `SourceProvider`:** tidak ada kode baru di `ProxyProvider`; perubahan `providerStatus` mengubah tupel
   (uid, isAdmin, isProvider) sehingga `syncUser` membuka aliran "milik sendiri". Terbukti hanya oleh `app_providers_test`
   (belum dijalankan).
8. **"Laporan Saya":** teks admin (`Sumber air tidak ditemukan`) sengaja TIDAK diubah. Selama daftar sumber masih dimuat
   ditampilkan "Memuat nama sumber…" supaya tidak terlanjur menyatakan "tidak lagi tayang".

### Perilaku Firestore/Firebase yang hanya ASUMSI (belum terbukti di emulator atau perangkat)
- Dokumen yang tidak ada di cache saat offline menghasilkan snapshot `exists == false` dengan `metadata.isFromCache == true`.
- Dengan `includeMetadataChanges: true`, peralihan cache -> server tiba sebagai snapshot tersendiri, dan penghapusan lokal
  menghasilkan snapshot dengan `hasPendingWrites == true`. Penjagaan pembuatan ulang profil bergantung pada keduanya.
- Listener `snapshots()` berakhir setelah galat (karena itu `restart()` diperlukan).
- `authStateChanges()` tidak menyala saat `User.reload()` (karena itu `restart()` dipanggil manual di `refresh()`).
- Setelah `user.delete()`, listener profil menerima `permission-denied`; galat itu diabaikan oleh penjagaan usang karena
  `currentUser` sudah null.
- Aturan baca `users/{uid}` berlaku sama untuk `snapshots()` dan `get()` (tes rules `S4 ... memantau` menguji `getDoc`,
  bukan listener sungguhan).

### Yang TIDAK teruji otomatis
- `FirestoreProfileSource` dan alur `FirebaseAuthService` (`signIn`, `register`, `refresh`, `deleteAccount`): hanya adaptor tipis
  yang memetakan tipe Firebase ke `ProfileSession`; tidak ada tes Flutter untuknya (butuh emulator/fake Firebase).
  Logika di dalam `ProfileSession` diuji dengan `ProfileSource` palsu.
- Batas waktu `awaitUser` (20 detik) pada `signIn`/`register` di jaringan lambat.
- Tampilan menu akun saat `profileLoaded` berubah.

### Keterbatasan yang diketahui
- `deleteAccount` untuk penyedia TERPUTUS akan ditolak rules (penghapusan `users/{uid}`) sampai S10(b) selesai.

## PERINGATAN penerapan
**Jangan menjalankan `firebase deploy --only firestore` dengan `firestore.rules` ini sebelum S11 selesai** (klien S3-S10 siap dan data lama sudah diperbaiki lewat 'Perbaiki data lama'). Sebelumnya catatan ini menyebut S3; keputusan final di prompt pelaksana adalah S11.
Klien yang ada sekarang membaca seluruh koleksi `water_sources` tanpa filter; rules baru menolak query itu
untuk non-admin, sehingga daftar sumber air akan kosong bagi warga. Berkas rules di repo ini adalah
sumber kebenaran untuk CI dan tes; penerapannya ke Firebase (rules dan indexes) dilakukan bersamaan dengan rilis klien di S11.

Sebelum menerbitkan:
1. Pastikan SEMUA dokumen `water_sources` punya field `isActive` (dokumen tanpa field itu tidak muncul di query publik).
2. Untuk dokumen lama dengan `isActive: false`, isi juga `listingStatus` (mis. `closed`). Dokumen dokumen sumber
   mengatakan langkah ini opsional; saya menilainya WAJIB untuk dokumen nonaktif: pembaruan parsial oleh admin
   (mis. lewat peninjauan laporan) memeriksa invarian pada dokumen hasil gabungan, dan `listingStatus` yang hilang
   dianggap `published`, sehingga `isActive: false` akan melanggar invarian.
3. Rilis klien baru bersamaan dengan rules.

## Penyimpangan dari dokumen sumber (semuanya memperketat, tidak ada yang melonggarkan)

1. **`ownerName` harus sama dengan nama usaha yang disetujui admin** (`providerOrgName()`, satu `get()`
   ke `provider_applications/{uid}`). Dokumen sumber hanya mengisinya dari UI; tanpa ini penyedia bisa
   menulis nama pihak lain (mis. instansi resmi) dan warga akan mempercayainya. Biaya: +1 akses dokumen
   pada penulisan penyedia (maksimum 3, jauh di bawah batas).
2. **Penyedia tidak boleh mengisi `reviewNote`, `closedReason`, `closedAt` saat membuat sumber.** Di dokumen
   sumber tidak dilarang, sehingga penyedia bisa menulis "Sudah diverifikasi admin".
3. **Alasan penutupan wajib (>= 3 karakter) dipaksa di rules**, bukan hanya di UI.
4. **Jalur (a) (ubah sebelum tayang):** `verifiedBy` harus `provider` dan `verifiedAt`, bila berubah, harus `request.time`.
5. **Aturan baca tetap `resource.data.isActive == true`** (bukan `.get(...)`). Analisis query rules mengenali
   perbandingan langsung; pemakaian `.get()` di aturan baca berisiko membuat query ditolak.
   Konsekuensinya langkah (1) di atas wajib.
6. **`WaterSource.toMap()` menghilangkan kolom opsional yang kosong**, tidak menulis `null`. Rules memeriksa
   tipe (`is string`); `null` akan ditolak.
7. **`ReportType.noLongerOperating` belum ditampilkan di formulir laporan** sampai S10, karena server menolaknya
   sampai rules diterapkan. Enum, label, ikon, dan rules sudah siap.
8. **Sakelar "Tampilkan di aplikasi" di form admin** kini memetakan ke `published` / `suspended` (atau mempertahankan
   status tak-tayang lain). Menayangkan lewat form belum mengisi `verifiedBy: admin`; itu tugas
   `SourceService.setListing` di S3.

9. **(R1) `intendedUse` dikunci pada jalur ubah (b) (sumber sudah tayang).** Itu klaim kelayakan air; bila penyedia
   bebas mengubahnya setelah diverifikasi, ia bisa menulis "aman diminum" tanpa tinjauan. Jalur (a) (belum tayang)
   tetap boleh; admin tetap boleh kapan saja. Jam layanan dan status tetap bisa diubah penyedia.
10. **(R1) Penyedia terputus tidak bisa menghapus `users/{uid}` maupun `provider_applications/{uid}`**, agar ia tidak
    menghapus jejaknya lalu mengajukan ulang. Hanya akun Auth-nya yang bisa dihapus (catat di kebijakan privasi).
    Dua catatan pelaksanaan:
    - Aturan `users` memakai `resource == null || ...` (penyimpangan kecil dari prompt): tanpa itu, pengguna yang
      dokumen profilnya tidak ada tidak bisa menghapus akunnya (`resource.data` pada dokumen tak ada = galat = ditolak).
    - **(R1.1)** Aturan hapus `provider_applications` TIDAK lagi bergantung pada urutan hapus di klien. Rumusnya:
      `!exists(users/{uid}) || userDoc().providerStatus != 'terminated'`. Bila profil sudah terhapus lebih dulu
      (aplikasi mati atau jaringan putus di tengah hapus akun), pengajuan tetap bisa dihapus, sehingga tidak ada data
      yatim (telepon, nama usaha). Penyedia yang diputus selalu punya profil dengan `providerStatus: terminated`,
      jadi tetap tidak bisa menghapus pengajuannya. Aturan hapus pada `users/{uid}` tidak diubah. Urutan di klien
      (pengajuan dulu, baru profil) **tetap dianjurkan**, tetapi tidak lagi wajib bagi rules.
    - Klien saat ini (`FirebaseAuthService.deleteAccount`) menghapus `users/{uid}` tanpa menghapus pengajuan dan tanpa
      membedakan penyedia terputus; untuk penyedia terputus itu akan ditolak rules. Belum ada dampak karena rules belum
      dideploy; diselesaikan di S10(b).

## Hal yang HARUS diverifikasi di emulator (saya tidak bisa)
1. Seluruh `rules_test/rules.test.js` lulus. **Setelah itu gagalkan satu tes dengan sengaja** (mis. hapus
   pemeriksaan `qualityFlag` dari `providerEdit` (b)) untuk memastikan harness menangkap pelanggaran.
2. **Batas akses dokumen.** Dua tes khusus: batch 8 penangguhan dan transaksi peninjauan yang menangguhkan sumber.
   Dokumen sumber tidak bisa memastikan apakah akses ke dokumen yang sama dihitung sekali atau berulang.
   Bila gagal, kecilkan ukuran potongan di S3.
3. **Query dengan aturan `||`.** Pastikan `where('isActive','==',true)` dan `where('ownerId','==',uid)`
   diizinkan, dan query tanpa filter ditolak (baris matriks pertama dan kedua).
4. Perilaku galat pada `userDoc()` untuk pengguna yang dokumen profilnya belum ada (harus ditolak, bukan membuat tes lain gagal).
5. **(R1/R1.1) Asumsi perilaku Firestore, belum terbukti:** (a) menghapus dokumen yang TIDAK ada dinilai oleh rules seperti
   biasa (bukan otomatis ditolak); (b) `resource == null` benar pada operasi hapus dokumen yang tidak ada;
   (c) `exists()` pada `users/{uid}` yang sudah terhapus bernilai false di dalam aturan hapus. Tes
   `R1: pengguna tanpa dokumen profil ...` dan `R1.1: ...` menguji ketiganya. Bila hasil emulator berbeda,
   catat perilaku nyata dan sesuaikan TES atau aturan berdasarkan perilaku itu, bukan sebaliknya.

## Asumsi dari dokumen sumber yang tetap berlaku
Ambang 3 hari (`kStaleAfter`, sudah ada) dan 7 hari (`kHideAfter`); penyembunyian hanya untuk sumber berpemilik;
nomor telepon hanya terlihat admin; penyedia tidak mengubah nama/lokasi setelah tayang; tanpa push (spanduk dan lencana).
Kesegaran dihitung dengan jam perangkat sementara `verifiedAt` ditulis dengan jam server: jam ponsel yang salah
akan memengaruhi tampilan (bukan keamanan).

## Syarat untuk S3 dan seterusnya (dicatat agar tidak terlupa)
- `terminate(uid)` menulis `providerStatus: terminated` DAHULU, baru menangguhkan sumber (potongan <= 8 dokumen,
  menulis `listingStatus` dan `isActive` bersamaan).
- **S10(b), urutan hapus akun yang aman:** (i) `closeAllOwned` dulu (butuh profil yang masih `active`; penyedia
  `terminated`/`none` melewatinya), lalu hapus pengajuan, lalu hapus profil `users/{uid}`, lalu akun Auth.
  (ii) Penolakan saat menghapus pengajuan untuk pengguna yang tidak punya pengajuan BUKAN galat fatal: abaikan dan
  lanjutkan ke langkah berikutnya (jangan membatalkan penghapusan akun karenanya).
- Hapus akun penyedia: `closeAllOwned` hanya untuk penyedia berstatus `active`. Penyedia `terminated` tidak
  bisa menulis lagi (rules), jadi memaksa langkah itu akan membuat akunnya tidak bisa dihapus; sumbernya sudah
  ditangguhkan oleh admin.
- `SourceProvider` dipecah per peran (`watchPublished`, `watchOwned`, `watchAll` hanya admin) lewat
  `ChangeNotifierProxyProvider<AuthProvider, SourceProvider>` + `syncUser`. Mulai setelah Fase 1 sampai M4.
- Satu langkah per commit; tiap langkah menyentuh model, service, UI, dan rules (lalu tes rules).
