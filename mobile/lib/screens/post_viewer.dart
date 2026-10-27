import 'package:flutter/material.dart';

import '../api/models.dart';
import '../util.dart';
import '../widgets/post_actions.dart' show postTypeIcon, reportPostFlow;
import '../widgets/post_media.dart';

/// Full-screen viewer opened from the grid: swipe up or down to move between the posts in the grid.
/// Each page owns its player, so leaving a page stops its audio or video.
class PostViewer extends StatefulWidget {
  const PostViewer({super.key, required this.posts, required this.initialIndex});

  final List<Post> posts;
  final int initialIndex;

  @override
  State<PostViewer> createState() => _PostViewerState();
}

class _PostViewerState extends State<PostViewer> {
  late final PageController _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.posts[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            scrollDirection: Axis.vertical,
            itemCount: widget.posts.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _Page(key: ValueKey(widget.posts[i].id), post: widget.posts[i]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  Text('${_index + 1} / ${widget.posts.length}', style: const TextStyle(color: Colors.white70)),
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    iconColor: Colors.white,
                    onSelected: (_) => reportPostFlow(context, post),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Report this post'))],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (post.distanceM != null) '${post.distanceM!.round()} m away',
      timeAgo(post.createdAt),
    ].join(' · ');
    final caption = post.isText ? null : post.caption;
    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 48), // keeps the content clear of the top bar
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Theme(
                    data: Theme.of(context).copyWith(brightness: Brightness.dark),
                    child: PostMedia(post: post),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (caption != null && caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(caption, style: const TextStyle(color: Colors.white, fontSize: 17)),
                  ),
                Row(
                  children: [
                    Icon(postTypeIcon(post), size: 15, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(meta, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const Spacer(),
                    const Icon(Icons.swap_vert, size: 16, color: Colors.white38),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
