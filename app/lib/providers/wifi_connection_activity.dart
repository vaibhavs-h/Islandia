import 'package:flutter/material.dart';

import '../engine/activity.dart';

/// Each call gets its own id (see buildBluetoothConnectionActivity, the
/// same shape for the other kind of thing a Mac connects to) instead of
/// sharing one fixed string — a fast disconnect-then-reconnect (or a
/// network switch, itself a disconnect+connect pair — see
/// WiFiConnectionChannel.handleSSIDChange) needs to read as distinct
/// arrivals, not one activity quietly changing its mind mid-display.
int _wifiNotificationSequence = 0;

/// A Wi-Fi network joining or leaving (§05, v1 tier) — P2 important,
/// transient, same shape as the Bluetooth connection notification:
/// announces itself once and ages out on its own after 5s via the engine's
/// own timeout handling.
Activity buildWiFiConnectionActivity({required String networkName, required bool connected}) {
  _wifiNotificationSequence++;
  return Activity(
    id: 'wifi-connection-$_wifiNotificationSequence',
    priority: ActivityPriority.alert,
    isTransient: true,
    autoDismissAfter: const Duration(seconds: 5),
    // Collapsed and expanded used to share one widget instance at one
    // size — bumping the size to better fill the expanded card's own
    // full 360x136 box (see island_shell.dart's _sizedOverlay) leaked
    // into the collapsed pill too, where the same size instead pushed
    // the network name into ellipsis at a width that used to fit it
    // (confirmed live: "Airtel_geri_42" truncated at the larger size
    // that hadn't truncated before). Two distinct widgets now, so each
    // view's size can be tuned for its own actual box.
    collapsedBuilder: (context, state) => _WiFiConnectionContent(networkName: networkName, connected: connected, expanded: false),
    expandedBuilder: (context, state) => _WiFiConnectionContent(networkName: networkName, connected: connected, expanded: true),
  );
}

class _WiFiConnectionContent extends StatelessWidget {
  const _WiFiConnectionContent({required this.networkName, required this.connected, required this.expanded});

  final String networkName;
  final bool connected;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final statusText = connected ? 'connected' : 'disconnected';
    final iconSize = expanded ? 20.0 : 18.0;
    final fontSize = expanded ? 17.0 : 15.0;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(connected ? Icons.wifi : Icons.wifi_off, color: Colors.white, size: iconSize),
        SizedBox(width: expanded ? 10 : 9),
        Flexible(
          child: Text(
            '$networkName $statusText',
            style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: expanded ? FontWeight.w600 : FontWeight.normal),
            overflow: TextOverflow.ellipsis,
            textAlign: expanded ? TextAlign.center : TextAlign.start,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        label: '$networkName $statusText.',
        excludeSemantics: true,
        liveRegion: true,
        // Centered only in the expanded card, which actually has real
        // spare width to center within — the collapsed pill stays
        // left-aligned exactly as it always was.
        child: expanded ? Center(child: row) : row,
      ),
    );
  }
}
