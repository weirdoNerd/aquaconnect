# AquaConnect

Temukan Air, Hubungkan Harapan. Aplikasi Android (Flutter + Firebase) untuk
menemukan sumber air bersih terdekat, melaporkan kondisinya, dan memverifikasi
laporan oleh pengelola. Fokus demo: Cengkareng, Jakarta Barat.

## Persyaratan
- Flutter 3.27 atau lebih baru (Dart 3.6+). Cek: `flutter --version`
- Android SDK dengan emulator atau perangkat fisik

## Menjalankan (mode tiruan, tanpa Firebase)
Hanya untuk debug. Build rilis SELALU memakai Firebase.

    ./tool/bootstrap.sh id.ac.kampus   # sekali saja: membuat folder android/ siap pakai
    flutter run

`tool/bootstrap.sh` menjalankan `flutter create`, lalu otomatis mengatur
`minSdk 23`, izin `INTERNET` + lokasi, `applicationId` (`<org>.aquaconnect`), dan
menyamakan `kAppPackage` di `lib/config.dart`. **Setelah itu commit folder
`android/`** agar anggota lain cukup `git clone` lalu `flutter run`.
Ganti `id.ac.kampus` dengan ID milik tim (ID berawalan `com.example` ditolak Google Play).

Akun demo (mode tiruan, debug saja):
`admin@aquaconnect.test / admin123` dan `warga@aquaconnect.test / warga123`.
Di emulator, atur lokasi ke `-6.1480, 106.7370` (⋯ > Location) agar urutan "Terdekat" masuk akal.

## Memakai Firebase
Ikuti `SETUP_FIREBASE.md`, lalu `flutter run --dart-define=USE_FIREBASE=true`.
Build rilis (`flutter build apk --release`) otomatis memakai Firebase dan akan
gagal dengan pesan jelas bila konfigurasinya belum lengkap.

## Pengujian
    flutter analyze
    flutter test
    # tes Security Rules (butuh Node 20, JDK 21, firebase-tools):
    cd rules_test && npm install && cd ..
    firebase emulators:exec --only firestore --project demo-aquaconnect "cd rules_test && node --test"

CI (GitHub Actions) menjalankan ketiganya: `.github/workflows/ci.yml`.

## Struktur
    lib/
      config.dart            useFirebase, kAppPackage, ambang data kedaluwarsa
      models/                WaterSource, WaterReport, AppUser
      services/              kontrak (Auth/Report/Source/Location) + implementasi Firebase
      dev/                   implementasi TIRUAN + data simulasi (bukan untuk produksi)
      providers/             state (Provider)
      screens/ widgets/ utils/
    firestore.rules          Security Rules (batas keamanan sebenarnya)
    firestore.indexes.json   indeks komposit
    rules_test/              tes rules di Firebase Emulator
    STATUS_PERBAIKAN.md      status tiap temuan audit

## Aturan perubahan skema data
Setiap field baru wajib diubah di EMPAT tempat sekaligus: model
(`fromMap`/`toMap`), service, UI, dan `firestore.rules` (termasuk daftar `hasOnly`).

## Penafian
Status "tersedia" berarti sumber air dilaporkan ada, bukan jaminan air aman diminum.
Data bertanda `[SIMULASI]` hanya untuk demo.

## Kebijakan Privasi Singkat (Penyedia & Hapus Akun)
- Data pengajuan penyedia (nama usaha/komunitas, nomor telepon kontak, deskripsi) hanya terlihat oleh admin untuk verifikasi dan peninjauan.
- Bila penyedia aktif menghapus akun, seluruh sumber miliknya ditutup terlebih dahulu lalu pengajuan, profil, dan akun masuk dihapus.
- Bila kemitraan penyedia telah diputus oleh admin (`terminated`), hanya akun masuk (autentikasi) yang dapat dihapus oleh pemilik akun; catatan pemutusan pada profil dan pengajuan tetap disimpan untuk mencegah penyalahgunaan atau pendaftaran ulang.
