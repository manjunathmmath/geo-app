import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/auth_controller.dart';
import '../util.dart';
import '../widgets/post_actions.dart';
import '../widgets/post_media.dart';
import '../widgets/sign_in_prompt.dart';

/// "Me": who is signed in, and the person's own posts (newest first) with their review status.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key, required this.active});

  /// True while this tab is on screen; the list reloads each time it opens.
  final bool active;

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  List<Post>? _posts;
  String? _error;
  bool _loading = false;
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(MeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    final api = context.read<ApiClient>();
    final auth = context.read<AuthController>();
    if (!auth.signedIn) return;
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
    final auth = context.watch<AuthController>();
    if (!auth.signedIn) {
      _wasSignedIn = false;
      _posts = null;
      return const SafeArea(child: SignInPrompt(message: 'Sign in to post, and to see whether your posts were approved.'));
    }
    if (!_wasSignedIn) {
      // Just signed in: load the list once the frame is done.
      _wasSignedIn = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _load();
      });
    }
    final scheme = Theme.of(context).colorScheme;
    final posts = _posts;
    final me = auth.user!;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(me.email.isEmpty ? '?' : me.email[0].toUpperCase(), style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me.email, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                        Text(me.isAdmin ? 'Administrator' : 'Creator', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                      ],
                    ),
                  ),
                  TextButton.icon(onPressed: auth.logout, icon: const Icon(Icons.logout, size: 18), label: const Text('Sign out')),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('My posts', style: Theme.of(context).textTheme.titleLarge),
            ),
            if (posts == null && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (_error != null && posts == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [Text(_error!), const SizedBox(height: 12), FilledButton(onPressed: _load, child: const Text('Try again'))]),
              ),
            if (posts != null && posts.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(32, 32, 32, 0),
                child: Text('You have not posted anything yet. Tap + to post at your spot.', textAlign: TextAlign.center),
              ),
            if (posts != null)
              for (final p in posts) ...[
                _Tile(post: p),
                const Divider(height: 1),
              ],
          ],
        ),
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
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: PostMedia(post: post, size: 56),
      title: Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(postTypeIcon(post), size: 14, color: muted),
              const SizedBox(width: 4),
              Text(timeAgo(post.createdAt)),
            ],
          ),
          if (post.rejectReason != null) Text('Reason: ${post.rejectReason}', style: TextStyle(color: color)),
        ],
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
