import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/provider_application.dart';
import '../models/provider_profile.dart';
import '../services/provider_service.dart';

/// Mengelola pengajuan penyedia dan daftar penyedia aktif/terputus untuk admin.
class ProviderAdminProvider extends ChangeNotifier {
  final ProviderService _service;
  ProviderAdminProvider(this._service);

  bool _synced = false;
  bool _disposed = false;
  String? _uid;
  bool _isAdmin = false;
  StreamSubscription<List<ProviderApplication>>? _sub;

  List<ProviderApplication> _pending = const [];
  List<ProviderProfile> _providers = const [];
  bool _loading = false;
  bool _busy = false;
  String? _loadError;
  String? _actionError;

  List<ProviderApplication> get pending => List.unmodifiable(_pending);
  List<ProviderProfile> get providers => List.unmodifiable(_providers);
  int get pendingCount => _pending.length;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get error => _actionError ?? _loadError;
  String? get loadError => _loadError;
  String? get actionError => _actionError;

  /// Dipanggil dari ProxyProvider saat build, jadi TIDAK memanggil notifyListeners.
  /// Hanya admin yang melanggan pengajuan dan memuat daftar penyedia.
  void syncUser(String? uid, {required bool isAdmin}) {
    if (_synced && uid == _uid && isAdmin == _isAdmin) return;
    _synced = true;
    _uid = uid;
    _isAdmin = isAdmin;

    _sub?.cancel();
    _sub = null;
    _pending = const [];
    _providers = const [];
    _loading = false;
    _busy = false;
    _loadError = null;
    _actionError = null;

    if (isAdmin && uid != null) {
      _loading = true;
      _subscribe(uid);
      _fetchProviders(uid);
    }
  }

  bool _active(String uid) => !_disposed && _uid == uid && _isAdmin;

  void _subscribe(String uid) {
    _sub = _service.watchPending().listen(
      (list) {
        if (!_active(uid)) return;
        _pending = list;
        _loadError = null;
        _loading = false;
        notifyListeners();
      },
      onError: (Object e) {
        if (!_active(uid)) return;
        debugPrint('ProviderAdminProvider stream error: $e');
        _loadError = 'Gagal memuat pengajuan penyedia.';
        _loading = false;
        notifyListeners();
      },
    );
  }

  Future<void> _fetchProviders(String uid) async {
    try {
      final list = await _service.fetchProviders();
      if (!_active(uid)) return;
      _providers = list;
      _loadError = null;
    } on ProviderException catch (e) {
      if (!_active(uid)) return;
      _loadError = e.message;
    } catch (e) {
      if (!_active(uid)) return;
      debugPrint('ProviderAdminProvider fetchProviders error: $e');
      _loadError = 'Gagal memuat daftar penyedia.';
    } finally {
      if (_active(uid)) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> reload() async {
    final uid = _uid;
    if (!_isAdmin || uid == null) return;
    _sub?.cancel();
    _sub = null;
    _loadError = null;
    _loading = true;
    notifyListeners();
    _subscribe(uid);
    await _fetchProviders(uid);
  }

  void clearError() {
    if (_actionError != null) {
      _actionError = null;
      notifyListeners();
    }
  }

  Future<bool> review(String uid, {required bool approve, String note = ''}) =>
      _runAction(() => _service.review(uid, approve: approve, note: note));

  Future<bool> terminate(String uid, String reason) => _runAction(
        () => _service.terminate(uid, reason),
        reloadOnError: true,
      );

  Future<bool> reactivate(String uid) =>
      _runAction(() => _service.reactivate(uid));

  Future<bool> _runAction(
    Future<void> Function() action, {
    bool reloadOnError = false,
  }) async {
    final adminUid = _uid;
    if (!_isAdmin || adminUid == null) {
      _actionError = 'Hanya pengelola yang dapat melakukan tindakan ini.';
      notifyListeners();
      return false;
    }
    if (_busy) return false;

    _busy = true;
    _actionError = null;
    notifyListeners();

    try {
      await action();
      if (_active(adminUid)) {
        await _fetchProviders(adminUid);
      }
      return true;
    } on ProviderException catch (e) {
      if (_active(adminUid)) {
        _actionError = e.message;
        if (reloadOnError) await _fetchProviders(adminUid);
      }
      return false;
    } catch (e) {
      debugPrint('ProviderAdminProvider action error: $e');
      if (_active(adminUid)) {
        _actionError = 'Tindakan gagal. Periksa koneksi lalu coba lagi.';
        if (reloadOnError) await _fetchProviders(adminUid);
      }
      return false;
    } finally {
      if (!_disposed && _uid == adminUid) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
