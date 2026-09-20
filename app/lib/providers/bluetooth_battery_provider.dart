import 'package:flutter/services.dart';

/// One connected Bluetooth accessory that reports battery over the standard
/// GATT Battery Service (0x180F/0x2A19) — a public CoreBluetooth API, unlike
/// AirPods' battery reporting, which uses an undocumented Apple protocol and
/// isn't covered by this provider at all (see BluetoothBatteryChannel.swift).
class BluetoothDeviceBattery {
  const BluetoothDeviceBattery({required this.name, required this.batteryPercent});

  final String name;
  final int batteryPercent;
}

/// Real Bluetooth accessory battery (§04/§05, alpha) — scoped to the public
/// GATT Battery Service only. Many keyboards, mice, and trackpads (including
/// Apple's own) implement it; plenty of audio accessories don't, since they
/// often report battery through a vendor-specific classic-Bluetooth profile
/// extension instead, which this doesn't attempt to decode.
class BluetoothBatteryProvider {
  BluetoothBatteryProvider._();

  static const EventChannel _channel = EventChannel('islandia/bluetooth-battery/updates');

  /// An empty list is a real, common state (nothing connected reports
  /// battery this way) — not an error. Fails quiet on anything else, same
  /// as every other provider here.
  static Stream<List<BluetoothDeviceBattery>> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      final devices = (event as List).cast<Map>();
      return devices.map((raw) {
        final map = raw.cast<String, Object?>();
        return BluetoothDeviceBattery(
          name: map['name'] as String,
          batteryPercent: (map['batteryPercent'] as num).round(),
        );
      }).toList();
    }).handleError((Object _) {});
  }
}

/// Lowest battery first — whichever device needs attention soonest is the
/// one worth surfacing in the collapsed pill.
List<BluetoothDeviceBattery> sortedByBatteryAscending(List<BluetoothDeviceBattery> devices) {
  final sorted = List<BluetoothDeviceBattery>.of(devices);
  sorted.sort((a, b) => a.batteryPercent.compareTo(b.batteryPercent));
  return sorted;
}
