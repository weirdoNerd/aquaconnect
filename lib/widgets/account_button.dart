import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/admin_screen.dart';
import '../screens/login_screen.dart';
import '../screens/my_reports_screen.dart';

class AccountButton extends StatelessWidget {
  const AccountButton({super.key});

  void _snack(BuildContext c, String text) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _onSelected(BuildContext context, String v) async {
    final auth = context.read<AuthProvider>();
    switch (v) {
      case 'logout':
        await auth.signOut();
      case 'admin':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminScreen()));
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
        final password = await showDialog<String>(
            context: context, builder: (_) => const _DeleteAccountDialog());
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
              Text(user.isAdmin ? 'Pengelola' : 'Warga',
                  style: const TextStyle(fontSize: 12)),
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
        const PopupMenuItem(value: 'reports', child: Text('Laporan saya')),
        const PopupMenuItem(value: 'delete', child: Text('Hapus akun')),
        const PopupMenuItem(value: 'logout', child: Text('Keluar')),
      ],
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hapus akun?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'Akun dan profilmu akan dihapus permanen. Laporan yang pernah '
              'dikirim tetap tersimpan tanpa nama. Masukkan kata sandi untuk melanjutkan.'),
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
