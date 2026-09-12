import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

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
Activity buildNowPlayingActivity(
  NowPlayingSnapshot snapshot, {
  AudioRouteSnapshot? audioRoute,
  required VoidCallback onControlPressed,
}) {
  return Activity(
    id: 'now-playing',
    priority: ActivityPriority.p3Ambient,
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
            // not what tapping it would do. Waveform while actually playing;
            // a play glyph while paused (was showing pause on both, backwards).
            Icon(
              snapshot.isPlaying ? Icons.graphic_eq : Icons.play_arrow,
              color: Colors.white70,
              size: 15,
            ),
          ],
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      // No blanket excludeSemantics wrapper here (there was one) — it would
      // have swallowed the artwork/title button semantics below along with
      // everything else. Plain text (artist, audio route, elapsed time) is
      // still perfectly readable via its own default semantics; only the
      // two actionable regions need an explicit label/action.
      child: Semantics(
        label: '${snapshot.isPlaying ? "Playing" : "Paused"}.',
        child: Row(
          // Centered rather than top-aligned: the content's natural height
          // will rarely match the pill's exact height pixel-for-pixel, and
          // centering is what keeps the top/bottom padding looking equal
          // regardless — top-aligning just dumps all the slack at the bottom.
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Artwork and title both jump to the source app — not the
            // artist name (a plain string, not a Spotify artist ID or
            // YouTube channel URL — nothing to reliably deep-link to), and
            // not a specific browser tab (MediaRemote doesn't say which one).
            Semantics(
              button: true,
              label: 'Open ${snapshot.title} in its app',
              onTap: _activateSourceApp,
              excludeSemantics: true,
              child: GestureDetector(
                onTap: _activateSourceApp,
                child: _Artwork(snapshot: snapshot, size: 64),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
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
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (snapshot.artist != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      snapshot.artist!,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (widget.audioRoute != null && !widget.audioRoute!.isBuiltIn) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.speaker_group, color: Colors.white38, size: 11),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            widget.audioRoute!.name,
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (progress != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatDuration(elapsed)} / ${formatDuration(duration!)}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ControlButton(
                        icon: CupertinoIcons.backward_fill,
                        label: 'Previous track',
                        onTap: () {
                          NowPlayingProvider.send(NowPlayingProvider.commandPreviousTrack);
                          widget.onControlPressed();
                        },
                      ),
                      const SizedBox(width: 10),
                      _ControlButton(
                        icon: snapshot.isPlaying ? CupertinoIcons.pause_solid : CupertinoIcons.play_arrow_solid,
                        label: snapshot.isPlaying ? 'Pause' : 'Play',
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
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.label, required this.onTap, this.filled = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

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
            padding: const EdgeInsets.all(6),
            child: Icon(icon, color: filled ? Colors.black : Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}
