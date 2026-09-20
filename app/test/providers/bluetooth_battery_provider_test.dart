import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/providers/bluetooth_battery_provider.dart';

void main() {
  group('sortedByBatteryAscending', () {
    test('orders lowest battery first', () {
      final sorted = sortedByBatteryAscending(const [
        BluetoothDeviceBattery(name: 'Magic Mouse', batteryPercent: 80),
        BluetoothDeviceBattery(name: 'Sony Headphones', batteryPercent: 15),
        BluetoothDeviceBattery(name: 'Magic Keyboard', batteryPercent: 45),
      ]);

      expect(sorted.map((d) => d.name), ['Sony Headphones', 'Magic Keyboard', 'Magic Mouse']);
    });

    test('does not mutate the original list', () {
      final original = [
        const BluetoothDeviceBattery(name: 'A', batteryPercent: 50),
        const BluetoothDeviceBattery(name: 'B', batteryPercent: 10),
      ];
      sortedByBatteryAscending(original);

      expect(original.map((d) => d.name), ['A', 'B']);
    });

    test('a single device sorts trivially', () {
      final sorted = sortedByBatteryAscending(const [BluetoothDeviceBattery(name: 'Solo', batteryPercent: 42)]);
      expect(sorted, hasLength(1));
    });
  });
}
