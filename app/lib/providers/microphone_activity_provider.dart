import 'package:flutter/services.dart';

/// Real mic-in-use detection (§04/§05, v1 tier) — CoreAudio's
/// kAudioDevicePropertyDeviceIsRunningSomewhere on the default input device,
/// a public API that reports whether *any* process has it running, not just
/// this one. Known caveat (native side, MicrophoneActivityChannel.swift):
/// doesn't report correctly for Bluetooth microphones — built-in/wired mics
/// work.
class MicrophoneActivityProvider {
  MicrophoneActivityProvider._();

  static const EventChannel _channel = EventChannel('islandia/microphone-activity/updates');

  static Stream<bool> get updates {
    return _channel.receiveBroadcastStream().map((event) => event as bool).handleError((Object _) {});
  }
}
