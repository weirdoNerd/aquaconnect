import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config.dart';
import '../models/provider_application.dart';
import '../services/provider_service.dart';

/// State pengajuan menjadi penyedia air untuk pengguna yang sedang masuk.
class ProviderApplicationProvider extends ChangeNotifier {
  final ProviderService _service;
  ProviderApplicationProvider(this._service);

  String? _uid;
  StreamSubscription<ProviderApplication?>? _sub;

  ProviderApplication? _application;
  bool _loading = false;
  bool _submitting = false;
  String? _error;

  ProviderApplication? get application => _application;
  bool get loading => _loading;
  bool get submitting => _submitting;
  String? get error => _error;

  /// Dipanggil dari ProxyProvider saat build, jadi TIDAK memanggil notifyListeners.
  /// Mengosongkan state dan membatalkan langganan lama saat pengguna berganti/keluar.
  void syncUser(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    _sub?.cancel();
    _sub = null;
    _application = null;
    _loading = false;
    _submitting = false;
    _error = null;
    if (uid != null) _subscribe(uid);
  }

  void _subscribe(String uid) {
    _loading = true;
    _sub = _service.watchMyApplication(uid).listen(
      (app) {
        if (_uid != uid) return;
        _application = app;
        _loading = false;
        _error = null;
        notifyListeners();
      },
      onError: (Object e) {
        if (_uid != uid) return;
        debugPrint('ProviderApplicationProvider stream error: $e');
        _loading = false;
        _error = _friendlyError(e);
        notifyListeners();
      },
    );
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  void retry() {
    final uid = _uid;
    if (uid == null) return;
    _sub?.cancel();
    _error = null;
    _subscribe(uid);
    notifyListeners();
  }

  /// Mengirim pengajuan baru atau pengajuan ulang memakai [kProviderTermsVersion].
  Future<bool> apply(
    String organizationName,
    String contactPhone,
    String description,
  ) async {
    final uid = _uid;
    if (uid == null) {
      _error = 'Silakan masuk terlebih dahulu.';
      notifyListeners();
      return false;
    }

    _submitting = true;
    _error = null;
    notifyListeners();

    try {
      await _service.apply(ProviderApplication(
        uid: uid,
        organizationName: organizationName.trim(),
        contactPhone: contactPhone.trim(),
        description: description.trim(),
        termsVersion: kProviderTermsVersion,
      ));
      return true;
    } on ProviderException catch (e) {
      if (_uid == uid) _error = _friendlyMessage(e.message);
      return false;
    } catch (e) {
      debugPrint('ProviderApplicationProvider apply error: $e');
      if (_uid == uid) _error = _friendlyError(e);
      return false;
    } finally {
      if (_uid == uid) {
        _submitting = false;
        notifyListeners();
      }
    }
  }

  static String _friendlyMessage(String msg) {
    if (msg == 'Tidak ada izin untuk tindakan ini.' ||
        msg.contains('permission-denied')) {
      return 'Verifikasi email dulu atau pastikan akun belum pernah disetujui.';
    }
    return msg;
  }

  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('permission-denied') ||
        s.contains('Tidak ada izin untuk tindakan ini.')) {
      return 'Verifikasi email dulu atau pastikan Anda memiliki izin untuk melihat pengajuan.';
    }
    return 'Gagal memproses pengajuan. Periksa koneksi lalu coba lagi.';
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
