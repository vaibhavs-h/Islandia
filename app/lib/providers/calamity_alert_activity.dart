import 'package:flutter/material.dart';

import '../engine/activity.dart';
import 'calamity_alert_provider.dart';

/// A nearby natural-disaster alert (§05, Phase 3) — P2 important,
/// transient, same shape as buildWiFiConnectionActivity/
/// buildSevereWeatherAlertActivity: announces itself once and ages out
/// after 5s via the engine's own timeout handling. Deduped by the
/// [CalamityAlert.id] island_shell.dart already tracked before calling
/// this — native re-emits the same event on every poll tick it's still in
/// USGS/GDACS's own feed, so this only ever gets called once per genuinely
/// new event, not once per tick.
Activity buildCalamityAlertActivity(CalamityAlert alert) {
  return Activity(
    id: 'calamity-${alert.id}',
    priority: ActivityPriority.alert,
    isTransient: true,
    autoDismissAfter: const Duration(seconds: 5),
    collapsedBuilder: (context, state) => _CalamityAlertContent(alert: alert, expanded: false),
    expandedBuilder: (context, state) => _CalamityAlertContent(alert: alert, expanded: true),
  );
}

IconData _iconFor(String kind) {
  switch (kind) {
    case 'earthquake':
      return Icons.vibration;
    case 'tsunami':
      return Icons.tsunami;
    case 'flood':
      return Icons.water;
    case 'cyclone':
      return Icons.cyclone;
    case 'volcano':
      return Icons.landscape;
    case 'wildfire':
      return Icons.local_fire_department;
    case 'drought':
      return Icons.grain;
    default:
      return Icons.warning_amber_rounded;
  }
}

class _CalamityAlertContent extends StatelessWidget {
  const _CalamityAlertContent({required this.alert, required this.expanded});

  final CalamityAlert alert;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final label = alert.place.isEmpty ? alert.headline : '${alert.headline}, ${alert.place}';
    final iconSize = expanded ? 20.0 : 18.0;
    final fontSize = expanded ? 17.0 : 15.0;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_iconFor(alert.kind), color: Colors.white, size: iconSize),
        SizedBox(width: expanded ? 10 : 9),
        Flexible(
          child: Text(
            label,
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
        // GDACS's flood/cyclone/volcano/wildfire/drought data is itself
        // aggregated and risk-scored by GDACS from other feeds, not
        // verbatim government warning text the way USGS's earthquake data
        // (a direct seismic-network reading) or NWS's alerts (literal
        // government bulletins) are — named here so a screen reader
        // doesn't imply more official certainty than the data actually
        // carries. See CalamityAlertChannel.swift's own doc comment.
        label: alert.source == 'gdacs' ? '$label. Source: GDACS disaster monitoring.' : '$label.',
        excludeSemantics: true,
        liveRegion: true,
        child: expanded ? Center(child: row) : row,
      ),
    );
  }
}
