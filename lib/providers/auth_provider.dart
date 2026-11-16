import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _service;
  late final StreamSubscription<AppUser?> _sub;

  AppUser? _user;
  bool _loading = false;
  String? _error;

  AuthProvider(this._service) {
    _user = _service.currentUser;
    _sub = _service.authChanges.listen((u) {
      _user = u;
      notifyListeners();
    });
  }

  AppUser? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isProvider => _user?.isProvider ?? false;
  bool get loading => _loading;
  String? get error => _error;

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) =>
      _run(() => _service.signIn(email, password));

  Future<bool> register(String name, String email, String password) =>
      _run(() => _service.register(name, email, password));

  Future<bool> sendPasswordReset(String email) =>
      _run(() => _service.sendPasswordReset(email));

  Future<bool> sendVerification() => _run(_service.sendEmailVerification);

  Future<bool> refreshUser() => _run(_service.refresh);

  Future<bool> deleteAccount(String password) =>
      _run(() => _service.deleteAccount(password));

  Future<void> signOut() => _service.signOut();

  Future<bool> _run(Future<void> Function() action) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      debugPrint('AuthProvider: $e');
      _error = 'Terjadi kesalahan. Periksa koneksi lalu coba lagi.';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
