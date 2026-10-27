import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../auth/auth_controller.dart';
import '../services/location_service.dart';
import '../util.dart';
import '../widgets/audio_post_player.dart';
import '../widgets/gps_badge.dart';
import '../widgets/video_post_player.dart';

enum PostMode { photo, video, audio, text }

extension PostModeInfo on PostMode {
  String get label => switch (this) {
        PostMode.photo => 'Photo',
        PostMode.video => 'Video',
        PostMode.audio => 'Audio',
        PostMode.text => 'Text',
      };

  IconData get icon => switch (this) {
        PostMode.photo => Icons.photo_camera_outlined,
        PostMode.video => Icons.videocam_outlined,
        PostMode.audio => Icons.mic_none,
        PostMode.text => Icons.notes,
      };
}

/// Makes one post at the phone's current position. Pops with the created [Post] when it is sent.
/// Photo and video open the camera straight away; text opens the keyboard.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key, required this.mode});

  final PostMode mode;

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  static const _maxBytes = 50 * 1024 * 1024; // the server's file limit
  static const _maxVideoSeconds = 30;
  static const _maxAudioSeconds = 60;
  static const _maxText = 1000;

  final _caption = TextEditingController();
  final _text = TextEditingController();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();

  XFile? _image;
  XFile? _video;
  String? _audioPath;
  bool _recording = false;
  int _recSeconds = 0;
  Timer? _recTimer;

  Position? _pos = LocationService.last;
  String? _locError;
  bool _locating = false;
  bool _busy = false;
  String? _error;

  PostMode get _mode => widget.mode;

  @override
  void initState() {
    super.initState();
    _locate();
    // Go straight to the camera: that is why the person tapped Photo or Video.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mode == PostMode.photo) _pickPhoto(ImageSource.camera);
      if (_mode == PostMode.video) _pickVideo(ImageSource.camera);
    });
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    _recorder.dispose();
    _caption.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
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

  // ---- choosing content ----

  Future<void> _pickPhoto(ImageSource source) async {
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

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final file = await _picker.pickVideo(source: source, maxDuration: const Duration(seconds: _maxVideoSeconds));
      if (file == null || !mounted) return;
      if (await file.length() > _maxBytes) {
        if (mounted) setState(() => _error = 'That video is larger than 50 MB. Record a shorter clip (up to $_maxVideoSeconds seconds).');
        return;
      }
      if (mounted) {
        setState(() {
          _video = file;
          _error = null;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = 'Could not open the ${source == ImageSource.camera ? 'camera' : 'video library'}: ${e.message ?? e.code}');
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) setState(() => _error = 'Microphone permission is needed to record audio. Allow it in the phone settings.');
        return;
      }
      final path = '${Directory.systemTemp.path}${Platform.pathSeparator}geoapp_${DateTime.now().millisecondsSinceEpoch}.wav';
      // WAV is large per minute but plays everywhere and needs no extra conversion on the server.
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 22050, numChannels: 1), path: path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recSeconds = 0;
        _audioPath = null;
        _error = null;
      });
      _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _recSeconds++);
        if (_recSeconds >= _maxAudioSeconds) _stopRecording();
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not start recording.');
    }
  }

  Future<void> _stopRecording() async {
    _recTimer?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      // Fall through: nothing was recorded.
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _audioPath = path;
      if (path == null) _error = 'The recording failed. Try again.';
    });
  }

  void _discardAudio() {
    final p = _audioPath;
    setState(() => _audioPath = null);
    if (p != null) {
      File(p).delete().catchError((_) => File(p));
    }
  }

  bool get _hasContent {
    switch (_mode) {
      case PostMode.photo:
        return _image != null;
      case PostMode.video:
        return _video != null;
      case PostMode.audio:
        return _audioPath != null && !_recording;
      case PostMode.text:
        return _text.text.trim().isNotEmpty;
    }
  }

  // ---- publishing ----

  Future<void> _publish() async {
    final pos = _pos;
    if (pos == null || !_hasContent) return;
    final api = context.read<ApiClient>();
    final auth = context.read<AuthController>();
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final isText = _mode == PostMode.text;
      final String? path = switch (_mode) {
        PostMode.photo => _image?.path,
        PostMode.video => _video?.path,
        PostMode.audio => _audioPath,
        PostMode.text => null,
      };
      final post = await api.createPost(
        filePath: path,
        text: isText ? _text.text : null,
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        caption: isText ? null : _caption.text,
      );
      navigator.pop(post);
    } on ApiException catch (e) {
      if (e.status == 401) {
        await auth.logout();
        navigator.pop();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- screen ----

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pos = _pos;
    final tooWeak = pos != null && pos.accuracy > gpsPostLimitMetres;
    final canPublish = _hasContent && pos != null && !tooWeak && !_busy;

    return Scaffold(
      appBar: AppBar(title: Text('New ${_mode.label.toLowerCase()} post')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            GpsStatusLine(position: pos, locating: _locating, error: _locError, onRefresh: _locate),
            const SizedBox(height: 16),
            _contentSection(scheme),
            if (_mode != PostMode.text) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _caption,
                maxLength: 500,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Caption (optional)', border: OutlineInputBorder()),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
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
        ),
      ),
    );
  }

  Widget _contentSection(ColorScheme scheme) {
    switch (_mode) {
      case PostMode.photo:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_image == null)
              _placeholder(scheme, Icons.photo_camera_outlined, 'Take or choose a photo')
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(aspectRatio: 4 / 3, child: Image.file(File(_image!.path), fit: BoxFit.cover)),
              ),
            const SizedBox(height: 12),
            _twoButtons(
              Icons.photo_camera_outlined, _image == null ? 'Camera' : 'Retake', () => _pickPhoto(ImageSource.camera),
              Icons.photo_library_outlined, 'Gallery', () => _pickPhoto(ImageSource.gallery),
            ),
          ],
        );
      case PostMode.video:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_video == null)
              _placeholder(scheme, Icons.videocam_outlined, 'Record or choose a video\nup to $_maxVideoSeconds seconds, 50 MB')
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: VideoPostPlayer(key: ValueKey(_video!.path), file: File(_video!.path)),
              ),
            const SizedBox(height: 12),
            _twoButtons(
              Icons.videocam_outlined, _video == null ? 'Record' : 'Record again', () => _pickVideo(ImageSource.camera),
              Icons.video_library_outlined, 'Gallery', () => _pickVideo(ImageSource.gallery),
            ),
          ],
        );
      case PostMode.audio:
        return _audioSection(scheme);
      case PostMode.text:
        return TextField(
          controller: _text,
          autofocus: true,
          maxLength: _maxText,
          minLines: 6,
          maxLines: 12,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Write what you want people at this spot to read',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        );
    }
  }

  Widget _audioSection(ColorScheme scheme) {
    if (_recording) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 28),
            const SizedBox(height: 8),
            Text(
              'Recording  ${formatDuration(Duration(seconds: _recSeconds))} / ${formatDuration(const Duration(seconds: _maxAudioSeconds))}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _toggleRecording, icon: const Icon(Icons.stop), label: const Text('Stop')),
          ],
        ),
      );
    }
    final path = _audioPath;
    if (path != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AudioPostPlayer(key: ValueKey(path), file: File(path)),
          ),
          const SizedBox(height: 12),
          _twoButtons(
            Icons.mic_none, 'Record again', _toggleRecording,
            Icons.delete_outline, 'Discard', _discardAudio,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _placeholder(scheme, Icons.mic_none, 'Record up to $_maxAudioSeconds seconds of sound'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _toggleRecording, icon: const Icon(Icons.mic), label: const Text('Start recording')),
      ],
    );
  }

  Widget _placeholder(ColorScheme scheme, IconData icon, String text) => Container(
        height: 170,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _twoButtons(IconData i1, String l1, VoidCallback f1, IconData i2, String l2, VoidCallback f2) => Row(
        children: [
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : f1, icon: Icon(i1), label: Text(l1))),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : f2, icon: Icon(i2), label: Text(l2))),
        ],
      );
}
