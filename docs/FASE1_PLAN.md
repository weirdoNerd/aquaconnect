# Fase 1: Peta dan Navigasi Terintegrasi (Tingkat 2): rencana final

Dasar: `Fase_1_Peta_dan_Navigasi_Terintegrasi__Tingkat_2_.md`, dikoreksi setelah
memeriksa sumber resmi openrouteservice (ORS) pada 8 November 2026.

## Keputusan

| ID | Keputusan |
| --- | --- |
| D1 | Pakai `api.heigit.org`. Directions: `{base}/v2/directions/{profil}/geojson`, base bawaan `https://api.heigit.org/openrouteservice`. Geocoding: base terpisah, bawaan `https://api.heigit.org/pelias/v1`. Keduanya bisa diubah lewat `--dart-define` (`ORS_BASE_URL`, `ORS_GEOCODE_BASE_URL`), tanpa garis miring di akhir. Ada tes yang memeriksa URL yang terbentuk. |
| D2 | Moda motor/mobil tetap ada, berlabel "perkiraan". Dialog konfirmasi sekali ("Jangan mengoperasikan ponsel saat berkendara", disimpan sebagai `driving_safety_ack_v1`), ditambah satu baris pengingat permanen di panel selama moda itu aktif. **Fase 1b (suara) dinaikkan prioritasnya.** |
| D3 | Simulasi hanya lewat tombol eksplisit di debug, atau di build dengan `DEMO_SIM`. Spanduk "SIMULASI" tidak bisa dimatikan. Build `DEMO_SIM` hanya untuk demo, bukan rilis ke pengguna. |
| D4 | Persetujuan layanan rute online satu kali, bernomor versi (`routing_consent_v1`) agar muncul lagi bila penyedia berubah. Sakelar "Layanan rute online" di menu akun; mati = mode garis lurus. Pencarian alamat (D7) tunduk pada persetujuan yang sama karena mengirim teks ketikan ke pihak ketiga. |
| D5 | Irisan vertikal. Aturan: tiap irisan menyisakan aplikasi yang berjalan dengan tes lulus, dan **tidak ada layar sebelum verifikasi respons nyata (M0/M1)**. |
| D6 | Rute berakhir di jalan terdekat; sisa jaraknya digambar garis putus-putus lurus dengan teks "Sisa X m, ikuti garis putus-putus". Jangan diam-diam memakai jalan yang jauh. Radius tiba dihitung terhadap titik sumber air sebenarnya. Batas "jauh" diputuskan setelah melihat respons nyata. |
| D7 | Pencarian alamat opsional dan terakhir. Pin tengah + "Lokasi saya" sudah memenuhi catatan dosen. |

## Koreksi fakta (supaya dokumen tim akurat)
- Pengumuman resmi: `api.openrouteservice.org` usang sejak 28 April 2026; kuota dipotong
  jadi 10% sejak 27 Agustus; rencana 24 Agustus dan 28 September dicoret/diganti; penutupan
  akhir jendela 2-6 November 2026. Per hari ini anggap sudah mati.
- Klaim "garis miring di akhir base URL menyebabkan galat" belum terverifikasi. Yang terbukti di forum:
  galat 403 karena URL dari playground punya segmen `heigit/` ekstra. Kita tetap membuang garis miring dan menguji URL-nya.
- Menurut pengumuman, kunci yang ada sudah bisa dipakai di alamat baru dan kuotanya terlihat
  di `account.heigit.org` (bukan lagi dashboard openrouteservice.org). Dibuktikan oleh M0.
- CORS di forum hanya relevan untuk klien browser, bukan aplikasi Android.
- Kode tipe belokan 0-13 cocok dengan dokumentasi resmi (tipe 14-17 ada: angkutan umum dan
  unknown, jadi cabang `unknown` wajib). Respons bundaran memuat `exit_number`; pakai untuk teks
  "ambil jalan keluar ke-N". Putar balik kadang tidak muncul sebagai langkah: jangan diandalkan.
  Jangan mengirim `instructions: false` (di sebagian laporan itu juga menghapus `segments`).
- Bahasa Indonesia tidak ada di daftar bahasa instruksi ORS yang ditemukan, jadi teks dibuat sendiri.
- Kuota gratis Standard: 2.000 permintaan rute/hari, 40/menit (cek ulang di `account.heigit.org/info/plans`).
  403 bisa berarti kuota harian habis ATAU kunci/jalur salah; 429 = batas per menit; 401 = tanpa kunci;
  2010 = titik tidak dekat jalan. Semua ini dibuktikan oleh M0, bukan dianggap benar.
- Lisensi hasil: staf menyebut CC-BY-SA 4.0 (ToS lama menyebut CC-BY 4.0), atribusi wajib,
  penggunaan komersial diizinkan di paket Standard. Baca ToS terbaru di `account.heigit.org/info/tos`.
  Staf menyatakan mereka tidak dapat menentukan apakah koordinat termasuk data pribadi:
  karena itu pemberitahuan privasi (D4) wajib.

## Urutan dan gerbang

