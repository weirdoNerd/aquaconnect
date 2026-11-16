import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/app_user.dart';
import '../models/provider_application.dart';
import '../providers/auth_provider.dart';
import '../providers/provider_application_provider.dart';
import 'login_screen.dart';

/// Teks Ketentuan Penyedia (disimpan di satu tempat; naikkan bersama
/// [kProviderTermsVersion] dan batas `termsVersion` di firestore.rules).
const String kProviderTermsHeader =
    'Ketentuan Penyedia v$kProviderTermsVersion (DRAF — untuk disepakati bersama dosen)';

const List<String> kProviderTermsItems = [
  'Data yang dikirimkan benar dan penyedia berhak atas lokasi sumber air tersebut.',
  'Konfirmasi ketersediaan air dilakukan minimal setiap 3 hari sekali selama sumber tayang.',
  'Tutup sumber di aplikasi apabila berhenti menyediakan air.',
  'Sumber yang tidak dikonfirmasi dapat disembunyikan dan kemitraan dapat diputus apabila ketentuan dilanggar.',
  'Data pengajuan hanya dilihat oleh admin pengelola.',
];

class ProviderApplyScreen extends StatefulWidget {
  const ProviderApplyScreen({super.key});

  @override
  State<ProviderApplyScreen> createState() => _ProviderApplyScreenState();
}

class _ProviderApplyScreenState extends State<ProviderApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _orgCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _agreed = false;
  bool _reapplying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProviderApplicationProvider>().clearError();
    });
  }

  @override
  void dispose() {
    _orgCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  static String? _validateOrg(String? v) {
    final t = (v ?? '').trim();
    if (t.length < 3 || t.length > 80) {
      return 'Nama usaha/pengelola harus 3-80 karakter.';
    }
    return null;
  }

  static String? _validatePhone(String? v) {
    final t = (v ?? '').trim();
    if (!ProviderApplication.isValidPhone(t)) {
      return 'Nomor telepon 6-20 karakter (hanya angka, +, dan spasi).';
    }
    return null;
  }

  static String? _validateDesc(String? v) {
    final t = (v ?? '').trim();
    if (t.length < 10 || t.length > 300) {
      return 'Deskripsi harus 10-300 karakter.';
    }
    return null;
  }

  bool get _isFormValid =>
      _validateOrg(_orgCtrl.text) == null &&
      _validatePhone(_phoneCtrl.text) == null &&
      _validateDesc(_descCtrl.text) == null &&
      _agreed;

  void _startReapply(ProviderApplication old) {
    setState(() {
      _orgCtrl.text = old.organizationName;
      _phoneCtrl.text = old.contactPhone;
      _descCtrl.text = old.description;
      _agreed = false;
      _reapplying = true;
    });
    context.read<ProviderApplicationProvider>().clearError();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || !_agreed) return;
    final prov = context.read<ProviderApplicationProvider>();
    final ok = await prov.apply(
      _orgCtrl.text,
      _phoneCtrl.text,
      _descCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _reapplying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pengajuan penyedia berhasil dikirim.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final appProv = context.watch<ProviderApplicationProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Penyedia Air')),
      body: SafeArea(
        child: _buildBody(context, auth, user, appProv),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AuthProvider auth,
    AppUser? user,
    ProviderApplicationProvider appProv,
  ) {
    // 3a. Belum login.
    if (user == null) {
      return _StatusView(
        icon: Icons.login,
        title: 'Masuk terlebih dahulu',
        message: 'Masuk dengan akun Anda untuk mengajukan diri sebagai penyedia air.',
        actionLabel: 'Masuk',
        onAction: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
      );
    }

    // 3f. Status penyedia aktif (otoritas: user.providerStatus).
    if (user.providerStatus == ProviderStatus.active) {
      return _StatusView(
        icon: Icons.verified_user,
        iconColor: Colors.green.shade800,
        title: 'Kamu sudah menjadi penyedia',
        message: 'Halaman Sumber Saya hadir di pembaruan berikutnya.',
      );
    }

    // 3g. Kemitraan diputus (otoritas: user.providerStatus).
    if (user.providerStatus == ProviderStatus.terminated) {
      final note = user.providerNote?.trim() ?? '';
      return _StatusView(
        icon: Icons.block,
        iconColor: Colors.red.shade800,
        title: 'Kemitraan penyedia diputus',
        message: note.isNotEmpty
            ? 'Alasan pemutusan: $note'
            : 'Kemitraan penyedia Anda telah dihentikan oleh pengelola.',
      );
    }

    // 3b. Wajib verifikasi email sebelum mengajukan.
    if (kRequireVerifiedEmail && !user.emailVerified) {
      return _VerifyEmailView(auth: auth);
    }

    final app = appProv.application;

    if (appProv.loading && app == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (appProv.error != null && app == null && !_reapplying) {
      return _StatusView(
        icon: Icons.error_outline,
        iconColor: Colors.red.shade800,
        title: 'Gagal memuat pengajuan',
        message: appProv.error!,
        actionLabel: 'Coba lagi',
        onAction: appProv.retry,
      );
    }

    // 3d. Sedang menunggu peninjauan admin.
    if (app != null && app.status == ApplicationStatus.pending) {
      return _PendingView(application: app);
    }

    // 3e. Ditolak (sebelum menekan tombol ajukan ulang).
    if (app != null &&
        app.status == ApplicationStatus.rejected &&
        !_reapplying) {
      return _RejectedView(
        application: app,
        onReapply: () => _startReapply(app),
      );
    }

    // 3c. Belum mengajukan atau sedang mengajukan ulang.
    return _buildForm(context, appProv);
  }

  Widget _buildForm(
    BuildContext context,
    ProviderApplicationProvider appProv,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _reapplying ? 'Ajukan ulang penyedia air' : 'Daftar sebagai penyedia air',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Isi data pengelola sumber air berikut untuk ditinjau admin.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _orgCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nama usaha / pengelola',
                    hintText: 'Contoh: Depot Air Bersih RW 03',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateOrg,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nomor telepon',
                    hintText: 'Contoh: +62 812 3456 7890',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validatePhone,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Deskripsi singkat',
                    hintText: 'Jelaskan sumber air yang dikelola dan jam layanannya.',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateDesc,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                const _TermsBox(),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _agreed,
                  onChanged: appProv.submitting
                      ? null
                      : (v) => setState(() => _agreed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'Saya telah membaca dan menyetujui Ketentuan Penyedia v$kProviderTermsVersion (DRAF).',
                  ),
                ),
                if (appProv.error != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 18, color: scheme.error),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          appProv.error!,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: (_isFormValid && !appProv.submitting) ? _submit : null,
                  child: appProv.submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_reapplying ? 'Kirim pengajuan ulang' : 'Kirim pengajuan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TermsBox extends StatelessWidget {
  const _TermsBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            kProviderTermsHeader,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < kProviderTermsItems.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${i + 1}. ${kProviderTermsItems[i]}'),
            ),
        ],
      ),
    );
  }
}

