import 'package:flutter/material.dart';

import '../engine/activity.dart';
import '../shell/island_button.dart';
import 'battery_provider.dart';

/// Real battery data (§04/§05, alpha) normalized into the same [Activity]
/// shape every fake and future-real activity uses — the shell above never
/// needs to know this one happens to be backed by IOKit instead of a fake
/// timer.
///
/// [onSimulateCall]/[onStartTimer] are dev-only triggers for exercising the
/// priority-preemption and transient-notification demos — they live here
/// because Battery is the one activity that's reliably always present to
/// reach them from, not because they're conceptually battery-related. They
/// should move out once there's a real way to trigger those flows (an
/// actual incoming call, a real reason to start a timer from the shell).
Activity buildBatteryActivity(
  BatterySnapshot snapshot, {
  required VoidCallback onSimulateCall,
  required VoidCallback onStartTimer,
}) {
  return Activity(
    id: 'battery',
    priority: ActivityPriority.p3Ambient,
    collapsedBuilder: (context, state) => _BatteryCollapsed(snapshot: snapshot),
    expandedBuilder: (context, state) => _BatteryExpanded(
      snapshot: snapshot,
      onSimulateCall: onSimulateCall,
      onStartTimer: onStartTimer,
    ),
  );
}

IconData _iconFor(BatterySnapshot snapshot) {
  if (snapshot.isCharging) return Icons.battery_charging_full;
  if (snapshot.percentageRounded <= 10) return Icons.battery_alert;
  return Icons.battery_full;
}

String _statusLine(BatterySnapshot snapshot) {
  if (snapshot.isCharged && snapshot.isOnACPower) return 'Charged';
  if (snapshot.isCharging) return 'Charging';
  if (snapshot.isOnACPower) return 'On power adapter';
  return 'On battery';
}

class _BatteryCollapsed extends StatelessWidget {
  const _BatteryCollapsed({required this.snapshot});

  final BatterySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Battery, ${snapshot.percentageRounded} percent, ${_statusLine(snapshot)}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(_iconFor(snapshot), color: Colors.white, size: 18),
            const SizedBox(width: 9),
            Text('${snapshot.percentageRounded}%', style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _BatteryExpanded extends StatelessWidget {
  const _BatteryExpanded({
    required this.snapshot,
    required this.onSimulateCall,
    required this.onStartTimer,
  });

  final BatterySnapshot snapshot;
  final VoidCallback onSimulateCall;
  final VoidCallback onStartTimer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            label: 'Battery, ${snapshot.percentageRounded} percent, ${_statusLine(snapshot)}.',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(_iconFor(snapshot), color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('${snapshot.percentageRounded}%', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_statusLine(snapshot), style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: IslandButton(label: 'Simulate incoming call', color: const Color(0xFF33363C), onTap: onSimulateCall),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: IslandButton(label: 'Start 1-min timer', color: const Color(0xFF33363C), onTap: onStartTimer),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
