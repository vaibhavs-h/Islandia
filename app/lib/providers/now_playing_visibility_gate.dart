import 'dart:async';

import 'package:flutter/foundation.dart';

/// A paused track isn't "current" forever. Closing the source app's window
/// doesn't quit it on macOS (Spotify, say, keeps running, paused) — without
/// this, it would stay registered with MediaRemote, and therefore visible
/// on the Island, indefinitely. After [hideAfterPaused] with no change,
/// [onHide] fires so the shell can step Now Playing aside for whatever's
/// next (Battery).
class NowPlayingVisibilityGate {
  NowPlayingVisibilityGate({required this.hideAfterPaused, required this.onHide});

  final Duration hideAfterPaused;
  final VoidCallback onHide;

  Timer? _timer;
  bool _hidden = false;

  bool get isHidden => _hidden;

  /// Call on every snapshot update. Starts the countdown once per pause —
  /// a later still-paused update (a metadata tweak, an audio-route change)
  /// does not restart it, so this really does mean [hideAfterPaused] of no
  /// change, not of no updates.
  void update({required bool isPlaying}) {
    if (isPlaying) {
      reset();
      return;
    }
    _timer ??= Timer(hideAfterPaused, () {
      _hidden = true;
      onHide();
    });
  }

  /// Nothing playing at all — distinct from paused; clears back to the
  /// initial, not-hidden state so a later track starts its own fresh clock.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _hidden = false;
  }

  void dispose() {
    _timer?.cancel();
  }
}
