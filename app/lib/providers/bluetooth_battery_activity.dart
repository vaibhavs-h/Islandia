import 'package:flutter/material.dart';

import '../engine/activity.dart';
import 'bluetooth_battery_provider.dart';

/// Real Bluetooth accessory battery (§04/§05, alpha) — see
/// BluetoothBatteryProvider for what this is (and isn't) scoped to. [devices]
/// is never empty here — the shell only registers this activity while at
/// least one device is reporting.
Activity buildBluetoothBatteryActivity(List<BluetoothDeviceBattery> devices) {
  final sorted = sortedByBatteryAscending(devices);
  return Activity(
    id: 'bluetooth-battery',
    priority: ActivityPriority.dashboard,
    collapsedBuilder: (context, state) => _BluetoothBatteryCollapsed(devices: sorted),
    expandedBuilder: (context, state) => _BluetoothBatteryExpanded(devices: sorted),
  );
}

/// Each call gets its own id (see buildBluetoothConnectionActivity) instead
/// of sharing one fixed string — a fast connect-then-disconnect needs to
/// read as two distinct arrivals, not one activity quietly changing its
/// mind mid-display.
int _connectionNotificationSequence = 0;

/// A device joining or leaving the battery-tracked set (§05, v1 tier) —
/// Alert tier, transient: announces itself once and ages out on its own
/// after 5s via the engine's
/// own timeout handling. Scoped to the same devices BluetoothBatteryProvider
/// already tracks (the standard GATT Battery Service), not every Bluetooth
/// device macOS knows about.
/// [batteryPercent] is shown only alongside a *connect* — a device that just
/// disconnected doesn't have a current reading worth announcing, and passing
/// one there would read as if it were still connected. It's also only ever
/// available for BLE devices in the first place (BluetoothBatteryProvider);
/// the Classic-device connect/disconnect path (BluetoothClassicProvider) has
/// no battery source at all, so it's always null there — the notification
/// just quietly omits it, same as today.
Activity buildBluetoothConnectionActivity({required String deviceName, required bool connected, int? batteryPercent}) {
  // A *fixed* id here (there used to be one) means ActivityStack treats a
  // fast reconnect/disconnect as the same activity being updated in place —
  // right for a battery percentage ticking down, wrong for "connected" and
  // "disconnected" being two different facts. An in-place update never
  // triggers island_shell's cross-fade at all, so the text just jumped,
  // sometimes visibly overlapping whatever was still fading out underneath
  // from the *previous* transition. Giving every call its own id makes each
  // one a genuine new arrival, which does cross-fade smoothly, same as any
  // other activity change.
  _connectionNotificationSequence++;
  final effectiveBatteryPercent = connected ? batteryPercent : null;
  return Activity(
    id: 'bluetooth-connection-$_connectionNotificationSequence',
    priority: ActivityPriority.alert,
    isTransient: true,
    autoDismissAfter: const Duration(seconds: 5),
    // Two distinct widgets, not one shared instance — see
    // wifi_connection_activity.dart's own equivalent for why: a size
    // tuned for the expanded card's full box leaked into the collapsed
    // pill too and truncated names that used to fit there.
    collapsedBuilder: (context, state) =>
        _BluetoothConnectionContent(deviceName: deviceName, connected: connected, batteryPercent: effectiveBatteryPercent, expanded: false),
    expandedBuilder: (context, state) =>
        _BluetoothConnectionContent(deviceName: deviceName, connected: connected, batteryPercent: effectiveBatteryPercent, expanded: true),
  );
}

class _BluetoothConnectionContent extends StatelessWidget {
  const _BluetoothConnectionContent({required this.deviceName, required this.connected, required this.expanded, this.batteryPercent});

  final String deviceName;
  final bool connected;
  final bool expanded;
  final int? batteryPercent;

  @override
  Widget build(BuildContext context) {
    final statusText = connected ? 'connected' : 'disconnected';
    final percent = batteryPercent;
    final label = '$deviceName $statusText${percent != null ? ', $percent percent' : ''}';
    final iconSize = expanded ? 20.0 : 18.0;
    final fontSize = expanded ? 17.0 : 15.0;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: Colors.white, size: iconSize),
        SizedBox(width: expanded ? 10 : 9),
        Flexible(
          child: Text(
            '$deviceName $statusText',
            style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: expanded ? FontWeight.w600 : FontWeight.normal),
            overflow: TextOverflow.ellipsis,
            textAlign: expanded ? TextAlign.center : TextAlign.start,
          ),
        ),
        if (percent != null) ...[
          SizedBox(width: expanded ? 9 : 8),
          Icon(_batteryIconFor(percent), color: Colors.white60, size: expanded ? 17 : 15),
          const SizedBox(width: 3),
          Text('$percent%', style: TextStyle(color: Colors.white60, fontSize: expanded ? 15 : 13, fontWeight: FontWeight.w600)),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        label: '$label.',
        excludeSemantics: true,
        liveRegion: true,
        child: expanded ? Center(child: row) : row,
      ),
    );
  }
}

IconData _batteryIconFor(int percent) {
  if (percent <= 10) return Icons.battery_alert;
  if (percent <= 50) return Icons.battery_3_bar;
  return Icons.battery_full;
}

class _BluetoothBatteryCollapsed extends StatelessWidget {
  const _BluetoothBatteryCollapsed({required this.devices});

  final List<BluetoothDeviceBattery> devices;

  @override
  Widget build(BuildContext context) {
    final lowest = devices.first;
    final extra = devices.length - 1;
    return Semantics(
      label: '${lowest.name}, ${lowest.batteryPercent} percent'
          '${extra > 0 ? ', and $extra other Bluetooth device${extra == 1 ? '' : 's'}' : ''}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth, color: Colors.white, size: 16),
            const SizedBox(width: 7),
            Icon(_batteryIconFor(lowest.batteryPercent), color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text('${lowest.batteryPercent}%', style: const TextStyle(color: Colors.white, fontSize: 15)),
            if (extra > 0) ...[
              const SizedBox(width: 6),
              Text('+$extra', style: const TextStyle(color: Colors.white60, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class _BluetoothBatteryExpanded extends StatelessWidget {
  const _BluetoothBatteryExpanded({required this.devices});

  final List<BluetoothDeviceBattery> devices;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final device in devices) ...[
            Semantics(
              label: '${device.name}, ${device.batteryPercent} percent.',
              excludeSemantics: true,
              child: Row(
                children: [
                  Icon(_batteryIconFor(device.batteryPercent), color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      device.name,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${device.batteryPercent}%',
                    style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (device != devices.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
