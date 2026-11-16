# Panduan Demo AquaConnect (Mode Tiruan / Debug)

Dokumen ini menjelaskan akun, urutan skenario per peran, serta pemisahan jujur antara bagian yang **disimulasikan** dan **sungguhan** pada mode tiruan (`useFirebase == false`, default saat `flutter run` dalam mode debug).

---

## 1. Menjalankan Aplikasi Mode Demo

```bash
flutter run
```

> Catatan: Semua data mode tiruan disimpan di memori (`lib/dev/`) dan akan kembali ke kondisi awal setiap kali aplikasi dimulai ulang. Build rilis (`flutter build apk --release`) selalu mewajibkan Firebase (`kReleaseMode`).

---

## 2. Akun Demo (`MockAuthService`)

Saat layar **Masuk** dibuka dalam mode debug non-Firebase, keempat akun di bawah tampil pada kotak petunjuk demo:

| Peran | Email | Kata Sandi | UID Stabil | Keadaan Awal (Seed) |
|---|---|---|---|---|
| **Admin / Pengelola** | `admin@aquaconnect.test` | `admin123` | `mock-admin` | Role `admin` |
| **Warga** | `warga@aquaconnect.test` | `warga123` | `mock-user` | Role `user`, `providerStatus: none` |
| **Penyedia Aktif** | `penyedia@aquaconnect.test` | `penyedia123` | `mock-provider` | `providerStatus: active`, `emailVerified: true`, punya 4 sumber seed |
| **Calon Penyedia** | `calon@aquaconnect.test` | `calon123` | `mock-calon` | Warga biasa dengan 1 pengajuan `pending` di `MockProviderService` |

### Data Sumber Air Seed (`lib/dev/dummy_sources.dart`)
Seluruh 9 sumber berawalan `[SIMULASI]` (`isSimulated: true`) dengan koordinat sekitar Cengkareng, Jakarta Barat:
- **5 sumber kelolaan admin** (`sim-1` s.d. `sim-5`):
  - Termasuk `sim-4` (`[SIMULASI] Sumur Umum Taman Warga`, berstatus `unavailable`) yang terakhir dikonfirmasi **5 hari lalu**, sehingga menampilkan label `Belum dikonfirmasi 5 hari` tanpa disembunyikan.
- **4 sumber milik `mock-provider`** (`ownerName: 'Penyedia Demo'`, `verifiedBy: VerifiedBy.provider`):
  1. `sim-prov-1`: Tersedia, dikonfirmasi **2 jam lalu** (`Freshness.fresh`, tayang).
  2. `sim-prov-2`: Terbatas, dikonfirmasi **4 hari lalu** (`Freshness.stale` / tidak pasti, tayang).
  3. `sim-prov-3`: Tersedia, dikonfirmasi **8 hari lalu** (`Freshness.expired` / kedaluwarsa, otomatis disembunyikan dari daftar warga kecuali chip **`Tampilkan yang belum dikonfirmasi`** diaktifkan).
  4. `sim-prov-4`: Berstatus **`pending`** (belum tayang ke warga; menunggu verifikasi admin).

---

## 3. Skenario Demo (Urutan Klik per Peran)

### A. Warga / Pencari Air (`warga@aquaconnect.test`)
1. Buka aplikasi -> daftar sumber air tampil di layar utama (`SourceListScreen`).
2. Gunakan kolom pencarian, chip filter jenis sumber (`Sumur umum`, `Pos distribusi`, `Titik isi ulang`, `Lainnya`), atau chip **`Tampilkan yang belum dikonfirmasi`** (untuk melihat sumber berpemilik yang kedaluwarsa > 7 hari seperti `sim-prov-3`).
3. Ketuk chip **`Terdekat`** untuk mengurutkan berdasarkan jarak (membutuhkan izin lokasi perangkat/emulator), atau buka ikon peta -> ketuk tombol **`Lokasiku`** untuk memusatkan peta ke lokasi pengguna.
4. Buka tampilan **Peta** -> lihat penanda status warna dan ikon di peta (sumber yang belum dikonfirmasi > 3 hari tampak redup), lalu ketuk marker atau kartu sumber untuk membuka **Detail Sumber**.
5. Di halaman detail, amati label kesegaran (mis. `Belum dikonfirmasi 5 hari` pada `sim-4` atau lencana **`Tidak pasti`** pada `sim-prov-2`) dan lencana `[SIMULASI]`. Ketuk **`Lihat di peta`** untuk membuka peta garis lurus dalam aplikasi (`SourceRouteScreen`: penanda tujuan & pengguna, garis putus-putus, jarak, arah kompas, dan tombol **`Perbarui lokasi`** — tanpa membuka Google Maps).
6. Ketuk ikon **Akun** (pojok kanan atas) -> **Masuk** -> masukkan `warga@aquaconnect.test` / `warga123` -> **Masuk**.
7. Buka detail sumber -> ketuk **`Laporkan kondisi`** -> pilih kondisi (termasuk **`Sudah tidak beroperasi`**) dan kirim laporan -> buka ikon **Akun** -> **`Laporan saya`** untuk memantau statusnya.

