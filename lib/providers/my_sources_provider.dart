import 'package:flutter/foundation.dart';
import '../config.dart';
import '../models/water_source.dart';
import '../services/source_service.dart';

/// Mengelola aksi operasional penyedia aktif pada sumber miliknya dengan status
/// sibuk dan galat per sumber.
class MySourcesProvider extends ChangeNotifier {
  final SourceService _service;
  MySourcesProvider(this._service);

  bool _synced = false;
  String? _uid;
  bool _isProvider = false;

  final Set<String> _busyIds = {};
  final Map<String, String> _errors = {};
  bool _bulkBusy = false;
  String? _bulkError;

  bool isBusy(String id) => _busyIds.contains(id);
  String? errorFor(String id) => _errors[id];
  bool get bulkBusy => _bulkBusy;
  String? get bulkError => _bulkError;

  /// Sumber milik penyedia aktif dari daftar [SourceProvider.all].
  List<WaterSource> ownedFrom(List<WaterSource> all) {
    final uid = _uid;
    if (uid == null) return const [];
    return all.where((s) => s.ownerId == uid).toList();
  }

  /// True bila sumber tayang dan konfirmasinya lebih lama dari [kReconfirmReminderAfter].
  static bool needsReconfirm(WaterSource s, [DateTime? now]) {
    if (s.listingStatus != ListingStatus.published) return false;
    final v = s.verifiedAt;
    if (v == null) return true;
    return (now ?? DateTime.now()).difference(v) > kReconfirmReminderAfter;
  }

  /// Daftar sumber tayang milik penyedia yang perlu dikonfirmasi ulang.
  static List<WaterSource> dueFor(String? uid, List<WaterSource> all,
      [DateTime? now]) {
    if (uid == null) return const [];
    return [
      for (final s in all)
        if (s.ownerId == uid && needsReconfirm(s, now)) s,
    ];
  }

  List<WaterSource> dueFrom(List<WaterSource> all, [DateTime? now]) =>
      dueFor(_uid, all, now);

  /// Dipanggil dari ProxyProvider saat build, jadi TIDAK memanggil notifyListeners.
  void syncUser(String? uid, {required bool isProvider}) {
    if (_synced && uid == _uid && isProvider == _isProvider) return;
    _synced = true;
    _uid = uid;
    _isProvider = isProvider;
    _busyIds.clear();
    _errors.clear();
    _bulkBusy = false;
    _bulkError = null;
  }

  void clearError(String id) {
    if (_errors.remove(id) != null) notifyListeners();
  }

  void clearBulkError() {
    if (_bulkError != null) {
      _bulkError = null;
      notifyListeners();
    }
  }

  Future<bool> updateOperational(
    String id, {
    Availability? availability,
    String? openingHours,
  }) =>
      _runFor(
        id,
        () => _service.updateOperational(
          id,
          availability: availability,
          openingHours: openingHours,
        ),
      );

  Future<bool> confirmStillCurrent(String id) =>
      _runFor(id, () => _service.confirmStillCurrent(id));

  Future<bool> closeOwned(String id, String reason) =>
      _runFor(id, () => _service.closeOwned(id, reason));

  /// Mengirim sumber baru milik penyedia aktif (status awal `pending`).
  /// Mengembalikan pesan galat, atau null jika berhasil.
  Future<String?> createAsProvider(WaterSource draft, String ownerName) =>
      _guardAction(
        () => _service.createAsProvider(draft, _uid!, ownerName),
        fallbackError: 'Gagal mengirim sumber. Periksa koneksi lalu coba lagi.',
      );

  /// Mengirim ulang sumber belum tayang (`pending` / `rejected`).
  /// Mengembalikan pesan galat, atau null jika berhasil.
  Future<String?> resubmit(WaterSource updated) => _guardAction(
        () => _service.resubmit(updated),
        fallbackError:
            'Gagal mengirim perubahan. Periksa koneksi lalu coba lagi.',
      );

