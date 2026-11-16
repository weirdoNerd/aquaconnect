#!/usr/bin/env bash
# Membuat folder android/ yang sudah sesuai kebutuhan AquaConnect
# (minSdk 23, izin INTERNET + lokasi, applicationId milik tim).
# Pemakaian:  ./tool/bootstrap.sh [org]     contoh: ./tool/bootstrap.sh id.ac.kampus
# Setelah itu COMMIT folder android/ agar anggota lain cukup `git clone` + `flutter run`.
set -euo pipefail
ORG="${1:-id.ac.kampus}"
cd "$(dirname "$0")/.."

if [ -d android ]; then
  echo "Folder android/ sudah ada. Melewati pembuatan."
else
  command -v flutter >/dev/null || { echo "Flutter belum terpasang."; exit 1; }
  tmp="$(mktemp -d)"
  cp -r lib test pubspec.yaml analysis_options.yaml "$tmp"/
  flutter create . --platforms=android --org "$ORG" --project-name aquaconnect
  rm -rf lib test
  cp -r "$tmp/lib" lib
  cp -r "$tmp/test" test
  cp "$tmp/pubspec.yaml" pubspec.yaml
  cp "$tmp/analysis_options.yaml" analysis_options.yaml
  python3 tool/patch_android.py
fi

# Samakan konstanta aplikasi dengan applicationId
sed -i.bak "s#const String kAppPackage = .*#const String kAppPackage = '${ORG}.aquaconnect';#" lib/config.dart
rm -f lib/config.dart.bak
flutter pub get
echo "Selesai. applicationId: ${ORG}.aquaconnect"
