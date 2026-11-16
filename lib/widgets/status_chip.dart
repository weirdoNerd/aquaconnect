import 'package:flutter/material.dart';
import '../models/water_report.dart';

class ReportStatusChip extends StatelessWidget {
  final ReportStatus status;
  const ReportStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final c = status.darkColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c),
      ),
      child: Text(status.label,
          style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
