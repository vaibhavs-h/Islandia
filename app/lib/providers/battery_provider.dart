import 'package:flutter/services.dart';

/// A normalized snapshot of Mac battery/power state — whatever the source
/// (today: IOKit directly; nothing else is planned to feed this), the shell
/// only ever sees this shape (§04).
class BatterySnapshot {
  const BatterySnapshot({
    required this.percentage,
    required this.isCharging,
    required this.isCharged,
    required this.isOnACPower,
  });

  /// 0.0–1.0.
  final double percentage;
  final bool isCharging;
  final bool isCharged;
  final bool isOnACPower;

  int get percentageRounded => (percentage * 100).round();
}

/// The first real (non-fake) provider (§05, alpha tier): battery/charging
/// status via IOKit, pushed from native — see BatteryStreamHandler.swift —
/// whenever the power source actually changes, never polled from Dart.
class BatteryProvider {
  BatteryProvider._();

  static const EventChannel _channel = EventChannel('islandia/battery/updates');

  /// Empty (not an error) on a Mac with no battery, and equally silent on
  /// any other failure (no native handler registered, a malformed event) —
  /// §10's "fail quiet" applies here same as everywhere else: hide the one
  /// affected activity, don't take the rest of the app down with it, and
  /// don't retry forever in a tight loop.
  static Stream<BatterySnapshot> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<String, Object?>();
      return BatterySnapshot(
        percentage: (map['percentage'] as num).toDouble(),
        isCharging: map['isCharging'] as bool,
        isCharged: map['isCharged'] as bool,
        isOnACPower: map['isOnACPower'] as bool,
      );
    }).handleError((Object _) {});
  }
}