| Irisan | Isi | Gerbang keluar |
| --- | --- | --- |
| **M0** | Akun + kunci di `account.heigit.org`; jalankan `tool/ors_probe.ps1`; simpan hasil di `test/fixtures/ors/`. | Fixture nyata ada: rute jalan kaki, mobil, galat 2010, kunci salah, tanpa kunci, permintaan rusak. |
| **M1a** | Bagian murni yang tidak bergantung format ORS: model rute, `route_math`, `instruction_text`, `bearingDegrees`, config + tes. | `flutter analyze` bersih, tes lulus. |
| **M1b** | `OrsRoutingService.parse`, pembentukan URL, pemetaan galat, `StraightLine`, `Fallback`; semua diuji dengan **fixture nyata M0**. | Tes lulus dengan fixture nyata; pemetaan kode galat cocok dengan hasil M0. |
| **M2** | `watchPosition`, `NavigationProvider` dasar + simulasi, layar minimal (peta, garis rute, penanda, sisa jarak). | Bisa didemokan di emulator; tes lulus. |
| **M3** | Kartu instruksi, hitung ulang rute, deteksi tiba, peringatan keselamatan/privasi/persetujuan, moda motor. | Skenario manual (a)-(f). |
| **M4** | Sambung ke detail dan peta, `AppTileLayer` bersama, hapus Google Maps dan `url_launcher`. | `grep -rni google lib` bersih. |
| **M5** | Pemilih lokasi: pin tengah, "Lokasi saya"; pencarian alamat (opsional, tunduk persetujuan). | Tes widget pemilih. |
| **M6** | QA manual (a)-(i) di perangkat fisik, README/SETUP, atribusi final. | Definisi selesai terpenuhi. |

## Hal yang M0 harus membuktikan (cocokkan sebelum menulis parser)
1. Nama kolom: `features[0].geometry.coordinates`, `properties.summary`, `properties.segments[].steps[]`, `way_points`.
2. Kode `type` dan nama jalan kosong (`"-"`) pada rute Cengkareng nyata.
3. Bentuk badan galat dan kode (2010, 401/403, 429, 400) pada `*_response.json` galat.
4. Apakah `radiuses` ada di dokumentasi/respons, nilai bawaannya, dan perilaku `-1` (lihat `no_road_unlimited`:
   seberapa jauh titik akhir tersambung dari titik yang diminta).
5. Header kuota (`x-ratelimit-*`) dan jumlah sisa.
6. Atribusi yang dikembalikan di `metadata.attribution`.

## Perubahan kode yang sudah dipetakan (untuk M1 dan M4)
- `config.dart`: `kOrsApiKey`, `kOrsBaseUrl`, `kOrsGeocodeBaseUrl`, `kRoutingAvailable`, `kDemoSimulation`, ambang rute.
- Satu `AppTileLayer` (atribusi OSM + ORS, User-Agent `kAppPackage`) menggantikan empat `TileLayer`;
  juga agar tes widget tidak mengunduh tile.
- `showLocationError` dilepas dari `SourceProvider`.
- `LocationService` dan `RoutingService` dibuat sekali di `Bootstrap` dan dibagikan lewat `Provider`.
- Pisahkan "ambil lokasi" dari "urutkan terdekat" (tombol Lokasiku tidak lagi mengubah urutan daftar).
- `dart_defines.json` masuk `.gitignore` (tambahkan manual: `echo dart_defines.json >> .gitignore`).

## Catatan dari review M1a (9 November 2026)

Sudah ditutup:
- `snapToRoute` punya batas atas jendela (`maxSegments`), dengan tes rute yang memotong dirinya.
  Di M2, `NavigationProvider` memakai jendela (mis. 50 segmen dari segmen terakhir) dan kembali ke
  pencarian global hanya saat menyimpang.
- Redaksi diperbaiki: "Tetap di kiri menuju Jl. X" (bukan "Tetap di sisi kiri ke Jl. X").
- `tool/ors_probe.ps1` menolak berjalan tanpa memastikan `dart_defines.json` diabaikan git
  (menambahkannya ke `.gitignore` bila perlu). Zip sengaja tidak memuat `.gitignore` agar tidak menimpa
  berkas bawaan `flutter create`.

Syarat untuk M1b dan M2 (belum dikerjakan):
- **Rute degeneratif.** `RoutePlan` memakai `assert(points.length >= 2)`. `parse` WAJIB mengubah
  rute berisi kurang dari dua titik, atau tanpa langkah, menjadi `RoutingException`, bukan membiarkan
  assert gagal. Bila pengguna sudah berada dalam `kArriveMeters` dari sumber air, `NavigationProvider`
  langsung menyatakan tiba tanpa meminta rute.
- Rute setelah diterima tidak boleh punya `firstPoint`/`lastPoint` di luar `points`; `parse` memvalidasinya.
- Angka kuota dan klaim lisensi di dokumen ini belum diverifikasi; M0 yang membuktikannya.

Keadaan: Fase 2 S1-S4, R1, dan R1.1 sudah ditulis (model, rules, tes rules, lapisan data, profil langsung;
lihat `docs/FASE2_PLAN.md`). Hasil CI dan emulator belum ada, kecuali tes rules sampai R1.1 yang sudah
dilaporkan lulus di emulator. Fase 1 masih menunggu M0 (fixture ORS): M1b dst. belum boleh dikerjakan.
