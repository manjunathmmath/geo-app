import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../util.dart';

/// Plays a video from the server ([url]) or from a file on the phone ([file], for the preview before posting).
/// Nothing is downloaded until the play button is tapped, so a long feed stays light.
class VideoPostPlayer extends StatefulWidget {
  const VideoPostPlayer({super.key, this.url, this.file}) : assert(url != null || file != null);

  final String? url;
  final File? file;

  @override
  State<VideoPostPlayer> createState() => _VideoPostPlayerState();
}

class _VideoPostPlayerState extends State<VideoPostPlayer> {
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

  Future<void> _start() async {
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
        return;
      }
      c.addListener(_onChange);
      MediaFocus.claim(c);
      setState(() => _controller = c);
      await c.play();
    } catch (e) {
      await c.dispose();
      if (mounted) setState(() => _error = 'This video could not be played.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      await c.pause();
    } else {
      // Restart from the beginning when it has reached the end.
      if (c.value.position >= c.value.duration && c.value.duration > Duration.zero) await c.seekTo(Duration.zero);
      MediaFocus.claim(c);
      await c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;

    if (!ready) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        iconSize: 64,
                        color: Colors.white,
                        tooltip: 'Play video',
                        onPressed: _start,
                        icon: const Icon(Icons.play_circle_fill),
                      ),
                      Text(
                        _error ?? 'Tap to play',
                        style: TextStyle(color: _error == null ? Colors.white70 : Colors.redAccent.shade100),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }

    final size = c.value.size;
    // Keep very tall or very wide clips inside a sensible box.
    final ratio = c.value.aspectRatio.clamp(0.75, 1.78).toDouble();
    return ColoredBox(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(c)),
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggle,
              child: AnimatedOpacity(
                opacity: c.value.isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: const Center(child: Icon(Icons.play_circle_fill, size: 64, color: Colors.white70)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${formatDuration(c.value.position)} / ${formatDuration(c.value.duration)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.only(top: 4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
