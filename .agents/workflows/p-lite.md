---
description: P-lite - peta dalam aplikasi versi ringan (tanpa layanan rute)
---
TUGAS P-lite. JANGAN menambah paket baru, JANGAN menyentuh firestore.rules, JANGAN menulis
layanan rute atau memakai kunci HeiGIT. Ini BUKAN navigasi belok-per-belok.

1. lib/screens/source_route_screen.dart (menerima sourceId; ambil sumber lewat context.select
   dari SourceProvider.byId seperti SourceDetailScreen). FlutterMap dengan tile OSM (ikuti
   TileLayer yang ada, User-Agent kAppPackage), penanda tujuan (alignment topCenter), penanda
   pengguna, dan garis lurus antara keduanya (putus-putus bila didukung versi flutter_map).
   Kamera memuat kedua titik (fitCamera).
2. Panel: 'Jarak {formatDistance}' dan 'Arah {compassLabel(bearingDegrees)}' + keterangan tetap
   'Garis lurus, bukan rute jalan'. Perkiraan waktu TIDAK ditampilkan.
3. Lokasi dari LocationService.getCurrent() (sekali) + tombol 'Perbarui lokasi'. Bila lokasi tidak
   tersedia tampilkan hanya tujuan, pesan jelas, dan tombol seperti showLocationError.
4. source_detail_screen.dart: hapus _openNavigation, impor url_launcher, dan tombol 'Buka
   petunjuk arah'; ganti tombol 'Lihat di peta' (nonaktif bila !isActive).
5. Hapus url_launcher dari pubspec.yaml bila tak terpakai. Teks bantuan location_picker_screen
   yang menyebut Google Maps jadi netral ('Format: -6.1480, 106.7370'). Setelah selesai
   `grep -rni google lib` harus kosong.
6. Tes: widget test dengan fake LocationService (jarak dan arah benar untuk dua koordinat
   diketahui, 'Perbarui lokasi', keadaan tanpa lokasi); detail tidak lagi memuat teks Google Maps.
7. Jalankan /cek. Perbarui docs/FASE1_PLAN.md: P-lite selesai sebagian; M1b-M4 belum.
