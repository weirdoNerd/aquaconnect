import 'package:flutter/material.dart';
import '../models/water_source.dart';

class AvailabilityBadge extends StatelessWidget {
  final Availability availability;
  const AvailabilityBadge({super.key, required this.availability});

  @override
  Widget build(BuildContext context) {
    final c = availability.darkColor;
    return Semantics(
      label: 'Status: ${availability.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: availability.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(availability.icon, size: 14, color: c),
            const SizedBox(width: 4),
            Text(availability.label,
                style: TextStyle(
                    color: c, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
