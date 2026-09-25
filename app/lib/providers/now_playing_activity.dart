import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../engine/activity.dart';
import 'audio_route_provider.dart';
import 'duration_format.dart';
import 'now_playing_provider.dart';

/// Real Now Playing (§04/§05, alpha): Spotify, Apple Music, a browser tab —
/// all the same [Activity], regardless of source, per §04's whole point.
/// [audioRoute] is a second, independent CoreAudio-backed provider — only
/// surfaced here when it's something the user deliberately switched to
/// (AirPods, a HomePod, AirPlay), not the boring built-in-speakers default.
/// [onControlPressed] fires after every control button tap (not just
/// send()) so the shell can reset its auto-collapse clock — a press that
/// actually changes playback is a relevant interaction, not idle hovering.
///
/// `clock` tier, not `dashboard` — sits in the same band as the Clock's
/// own timer/stopwatch live view, one level above Weather/Battery/Wi-Fi/
/// Bluetooth. This band isn't a flat tier on its own: island_shell.dart's
/// own resolveClockTierWinner/_refreshClockTierActivity decides which ONE
/// of {this, a running stopwatch, a running timer} actually gets
/// registered at `clock` on any given tick — see that resolver's own doc
/// comment for the exact ordering (a timer close to completing can
/// outrank both a running stopwatch and this).
Activity buildNowPlayingActivity(
  NowPlayingSnapshot snapshot, {
  AudioRouteSnapshot? audioRoute,
  required VoidCallback onControlPressed,
}) {
  return Activity(
    id: 'now-playing',
    priority: ActivityPriority.clock,
    collapsedBuilder: (context, state) => _NowPlayingCollapsed(snapshot: snapshot),
    expandedBuilder: (context, state) => _NowPlayingExpanded(
      snapshot: snapshot,
      audioRoute: audioRoute,
      onControlPressed: onControlPressed,
    ),
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.snapshot, required this.size, this.circular = false});

  final NowPlayingSnapshot snapshot;
  final double size;

  /// The collapsed pill is a full stadium shape — a rounded-square thumbnail
  /// inside it reads as a mismatched corner radius, not a deliberate
  /// contrast. The expanded card has room to breathe, so album art there
  /// stays a normal rounded square instead (matching how art is presented
  /// everywhere else, from Music.app to Control Center).
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final bytes = snapshot.artworkBytes;
    final content = SizedBox(
      width: size,
      height: size,
      child: bytes == null
          ? ColoredBox(
              color: const Color(0xFF2A2C31),
              child: Icon(Icons.music_note, color: Colors.white38, size: size * 0.55),
            )
          : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    );
    if (circular) {
      return ClipOval(child: content);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(size / 5), child: content);
  }
}

class _NowPlayingCollapsed extends StatelessWidget {
  const _NowPlayingCollapsed({required this.snapshot});

  final NowPlayingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${snapshot.title}${snapshot.artist != null ? ", ${snapshot.artist}" : ""}. '
          '${snapshot.isPlaying ? "Playing" : "Paused"}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _Artwork(snapshot: snapshot, size: 26, circular: true),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                snapshot.title,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            // A status indicator, not a button — it shows what IS happening,
            // not what tapping it would do. An animated waveform while
            // actually playing; a play glyph while paused (was showing
            // pause on both, backwards).
            _WaveformIndicator(isPlaying: snapshot.isPlaying),
          ],
        ),
      ),
    );
  }
}

/// The animated waveform swap-in for the old static `Icons.graphic_eq` — a
/// real looping video (muted; it's a visual only) rather than an icon
/// animation, since that's the asset this was actually asked to use.
/// Keeps its [VideoPlayerController] alive across play/pause toggles rather
/// than tearing it down each time: `didUpdateWidget` just calls play()/
/// pause() on the existing controller, so resuming picks up the loop where
/// it left off instead of re-initializing (near-instant for a small local
/// asset either way, but no reason to redo the work). Only actually falls
/// back to the static play glyph while paused, or for the brief window
/// before the controller finishes initializing.
class _WaveformIndicator extends StatefulWidget {
  const _WaveformIndicator({required this.isPlaying});

  final bool isPlaying;

  @override
  State<_WaveformIndicator> createState() => _WaveformIndicatorState();
}