class _VerifyEmailView extends StatelessWidget {
  final AuthProvider auth;
  const _VerifyEmailView({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.mark_email_unread_outlined,
                  size: 56, color: Colors.orange.shade800),
              const SizedBox(height: 12),
              Text(
                'Verifikasi email diperlukan',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Email akun Anda belum terverifikasi. Verifikasi email terlebih '
                'dahulu sebelum mengajukan menjadi penyedia air.',
                textAlign: TextAlign.center,
              ),
              if (auth.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  auth.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: auth.loading
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await auth.sendVerification();
                        if (context.mounted) {
                          messenger.showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Email verifikasi dikirim. Cek kotak masuk.'
                                : auth.error ?? 'Gagal mengirim email verifikasi.'),
                          ));
                        }
                      },
                child: const Text('Kirim ulang email verifikasi'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: auth.loading ? null : () => auth.refreshUser(),
                child: const Text('Saya sudah verifikasi'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingView extends StatelessWidget {
  final ProviderApplication application;
  const _PendingView({required this.application});

  @override
  Widget build(BuildContext context) {
    final submittedAt = application.createdAt != null
        ? DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(application.createdAt!)
        : '-';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.hourglass_top, color: Colors.orange.shade900),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Menunggu peninjauan admin',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pengajuan Anda sedang diperiksa oleh pengelola. Anda akan '
                    'langsung menjadi penyedia setelah disetujui.',
                  ),
                  const Divider(height: 24),
                  _SummaryRow(
                    label: 'Nama usaha / pengelola',
                    value: application.organizationName,
                  ),
                  _SummaryRow(
                    label: 'Nomor telepon',
                    value: application.contactPhone,
                  ),
                  _SummaryRow(
                    label: 'Deskripsi',
                    value: application.description,
                  ),
                  _SummaryRow(
                    label: 'Dikirim pada',
                    value: submittedAt,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RejectedView extends StatelessWidget {
  final ProviderApplication application;
  final VoidCallback onReapply;
  const _RejectedView({required this.application, required this.onReapply});

  @override
  Widget build(BuildContext context) {
    final note = application.adminNote.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: Colors.red.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pengajuan ditolak',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    note.isNotEmpty
                        ? 'Catatan admin: $note'
                        : 'Pengajuan Anda belum dapat disetujui.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: onReapply,
                    child: const Text('Ajukan ulang'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(value),
        ],
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StatusView({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: iconColor ?? Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