  Future<String?> _guardAction(
    Future<void> Function() action, {
    required String fallbackError,
  }) async {
    final uid = _uid;
    if (!_isProvider || uid == null) {
      return 'Hanya penyedia aktif yang dapat mengelola sumber.';
    }
    try {
      await action();
      return null;
    } on SourceException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('MySourcesProvider form error: $e');
      return fallbackError;
    }
  }

  /// Mengonfirmasi semua [targets] secara berurutan tanpa berhenti di tengah
  /// bila ada yang gagal.
  Future<({int succeeded, List<String> failedNames})> confirmAll(
      List<WaterSource> targets) async {
    final uid = _uid;
    if (!_isProvider || uid == null) {
      _bulkError = 'Hanya penyedia aktif yang dapat mengonfirmasi sumber.';
      notifyListeners();
      return (succeeded: 0, failedNames: const <String>[]);
    }
    if (targets.isEmpty) {
      return (succeeded: 0, failedNames: const <String>[]);
    }

    _bulkBusy = true;
    _bulkError = null;
    notifyListeners();

    var succeeded = 0;
    final failed = <String>[];
    try {
      for (final s in targets) {
        if (_uid != uid || !_isProvider) break;
        final ok = await confirmStillCurrent(s.id);
        if (ok) {
          succeeded++;
        } else {
          failed.add(s.name);
        }
      }
      if (_uid == uid && failed.isNotEmpty) {
        _bulkError =
            '${failed.length} sumber gagal dikonfirmasi: ${failed.join(', ')}.';
      }
      return (succeeded: succeeded, failedNames: failed);
    } finally {
      if (_uid == uid) {
        _bulkBusy = false;
        notifyListeners();
      }
    }
  }

  /// Menutup semua sumber yang dapat ditutup penyedia (`pending`, `rejected`,
  /// `published`). Sumber berstatus `suspended` tidak tersentuh.
  Future<int?> closeAllOwned(String reason) async {
    final uid = _uid;
    if (!_isProvider || uid == null) {
      _bulkError = 'Hanya penyedia aktif yang dapat menutup sumber.';
      notifyListeners();
      return null;
    }

    _bulkBusy = true;
    _bulkError = null;
    notifyListeners();

    try {
      return await _service.closeAllOwned(uid, reason);
    } on SourceBatchException catch (e) {
      if (_uid == uid) {
        _bulkError =
            '${e.message} ${e.done} sumber ditutup, ${e.remaining} sumber belum selesai.';
      }
      return null;
    } on SourceException catch (e) {
      if (_uid == uid) _bulkError = e.message;
      return null;
    } catch (e) {
      debugPrint('MySourcesProvider closeAllOwned error: $e');
      if (_uid == uid) {
        _bulkError = 'Gagal menutup semua sumber. Periksa koneksi lalu coba lagi.';
      }
      return null;
    } finally {
      if (_uid == uid) {
        _bulkBusy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _runFor(String id, Future<void> Function() action) async {
    final uid = _uid;
    if (!_isProvider || uid == null) {
      _errors[id] = 'Hanya penyedia aktif yang dapat mengelola sumber.';
      notifyListeners();
      return false;
    }
    if (_busyIds.contains(id)) return false;

    _busyIds.add(id);
    _errors.remove(id);
    notifyListeners();

    try {
      await action();
      return true;
    } on SourceBatchException catch (e) {
      if (_uid == uid) {
        _errors[id] = '${e.message} (${e.done} selesai, ${e.remaining} tersisa).';
      }
      return false;
    } on SourceException catch (e) {
      if (_uid == uid) _errors[id] = e.message;
      return false;
    } catch (e) {
      debugPrint('MySourcesProvider action error ($id): $e');
      if (_uid == uid) {
        _errors[id] = 'Gagal menyimpan perubahan. Periksa koneksi lalu coba lagi.';
      }
      return false;
    } finally {
      if (_uid == uid) {
        _busyIds.remove(id);
        notifyListeners();
      }
    }
  }
}
