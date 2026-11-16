---
description: Jalankan tes firestore.rules di emulator
---
1. Bila rules_test/node_modules belum ada: `cd rules_test && npm install`.
2. Dari root proyek: `firebase emulators:exec --only firestore --project demo-aquaconnect "cd rules_test && node --test"`.
3. Laporkan jumlah tes lulus dan gagal. Untuk yang gagal, tampilkan nama tes dan pesan galat.
Peringatan: tes yang gagal bisa berarti tesnya yang salah, bukan rules-nya. Jangan mengubah
firestore.rules hanya agar tes lulus; laporkan perilaku sebenarnya.
