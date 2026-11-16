# AquaConnect: aturan proyek untuk agen

Aplikasi Flutter + Firebase (peta ketersediaan air bersih). Pemiliknya mahasiswa; dosennya
memberi tiga saran yang menjadi kriteria selesai:
1. Peta terintegrasi di dalam aplikasi yang menuntun pencari air ke lokasi, tanpa membuka Google Maps.
2. Nilai umpan balik: apa gunanya bagi penyedia air dan bagi pencari air.
3. Penyedia yang berhenti menyediakan air tidak boleh tetap tampil 'tersedia': penyedia
   (pengguna yang mengunggah sumber) memperbarui ketersediaan dan menutup sumbernya, data
   yang tidak dikonfirmasi memudar lalu tersembunyi, admin dapat memutus penyedia.

## Baca dulu setiap sesi
docs/FASE1_PLAN.md, docs/FASE2_PLAN.md, firestore.rules, rules_test/rules.test.js,
lib/config.dart, STATUS_PERBAIKAN.md. Keadaan terkini proyek ada di tabel status kedua
dokumen FASE itu. Bila catatan di dokumen bertentangan dengan hasil perintah nyata
(flutter analyze, flutter test, tes rules), PERCAYAI HASIL PERINTAH dan laporkan bedanya.

## Keputusan final (jangan ditanyakan ulang)
- Layanan rute: HeiGIT di api.heigit.org (base URL lewat dart-define, tanpa garis miring di
  akhir). ORS tidak punya profil motor: 'Motor/mobil (perkiraan)' memakai driving-car, dengan
  dialog keselamatan sekali ('jangan mengoperasikan ponsel saat berkendara').
- Simulasi navigasi hanya lewat tombol eksplisit di debug atau build DEMO_SIM, dengan spanduk
  SIMULASI permanen. Persetujuan privasi layanan rute: sekali, bernomor versi, ada sakelar
  untuk mencabut. Pencarian alamat opsional dan paling akhir.
- Penyedia: siapa pun yang login dengan email terverifikasi boleh mengajukan; admin
  menyetujui; sumber baru dari penyedia berstatus pending sampai admin memverifikasi.
- Kesegaran: 3 hari = 'tidak pasti', 7 hari = disembunyikan, HANYA untuk sumber berpemilik
  (sumber kelolaan admin hanya diberi label). Telepon penyedia hanya terlihat admin. Setelah
  tayang penyedia TIDAK boleh mengubah nama, lokasi, maupun intendedUse (rules R1).
- Tanpa push notification, tanpa Cloud Functions.
- Pemutusan penyedia: tulis providerStatus=terminated DAHULU, baru tangguhkan sumber dalam
  potongan maksimal 8 dokumen (batas akses dokumen di rules).

## Cara kerja
- Satu blok tugas per sesi (slash command di .agents/workflows). Kerjakan hanya blok itu.
- Susun rencana dulu, lalu kerjakan. Untuk blok yang menyentuh firestore.rules atau Firebase,
  tampilkan rencana dan tunggu persetujuan sebelum mengubah apa pun.
- Setelah selesai JALANKAN SENDIRI flutter analyze dan flutter test (dan /rules-test bila
  menyentuh rules atau layanan Firestore). Tempel hasil sebenarnya; jangan menyiratkan lulus
  bila tidak dijalankan.
- Laporan akhir singkat dan jujur: berkas berubah, tes ditambah, hasil perintah, yang belum
  terverifikasi, keputusan untuk pemilik.
