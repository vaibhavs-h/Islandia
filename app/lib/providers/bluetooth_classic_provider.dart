import 'package:flutter/services.dart';

/// A single connect or disconnect event for a Bluetooth Classic accessory
/// (headphones, earbuds, speakers) — see BluetoothClassicChannel.swift for
/// why this needs IOBluetooth rather than the CoreBluetooth path
/// BluetoothBatteryProvider uses.
/// [batteryPercent] is only ever present on a connect — see the native side
/// for where it actually comes from (bluetoothd's own CBPowerSource
/// logging) — and even then only when a reading happened to be available
/// within its grace window; a disconnect, or a connect with nothing found,
/// leaves it null.
class BluetoothClassicEvent {
  const BluetoothClassicEvent({required this.name, required this.connected, this.batteryPercent});

  final String name;
  final bool connected;
  final int? batteryPercent;
}

/// Real Bluetooth Classic connect/disconnect (§04/§05, v1 tier). Unlike
/// BluetoothBatteryProvider's polled snapshots, the native side already
/// hands over discrete events — nothing to diff here, just forward each one.
class BluetoothClassicProvider {
  BluetoothClassicProvider._();

  static const EventChannel _channel = EventChannel('islandia/bluetooth-classic/updates');

  static Stream<BluetoothClassicEvent> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<String, Object?>();
      return BluetoothClassicEvent(
        name: map['name'] as String,
        connected: map['connected'] as bool,
        batteryPercent: (map['batteryPercent'] as num?)?.round(),
      );
    }).handleError((Object _) {});
  }
}