### B. Admin / Pengelola (`admin@aquaconnect.test`)
1. Ketuk ikon **Akun** -> keluar jika masih login -> **Masuk** dengan `admin@aquaconnect.test` / `admin123`.
2. Ketuk ikon **Akun** -> **`Panel pengelola`** (`AdminScreen`), yang memiliki 3 tab:
   - **Tab `Laporan`:** tinjau laporan warga yang masuk via `ReviewSheet` (untuk jenis `Sudah tidak beroperasi`, tersedia opsi **`Tangguhkan sumber air`** dengan konfirmasi eksplisit); setujui atau tolak dengan catatan.
   - **Tab `Sumber air`:** tambah/ubah sumber lewat form admin, gunakan filter **`Menunggu verifikasi (n)`** untuk meninjau sumber `pending` milik penyedia via `ListingReviewSheet` (periksa pin peta -> setujui/tolak), serta tombol **`Perbaiki data lama`**.
   - **Tab `Penyedia`:** tinjau pengajuan penyedia (`calon@aquaconnect.test`), setujui/tolak, serta putus kemitraan (**`Putuskan kemitraan`**) atau **`Aktifkan kembali`** penyedia.

### C. Calon Penyedia (`calon@aquaconnect.test`) & Penyedia (`penyedia@aquaconnect.test`)
1. Masuk dengan `calon@aquaconnect.test` / `calon123` -> ketuk ikon **Akun** -> **`Status pengajuan`** (`ProviderApplyScreen`) untuk melihat pengajuan `pending` (`[SIMULASI] Depot Air Sejahtera`); atau masuk sebagai `warga` -> **`Jadi penyedia`** untuk mencoba mengirim pengajuan baru.
2. Masuk dengan `penyedia@aquaconnect.test` / `penyedia123`:
   - Ketuk ikon **Akun** -> **`Sumber saya`** (`MySourcesScreen`; bila ada sumber tayang > 48 jam belum dikonfirmasi seperti `sim-prov-2`, tampil lencana jumlah dan spanduk pengingat **`Konfirmasi semua`**).
   - Pada sumber `published`, coba **`Konfirmasi masih tersedia`**, ubah status (**Tersedia** / **Terbatas** / **Habis**), **`Edit`** (nama/alamat/jenis/tujuan/lokasi terkunci; hanya ketersediaan & jam layanan yang dapat diubah), atau **`Tutup sumber`** / **`Hentikan semua sumber saya`**.
   - Ketuk **`Tambah sumber`** untuk mengirim sumber baru (`pending` sampai disetujui admin), atau **`Edit`** pada sumber `pending`/`rejected`.

---

## 4. Yang DISIMULASIKAN vs Sungguhan

| Aspek | Status | Keterangan |
|---|---|---|
| Titik & data 9 sumber air Cengkareng | **DISIMULASIKAN** | Data buatan berlabel `[SIMULASI]` (`isSimulated: true`), bukan hasil survei lapangan nyata. |
| Autentikasi & database di mode debug | **DISIMULASIKAN** | Disimpan di memori (`MockAuthService`, `MockSourceService`, `MockReportService`, `MockProviderService`); hilang saat aplikasi ditutup. |
| Peta OSM (`flutter_map`), jarak, & arah kompas (P-lite) | **Sungguhan** | Menampilkan tile OpenStreetMap dan menghitung jarak/arah kompas dengan koordinat GPS perangkat di `SourceMapScreen` & `SourceRouteScreen` (garis lurus, tanpa Google Maps). |
| Navigasi rute jalan (HeiGIT) & simulasi perjalanan | **Belum aktif** | Rute jalan turn-by-turn (`M1b–M3`) dan simulasi perjalanan `DEMO_SIM` belum dibangun; saat ini memakai peta garis lurus P-lite. |
| Aturan bisnis, role-based streams, & validasi | **Sungguhan** | `AuthProvider`, `SourceProvider`, `ReportProvider`, `AdminProvider`, `MySourcesProvider`, `ProviderApplicationProvider`, `ProviderAdminProvider`, dan validator shared bekerja nyata; aturan server Firebase ditulis di `firestore.rules` (terpisah untuk build rilis/emulator). |
