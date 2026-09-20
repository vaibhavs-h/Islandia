import 'package:flutter/services.dart';

/// Screen capture indicator (§04/§05, v1 tier) — see
/// ScreenCaptureActivityChannel.swift for the (fragile, log-based) source.
/// Deliberately fires for a recording, a screen share, and a plain
/// screenshot alike, matching macOS's own purple indicator exactly.
class ScreenCaptureActivityProvider {
  ScreenCaptureActivityProvider._();

  static const EventChannel _channel = EventChannel('islandia/screen-capture-activity/updates');

  static Stream<bool> get updates {
    return _channel.receiveBroadcastStream().map((event) => event as bool).handleError((Object _) {});
  }
}