class _WaveformIndicatorState extends State<_WaveformIndicator> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  /// How much before the true end to jump back to the start. `setLooping`
  /// waits for the platform to report genuine end-of-playback and only then
  /// seeks — a real, well-documented gap in `video_player`'s AVFoundation
  /// implementation (it doesn't use AVFoundation's own `AVPlayerLooper`,
  /// the API made for gapless looping) that shows up as a brief but
  /// noticeable freeze each loop. Seeking back *before* playback would
  /// naturally stop avoids that stop-detect-restart cycle entirely — the
  /// player is never actually between "playing" and "ended", just
  /// continuously playing with an occasional jump. Not truly gapless (that
  /// needs the native AVPlayerLooper route, a real platform-view project of
  /// its own — declined as more than this is worth), but removes the
  /// specific cause of the visible stall.
  static const _loopEarlyBy = Duration(milliseconds: 150);

  Future<void> _initController() async {
    final controller = VideoPlayerController.asset('assets/video/now_playing_waveform.mp4');
    try {
      await controller.initialize();
      // Deliberately NOT controller.setLooping(true) — see _loopEarlyBy.
      // Decorative only — this must never actually play sound.
      await controller.setVolume(0);
    } catch (_) {
      // No platform video support, a bad asset, whatever — the static play
      // glyph this replaces is a perfectly fine fallback, not worth taking
      // the whole indicator down over. build() already falls back to it
      // whenever _controller is null, so there's nothing further to do
      // here beyond not leaking the controller we just failed to set up.
      unawaited(controller.dispose());
      return;
    }
    if (!mounted) {
      unawaited(controller.dispose());
      return;
    }
    controller.addListener(_loopEarly);
    setState(() => _controller = controller);
    if (widget.isPlaying) controller.play();
  }

  bool _looping = false;

  void _loopEarly() {
    final controller = _controller;
    if (controller == null || _looping) return;
    final value = controller.value;
    if (!value.isPlaying || !value.isInitialized) return;
    if (value.position < value.duration - _loopEarlyBy) return;
    // seekTo alone is enough — the player was already playing and never
    // actually stopped, so there's nothing to resume.
    _looping = true;
    controller.seekTo(Duration.zero).whenComplete(() => _looping = false);
  }

  @override
  void didUpdateWidget(covariant _WaveformIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying == oldWidget.isPlaying) return;
    final controller = _controller;
    if (controller == null) return; // still initializing — _initController itself honors the current isPlaying once ready.
    if (widget.isPlaying) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  static const _width = 22.0;
  static const _height = 15.0;
  static const _zoom = 1.6;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!widget.isPlaying || controller == null || !controller.value.isInitialized) {
      return const SizedBox(
        width: _width,
        height: _height,
        child: Center(child: Icon(Icons.play_arrow, color: Colors.white70, size: 15)),
      );
    }
    // VideoPlayer has no BoxFit of its own — rendering it at its native
    // size inside a FittedBox is the standard way to get cover-style
    // cropping instead of a stretched/distorted picture.
    return SizedBox(
      width: _width,
      height: _height,
      // ClipRect isn't optional once _zoom pushes the video past a plain
      // cover-fit — FittedBox itself doesn't clip its child by default, and
      // without this the extra-scaled content would paint outside the
      // intended 22x15 footprint instead of just cropping tighter within it.
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            // The source video frames the waveform with a fair amount of
            // black padding on the sides — a plain cover-fit still shows
            // mostly that padding and the short, quiet outer bars at this
            // size, leaving the tall center bars (the part that actually
            // reads as "a waveform" this small) less prominent than they
            // should be. Zooming in past cover crops the padding out
            // without changing the 22x15 footprint at all.
            child: Transform.scale(scale: _zoom, child: VideoPlayer(controller)),
          ),
        ),
      ),
    );
  }
}

class _NowPlayingExpanded extends StatefulWidget {
  const _NowPlayingExpanded({required this.snapshot, this.audioRoute, required this.onControlPressed});

  final NowPlayingSnapshot snapshot;
  final AudioRouteSnapshot? audioRoute;
  final VoidCallback onControlPressed;

  @override
  State<_NowPlayingExpanded> createState() => _NowPlayingExpandedState();
}

