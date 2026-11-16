import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/water_report.dart';
import '../models/water_source.dart';
import '../services/report_service.dart';
import '../services/source_service.dart';

class AdminProvider extends ChangeNotifier {
  final ReportService _service;
  AdminProvider(this._service);

  String? _ownerUid;
  StreamSubscription<List<WaterReport>>? _pendingSub;

  List<WaterReport> _pending = [];
  List<WaterReport> _history = [];
  ReportStatus _filter = ReportStatus.pending;
  bool _loading = false;
  bool _busy = false;
  String? _loadError;
  String? _reviewError;

  ReportStatus get filter => _filter;
  bool get loading => _loading;
  bool get busy => _busy;
  String? get loadError => _loadError;
  String? get reviewError => _reviewError;
  List<WaterReport> get items =>
      _filter == ReportStatus.pending ? _pending : _history;
  int get pendingCount => _pending.length;

  /// Tanpa notifyListeners (dipanggil dari ProxyProvider saat build).
  void syncUser(String? uid) {
    if (uid == _ownerUid) return;
    _ownerUid = uid;
    _pendingSub?.cancel();
    _pendingSub = null;
    _pending = [];
    _history = [];
    _filter = ReportStatus.pending;
    _loading = false;
    _busy = false;
    _loadError = null;
    _reviewError = null;
  }

  /// Mulai mendengarkan laporan pending (dipanggil saat panel admin dibuka).
  void start() {
    if (_pendingSub != null) return;
    _loading = true;
    _loadError = null;
    notifyListeners();
    _pendingSub = _service.watchPending().listen(
      (list) {
        _pending = list;
        if (_filter == ReportStatus.pending) _loading = false;
        _loadError = null;
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('AdminProvider stream error: $e');
        _loading = false;
        _loadError = 'Gagal memuat laporan. Periksa koneksi lalu coba lagi.';
        notifyListeners();
      },
    );
  }

  Future<void> reload() async {
    _pendingSub?.cancel();
    _pendingSub = null;
    start();
    if (_filter != ReportStatus.pending) await _loadHistory(_filter);
  }

  void setFilter(ReportStatus s) {
    _filter = s;
    notifyListeners();
    if (s != ReportStatus.pending) _loadHistory(s);
  }

  Future<void> _loadHistory(ReportStatus s) async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final list = await _service.fetchByStatus(s);
      if (_filter == s) _history = list;
    } on ReportException catch (e) {
      _loadError = e.message;
    } catch (e) {
      debugPrint('AdminProvider._loadHistory: $e');
      _loadError = 'Gagal memuat riwayat laporan.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clearReviewError() {
    if (_reviewError != null) {
      _reviewError = null;
      notifyListeners();
    }
  }

  /// Tinjau laporan. Jika disetujui, sumber air ikut diperbarui secara atomik
  /// di service. Mengembalikan true bila tersimpan.
  Future<bool> review(
    WaterReport report, {
    required bool approve,
    String note = '',
    Availability? newAvailability,
    bool suspendSource = false,
  }) async {
    if (!approve && note.trim().length < 5) {
      _reviewError = 'Alasan penolakan wajib diisi (min. 5 karakter).';
      notifyListeners();
      return false;
    }
    _busy = true;
    _reviewError = null;
    notifyListeners();
    var saved = false;
    try {
      await _service.review(
        id: report.id,
        approve: approve,
        adminNote: note.trim(),
        sourceUpdate: approve
            ? SourceUpdate(
                sourceId: report.sourceId,
                availability: newAvailability,
                markQualityConcern: report.type == ReportType.qualityConcern,
                suspend: suspendSource,
              )
            : null,
      );
      saved = true;
      // Perbarui daftar lokal; tidak ada fetch ulang yang bisa gagal (T2.1).
      _pending = _pending.where((r) => r.id != report.id).toList();
    } on ReportException catch (e) {
      _reviewError = e.message;
    } catch (e) {
      debugPrint('AdminProvider.review: $e');
      _reviewError = 'Gagal menyimpan hasil tinjauan. Coba lagi.';
    } finally {
      _busy = false;
      notifyListeners();
    }
    return saved;
  }

  @override
  void dispose() {
    _pendingSub?.cancel();
    super.dispose();
  }
}
