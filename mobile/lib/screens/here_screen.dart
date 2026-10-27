import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../services/location_service.dart';
import '../widgets/gps_badge.dart';
import '../widgets/post_tile.dart';
import 'post_viewer.dart';

/// "Here": what has been posted within the search radius of where the phone is now, newest first.
/// Works without signing in.
class HereScreen extends StatefulWidget {
  const HereScreen({super.key, required this.active, required this.onPost});

  /// True while this tab is on screen; position updates and checks for new posts only run then.
  final bool active;

  /// Opens the "new post" chooser (used by the empty state).
  final VoidCallback onPost;

  @override
  State<HereScreen> createState() => _HereScreenState();
}

class _HereScreenState extends State<HereScreen> {
  static const _reloadAfterMetres = 10;
  static const _checkEvery = Duration(seconds: 30);

  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('IMAGE', 'Photo'),
    ('VIDEO', 'Video'),
    ('AUDIO', 'Audio'),
    ('TEXT', 'Text'),
  ];

  final _scroll = ScrollController();
  Position? _pos;
  Position? _loadedAt;
  List<Post>? _posts;
  List<Post>? _incoming; // newer results held back until the user taps the "new posts" banner
  String? _error;
  bool _loading = false;
  bool _explained = false;
  String? _filter;
  StreamSubscription<Position>? _sub;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(HereScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _activate();
    } else if (!widget.active && oldWidget.active) {
      _deactivate();
    }
  }

  @override
  void dispose() {
    _deactivate();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    await _refresh();
    if (!mounted || !widget.active || _error != null) return;
    _sub ??= LocationService.updates().listen((p) {
      _pos = p;
      final last = _loadedAt;
      if (last == null || LocationService.metresBetween(last, p) > _reloadAfterMetres) {
        _refresh(position: p);
      } else if (mounted) {
        setState(() {}); // the GPS badge follows the latest accuracy
      }
    }, onError: (_) {});
    _poll ??= Timer.periodic(_checkEvery, (_) => _refresh(quiet: true));
  }

  void _deactivate() {
    _sub?.cancel();
    _sub = null;
    _poll?.cancel();
    _poll = null;
  }

  /// Explains why the location is needed before Android asks for it the first time.
  Future<bool> _explainLocationIfNeeded() async {
    if (_explained) return true;
    _explained = true;
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.denied || !mounted) return true;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.my_location),
        title: const Text('Allow your location'),
        content: const Text(
          'GeoApp uses where you are to show the posts around you, and to tag your own posts with the spot where you made them. '
          'Your position is not shared with other people.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) setState(() => _error = 'GeoApp needs your location to find the posts around you.');
      _explained = false; // ask again next time
      return false;
    }
    return true;
  }

  /// [quiet] = a background check for new posts at the current spot: new results wait behind a banner instead of
  /// moving the list while the person is reading it.
  Future<void> _refresh({Position? position, bool quiet = false}) async {
    if (_loading) return;
    if (quiet && _pos == null) return;
    final api = context.read<ApiClient>();
    if (!quiet && position == null && !await _explainLocationIfNeeded()) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      if (!quiet) _error = null;
    });
    try {
      final p = position ?? (quiet ? _pos! : await LocationService.current());
      final posts = await api.nearby(p.latitude, p.longitude);
      if (!mounted) return;
      setState(() {
        _pos = p;
        final shown = _posts;
        if (quiet && shown != null) {
          final known = shown.map((e) => e.id).toSet();
          if (posts.any((e) => !known.contains(e.id))) {
            _incoming = posts;
          } else {
            _posts = posts; // only removals or no change: update without a banner
            _incoming = null;
          }
        } else {
          _loadedAt = p;
          _posts = posts;
          _incoming = null;
        }
      });
    } on LocationException catch (e) {
      if (mounted && !quiet) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted && !quiet) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showIncoming() {
    setState(() {
      _posts = _incoming;
      _incoming = null;
    });
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text('Here', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('within ${Config.radiusMeters} m', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const Spacer(),
                GpsBadge(position: _pos, loading: _loading, error: _error),
              ],
            ),
          ),
          if (posts != null && posts.isNotEmpty) _filterChips(posts),
          if (_incoming != null) _newPostsBanner(),
          Expanded(child: _body(posts)),
        ],
      ),
    );
  }

  Widget _filterChips(List<Post> posts) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          for (final (type, label) in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$label ${type == null ? posts.length : posts.where((p) => p.type == type).length}'),
                selected: _filter == type,
                onSelected: (_) => setState(() => _filter = type),
              ),
            ),
        ],
      ),
    );
  }

  Widget _newPostsBanner() {
    final known = (_posts ?? const <Post>[]).map((e) => e.id).toSet();
    final fresh = _incoming!.where((e) => !known.contains(e.id)).length;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: _showIncoming,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_upward, size: 16, color: scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Text(
                  fresh == 1 ? '1 new post' : '$fresh new posts',
                  style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(List<Post>? posts) {
    if (_error != null && posts == null) {
      return _Message(
        icon: Icons.location_off_outlined,
        title: 'Can\'t look around yet',
        text: _error!,
        action: 'Try again',
        onAction: _refresh,
      );
    }
    if (posts == null) return const Center(child: CircularProgressIndicator());

    if (posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 420,
              child: _Message(
                icon: Icons.location_searching,
                title: 'Nothing here yet',
                text: 'Be the first to post at this spot.\nNew posts appear after a moderator approves them.',
                action: 'Post here',
                onAction: widget.onPost,
              ),
            ),
          ],
        ),
      );
    }

    final visible = _filter == null ? posts : posts.where((p) => p.type == _filter).toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: visible.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No posts of this kind right here.')),
              ],
            )
          : GridView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96), // room for the + button
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) => PostTile(
                key: ValueKey(visible[i].id),
                post: visible[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PostViewer(posts: visible, initialIndex: i)),
                ),
              ),
            ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text, required this.action, required this.onAction});

  final IconData icon;
  final String title;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
