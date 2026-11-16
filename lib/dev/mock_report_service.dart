import 'dart:async';
import '../models/water_report.dart';
import '../services/report_service.dart';
import '../services/source_service.dart';

/// Penyimpanan TIRUAN di memori. Jangan dipakai di rilis.
class MockReportService implements ReportService {
  final SourceService _sources;
  MockReportService(this._sources);

  final _ctrl = StreamController<void>.broadcast();

  final List<WaterReport> _store = [
    WaterReport(
      id: 'seed-1',
      sourceId: 'sim-2',
      reporterId: 'mock-user',
      type: ReportType.noWater,
      description: 'Pagi ini air sudah habis sebelum jam 10.',
      status: ReportStatus.approved,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      reviewedAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    WaterReport(
      id: 'seed-2',
      sourceId: 'sim-4',
      reporterId: 'mock-user',
      type: ReportType.inaccessible,
      description: 'Gerbang terkunci.',
      status: ReportStatus.rejected,
      adminNote: 'Gerbang hanya terkunci malam hari, siang tetap dibuka.',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      reviewedAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    WaterReport(
      id: 'seed-3',
      sourceId: 'sim-1',
      reporterId: 'mock-other-1',
      type: ReportType.noWater,
      description: 'Timba sudah kering sejak kemarin sore.',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
    ),
    WaterReport(
      id: 'seed-4',
      sourceId: 'sim-3',
      reporterId: 'mock-other-2',
      type: ReportType.qualityConcern,
      description: 'Air terlihat keruh dan berbau tidak biasa.',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    WaterReport(
      id: 'seed-5',
      sourceId: 'sim-5',
      reporterId: 'mock-other-3',
      type: ReportType.inaccessible,
      description: 'Jalan menuju pos tergenang dan tidak bisa dilewati.',
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  ];

  DateTime _t(WaterReport r) => r.createdAt ?? DateTime.now();

  List<WaterReport> _mineOf(String uid) =>
      _store.where((r) => r.reporterId == uid).toList()
        ..sort((a, b) => _t(b).compareTo(_t(a)));

  List<WaterReport> _pending(int limit) => (_store
          .where((r) => r.status == ReportStatus.pending)
          .toList()
        ..sort((a, b) => _t(b).compareTo(_t(a))))
      .take(limit)
      .toList();

  @override
  Stream<List<WaterReport>> watchByReporter(String uid) async* {
    yield _mineOf(uid);
    yield* _ctrl.stream.map((_) => _mineOf(uid));
  }

  @override
  Stream<List<WaterReport>> watchPending({int limit = 50}) async* {
    yield _pending(limit);
    yield* _ctrl.stream.map((_) => _pending(limit));
  }

  @override
  Future<List<WaterReport>> fetchByStatus(ReportStatus status,
      {int limit = 50}) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final list = _store.where((r) => r.status == status).toList()
      ..sort((a, b) =>
          (b.reviewedAt ?? _t(b)).compareTo(a.reviewedAt ?? _t(a)));
    return list.take(limit).toList();
  }

  @override
  Future<void> submit({
    required String sourceId,
    required String reporterId,
    required ReportType type,
    required String description,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final duplicate = _store.any((r) =>
        r.reporterId == reporterId &&
        r.sourceId == sourceId &&
        r.type == type &&
        r.status == ReportStatus.pending);
    if (duplicate) {
      throw const ReportException(
          'Kamu sudah mengirim laporan serupa untuk sumber ini dan masih menunggu verifikasi.');
    }
    _store.add(WaterReport(
      id: 'rep-${DateTime.now().microsecondsSinceEpoch}',
      sourceId: sourceId,
      reporterId: reporterId,
      type: type,
      description: description.trim(),
      createdAt: DateTime.now(),
    ));
    _ctrl.add(null);
  }

  @override
  Future<void> review({
    required String id,
    required bool approve,
    required String adminNote,
    SourceUpdate? sourceUpdate,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final i = _store.indexWhere((r) => r.id == id);
    if (i < 0) throw const ReportException('Laporan tidak ditemukan.');
    if (_store[i].status != ReportStatus.pending) {
      throw const ReportException('Laporan ini sudah ditinjau.');
    }
    if (!approve && adminNote.trim().length < 5) {
      throw const ReportException('Alasan penolakan wajib diisi (min. 5 karakter).');
    }
    _store[i] = _store[i].copyWith(
      status: approve ? ReportStatus.approved : ReportStatus.rejected,
      adminNote: adminNote,
      reviewedAt: DateTime.now(),
    );
    if (approve && sourceUpdate != null) {
      await _sources.applyUpdate(sourceUpdate);
    }
    _ctrl.add(null);
  }
}
