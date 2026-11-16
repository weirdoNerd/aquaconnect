import 'package:flutter/material.dart';

enum ReportType {
  noWater,
  inaccessible,
  qualityConcern,
  backAvailable,
  noLongerOperating
}

enum ReportStatus { pending, approved, rejected }

extension ReportTypeX on ReportType {
  String get label => switch (this) {
        ReportType.noWater => 'Air habis',
        ReportType.inaccessible => 'Sumber tidak dapat diakses',
        ReportType.qualityConcern => 'Dugaan masalah kualitas air',
        ReportType.backAvailable => 'Air sudah tersedia kembali',
        ReportType.noLongerOperating => 'Sudah tidak beroperasi',
      };

  IconData get icon => switch (this) {
        ReportType.noWater => Icons.water_drop_outlined,
        ReportType.inaccessible => Icons.block,
        ReportType.qualityConcern => Icons.warning_amber_rounded,
        ReportType.backAvailable => Icons.check_circle_outline,
        ReportType.noLongerOperating => Icons.power_settings_new,
      };
}

extension ReportStatusX on ReportStatus {
  String get label => switch (this) {
        ReportStatus.pending => 'Menunggu verifikasi',
        ReportStatus.approved => 'Disetujui',
        ReportStatus.rejected => 'Ditolak',
      };

  Color get color => switch (this) {
        ReportStatus.pending => Colors.orange,
        ReportStatus.approved => Colors.green,
        ReportStatus.rejected => Colors.red,
      };

  Color get darkColor => switch (this) {
        ReportStatus.pending => Colors.orange.shade900,
        ReportStatus.approved => Colors.green.shade800,
        ReportStatus.rejected => Colors.red.shade800,
      };
}

/// Nama sumber air tidak disimpan di laporan (denormalisasi dihapus):
/// tampilkan lewat SourceProvider.byId(sourceId).
class WaterReport {
  final String id;
  final String sourceId;
  final String reporterId;
  final ReportType type;
  final String description;
  final ReportStatus status;
  final String adminNote;

  /// Null sesaat bila serverTimestamp belum dikonfirmasi server.
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  const WaterReport({
    required this.id,
    required this.sourceId,
    required this.reporterId,
    required this.type,
    required this.description,
    this.status = ReportStatus.pending,
    this.adminNote = '',
    this.createdAt,
    this.reviewedAt,
  });

  WaterReport copyWith({
    ReportStatus? status,
    String? adminNote,
    DateTime? reviewedAt,
  }) =>
      WaterReport(
        id: id,
        sourceId: sourceId,
        reporterId: reporterId,
        type: type,
        description: description,
        status: status ?? this.status,
        adminNote: adminNote ?? this.adminNote,
        createdAt: createdAt,
        reviewedAt: reviewedAt ?? this.reviewedAt,
      );
}
