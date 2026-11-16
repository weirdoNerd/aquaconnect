# Memasang paket ini di proyek AquaConnect

1. Salin ke ROOT proyek (folder yang berisi pubspec.yaml): AGENTS.md dan folder .agents/
   (berisi rules/ dan workflows/). Struktur akhir:
     aquaconnect/
       AGENTS.md
       .agents/rules/00-keamanan.md, 01-kualitas-flutter.md
       .agents/workflows/cek.md, rules-test.md, d1.md, s5.md, s6.md, ... siap-demo.md
2. Buka folder proyek di Antigravity (File > Open Folder). Aturan di .agents/rules dan AGENTS.md
   terbaca otomatis. Workflow dipanggil dengan mengetik / di panel Agent, lalu nama (mis. /s5).
3. Bila slash command tidak muncul: beberapa versi Antigravity membaca folder `.agent/`
   (tanpa 's'). Salin juga isi .agents/ ke .agent/ dan buka ulang proyek.
4. Pastikan .gitignore memuat: dart_defines.json, firestore-debug.log, rules_test/node_modules.
5. Alur satu blok: git status bersih -> jalankan workflow -> baca RENCANA agen -> setujui ->
   baca laporan -> jalankan /cek (dan /rules-test) -> periksa perubahan (diff) -> `git add` dan
   `git commit` OLEH ANDA -> lanjut blok berikutnya.
