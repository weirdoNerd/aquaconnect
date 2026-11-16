import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../providers/auth_provider.dart';
import 'register_screen.dart';

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // Error dari layar lain tidak boleh terbawa ke sini.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().clearError();
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final nav = Navigator.of(context);
    final ok = await context.read<AuthProvider>().signIn(_email.text, _password.text);
    if (ok && mounted) nav.pop();
  }

  Future<void> _forgot() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initial: _email.text.trim()),
    );
    if (email == null || !mounted) return;
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await auth.sendPasswordReset(email);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Jika email terdaftar, tautan reset kata sandi telah dikirim.'
          : auth.error ?? 'Gagal mengirim email reset.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Masuk')),
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
                    Icon(Icons.water_drop, size: 64, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text('AquaConnect',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const Text('Temukan Air, Hubungkan Harapan.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => auth.clearError(),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Email wajib diisi';
                        if (!_emailRegex.hasMatch(t)) return 'Format email tidak valid';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Kata sandi',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Tampilkan sandi' : 'Sembunyikan sandi',
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onChanged: (_) => auth.clearError(),
                      // Aturan panjang hanya untuk pendaftaran, bukan saat masuk.
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Kata sandi wajib diisi' : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: auth.loading ? null : _forgot,
                        child: const Text('Lupa kata sandi?'),
                      ),
                    ),
                    if (auth.error != null) ...[
                      Text(auth.error!, style: TextStyle(color: scheme.error)),
                      const SizedBox(height: 8),
                    ],
                    FilledButton(
                      onPressed: auth.loading ? null : _submit,
                      child: auth.loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Masuk'),
                    ),
                    TextButton(
                      onPressed: auth.loading
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen())),
                      child: const Text('Belum punya akun? Daftar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Lanjut tanpa masuk'),
                    ),
                    if (kDebugMode && !useFirebase)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Akun demo (hanya mode debug):\n'
                          'admin@aquaconnect.test / admin123 (Admin)\n'
                          'warga@aquaconnect.test / warga123 (Warga)\n'
                          'penyedia@aquaconnect.test / penyedia123 (Penyedia)\n'
                          'calon@aquaconnect.test / calon123 (Calon penyedia)',
                          style: TextStyle(fontSize: 12),
                        ),
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

class _ForgotPasswordDialog extends StatefulWidget {
  final String initial;
  const _ForgotPasswordDialog({required this.initial});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _apply() {
    final t = _ctrl.text.trim();
    if (!_emailRegex.hasMatch(t)) {
      setState(() => _error = 'Format email tidak valid');
      return;
    }
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset kata sandi'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: 'Email akun',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _apply(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(onPressed: _apply, child: const Text('Kirim tautan')),
      ],
    );
  }
}
