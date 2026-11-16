import '../models/water_report.dart';
import 'source_service.dart';

class ReportException implements Exception {
  final String message;
  const ReportException(this.message);
}

abstract class ReportService {
  /// Laporan milik satu pengguna (realtime).
  Stream<List<WaterReport>> watchByReporter(String uid);

  /// Laporan menunggu verifikasi (khusus admin, realtime, dibatasi).
  Stream<List<WaterReport>> watchPending({int limit = 50});

  /// Riwayat laporan yang sudah ditinjau (khusus admin).
  Future<List<WaterReport>> fetchByStatus(ReportStatus status, {int limit = 50});

  Future<void> submit({
    required String sourceId,
    required String reporterId,
    required ReportType type,
    required String description,
  });

  /// Laporan + sumber air + pelepasan kunci diperbarui atomik.
  Future<void> review({
    required String id,
    required bool approve,
    required String adminNote,
    SourceUpdate? sourceUpdate,
  });
}
