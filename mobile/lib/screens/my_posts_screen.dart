import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/auth_controller.dart';
import '../util.dart';
import '../widgets/post_media.dart';

/// The signed-in user's own posts with their review status and any rejection reason.
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key, required this.active});

  /// True while this tab is on screen; the list reloads each time it opens.
  final bool active;

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  List<Post>? _posts;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(MyPostsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    final api = context.read<ApiClient>();
    final auth = context.read<AuthController>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await api.mine();
      if (mounted) setState(() => _posts = posts);
    } on ApiException catch (e) {
      if (e.status == 401) await auth.logout();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    if (posts == null) {
      return Center(
        child: _error != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Try again')),
              ])
            : const CircularProgressIndicator(),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: posts.isEmpty
          ? ListView(children: const [
              SizedBox(height: 80),
              Center(child: Text('You have not posted anything yet.')),
            ])
          : ListView.separated(
              itemCount: posts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _Tile(post: posts[i]),
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(post.status);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: PostMedia(post: post, size: 56),
      title: Text(post.caption ?? '(no caption)', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${formatDateTime(post.createdAt)}${post.rejectReason != null ? '\nReason: ${post.rejectReason}' : ''}',
      ),
      isThreeLine: post.rejectReason != null,
      trailing: Chip(
        label: Text(statusLabel(post.status), style: TextStyle(color: color, fontSize: 12)),
        side: BorderSide(color: color),
        backgroundColor: color.withValues(alpha: 0.08),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
