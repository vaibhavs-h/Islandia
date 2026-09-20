import 'package:flutter/services.dart';

/// A single join or leave event for a Wi-Fi network — see
/// WiFiConnectionChannel.swift for where this comes from (CoreWLAN's
/// CWEventDelegate, gated behind Location Services authorization).
class WiFiConnectionEvent {
  const WiFiConnectionEvent({required this.name, required this.connected});

  final String name;
  final bool connected;
}

/// Real Wi-Fi network join/leave (§05, v1 tier) — same shape as
/// BluetoothClassicProvider: native already hands over discrete events,
/// nothing to diff here, just forward each one.
class WiFiConnectionProvider {
  WiFiConnectionProvider._();

  static const EventChannel _channel = EventChannel('islandia/wifi-connection/updates');

  static Stream<WiFiConnectionEvent> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<String, Object?>();
      return WiFiConnectionEvent(name: map['name'] as String, connected: map['connected'] as bool);
    }).handleError((Object _) {});
  }
}
