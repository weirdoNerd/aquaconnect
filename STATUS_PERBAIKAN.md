# Status perbaikan berdasarkan "AquaConnect: Analisis dan Instruksi Perbaikan"

**Penting:** Flutter/Dart tidak tersedia di lingkungan pembuat perbaikan ini, sehingga
`flutter analyze`, `flutter test`, tes rules, dan build rilis BELUM dijalankan.
Yang sudah dilakukan hanyalah pemeriksaan kasar (kurung seimbang, semua impor lokal ada,
tidak ada sisa referensi ke API lama). Jalankan semuanya sebelum menganggap selesai.

Legenda: ✅ dikerjakan di kode · 🟡 sebagian · ⬜ belum (alasan tertulis)

| ID | Status | Catatan |
| --- | --- | --- |
| T0.1 | 🟡 | `tool/bootstrap.sh` membuat `android/` (minSdk 23, izin, applicationId) dan menyamakan `kAppPackage`; `kAppPackage` dipakai di ketiga `TileLayer`. Folder `android/` **belum** di-commit karena butuh Flutter: jalankan skrip lalu commit. README sudah dirapikan. |
| T0.2 | ✅ | `sdk ^3.6.0`, `flutter >=3.27.0`, `analysis_options.yaml`, `firebase.json`, `firestore.indexes.json`, README dan komentar usang dibersihkan. |
| T1.1 | ✅ | Default `useFirebase = kReleaseMode`; `main()` menolak rilis tanpa Firebase; init Firebase dibungkus dan menampilkan `ConfigErrorScreen` + coba lagi; mock dan data simulasi dipindah ke `lib/dev/`; seed dipanggil dari layar admin. **Belum diverifikasi:** `strings app.apk \| grep admin123` pada APK rilis (teks petunjuk akun ada di cabang `kDebugMode && !useFirebase` yang seharusnya terbuang saat rilis). |
| T1.2 | ✅ | `syncUser` + `ChangeNotifierProxyProvider` untuk `ReportProvider` dan `AdminProvider`; layar "Laporan Saya" menampilkan galat walau ada data lama. Tes: `provider_test.dart`. |
| T1.3 | ✅ | Hasil profil usang diabaikan; profil dibuat ulang bila tidak ada; `updateDisplayName` dan email verifikasi tidak fatal; profil gagal dibaca ditandai `profileLoaded: false` (admin tidak diturunkan diam-diam, UI menawarkan muat ulang); `signIn` menunggu emisi listener (satu jalur). |
| T1.4 | ✅ | `firestore.rules` diperketat sesuai temuan (users, reports, water_sources, `hasOnly`, panjang field, `reviewedAt == request.time`, penolakan wajib catatan). Tes: `rules_test/rules.test.js` (belum dijalankan). |
| T1.5 | 🟡 | ✅ verifikasi email (kirim saat daftar, banner/aksi, syarat di rules) dan ✅ pencegah duplikat tak-terlewati lewat `report_locks` (batch + `existsAfter`; kunci dilepas di transaksi `review`). ⬜ App Check dan pembatasan API key/budget alert: butuh setelan Console dan paket yang API-nya berbeda antarversi; langkahnya ada di `SETUP_FIREBASE.md`. |
| T2.1 | ✅ | Aksi berhasil tidak lagi tampak gagal akibat fetch ulang; daftar admin diperbarui lokal/stream; hasil kirim: `sent` / `queued` (timeout, Firestore mengirim saat online) / `failed`. |
| T2.2 | ✅ | `SourceDetailScreen` dan `ReportFormScreen` menerima `sourceId` dan memakai `context.select`. |
| T2.3 | ✅ | Galat dipisah (`loadError` / `submitError` / `reviewError`), dibersihkan di `initState`; `MediaQuery` memakai context builder. Perlu uji di perangkat. |
| T2.4 | ✅ | `qualityFlag` (model, service, UI, rules); `intendedUse` tidak lagi ditimpa; banner merah di detail, ikon di kartu, sakelar cabut penanda di form. Migrasi data lama manual (lihat `SETUP_FIREBASE.md`). |
| T2.5 | ✅ | `updatedAt`/`verifiedAt` bertipe `DateTime?`; satu helper `asDateTime`; `verifiedAt` hanya diisi saat laporan disetujui, sumber baru, atau sakelar "Konfirmasi status sekarang". |
| T2.6 | ✅ | `ReportType.backAvailable` (saran status Tersedia, rules diperbarui). |
| T2.7 | 🟡 | ✅ penyelarasan pin, peta terpusat pada lokasi pengguna/batas sumber, ikon status + legenda, tombol "Lokasiku", User-Agent `kAppPackage`. ⬜ Penyedia tile tetap OSM: ganti sebelum rilis publik bila lalu lintas besar. |
| T2.8 | ✅ | `isActive` (penghapusan lunak); warga tidak melihat sumber nonaktif; admin melihat label "Nonaktif". |
| T2.9 | ✅ | Lupa sandi, verifikasi email, hapus akun (reautentikasi + hapus profil + hapus akun; rules `users` delete), validator sandi saat masuk hanya "wajib terisi". |
| T2.10 | 🟡 | ✅ `debugPrint` pada kegagalan, hitungan dokumen sumber yang dilewati tampil di panel admin, `byNameOrNull` (jenis asing menjadi `other`), pesan `saveSource` dibedakan per penyebab. 🟡 Laporan berformat salah hanya dicatat di log (belum dihitung di UI). Crashlytics tidak dipasang. |
| F3 | 🟡 | ✅ stream laporan pending (limit 50) + indeks, `sourceName` dihapus (rules + model), indikator cache, label kedaluwarsa (72 jam), lokasi akurasi sedang + posisi terakhir, memoisasi `items`, urut nama tak peka huruf. 🟡 Riwayat disetujui/ditolak dimuat sekali (50 terbaru), belum berhalaman. ⬜ Query geohash (hanya perlu bila sumber melewati beberapa ratus). |
| F4 | 🟡 | ✅ `locale id`, chip tanpa tinggi tetap, Semantics pada marker/badge dan kontras warna lebih gelap, `launchUrl` aman, penafian sekali saat pertama dibuka, "Laporan Saya" realtime. ⬜ "N laporan menunggu" per sumber (rules melarang warga membaca laporan orang lain; butuh penghitung di dokumen sumber). ⬜ Notifikasi FCM. |
| F5 | 🟡 | ✅ tes unit model/geo/provider (mock), 3 tes widget, tes rules (10+ kasus dari matriks), CI GitHub Actions. ⬜ Tes widget "detail ikut berubah saat sumber diperbarui" dan validasi form daftar/laporan belum ditulis. |

## Perubahan yang memengaruhi data yang sudah ada
Lihat bagian "Migrasi" di `SETUP_FIREBASE.md`, dan terbitkan ulang rules + indeks
(`firebase deploy --only firestore`) SEBELUM menjalankan aplikasi versi baru.
