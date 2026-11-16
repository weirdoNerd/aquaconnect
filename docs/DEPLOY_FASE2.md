# Panduan Deploy & Data Demo Fase 2 (Penyedia & Siklus Hidup Sumber)

> **Peringatan penting:** Terbitkan `firestore.rules` dan `firestore.indexes.json` **BERSAMAAN** dengan rilis klien baru (mengandung query `where('isActive', isEqualTo: true)` dan `where('ownerId', isEqualTo: uid)`). Klien lama yang membaca seluruh `water_sources` tanpa filter akan ditolak oleh rules Fase 2.

---

## Urutan Deploy

1. **Buat PROYEK FIREBASE BARU khusus demo atau staging (disarankan, agar proyek lama aman)**
   - Buka https://console.firebase.google.com > **Add project** (paket Spark/gratis).
   - Aktifkan **Authentication > Sign-in method > Email/Password**.
   - Aktifkan **Firestore Database > Create database** (wilayah terdekat, mis. `asia-southeast2`, mode produksi).
   - Hubungkan proyek baru ke aplikasi:
     ```bash
     firebase login
     firebase use <id-proyek-baru>
     flutterfire configure --platforms=android
     ```

2. **Pastikan semua dokumen `water_sources` punya `isActive`**
   - Pada proyek baru yang masih kosong, langkah ini langsung terpenuhi.
   - Jika memigrasikan proyek lama (tidak disarankan langsung di produksi tanpa staging), periksa di Firebase Console > Firestore > `water_sources` bahwa dokumen lama minimal sudah siap dilengkapi, karena dokumen tanpa `isActive: true` tidak akan muncul di query publik warga setelah rules Fase 2 aktif.

3. **Deploy `firestore.rules` + `firestore.indexes.json` BERSAMAAN dengan rilis klien**
   - Sebelum deploy, pastikan seluruh tes rules lulus di emulator:
     ```bash
     cd rules_test && npm install && cd ..
     firebase emulators:exec --only firestore --project demo-aquaconnect "cd rules_test && node --test"
     ```
   - Terbitkan rules dan indeks komposit (`reports`):
     ```bash
     firebase use <id-proyek>
     firebase deploy --only firestore:rules,firestore:indexes
     ```
   - Tunggu semua indeks pada koleksi `reports` (`(status, createdAt)` dan `(status, reviewedAt)`) berstatus **Enabled** di Firebase Console sebelum membuka Panel pengelola.
   - Rilis/build aplikasi versi Fase 2 (`flutter run --dart-define=USE_FIREBASE=true` atau `flutter build apk --release`) bersamaan dengan penerapan rules ini.

4. **Jalankan `'Perbaiki data lama'` sebagai admin**
   - Masuk sebagai akun admin -> buka **Panel pengelola** -> tab **Sumber air** -> ketuk **Perbaiki data lama**.
   - Dialog pratinjau akan menampilkan jumlah dokumen lama yang belum memiliki `isActive` atau `listingStatus`.
   - Proses mengisi `isActive` (bila kosong) dan `listingStatus` (`published` bila `isActive`, selain itu `closed`) per potongan maksimal 8 dokumen, dan bersifat idempoten (aman dijalankan ulang bila terputus).

5. **Beri akun admin pertama lewat Console**
   - Daftar satu akun lewat aplikasi (selalu tercatat sebagai `role: "user"`) dan verifikasi emailnya.
   - Di Firebase Console > Firestore > `users/{uid}`, ubah field `role` menjadi `"admin"`.
   - Keluar lalu masuk ulang di aplikasi (peran admin sengaja tidak pernah bisa diatur dari dalam aplikasi).

6. **Uji dengan tiga akun**
   - **Akun Warga** (email terverifikasi): lihat daftar/peta publik (sumber kedaluwarsa > 7 hari berpemilik tersembunyi kecuali sakelar "Tampilkan yang belum dikonfirmasi" aktif), coba melapor termasuk `Sudah tidak beroperasi`, cek **Jadi penyedia** -> pengajuan tersimpan `pending`.
   - **Akun Penyedia Aktif**: buka **Sumber saya**, **Tambah sumber** (berstatus `pending`, belum tampil di daftar publik), edit sumber `pending`/`rejected`, konfirmasi ketersediaan, ubah jam/status sumber `published`, serta uji **Tutup sumber**.
   - **Akun Admin**: tinjau pengajuan di tab **Penyedia** (setujui/tolak/putus kemitraan), tinjau sumber `pending` di tab **Sumber air** > **Menunggu verifikasi (n)** (periksa pin peta -> setujui/tolak), dan tinjau laporan `Sudah tidak beroperasi` dengan opsi tangguhkan sumber.

---

## Menyiapkan Data Demo Firebase (S11d)

