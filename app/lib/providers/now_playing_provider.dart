import 'dart:convert';

import 'package:flutter/services.dart';

/// A normalized snapshot of whatever's playing system-wide (§04) — Spotify,
/// Apple Music, a browser tab, all become this one shape. Sourced from
/// MediaRemote via the vendored `mediaremote-adapter` helper; see
/// NowPlayingChannel.swift for why that detour is necessary at all.
class NowPlayingSnapshot {
  const NowPlayingSnapshot({
    required this.bundleIdentifier,
    required this.title,
    this.artist,
    this.album,
    required this.isPlaying,
    this.elapsedSeconds,
    this.durationSeconds,
    this.timestamp,
    this.artworkBytes,
  });

  final String bundleIdentifier;
  final String title;
  final String? artist;
  final String? album;
  final bool isPlaying;

  /// The elapsed time as of [timestamp] — a snapshot, not a live clock. Use
  /// [currentElapsed] to read it as of right now.
  final double? elapsedSeconds;
  final double? durationSeconds;
  final DateTime? timestamp;
  final Uint8List? artworkBytes;

  /// Extrapolates from the last known elapsed time + timestamp rather than
  /// polling — MediaRemote only pushes on real events (play/pause/seek/track
  /// change), not once a second, so anything that wants a smoothly ticking
  /// clock has to derive it locally instead of waiting on more pushes.
  Duration currentElapsed() {
    final baseline = Duration(milliseconds: ((elapsedSeconds ?? 0) * 1000).round());
    if (!isPlaying || timestamp == null) return baseline;
    final sinceUpdate = DateTime.now().difference(timestamp!);
    return sinceUpdate.isNegative ? baseline : baseline + sinceUpdate;
  }

  Duration? get duration =>
      durationSeconds == null ? null : Duration(milliseconds: (durationSeconds! * 1000).round());
}

/// Real Now Playing (§04/§05, alpha) — the first activity in this codebase
/// backed by a private macOS framework, isolated behind a subprocess exactly
/// as §01 requires so a MediaRemote breakage (Apple has tightened access to
/// it before) only silences this one provider, not the app.
class NowPlayingProvider {
  NowPlayingProvider._();

  static const EventChannel _channel = EventChannel('islandia/now-playing/updates');
  static const MethodChannel _controlChannel = MethodChannel('islandia/now-playing/control');

  static const int commandPlay = 0;
  static const int commandPause = 1;
  static const int commandTogglePlayPause = 2;
  static const int commandNextTrack = 4;
  static const int commandPreviousTrack = 5;

  /// Null means "nothing playing anywhere" — §04's mandatory fields
  /// (bundleIdentifier, playing, title) being absent is a real, common state
  /// (nobody has anything open), not an error to surface.
  static Stream<NowPlayingSnapshot?> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<String, Object?>();
      // For media playing natively (Spotify, Music), `bundleIdentifier` is
      // the app itself. For a browser tab, MediaRemote reports the bundle
      // identifier of the browser's internal media/content process there,
      // not the browser app — `parentApplicationBundleIdentifier` is the
      // real top-level app in that case, and what activateSourceApp
      // actually needs to bring to the front.
      final bundleIdentifier =
          (map['parentApplicationBundleIdentifier'] as String?) ?? (map['bundleIdentifier'] as String?);
      final title = map['title'] as String?;
      if (bundleIdentifier == null || title == null) return null;
      return NowPlayingSnapshot(
        bundleIdentifier: bundleIdentifier,
        title: title,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        isPlaying: map['playing'] as bool? ?? false,
        elapsedSeconds: (map['elapsedTime'] as num?)?.toDouble(),
        durationSeconds: (map['duration'] as num?)?.toDouble(),
        timestamp: _parseTimestamp(map['timestamp']),
        artworkBytes: _decodeArtwork(map['artworkData']),
      );
    }).handleError((Object _) {});
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  static Uint8List? _decodeArtwork(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  static Future<void> send(int commandId) {
    return _controlChannel.invokeMethod('send', commandId);
  }

  /// Brings the source app to the front — deliberately just the app, not a
  /// specific browser tab or an artist/channel page, since MediaRemote's
  /// payload has nothing reliable to act on for either of those.
  static Future<void> activateSourceApp(String bundleIdentifier) {
    return _controlChannel.invokeMethod('activateSourceApp', bundleIdentifier);
  }

  /// Hardware media keys (the dedicated Previous/Play-Pause/Next keys) are a
  /// system-wide event type, not a normal keystroke — native watches for
  /// them via an `NSEvent` global monitor (NowPlayingChannel.swift) exactly
  /// like the window's own outside-click detection, so it can never
  /// interfere with normal typing in any other app. Native only reports
  /// *that* a media key was pressed; whether it's currently relevant to act
  /// on is a shell-state decision, made here in Dart. Pass `null` to stop
  /// listening.
  static void setMediaKeyHandler(void Function(String action)? handler) {
    _controlChannel.setMethodCallHandler(handler == null
        ? null
        : (call) async {
            if (call.method == 'mediaKey' && call.arguments is String) {
              handler(call.arguments as String);
            }
          });
  }
}
