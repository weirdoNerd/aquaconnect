---
description: Pemeriksaan akhir sebelum demo (tanpa fitur baru)
---
JANGAN menambah fitur. Lakukan:
1. /cek dan /rules-test; laporkan hasil sebenarnya.
2. Periksa docs/DEMO.md terhadap aplikasi nyata: setiap langkah skenario harus ada di layar. Daftar
   langkah yang tidak cocok.
3. `grep -rni google lib` (harus kosong bila P-lite/M4 selesai), cari impor tak terpakai, cari
   string 'admin123' hanya di lib/dev.
4. Pastikan build rilis menolak mode tiruan (config.dart) dan tidak ada kunci di repo.
5. Tulis perintah untuk saya: `flutter build apk --debug` (demo mode tiruan) dan
   `flutter run --dart-define-from-file=dart_defines.json` (mode Firebase).
6. Buat tabel kriteria dosen -> fitur -> bukti (layar/tes) yang JUJUR: tandai 'belum ada' bila belum.