class _NowPlayingExpandedState extends State<_NowPlayingExpanded> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTickerIfPlaying();
  }

  @override
  void didUpdateWidget(covariant _NowPlayingExpanded oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startTickerIfPlaying();
  }

  // MediaRemote pushes on real events (play/pause/seek/track change), not
  // once a second — a smoothly advancing progress readout has to come from
  // a local ticker recomputing NowPlayingSnapshot.currentElapsed(), not from
  // waiting on more pushes that aren't coming.
  void _startTickerIfPlaying() {
    final shouldTick = widget.snapshot.isPlaying;
    if (shouldTick && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else if (!shouldTick && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _activateSourceApp() {
    NowPlayingProvider.activateSourceApp(widget.snapshot.bundleIdentifier);
    widget.onControlPressed();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final elapsed = snapshot.currentElapsed();
    final duration = snapshot.duration;
    final progress = (duration != null && duration.inMilliseconds > 0)
        ? (elapsed.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : null;
    final showsAudioRoute = widget.audioRoute != null && !widget.audioRoute!.isBuiltIn;
    // Title, artist, and the audio-route line stacking all three at once
    // (an external output device on a track that also has a real artist) is
    // the one combination that doesn't fit the fixed box at the normal,
    // roomier spacing below — tighten just the gap before the progress bar
    // for that specific case rather than cramming every layout to fit it.
    final isDense = snapshot.artist != null && showsAudioRoute;
    const artworkSize = 56.0;
    const artworkGap = 10.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      // No blanket excludeSemantics wrapper here (there was one) — it would
      // have swallowed the artwork/title button semantics below along with
      // everything else. Plain text (artist, audio route, elapsed time) is
      // still perfectly readable via its own default semantics; only the
      // two actionable regions need an explicit label/action.
      child: Semantics(
        label: '${snapshot.isPlaying ? "Playing" : "Paused"}.',
        // The artwork is positioned independently (see the Positioned
        // below) so it can be centered against the whole card's height —
        // but the controls specifically should only center against the
        // *info* column's own width, not the artwork's too, so both the
        // text and the controls live in the same inset Column here.
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(left: artworkSize + artworkGap),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      button: true,
                      label: 'Open ${snapshot.title} in its app',
                      onTap: _activateSourceApp,
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: _activateSourceApp,
                        child: Text(
                          snapshot.title,
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (snapshot.artist != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        snapshot.artist!,
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (showsAudioRoute) ...[
                      SizedBox(height: isDense ? 1 : 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.speaker_group, color: Colors.white38, size: 12),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              widget.audioRoute!.name,
                              style: const TextStyle(color: Colors.white38, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    SizedBox(height: isDense ? 2 : 8),
                    if (progress != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      SizedBox(height: isDense ? 3 : 5),
                      Text(
                        '${formatDuration(elapsed)} / ${formatDuration(duration!)}',
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    SizedBox(height: isDense ? 4 : 6),
                    Row(
                      // Centers within *this* Column's width only — the
                      // Padding above already excludes the artwork's
                      // column, so this never accounts for it either.
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ControlButton(
                          icon: CupertinoIcons.backward_fill,
                          label: 'Previous track',
                          compact: isDense,
                          onTap: () {
                            NowPlayingProvider.send(NowPlayingProvider.commandPreviousTrack);
                            widget.onControlPressed();
                          },
                        ),
                        const SizedBox(width: 10),
                        _ControlButton(
                          icon: snapshot.isPlaying ? CupertinoIcons.pause_solid : CupertinoIcons.play_arrow_solid,
                          label: snapshot.isPlaying ? 'Pause' : 'Play',
                          compact: isDense,
                          onTap: () {
                            NowPlayingProvider.send(NowPlayingProvider.commandTogglePlayPause);
                            widget.onControlPressed();
                          },
                          filled: true,
                        ),
                        const SizedBox(width: 10),
                        _ControlButton(
                          icon: CupertinoIcons.forward_fill,
                          label: 'Next track',
                          compact: isDense,
                          onTap: () {
                            NowPlayingProvider.send(NowPlayingProvider.commandNextTrack);
                            widget.onControlPressed();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Positioned independently of the text/controls flow above —
            // see the comment on the Stack — so it's centered against the
            // card's actual full height, not just the space left over
            // above the controls.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Semantics(
                  button: true,
                  label: 'Open ${snapshot.title} in its app',
                  onTap: _activateSourceApp,
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const ValueKey('now-playing-artwork'),
                    onTap: _activateSourceApp,
                    child: _Artwork(snapshot: snapshot, size: artworkSize),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  /// A couple fewer px of padding — used only in the one layout combination
  /// (title + artist + audio route all shown) tight enough to need it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: filled ? Colors.white : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 6 : 7),
            child: Icon(icon, color: filled ? Colors.black : Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
