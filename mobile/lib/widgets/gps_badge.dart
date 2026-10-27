import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../util.dart';

/// A small pill showing how good the phone's GPS fix is: "GPS ±8 m", "Finding you…" or "No location".
class GpsBadge extends StatelessWidget {
  const GpsBadge({super.key, required this.position, required this.loading, this.error});

  final Position? position;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color color;
    final String label;
    if (error != null && position == null) {
      color = scheme.error;
      label = 'No location';
    } else if (position == null) {
      color = scheme.onSurfaceVariant;
      label = 'Finding you…';
    } else {
      color = gpsColor(gpsQuality(position!.accuracy));
      label = 'GPS ±${position!.accuracy.round()} m';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          loading
              ? SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2, color: color))
              : Icon(Icons.my_location, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// The GPS line shown before posting: good (green), usable (amber) or too weak to post (red).
class GpsStatusLine extends StatelessWidget {
  const GpsStatusLine({super.key, required this.position, required this.locating, required this.error, required this.onRefresh});

  final Position? position;
  final bool locating;
  final String? error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color color;
    final IconData icon;
    final String text;
    if (error != null) {
      color = scheme.error;
      icon = Icons.location_off_outlined;
      text = error!;
    } else if (position == null) {
      color = scheme.onSurfaceVariant;
      icon = Icons.my_location;
      text = locating ? 'Finding your position…' : 'Position not found yet.';
    } else {
      final acc = position!.accuracy.round();
      switch (gpsQuality(position!.accuracy)) {
        case GpsQuality.good:
          color = gpsColor(GpsQuality.good);
          icon = Icons.check_circle_outline;
          text = 'GPS ±$acc m. Good to post.';
        case GpsQuality.fair:
          color = gpsColor(GpsQuality.fair);
          icon = Icons.info_outline;
          text = 'GPS ±$acc m. You can post, but people may need to stand closer to see it.';
        case GpsQuality.poor:
          color = gpsColor(GpsQuality.poor);
          icon = Icons.warning_amber_outlined;
          text = 'GPS ±$acc m is too weak to post. Move to an open area and refresh.';
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          IconButton(
            tooltip: 'Refresh position',
            onPressed: locating ? null : onRefresh,
            icon: locating
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
