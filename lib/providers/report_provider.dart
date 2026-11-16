import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/water_report.dart';
import '../services/report_service.dart';

enum SubmitOutcome {
  /// Server mengonfirmasi laporan tersimpan.
  sent,

  /// Tidak ada konfirmasi tepat waktu; Firestore mengirim otomatis saat online.
  queued,

  /// Gagal. Lihat [ReportProvider.submitError].
  failed,
}

class ReportProvider extends ChangeNotifier {
  final ReportService _service;
  ReportProvider(this._service);

  String? _ownerUid;
  StreamSubscription<List<WaterReport>>? _sub;

  List<WaterReport> _mine = [];
  bool _loading = false;
  bool _submitting = false;
  String? _loadError;
  String? _submitError;

  List<WaterReport> get mine => _mine;
  bool get loading => _loading;
  bool get submitting => _submitting;
  String? get loadError => _loadError;
  String? get submitError => _submitError;

  /// Dipanggil dari ProxyProvider (saat build), jadi TIDAK memanggil
  /// notifyListeners. Mengosongkan data saat pemilik berganti (T1.2).
  void syncUser(String? uid) {
    if (uid == _ownerUid) return;
    _ownerUid = uid;
    _sub?.cancel();
    _sub = null;
    _mine = [];
    _loadError = null;
    _submitError = null;
    _loading = false;
    _submitting = false;
    if (uid != null) _subscribe(uid);
  }

  void _subscribe(String uid) {
    _loading = true;
    _sub = _service.watchByReporter(uid).listen(
      (list) {
        _mine = list;
        _loading = false;
        _loadError = null;
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('ReportProvider stream error: $e');
        _loading = false;
        _loadError = 'Gagal memuat laporan. Periksa koneksi lalu coba lagi.';
        notifyListeners();
      },
    );
  }

  void retry() {
    final uid = _ownerUid;
    if (uid == null) return;
    _sub?.cancel();
    _loadError = null;
    _subscribe(uid);
    notifyListeners();
  }

  void clearSubmitError() {
    if (_submitError != null) {
      _submitError = null;
      notifyListeners();
    }
  }

  Future<SubmitOutcome> submit({
    required String sourceId,
    required String reporterId,
    required ReportType type,
    required String description,
  }) async {
    _submitting = true;
    _submitError = null;
    notifyListeners();
    var outcome = SubmitOutcome.failed;
    try {
      await _service
          .submit(
            sourceId: sourceId,
            reporterId: reporterId,
            type: type,
            description: description,
          )
          .timeout(const Duration(seconds: 15));
      outcome = SubmitOutcome.sent;
      // Daftar "Laporan Saya" diperbarui oleh stream; tidak ada fetch ulang
      // yang bisa membuat aksi yang SUDAH berhasil tampak gagal (T2.1).
    } on TimeoutException {
      outcome = SubmitOutcome.queued;
    } on ReportException catch (e) {
      _submitError = e.message;
    } catch (e) {
      debugPrint('ReportProvider.submit: $e');
      _submitError = 'Gagal mengirim laporan. Periksa koneksi lalu coba lagi.';
    } finally {
      _submitting = false;
      notifyListeners();
    }
    return outcome;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
