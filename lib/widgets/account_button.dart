import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../models/provider_application.dart';
import '../providers/auth_provider.dart';
import '../providers/my_sources_provider.dart';
import '../providers/provider_application_provider.dart';
import '../providers/source_provider.dart';
import '../screens/admin_screen.dart';
import '../screens/login_screen.dart';
import '../screens/my_reports_screen.dart';
import '../screens/my_sources_screen.dart';
import '../screens/provider_apply_screen.dart';

class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  void _snack(BuildContext c, String text) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));

  String _roleLabel(AppUser user) {
    if (user.isProvider) return 'Penyedia';
    if (user.isAdmin) return 'Pengelola';
    return 'Warga';
  }

  String? _providerMenuLabel(AppUser user, ProviderApplication? app) {
    if (user.isAdmin) return null;
    if (user.providerStatus == ProviderStatus.active ||
        user.providerStatus == ProviderStatus.terminated) {
      return 'Status penyedia';
    }
    if (app != null &&
        (app.status == ApplicationStatus.pending ||
            app.status == ApplicationStatus.rejected)) {
      return 'Status pengajuan';
    }
    return 'Jadi penyedia';
  }

  Future<void> _onSelected(BuildContext context, String v) async {
    final auth = context.read<AuthProvider>();
    switch (v) {
      case 'logout':
        await auth.signOut();
      case 'admin':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminScreen()));
      case 'provider':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProviderApplyScreen()));
      case 'my_sources':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MySourcesScreen()));
      case 'reports':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const MyReportsScreen()));
      case 'verify':
        final ok = await auth.sendVerification();
        if (context.mounted) {
          _snack(context,
              ok ? 'Email verifikasi dikirim. Cek kotak masuk.' : auth.error ?? 'Gagal.');
        }
      case 'refresh':
        final ok = await auth.refreshUser();
        if (context.mounted && !ok) _snack(context, auth.error ?? 'Gagal memuat ulang.');
      case 'delete':
        final status = auth.user?.providerStatus ?? ProviderStatus.none;
        final password = await showDialog<String>(
          context: context,
          builder: (_) => _DeleteAccountDialog(providerStatus: status),
        );
        if (password == null || !context.mounted) return;
        final ok = await auth.deleteAccount(password);
        if (context.mounted) {
          _snack(context, ok ? 'Akun dihapus.' : auth.error ?? 'Gagal menghapus akun.');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    if (user == null) {
      return IconButton(
        icon: const Icon(Icons.login),
        tooltip: 'Masuk',
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const LoginScreen())),
      );
    }

    final app = context.watch<ProviderApplicationProvider>().application;
    final providerItem = _providerMenuLabel(user, app);
    SourceProvider? sourceProv;
    try {
      sourceProv = context.watch<SourceProvider>();
    } on ProviderNotFoundException {
      sourceProv = null;
    }
    final showMySources = user.isProvider && !user.isAdmin;
    final dueCount = (showMySources && sourceProv != null)
        ? MySourcesProvider.dueFor(user.uid, sourceProv.all).length
        : 0;

    return PopupMenuButton<String>(
      tooltip: 'Akun',
      icon: CircleAvatar(
        radius: 14,
        child: Text(user.name.isEmpty ? '?' : user.name[0].toUpperCase()),
      ),
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(user.email, style: const TextStyle(fontSize: 12)),
              Text(_roleLabel(user), style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (!user.profileLoaded)
          const PopupMenuItem(
              value: 'refresh', child: Text('Profil belum termuat, coba lagi')),
        if (!user.emailVerified) ...const [
          PopupMenuItem(value: 'verify', child: Text('Kirim ulang email verifikasi')),
          PopupMenuItem(value: 'refresh', child: Text('Saya sudah verifikasi')),
        ],
        if (user.isAdmin)
          const PopupMenuItem(value: 'admin', child: Text('Panel pengelola')),
        if (showMySources)
          PopupMenuItem(
            value: 'my_sources',
            child: Semantics(
              label: dueCount > 0
                  ? 'Sumber saya, $dueCount perlu dikonfirmasi'
                  : 'Sumber saya',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sumber saya'),
                  if (dueCount > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade900,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$dueCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (providerItem != null)
          PopupMenuItem(value: 'provider', child: Text(providerItem)),
        const PopupMenuItem(value: 'reports', child: Text('Laporan saya')),
        const PopupMenuItem(value: 'delete', child: Text('Hapus akun')),
        const PopupMenuItem(value: 'logout', child: Text('Keluar')),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  final ProviderStatus providerStatus;
  const _DeleteAccountDialog({required this.providerStatus});

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _message() => switch (widget.providerStatus) {
        ProviderStatus.active =>
          'Akun, pengajuan, dan profilmu akan dihapus permanen. Semua sumber air '
              'milik Anda akan ditutup terlebih dahulu. Laporan yang pernah dikirim '
              'tetap tersimpan tanpa nama. Masukkan kata sandi untuk melanjutkan.',
        ProviderStatus.terminated =>
          'Hanya akun masuk yang akan dihapus. Sesuai kebijakan privasi dan keamanan, '
              'catatan pemutusan kemitraan tetap disimpan agar tidak disalahgunakan. '
              'Masukkan kata sandi untuk melanjutkan.',
        ProviderStatus.none =>
          'Akun dan profilmu akan dihapus permanen. Laporan yang pernah '
              'dikirim tetap tersimpan tanpa nama. Masukkan kata sandi untuk melanjutkan.',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hapus akun?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_message()),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'Kata sandi', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
          onPressed: () {
            if (_ctrl.text.isNotEmpty) Navigator.pop(context, _ctrl.text);
          },
          child: const Text('Hapus akun'),
        ),
      ],
    );
  }
}
