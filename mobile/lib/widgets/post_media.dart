import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'audio_post_player.dart';
import 'video_post_player.dart';

/// The content of a post: the photo, a playable video or audio clip, or the words of a text post.
/// With [size] set it is a small square thumbnail for lists instead.
class PostMedia extends StatelessWidget {
  const PostMedia({super.key, required this.post, this.size, this.flat = false});

  final Post post;

  /// Square thumbnail size; null means the full-width content.
  final double? size;

  /// With [size]: no rounded corners (the caller clips, e.g. a grid tile).
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return size != null ? _thumbnail(context, scheme) : _full(context, scheme);
  }

  Widget _thumbnail(BuildContext context, ColorScheme scheme) {
    final s = size!;
    Widget child;
    // Photos and videos show their small preview; a photo without one falls back to the full file.
    final preview = post.thumbUrl ?? (post.isImage ? post.mediaUrl : null);
    if (preview != null) {
      child = Image.network(
        context.read<ApiClient>().absoluteUrl(preview),
        fit: BoxFit.cover,
        loadingBuilder: (c, w, progress) => progress == null ? w : ColoredBox(color: scheme.surfaceContainerHighest),
        errorBuilder: (c, e, st) => _icon(scheme, Icons.broken_image_outlined),
      );
    } else {
      child = _icon(
        scheme,
        post.isAudio
            ? Icons.graphic_eq
            : post.isVideo
                ? Icons.videocam
                : Icons.notes,
      );
    }
    final box = SizedBox(width: s, height: s, child: child);
    return flat ? box : ClipRRect(borderRadius: BorderRadius.circular(8), child: box);
  }

  Widget _icon(ColorScheme scheme, IconData icon) => ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(child: Icon(icon, color: scheme.onSurfaceVariant)),
      );

  Widget _full(BuildContext context, ColorScheme scheme) {
    final api = context.read<ApiClient>();
    final url = post.mediaUrl == null ? null : api.absoluteUrl(post.mediaUrl!);
    if (post.isText) {
      return Container(
        width: double.infinity,
        color: scheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(16),
        child: Text(post.text ?? '', style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4)),
      );
    }
    if (url == null) return const SizedBox.shrink();
    if (post.isVideo) return VideoPostPlayer(url: url);
    if (post.isAudio) return AudioPostPlayer(url: url);
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (c, w, progress) => progress == null ? w : ColoredBox(color: scheme.surfaceContainerHighest),
        errorBuilder: (c, e, st) => _icon(scheme, Icons.broken_image_outlined),
      ),
    );
  }
}
