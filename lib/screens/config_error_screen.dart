import 'package:flutter/material.dart';

/// Ditampilkan bila inisialisasi Firebase gagal, agar aplikasi tidak mati
/// tanpa pesan.
class ConfigErrorScreen extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ConfigErrorScreen({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 56),
                const SizedBox(height: 16),
                Text('Konfigurasi Firebase belum lengkap',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                    'Jalankan `flutterfire configure` lalu bangun ulang aplikasi '
                    '(lihat SETUP_FIREBASE.md). Jika sudah, periksa koneksi internet.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text('$error',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
