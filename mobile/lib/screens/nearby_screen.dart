import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../services/location_service.dart';
import '../util.dart';
import '../widgets/post_media.dart';

/// Posts within the search radius of where the phone is now. Works without signing in.
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key, required this.active});

  /// True while this tab is on screen; position updates only run then.
  final bool active;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  static const _reloadAfterMetres = 10;
  static const _weakAccuracyMetres = 30;

  Position? _pos;
  Position? _loadedAt;
  List<Post>? _posts;
  String? _error;
  bool _loading = false;
  StreamSubscription<Position>? _sub;

  @override
  void initState() {
    super.initState();
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(NearbyScreen oldWidget) {
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
    super.dispose();
  }

  Future<void> _activate() async {
    await _refresh();
    if (!mounted || !widget.active || _error != null || _sub != null) return;
    _sub = LocationService.updates().listen((p) {
      _pos = p;
      final last = _loadedAt;
      if (last == null || LocationService.metresBetween(last, p) > _reloadAfterMetres) {
        _refresh(position: p);
      }
    }, onError: (_) {});
  }

  void _deactivate() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _refresh({Position? position}) async {
    if (_loading) return;
    final api = context.read<ApiClient>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = position ?? await LocationService.current();
      final posts = await api.nearby(p.latitude, p.longitude);
      if (!mounted) return;
      setState(() {
        _pos = p;
        _loadedAt = p;
        _posts = posts;
      });
    } on LocationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    final Widget body;
    if (_error != null && posts == null) {
      body = _Message(text: _error!, action: 'Try again', onAction: _refresh);
    } else if (posts == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: posts.isEmpty
            ? ListView(children: const [
                SizedBox(height: 80),
                Icon(Icons.location_searching, size: 48),
                SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Nothing posted within ${Config.radiusMeters} m of you yet.\nPull down to refresh, or walk somewhere new.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: posts.length,
                itemBuilder: (context, i) => _PostCard(post: posts[i]),
              ),
      );
    }
    return Column(
      children: [
        _Banner(pos: _pos, loading: _loading, error: posts != null ? _error : null, weakAt: _weakAccuracyMetres),
        Expanded(child: body),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.pos, required this.loading, required this.error, required this.weakAt});

  final Position? pos;
  final bool loading;
  final String? error;
  final int weakAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weak = pos != null && pos!.accuracy > weakAt;
    final text = error ??
        (pos == null
            ? 'Finding your position…'
            : 'Posts within ${Config.radiusMeters} m · GPS ±${pos!.accuracy.round()} m'
                '${weak ? '\nWeak GPS signal: you may miss posts nearby. Try an open area.' : ''}');
    return Container(
      width: double.infinity,
      color: (error != null || weak) ? scheme.errorContainer : scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          if (loading) const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostMedia(post: post),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (post.caption != null) Text(post.caption!, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${post.distanceM != null ? '${post.distanceM!.round()} m away · ' : ''}${formatDateTime(post.createdAt)}',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.action, required this.onAction});

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
