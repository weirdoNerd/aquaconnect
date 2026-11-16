import 'package:flutter/material.dart';
import '../models/water_source.dart';
import 'availability_badge.dart';

class SourceCard extends StatelessWidget {
  final WaterSource source;
  final VoidCallback onTap;
  final String? distance;
  const SourceCard({
    super.key,
    required this.source,
    required this.onTap,
    this.distance,
  });

  @override
  Widget build(BuildContext context) {
    final stale = source.staleLabel;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        isThreeLine: true,
        leading: CircleAvatar(child: Icon(source.type.icon)),
        title: Row(
          children: [
            Expanded(child: Text(source.name)),
            if (source.qualityFlag)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(
                  message: 'Dugaan masalah kualitas',
                  child: Icon(Icons.warning_amber_rounded,
                      size: 20, color: Colors.red.shade800),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${source.type.label} • ${source.address}'),
            if (distance != null) Text('$distance dari lokasimu'),
            if (stale != null)
              Text(stale,
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
          ],
        ),
        trailing: AvailabilityBadge(availability: source.availability),
      ),
    );
  }
}
