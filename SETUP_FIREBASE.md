# Menyambungkan AquaConnect ke Firebase

Lakukan sekali oleh SATU anggota kelompok, lalu bagikan hasilnya lewat Git.

## 1. Buat proyek Firebase
1. https://console.firebase.google.com > **Add project** (paket Spark/gratis).
2. **Authentication** > Get started > aktifkan **Email/Password**.
3. **Firestore Database** > Create database > lokasi terdekat
   (mis. `asia-southeast2` Jakarta) > mode produksi.

## 2. Hubungkan ke aplikasi
    npm install -g firebase-tools
    firebase login
    dart pub global activate flutterfire_cli
    flutterfire configure --platforms=android

Perintah ini menimpa `lib/firebase_options.dart` dan menambah
`android/app/google-services.json`. (`minSdk 23` sudah diatur oleh `tool/bootstrap.sh`.)

## 3. Terbitkan Rules dan indeks
    firebase use <id-proyek>
    firebase deploy --only firestore

Ini menerbitkan `firestore.rules` dan `firestore.indexes.json`. Tunggu indeks
berstatus *Enabled* di Console (beberapa menit) sebelum membuka panel admin.

## 4. Jalankan dengan Firebase
    flutter run --dart-define=USE_FIREBASE=true
Build rilis tidak perlu flag ini.

## 5. Buat admin pertama
1. Daftar akun biasa di aplikasi (selalu berperan `user`) dan verifikasi emailnya.
2. Console > Firestore > `users` > dokumen akun itu > ubah `role` menjadi `admin`.
3. Keluar lalu masuk lagi. Peran admin tidak bisa diberikan dari dalam aplikasi, dan itu disengaja.

## 6. Data awal
Masuk sebagai admin > Panel pengelola > tab **Sumber air** > **Isi data contoh (debug)**
(hanya tampil di mode debug dan jika koleksi kosong). Itu data simulasi: ganti dengan
hasil survei lewat form tambah sumber air, lalu NONAKTIFKAN atau ubah data `[SIMULASI]`
sebelum rilis (tidak ada data simulasi di produksi).

## Email verifikasi
Mengirim laporan mensyaratkan email terverifikasi (`kRequireVerifiedEmail` di
`lib/config.dart` dan baris `email_verified` di `firestore.rules`). Untuk demo tanpa
email asli, matikan KEDUANYA sekaligus, lalu terbitkan ulang rules.

## Hardening sebelum rilis publik (dikerjakan di Console)
1. **API key**: Google Cloud Console > APIs & Services > Credentials > batasi key Android
   ke package name dan sidik jari SHA-1 yang benar.
2. **Budget alert**: Billing > Budgets & alerts, pasang peringatan biaya/kuota.
3. **Firebase App Check** (Play Integrity) untuk Firestore dan Auth: aktifkan mode
   *monitoring* dahulu, tambahkan paket `firebase_app_check` dan aktifkan setelah
   `initializeApp`, baru ubah ke *enforce* setelah lalu lintas sah terpantau aman.
   (Belum ada di kode karena API paketnya berbeda antarversi dan butuh setelan Console.)
4. Uji rules dengan `rules_test/` (tamu, warga, admin) sebelum setiap penerbitan.

## Migrasi dari versi sebelumnya
- Sumber air lama dengan `intendedUse` berisi "Dugaan masalah kualitas...": set
  `qualityFlag: true` dan isi `intendedUse` dengan nilai wajar (edit di Console atau form admin).
- Sumber air lama belum punya `verifiedAt`: tampil "Status belum pernah dikonfirmasi"
  sampai admin mengonfirmasi lewat form ("Konfirmasi status sekarang").
- Laporan lama yang masih `pending` tidak punya dokumen `report_locks`; tinjau atau
  tolak semuanya sebelum rilis. Field `sourceName` pada laporan lama diabaikan.
- `reportType` baru `backAvailable` hanya dikenali versi aplikasi terbaru.
