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
  3. `sim-prov-3`: Tersedia, dikonfirmasi **8 hari lalu** (`Freshness.expired` / kedaluwarsa, dirancang untuk disembunyikan dari warga pada tahap UI S9).
  4. `sim-prov-4`: Berstatus **`pending`** (belum tayang ke warga; menunggu verifikasi admin).

---

## 3. Skenario Demo (Urutan Klik per Peran)

### A. Warga / Pencari Air (`warga@aquaconnect.test`)
1. Buka aplikasi -> daftar sumber air tampil di layar utama (`SourceListScreen`).
2. Gunakan kolom pencarian atau chip filter jenis sumber (`Sumur umum`, `Pos distribusi`, `Titik isi ulang`) untuk menyaring daftar.
3. Ketuk tombol **Lokasiku / Terdekat** untuk mengurutkan berdasarkan jarak (membutuhkan izin lokasi perangkat/emulator).
4. Buka tampilan **Peta** -> lihat penanda status warna dan ikon di peta, lalu ketuk marker atau kartu sumber untuk membuka **Detail Sumber**.
5. Di halaman detail, amati label kesegaran (mis. `Belum dikonfirmasi 5 hari` pada `sim-4`) dan lencana `[SIMULASI]`. Jika kunci `ORS_API_KEY` dipasang, ketuk tombol rute untuk navigasi dalam aplikasi; di mode debug/demo tersedia tombol simulasi perjalanan dengan spanduk `SIMULASI`.
6. Ketuk ikon **Akun** (pojok kanan atas) -> **Masuk** -> masukkan `warga@aquaconnect.test` / `warga123` -> **Masuk**.
7. Buka detail sumber -> ketuk **Laporkan kondisi** -> pilih kondisi dan kirim laporan -> buka ikon **Akun** -> **Laporan saya** untuk melihat status laporan.

### B. Admin / Pengelola (`admin@aquaconnect.test`)
1. Ketuk ikon **Akun** -> keluar jika masih login -> **Masuk** dengan `admin@aquaconnect.test` / `admin123`.
2. Ketuk ikon **Akun** -> **Panel pengelola** (`AdminScreen`).
3. Tinjau laporan warga yang masuk (mis. laporan yang baru dikirim dari skenario Warga), lalu setujui atau tolak dengan catatan -> perubahan status langsung tercermin pada daftar sumber.
4. Tambah sumber baru atau ubah sumber yang ada melalui formulir admin (termasuk konfirmasi status atau menyembunyikan sumber).

### C. Calon Penyedia (`calon@aquaconnect.test`) & Penyedia (`penyedia@aquaconnect.test`)
1. Masuk dengan `calon@aquaconnect.test` / `calon123` untuk melihat akun warga yang telah memiliki 1 pengajuan `pending` (`[SIMULASI] Depot Air Sejahtera`) di `MockProviderService`.
2. Masuk dengan `penyedia@aquaconnect.test` / `penyedia123`:
   - `Bootstrap` otomatis menyambungkan `MockAuthService.authChanges` ke `MockSourceService.actAs('mock-provider')`, sehingga hak akses penyedia di lapisan service aktif saat login dan dicabut saat keluar.
   - `SourceProvider` melanggan `watchPublished()` + `watchOwned('mock-provider')` sehingga sumber milik penyedia (termasuk `sim-prov-4` berstatus `pending`) ikut termuat di provider.
3. **Catatan jujur cakupan UI saat ini:** layar khusus UI pengajuan penyedia (`S5`), tab admin peninjau pengajuan & pemutusan penyedia (`S6`), layar kelola **Sumber Saya** (`S8`), serta filter sembunyikan otomatis sumber kedaluwarsa >7 hari di UI warga (`S9`) belum dibangun dan dikerjakan pada blok S5–S10 berikutnya. Saat ini alur persetujuan penyedia (`review`, `terminate`, `reactivate` -> langsung memperbarui `MockAuthService`) dan izin operasi penyedia sudah aktif dan teruji di lapisan service/mock (`test/demo_mock_test.dart`).

---

## 4. Yang DISIMULASIKAN vs Sungguhan

| Aspek | Status | Keterangan |
|---|---|---|
| Titik & data 9 sumber air Cengkareng | **DISIMULASIKAN** | Data buatan berlabel `[SIMULASI]` (`isSimulated: true`), bukan hasil survei lapangan nyata. |
| Autentikasi & database di mode debug | **DISIMULASIKAN** | Disimpan di memori (`MockAuthService`, `MockSourceService`, `MockReportService`, `MockProviderService`); hilang saat aplikasi ditutup. |
| Simulasi navigasi rute (debug/`DEMO_SIM`) | **DISIMULASIKAN** | Menggerakkan posisi sepanjang rute secara virtual dengan spanduk `SIMULASI` permanen. |
| Peta OSM (`flutter_map`) & kalkulasi jarak | **Sungguhan** | Menampilkan tile OpenStreetMap dan menghitung jarak dengan koordinat GPS perangkat. |
| Rute dalam aplikasi (HeiGIT) | **Sungguhan** (bersyarat) | Memanggil `api.heigit.org` bila `--dart-define=ORS_API_KEY=...` diberikan dan pengguna menyetujui privasi rute. |
| Aturan bisnis, role-based streams, & validasi | **Sungguhan** | `AuthProvider`, `SourceProvider`, `ReportProvider`, `AdminProvider`, dan validator shared bekerja nyata; aturan server Firebase ditulis di `firestore.rules` (terpisah untuk build rilis/emulator). |
