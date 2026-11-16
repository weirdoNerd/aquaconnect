---
description: M1b - layanan rute HeiGIT (butuh fixture dari M0)
---
TUGAS M1b. Prasyarat: test/fixtures/ors/ berisi hasil tool/ors_probe.ps1 (walk_ok, car_ok,
no_road_*, bad_request, bad_key, no_key). Bila kosong, BERHENTI dan katakan; jangan menjalankan
probe sendiri dan jangan membuka dart_defines.json.
1. Cocokkan fixture dengan bagian 'Hal yang M0 harus membuktikan' di docs/FASE1_PLAN.md (kode
   type belokan, nama kolom, format galat, perilaku titik jauh dari jalan, header kuota). Catat
   hasilnya; koreksi kode atau rencana bila berbeda dari asumsi.
2. Tambah paket http. lib/services/routing_service.dart: RoutingService, RoutingException,
   OrsRoutingService (URL dari kOrsBaseUrl dengan TrimEnd('/'); koordinat urutan [bujur,
   lintang]; timeout 10 detik), OrsRoutingService.parse (fungsi murni), StraightLineRoutingService,
   FallbackRoutingService (kRoutingAvailable == false -> garis lurus tanpa jaringan).
3. Rute degeneratif -> RoutingException: kurang dari 2 titik, tanpa langkah, atau indeks
   way_points di luar points.
4. Tes: parse tiap fixture; JSON rusak; MockClient untuk 200/401/403/429/5xx/timeout; header
   Authorization terkirim; URL akhir persis
   https://api.heigit.org/openrouteservice/v2/directions/foot-walking/geojson; Fallback.
5. Jalankan /cek. Perbarui docs/FASE1_PLAN.md.
