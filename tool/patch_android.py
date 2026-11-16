"""Menambah minSdk 23 dan izin yang dibutuhkan AquaConnect ke proyek android/."""
import pathlib
import re

app = pathlib.Path("android/app")

for name in ("build.gradle.kts", "build.gradle"):
    p = app / name
    if p.exists():
        s = p.read_text()
        s = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", s)
        s = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", s)
        p.write_text(s)
        print(f"minSdk 23 -> {name}")

manifest = app / "src/main/AndroidManifest.xml"
s = manifest.read_text()
perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
]
add = "".join(
    f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in s
)
s = s.replace("<application", add + "    <application", 1)
manifest.write_text(s)
print("izin ditambahkan ke AndroidManifest.xml")
