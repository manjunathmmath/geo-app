import 'package:flutter/material.dart';

import '../services/location_service.dart';
import '../util.dart';
import 'compose_screen.dart';

/// The sheet behind the "+" button: pick what to post. Returns the chosen kind, or null if dismissed.
Future<PostMode?> showPostChooser(BuildContext context) {
  return showModalBottomSheet<PostMode>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _Chooser(),
  );
}

class _Chooser extends StatelessWidget {
  const _Chooser();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fix = LocationService.last;
    final quality = fix == null ? null : gpsQuality(fix.accuracy);
    final color = quality == null ? scheme.onSurfaceVariant : gpsColor(quality);
    final String gps = fix == null
        ? 'Your position is checked on the next screen.'
        : switch (quality!) {
            GpsQuality.good => 'GPS ±${fix.accuracy.round()} m. Good to post.',
            GpsQuality.fair => 'GPS ±${fix.accuracy.round()} m. You can post, but people may need to stand closer.',
            GpsQuality.poor => 'GPS ±${fix.accuracy.round()} m is too weak to post. Move to an open area first.',
          };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Post at your spot', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.my_location, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(gps, style: TextStyle(fontSize: 13, color: color))),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.7,
              children: [
                for (final m in PostMode.values) _Tile(mode: m),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'A moderator checks your post before anyone nearby can see it.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.mode});

  final PostMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pop(context, mode),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(mode.icon, size: 30),
            const SizedBox(height: 6),
            Text(mode.label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
