import 'package:flutter/material.dart';

import '../api/models.dart';
import 'post_actions.dart' show postTypeIcon;
import 'post_media.dart';

/// One square in the "Here" grid: the preview of a photo or video, or the first words of a text post,
/// with a small type badge. Tapping it is handled by the caller.
class PostTile extends StatelessWidget {
  const PostTile({super.key, required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (post.isText)
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  post.text ?? '',
                  maxLines: 6,
                  overflow: TextOverflow.fade,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.3),
                ),
              )
            else
              LayoutBuilder(builder: (_, box) => PostMedia(post: post, size: box.maxWidth, flat: true)),
            Positioned(
              left: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(postTypeIcon(post), size: 13, color: Colors.white),
                      if (post.distanceM != null) ...[
                        const SizedBox(width: 4),
                        Text('${post.distanceM!.round()} m', style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (post.isVideo)
              const Center(child: Icon(Icons.play_circle_fill, size: 36, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
