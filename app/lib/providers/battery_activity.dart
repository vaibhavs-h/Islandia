import 'package:flutter/material.dart';

import '../engine/activity.dart';
import 'battery_provider.dart';

/// Real battery data (§04/§05, alpha) normalized into the same [Activity]
/// shape every fake and future-real activity uses — the shell above never
/// needs to know this one happens to be backed by IOKit instead of a fake
/// timer.
Activity buildBatteryActivity(BatterySnapshot snapshot) {
  return Activity(
    id: 'battery',
    priority: ActivityPriority.p3Ambient,
    collapsedBuilder: (context, state) => _BatteryCollapsed(snapshot: snapshot),
    expandedBuilder: (context, state) => _BatteryExpanded(snapshot: snapshot),
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
  const _BatteryExpanded({required this.snapshot});

  final BatterySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
      // Nothing else lives in this card — no start-a-task buttons; Islandia
      // only ever reflects state, never originates it (§00's whole premise).
      // Centered rather than pinned to the top, so the percentage reads as
      // the one deliberate hero number instead of leaving a slab of empty
      // space where a button row used to be.
      child: Center(
        child: Semantics(
          label: 'Battery, ${snapshot.percentageRounded} percent, ${_statusLine(snapshot)}.',
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_iconFor(snapshot), color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    '${snapshot.percentageRounded}%',
                    style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_statusLine(snapshot), style: const TextStyle(color: Colors.white60, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
