import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

String formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// 0:07, 1:30 ...
String formatDuration(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// "just now", "5 min ago", "3 h ago", "2 d ago", or the date for anything older.
String timeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return formatDateTime(d);
}

/// How trustworthy a GPS fix is for a 20 m search. The server refuses posts worse than [gpsPostLimitMetres].
enum GpsQuality { good, fair, poor }

const double gpsGoodMetres = 30;
const double gpsPostLimitMetres = 100;

GpsQuality gpsQuality(double accuracyMetres) {
  if (accuracyMetres <= gpsGoodMetres) return GpsQuality.good;
  if (accuracyMetres <= gpsPostLimitMetres) return GpsQuality.fair;
  return GpsQuality.poor;
}

Color gpsColor(GpsQuality q) {
  switch (q) {
    case GpsQuality.good:
      return Colors.green.shade600;
    case GpsQuality.fair:
      return Colors.orange.shade700;
    case GpsQuality.poor:
      return Colors.red.shade600;
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'APPROVED':
      return Colors.green.shade700;
    case 'REJECTED':
      return Colors.red.shade700;
    default:
      return Colors.orange.shade800;
  }
}

String statusLabel(String status) {
  switch (status) {
    case 'APPROVED':
      return 'Published';
    case 'REJECTED':
      return 'Rejected';
    default:
      return 'In review';
  }
}

/// Only one audio or video clip plays at a time: starting one pauses the previous.
class MediaFocus {
  static VideoPlayerController? _current;

  static void claim(VideoPlayerController controller) {
    final previous = _current;
    if (previous != null && previous != controller) {
      try {
        previous.pause();
      } catch (_) {
        // That player was already disposed.
      }
    }
    _current = controller;
  }

  static void release(VideoPlayerController controller) {
    if (_current == controller) _current = null;
  }
}
