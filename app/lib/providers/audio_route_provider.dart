import 'package:flutter/services.dart';

/// The current default output device (§04/§05, alpha) — CoreAudio, a stable
/// public API, unlike Now Playing's MediaRemote detour.
class AudioRouteSnapshot {
  const AudioRouteSnapshot({required this.name, required this.isBuiltIn});

  final String name;

  /// True for the built-in speakers/headphone jack — false means the user
  /// deliberately switched to something (AirPods, a HomePod, USB, AirPlay).
  final bool isBuiltIn;
}

class AudioRouteProvider {
  AudioRouteProvider._();

  static const EventChannel _channel = EventChannel('islandia/audio-route/updates');

  /// Null if CoreAudio reports no default output device at all — rare, but
  /// fail quiet (§10) rather than crash on it.
  static Stream<AudioRouteSnapshot?> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<String, Object?>();
      final name = map['name'] as String?;
      if (name == null) return null;
      return AudioRouteSnapshot(name: name, isBuiltIn: map['isBuiltIn'] as bool? ?? false);
    }).handleError((Object _) {});
  }
}
