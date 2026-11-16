import 'package:flutter/material.dart';
import '../models/water_source.dart';

class AvailabilityBadge extends StatelessWidget {
  final Availability availability;
  final bool stale;
  const AvailabilityBadge({
    super.key,
    required this.availability,
    this.stale = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = stale ? Colors.grey.shade700 : availability.darkColor;
    final bg = stale
        ? Colors.grey.withValues(alpha: 0.14)
        : availability.color.withValues(alpha: 0.12);
    final icon = stale ? Icons.help_outline : availability.icon;
    final label = stale ? 'Tidak pasti' : availability.label;

    return Semantics(
      label: stale
          ? 'Status: Tidak pasti (${availability.label})'
          : 'Status: ${availability.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: c, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
