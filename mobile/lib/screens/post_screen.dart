import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/auth_controller.dart';
import '../services/location_service.dart';

/// Take or choose a photo and publish it at the phone's current position.
class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.active});

  /// True while this tab is on screen; the position is read when it first opens.
  final bool active;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  /// The server rejects posts with a worse GPS accuracy than this (app.geo.max-accuracy-m).
  static const _maxAccuracyMetres = 100;

  final _caption = TextEditingController();
  final _picker = ImagePicker();

  XFile? _image;
  Position? _pos;
  String? _locError;
  bool _locating = false;
  bool _busy = false;
  String? _error;
  Post? _done;
  bool _located = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _locate();
  }

  @override
  void didUpdateWidget(PostScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_located) _locate();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    _located = true;
    setState(() {
      _locating = true;
      _locError = null;
    });
    try {
      final p = await LocationService.current();
      if (mounted) setState(() => _pos = p);
    } on LocationException catch (e) {
      if (mounted) setState(() => _locError = e.message);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 2048, imageQuality: 85);
      if (file != null && mounted) {
        setState(() {
          _image = file;
          _error = null;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = 'Could not open the ${source == ImageSource.camera ? 'camera' : 'photo library'}: ${e.message ?? e.code}');
    }
  }

  Future<void> _publish() async {
    final image = _image;
    final pos = _pos;
    if (image == null || pos == null) return;
    final api = context.read<ApiClient>();
    final auth = context.read<AuthController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final post = await api.createPost(
        filePath: image.path,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        caption: _caption.text,
      );
      if (!mounted) return;
      setState(() {
        _done = post;
        _image = null;
        _caption.clear();
      });
    } on ApiException catch (e) {
      if (e.status == 401) await auth.logout();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    if (done != null) return _Done(post: done, onAnother: () => setState(() => _done = null));

    final scheme = Theme.of(context).colorScheme;
    final pos = _pos;
    final tooWeak = pos != null && pos.accuracy > _maxAccuracyMetres;
    final canPublish = _image != null && pos != null && !tooWeak && !_busy;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_image == null)
          Container(
            height: 200,
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: const Text('Add a photo'),
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(aspectRatio: 4 / 3, child: Image.file(File(_image!.path), fit: BoxFit.cover)),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _caption,
          maxLength: 500,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Caption (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        _LocationCard(pos: pos, locating: _locating, error: _locError, tooWeak: tooWeak, maxAccuracy: _maxAccuracyMetres, onRefresh: _locate),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: canPublish ? _publish : null,
          child: _busy
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Post here'),
        ),
        const SizedBox(height: 8),
        Text(
          'Your post is tied to where you are standing now. A moderator checks it before anyone nearby can see it.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.pos,
    required this.locating,
    required this.error,
    required this.tooWeak,
    required this.maxAccuracy,
    required this.onRefresh,
  });

  final Position? pos;
  final bool locating;
  final String? error;
  final bool tooWeak;
  final int maxAccuracy;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String text;
    if (error != null) {
      text = error!;
    } else if (locating && pos == null) {
      text = 'Finding your position…';
    } else if (pos == null) {
      text = 'Position not found yet.';
    } else {
      text = 'Your position: ${pos!.latitude.toStringAsFixed(5)}, ${pos!.longitude.toStringAsFixed(5)}\n'
          'GPS accuracy ±${pos!.accuracy.round()} m'
          '${tooWeak ? ' (too weak: need $maxAccuracy m or better. Move to an open area and refresh.)' : ''}';
    }
    return Card(
      color: (error != null || tooWeak) ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.my_location),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
            IconButton(
              tooltip: 'Refresh position',
              onPressed: locating ? null : onRefresh,
              icon: locating
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.post, required this.onAnother});

  final Post post;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final published = post.status == 'APPROVED';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(published ? Icons.check_circle_outline : Icons.hourglass_top, size: 56, color: Colors.green.shade700),
            const SizedBox(height: 12),
            Text(
              published
                  ? 'Published. People near this spot can see it now.'
                  : 'Sent for review. You will see its status under "My posts".',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAnother, child: const Text('Post another')),
          ],
        ),
      ),
    );
  }
}