Target kondisi awal demo:
- **1 penyedia aktif** (`providerStatus: "active"`) dengan **2 sumber tayang** (`published`, `isActive: true`).
- **1 pengajuan penyedia berstatus `pending`**.
- **1 sumber berstatus `pending`** milik penyedia aktif.

### Cara Tercepat Lewat Aplikasi + Console (Dijamin Lolos Rules)
1. **Siapkan 3 akun nyata (atau verifikasi email):**
   - `admin`: daftar di aplikasi -> ubah `users/{uid_admin}.role = "admin"` di Console -> masuk ulang.
   - `penyedia`: daftar di aplikasi, verifikasi email, ajukan lewat menu **Jadi penyedia** dengan nama usaha mis. `Depot Air Tirta Demo` -> setujui lewat akun `admin` di tab **Penyedia**.
   - `calon`: daftar di aplikasi, verifikasi email, ajukan lewat menu **Jadi penyedia** -> biarkan berstatus `pending` (**1 pengajuan pending** terpenuhi).
2. **Buat 3 sumber dari akun `penyedia`:**
   - Masuk sebagai `penyedia` -> **Sumber saya** -> **Tambah sumber** sebanyak 3 kali.
   - Masuk sebagai `admin` -> tab **Sumber air** -> **Menunggu verifikasi (3)**:
     - **Setujui 2 sumber** -> menjadi `published` (`isActive: true`, `verifiedBy: "admin"`). *(Opsional untuk demo kesegaran: di Console, mundurkan `verifiedAt` salah satu sumber tayang menjadi 4 hari yang lalu agar tampil lencana `Tidak pasti`.)*
     - **Biarkan 1 sumber tetap `pending`** -> **1 sumber pending** terpenuhi.

### Contoh Struktur Dokumen di Firebase Console (Bila Mengisi Manual)
Pastikan nama `ownerName` pada `water_sources` **sama persis** dengan `organizationName` di `provider_applications/{uid_penyedia}`:

- `users/{uid_penyedia}`:
  ```json
  {
    "uid": "<uid_penyedia>",
    "name": "Budi Penyedia",
    "email": "penyedia@contoh.id",
    "role": "user",
    "providerStatus": "active",
    "providerReviewedAt": "<server timestamp>",
    "providerNote": "",
    "createdAt": "<server timestamp>"
  }
  ```
- `provider_applications/{uid_penyedia}` (disetujui):
  ```json
  {
    "uid": "<uid_penyedia>",
    "organizationName": "Depot Air Tirta Demo",
    "contactPhone": "+6281234567890",
    "description": "Menyediakan air bersih dan air isi ulang untuk warga sekitar.",
    "termsVersion": 1,
    "status": "approved",
    "adminNote": "",
    "createdAt": "<server timestamp>",
    "reviewedAt": "<server timestamp>"
  }
  ```
- `water_sources/{id_sumber_1}` & `{id_sumber_2}` (2 sumber tayang milik penyedia):
  ```json
  {
    "name": "Depot Air Tirta Demo 1",
    "address": "Jl. Utama Cengkareng No. 10, Jakarta Barat",
    "latitude": -6.1465,
    "longitude": 106.7345,
    "sourceType": "refillStation",
    "availability": "available",
    "intendedUse": "Air minum isi ulang",
    "openingHours": "07:00-21:00",
    "isSimulated": false,
    "qualityFlag": false,
    "listingStatus": "published",
    "isActive": true,
    "ownerId": "<uid_penyedia>",
    "ownerName": "Depot Air Tirta Demo",
    "verifiedBy": "admin",
    "updatedAt": "<server timestamp>",
    "verifiedAt": "<server timestamp>"
  }
  ```
- `provider_applications/{uid_calon}` (1 pengajuan pending):
  ```json
  {
    "uid": "<uid_calon>",
    "organizationName": "Pos Air Bersih Mawar",
    "contactPhone": "+6281398765432",
    "description": "Pos tandon air bersih untuk warga RT 04.",
    "termsVersion": 1,
    "status": "pending",
    "adminNote": "",
    "createdAt": "<server timestamp>"
  }
  ```
- `water_sources/{id_sumber_pending}` (1 sumber pending):
  ```json
  {
    "name": "Pos Cadangan Tirta Demo",
    "address": "Cengkareng Barat Blok C, Jakarta Barat",
    "latitude": -6.1502,
    "longitude": 106.7310,
    "sourceType": "distributionPost",
    "availability": "limited",
    "intendedUse": "Kebutuhan rumah tangga dan mandi",
    "openingHours": "08:00-16:00",
    "isSimulated": false,
    "qualityFlag": false,
    "listingStatus": "pending",
    "isActive": false,
    "ownerId": "<uid_penyedia>",
    "ownerName": "Depot Air Tirta Demo",
    "verifiedBy": "provider",
    "updatedAt": "<server timestamp>",
    "verifiedAt": "<server timestamp>"
  }
  ```
