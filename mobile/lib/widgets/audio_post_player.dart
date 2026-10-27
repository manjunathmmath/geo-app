import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../util.dart';

/// Plays an audio clip from the server ([url]) or from a file on the phone ([file], for the preview before
/// posting). The platform video player also plays sound-only files, so one package serves both.
class AudioPostPlayer extends StatefulWidget {
  const AudioPostPlayer({super.key, this.url, this.file}) : assert(url != null || file != null);

  final String? url;
  final File? file;

  @override
  State<AudioPostPlayer> createState() => _AudioPostPlayerState();
}

class _AudioPostPlayerState extends State<AudioPostPlayer> {
  VideoPlayerController? _controller;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      MediaFocus.release(c);
      c.removeListener(_onChange);
      c.dispose();
    }
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<VideoPlayerController?> _ensure() async {
    final existing = _controller;
    if (existing != null && existing.value.isInitialized) return existing;
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = widget.file != null
        ? VideoPlayerController.file(widget.file!)
        : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return null;
      }
      c.addListener(_onChange);
      setState(() => _controller = c);
      return c;
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _error = 'This audio could not be played.');
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    final c = await _ensure();
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
      return;
    }
    if (c.value.duration > Duration.zero && c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
    MediaFocus.claim(c);
    await c.play();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final position = ready ? c.value.position : Duration.zero;
    final duration = ready ? c.value.duration : Duration.zero;
    final maxMs = duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
    final playing = ready && c.value.isPlaying;

    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      iconSize: 40,
                      tooltip: playing ? 'Pause' : 'Play audio',
                      onPressed: _toggle,
                      icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                    ),
              Expanded(
                child: Slider(
                  value: position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
                  max: maxMs,
                  onChanged: ready ? (v) => c.seekTo(Duration(milliseconds: v.toInt())) : null,
                ),
              ),
              Text(
                '${formatDuration(position)} / ${ready ? formatDuration(duration) : '--:--'}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: scheme.error, fontSize: 13)),
        ],
      ),
    );
  }
}
