---
trigger: always_on
---
# Aturan kualitas Flutter/Dart
1. Tidak boleh ada impor yang tidak terpakai dan tidak boleh ada peringatan analyzer pada
   berkas yang dibuat atau diubah. Periksa impor satu per satu.
2. Setiap perubahan perilaku disertai tes (unit atau widget). Setiap perubahan skema
   menyentuh empat tempat sekaligus: model, service, UI, firestore.rules (lalu tes rules).
3. Pakai pola yang sudah ada: ChangeNotifierProxyProvider dengan syncUser (reset tanpa
   notifyListeners saat dipanggil dari update), service di balik antarmuka dengan versi
   Firestore dan versi lib/dev (mock), fake bersama di test/helpers/fakes.dart.
4. Jangan membuat layar atau fitur di luar blok tugas. Jangan menghapus fitur yang berfungsi.
5. Teks antarmuka berbahasa Indonesia. Tampilan tidak boleh hanya mengandalkan warna.
6. Perbarui tabel status di docs/FASE1_PLAN.md atau docs/FASE2_PLAN.md dengan jujur: apa
   yang sudah dijalankan dan apa yang belum.
7. Jangan mengarang perilaku Firebase atau format layanan eksternal. Bukti = tes rules di
   emulator atau fixture asli. Yang tidak terbukti ditulis 'belum terverifikasi'.
