<#
  M0: mengambil respons NYATA dari openrouteservice untuk dijadikan data tes.

  Pemakaian (dari folder proyek, Windows PowerShell atau pwsh):
    Copy-Item dart_defines.example.json dart_defines.json   # lalu isi ORS_API_KEY
    .\tool\ors_probe.ps1

  Hasil di test/fixtures/ors/: NAMA.request.json, NAMA.response.json, NAMA.headers.txt
  Kunci TIDAK ditulis ke berkas hasil. JANGAN commit dart_defines.json.
  Skrip ini hanya memanggil jaringan; belum diuji di mesin saya (tidak ada PowerShell di sana).
#>
param(
  [string]$BaseUrl = 'https://api.heigit.org/openrouteservice',
  [string]$DefinesFile = 'dart_defines.json'
)

$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')   # tanpa garis miring di akhir

# Pastikan berkas berisi kunci tidak bisa ter-commit.
if ((Test-Path '.git') -and (Get-Command git -ErrorAction SilentlyContinue)) {
  git check-ignore -q $DefinesFile
  if ($LASTEXITCODE -eq 1) {   # 1 = ada di repo tetapi belum diabaikan
    $gi = '.gitignore'
    $existing = if (Test-Path $gi) { Get-Content $gi -Raw } else { '' }
    $prefix = if ($existing -and -not $existing.EndsWith("`n")) { "`n" } else { '' }
    Add-Content -Path $gi -Value ($prefix + $DefinesFile)
    Write-Host "$DefinesFile belum diabaikan git; ditambahkan ke .gitignore."
  }
}

if (-not (Test-Path $DefinesFile)) {
  throw "Tidak ada $DefinesFile. Salin dari dart_defines.example.json lalu isi kuncinya."
}
$key = (Get-Content $DefinesFile -Raw | ConvertFrom-Json).ORS_API_KEY
if ([string]::IsNullOrWhiteSpace($key) -or $key -eq 'isi_di_sini') {
  throw 'Isi ORS_API_KEY di dart_defines.json.'
}

$out = 'test/fixtures/ors'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

# URUTAN ORS: [bujur, lintang] (kebalikan LatLng). Titik di sekitar Cengkareng.
$from = '[106.7340,-6.1450]'
$to   = '[106.7440,-6.1380]'
$sea  = '[106.8000,-6.0200]'   # Teluk Jakarta: sengaja jauh dari jalan

function Invoke-Probe {
  param([string]$Name, [string]$OrsProfile, [string]$Body, [string]$ApiKey)
  $reqFile = Join-Path $out "$Name.request.json"
  $resFile = Join-Path $out "$Name.response.json"
  $hdrFile = Join-Path $out "$Name.headers.txt"
  [IO.File]::WriteAllText($reqFile, $Body, $utf8)

  $curlArgs = @(
    '-s', '-o', $resFile, '-D', $hdrFile, '-w', '%{http_code}', '-X', 'POST',
    "$BaseUrl/v2/directions/$OrsProfile/geojson",
    '-H', 'Content-Type: application/json; charset=utf-8',
    '-H', 'Accept: application/geo+json, application/json',
    '--data-binary', "@$reqFile"
  )
  if ($ApiKey) { $curlArgs += @('-H', "Authorization: $ApiKey") }

  $status = & curl.exe @curlArgs
  '{0,-20} HTTP {1}' -f $Name, $status
}

$ok  = '{"coordinates":[' + $from + ',' + $to  + '],"instructions":true,"units":"m"}'
$far = '{"coordinates":[' + $from + ',' + $sea + '],"instructions":true,"units":"m"}'
$farUnlimited = '{"coordinates":[' + $from + ',' + $sea + '],"radiuses":[-1,-1],"instructions":true,"units":"m"}'

Write-Host "Memanggil $BaseUrl (7 permintaan, jauh di bawah kuota harian)..."
Invoke-Probe 'walk_ok'           'foot-walking' $ok $key
Invoke-Probe 'car_ok'            'driving-car'  $ok $key
Invoke-Probe 'no_road_default'   'foot-walking' $far $key
Invoke-Probe 'no_road_unlimited' 'foot-walking' $farUnlimited $key
Invoke-Probe 'bad_request'       'foot-walking' '{"coordinates":[[0]]}' $key
Invoke-Probe 'bad_key'           'foot-walking' $ok 'kunci-palsu'
Invoke-Probe 'no_key'            'foot-walking' $ok ''

Write-Host ''
Write-Host 'Header kuota (walk_ok):'
Select-String -Path (Join-Path $out 'walk_ok.headers.txt') -Pattern 'ratelimit' | ForEach-Object { $_.Line }
Write-Host ''
Write-Host "Selesai. Periksa isi $out lalu kirim folder itu. Kunci tidak ada di berkas hasil."
