import 'package:flutter/services.dart';

/// Camera-in-use detection (§04/§05, v1 tier — fragile by design, knowingly
/// shipped that way). There is no public API for this at all: Apple exposes
/// nothing for detecting another app's camera session. Native
/// (CameraActivityChannel.swift) watches the unified system log for the
/// exact message pairs CMIOExtensionProvider emits when a client starts or
/// stops a camera stream — confirmed live against this machine, but it's a
/// log *message format*, not a documented API, and Apple could change or
/// redact it on any OS update with zero notice. There's no fallback if it
/// breaks, only silence — same trade the user explicitly accepted for the
/// screen-recording attempt.
class CameraActivityProvider {
  CameraActivityProvider._();

  static const EventChannel _channel = EventChannel('islandia/camera-activity/updates');

  static Stream<bool> get updates {
    return _channel.receiveBroadcastStream().map((event) => event as bool).handleError((Object _) {});
  }
}
