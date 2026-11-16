---
trigger: always_on
---
# Aturan keamanan (selalu berlaku)
1. JANGAN menjalankan `firebase deploy`, `git push`, `git commit`, `git reset --hard`,
   `rm -rf`, atau perintah yang menghapus data di Firebase. Bila perlu, tulis perintahnya
   untuk saya jalankan sendiri.
2. JANGAN mengubah atau melonggarkan `firestore.rules` kecuali blok tugas secara eksplisit
   menyuruhnya. Bila sebuah operasi ditolak rules, berhenti dan laporkan operasi, field, dan
   alasannya; jangan melonggarkan aturan agar kodenya lolos.
3. JANGAN menulis, mencetak, atau menyimpan kunci API (HeiGIT/ORS, Firebase) atau koordinat
   pengguna di kode, tes, log, dokumen, atau fixture. Kunci hanya dibaca lewat
   `kOrsApiKey` di lib/config.dart dari --dart-define. Berkas dart_defines.json tidak boleh
   dibuka, dicetak, atau dikomit.
4. JANGAN mengirim data pengguna ke layanan di luar yang disebut di AGENTS.md.
5. Build rilis wajib memakai Firebase; mode tiruan (mock) hanya untuk debug dan demo.
