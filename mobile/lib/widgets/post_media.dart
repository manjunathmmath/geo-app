import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// The picture for an image post, or a labelled placeholder for audio and video
/// (playback for those is not built yet).
class PostMedia extends StatelessWidget {
  const PostMedia({super.key, required this.post, this.size});

  final Post post;

  /// Square thumbnail size; null means fill the width at 4:3.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(post.type == 'AUDIO' ? Icons.graphic_eq : Icons.videocam, size: size == null ? 40 : 24, color: scheme.onSurfaceVariant),
            if (size == null) ...[
              const SizedBox(height: 6),
              Text('${post.type == 'AUDIO' ? 'Audio' : 'Video'} post (playback coming soon)', style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );

    final Widget child = post.isImage
        ? Image.network(
            context.read<ApiClient>().absoluteUrl(post.mediaUrl),
            fit: BoxFit.cover,
            loadingBuilder: (c, w, progress) => progress == null ? w : ColoredBox(color: scheme.surfaceContainerHighest),
            errorBuilder: (c, e, s) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
            ),
          )
        : placeholder;

    if (size != null) {
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: size, height: size, child: child));
    }
    return AspectRatio(aspectRatio: 4 / 3, child: child);
  }
}
