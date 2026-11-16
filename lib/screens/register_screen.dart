import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().clearError();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context
        .read<AuthProvider>()
        .register(_name.text, _email.text, _password.text);
    if (ok && mounted) {
      nav.popUntil((r) => r.isFirst);
      if (useFirebase && kRequireVerifiedEmail) {
        messenger.showSnackBar(const SnackBar(
            content: Text('Akun dibuat. Cek email untuk verifikasi sebelum mengirim laporan.')));
      }
    }
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Daftar')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      maxLength: 60,
                      decoration: _dec('Nama', Icons.person_outline),
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Nama minimal 2 karakter'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _dec('Email', Icons.email_outlined),
                      onChanged: (_) => auth.clearError(),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Email wajib diisi';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                          return 'Format email tidak valid';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      decoration: _dec('Kata sandi', Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Tampilkan sandi' : 'Sembunyikan sandi',
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6) ? 'Minimal 6 karakter' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: _dec('Ulangi kata sandi', Icons.lock_reset_outlined),
                      validator: (v) =>
                          v != _password.text ? 'Kata sandi tidak sama' : null,
                    ),
                    if (auth.error != null) ...[
                      const SizedBox(height: 12),
                      Text(auth.error!, style: TextStyle(color: scheme.error)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: auth.loading ? null : _submit,
                      child: auth.loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Buat akun'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
