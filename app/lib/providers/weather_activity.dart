import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../engine/activity.dart';
import 'weather_provider.dart';

/// Same sequencing rule as buildWiFiConnectionActivity — a fresh id per
/// alert so a second severe reading (e.g. thunderstorm following heavy
/// rain, both still "severe") reads as a new arrival rather than the
/// engine silently updating the first one in place.
int _severeWeatherNotificationSequence = 0;

/// Current conditions (§05, Phase 3) — P3 ambient, persistent, same shape
/// as buildBatteryActivity: a normal resting background state, always
/// available, updated in place via the engine's register()-by-id path.
Activity buildWeatherActivity(WeatherSnapshot snapshot) {
  return Activity(
    id: 'weather',
    priority: ActivityPriority.p3Ambient,
    collapsedBuilder: (context, state) => _WeatherCollapsed(snapshot: snapshot),
    expandedBuilder: (context, state) => _WeatherExpanded(snapshot: snapshot),
  );
}

/// A self-defined "severe" reading (see WeatherChannel.swift's
/// severeWeatherCodes — Open-Meteo itself has no real alerts endpoint) —
/// P2 important, transient, same shape as buildWiFiConnectionActivity:
/// announces itself once and ages out after 5s via the engine's own
/// timeout handling.
Activity buildSevereWeatherAlertActivity(WeatherSnapshot snapshot) {
  _severeWeatherNotificationSequence++;
  return Activity(
    id: 'severe-weather-$_severeWeatherNotificationSequence',
    priority: ActivityPriority.p2Important,
    isTransient: true,
    autoDismissAfter: const Duration(seconds: 5),
    collapsedBuilder: (context, state) => _SevereWeatherAlertContent(snapshot: snapshot, expanded: false),
    expandedBuilder: (context, state) => _SevereWeatherAlertContent(snapshot: snapshot, expanded: true),
  );
}

/// Lucide's icon set (lucide.dev, via the `lucide_icons_flutter` package —
/// the plain `lucide_icons` package's IconData subclass fails to compile
/// against this Flutter SDK's now-sealed/final IconData; this package
/// constructs plain font-based IconData literals instead, which stays
/// compatible) — chosen specifically to match a reference weather-widget
/// design's own icon choices exactly (Sun/Moon/Cloud/CloudRain/Snowflake/
/// CloudLightning/CloudFog/Thermometer), not Material's built-in
/// weather-ish icons.
///
/// Only the clear-sky case (WMO 0-1, "clear"/"mainly clear") varies by
/// [isDay] — a sun by day, a moon by night, via Open-Meteo's own `is_day`
/// field (real sunrise/sunset for that location, not a client-side clock
/// guess). Every other condition (cloudy, rain, snow, etc.) keeps one icon
/// regardless of time of day, matching the reference — only its Sun/Moon
/// pair varies by isDay too.
IconData _iconFor(int weatherCode, {required bool isDay}) {
  if (weatherCode <= 1) return isDay ? LucideIcons.sun : LucideIcons.moon;
  if (weatherCode <= 3) return LucideIcons.cloud;
  if (weatherCode == 45 || weatherCode == 48) return LucideIcons.cloudFog;
  if (weatherCode >= 51 && weatherCode <= 67) return LucideIcons.cloudRain;
  if (weatherCode >= 71 && weatherCode <= 86) return LucideIcons.snowflake;
  if (weatherCode >= 95) return LucideIcons.cloudLightning;
  return LucideIcons.thermometer;
}

String _conditionFor(int weatherCode) {
  if (weatherCode == 0) return 'Clear';
  if (weatherCode <= 3) return 'Cloudy';
  if (weatherCode == 45 || weatherCode == 48) return 'Foggy';
  if (weatherCode >= 51 && weatherCode <= 57) return 'Drizzle';
  if (weatherCode >= 61 && weatherCode <= 67) return 'Rain';
  if (weatherCode >= 71 && weatherCode <= 86) return 'Snow';
  if (weatherCode >= 95) return 'Thunderstorm';
  return 'Cloudy';
}

/// The 16-point compass rose — far more glanceable in a small card than a
/// bare "117°", the same tradeoff every weather app makes for this figure.
String _compassDirection(double degrees) {
  const directions = [
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
  ];
  final index = ((degrees % 360) / 22.5).round() % 16;
  return directions[index];
}

class _WeatherCollapsed extends StatelessWidget {
  const _WeatherCollapsed({required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tempRounded = snapshot.temperatureCelsius.round();
    return Semantics(
      label: '$tempRounded degrees, ${_conditionFor(snapshot.weatherCode)}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(_iconFor(snapshot.weatherCode, isDay: snapshot.isDay), color: Colors.white, size: 18),
            const SizedBox(width: 9),
            Text('$tempRounded°', style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

/// One stat in the expanded card's bottom row — a value with a caption
/// underneath naming what it is, so nothing requires guessing at a glance
/// (an earlier icon-only version was unclear: a gauge or a droplet icon
/// alone doesn't say "pressure" or "precipitation" on its own). Divided
/// from its neighbors by a hairline, the same idea as a stats bar in a
/// sports score card — one clean row, not a grid of icons.
class _WeatherStat extends StatelessWidget {
  const _WeatherStat({required this.value, required this.caption});

  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(color: Colors.white60, fontSize: 10.5),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A single hairline between two [_WeatherStat]s — visually separates the
/// row into distinct fields without needing a boxed/card look for each one.
class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 28, width: 1, color: Colors.white24);
  }
}

class _WeatherExpanded extends StatelessWidget {
  const _WeatherExpanded({required this.snapshot});

  final WeatherSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tempRounded = snapshot.temperatureCelsius.round();
    final feelsLikeRounded = snapshot.apparentTemperatureCelsius.round();
    final condition = _conditionFor(snapshot.weatherCode);

    final semanticLabel =
        '$tempRounded degrees, $condition, feels like $feelsLikeRounded degrees. '
        '${snapshot.humidityPercent.round()} percent humidity. '
        'Wind ${snapshot.windSpeedKmh.round()} kilometers per hour from the ${_compassDirection(snapshot.windDirectionDegrees)}.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Semantics(
        label: semanticLabel,
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(_iconFor(snapshot.weatherCode, isDay: snapshot.isDay), color: Colors.white, size: 40),
                const SizedBox(width: 14),
                Text(
                  '$tempRounded°',
                  style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 14),
                // Flexible, not a bare Column — a long condition name
                // ("Thunderstorm") next to a wide negative temperature
                // ("-12°") can exceed the card's actual width; this is
                // what expanded_layouts_overflow_test.dart's extreme-value
                // cases caught (a real RenderFlex overflow, not a
                // hypothetical one) before this was added.
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        condition,
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Feels like $feelsLikeRounded°',
                        style: const TextStyle(color: Colors.white60, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _WeatherStat(value: '${snapshot.humidityPercent.round()}%', caption: 'Humidity'),
                const _StatDivider(),
                _WeatherStat(
                  value: '${snapshot.windSpeedKmh.round()} km/h ${_compassDirection(snapshot.windDirectionDegrees)}',
                  caption: 'Wind',
                ),
                const _StatDivider(),
                _WeatherStat(value: '${snapshot.precipitationMillimeters.toStringAsFixed(1)} mm', caption: 'Precipitation'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SevereWeatherAlertContent extends StatelessWidget {
  const _SevereWeatherAlertContent({required this.snapshot, required this.expanded});

  final WeatherSnapshot snapshot;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final condition = _conditionFor(snapshot.weatherCode);
    final label = '$condition warning';
    final iconSize = expanded ? 20.0 : 18.0;
    final fontSize = expanded ? 17.0 : 15.0;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_amber_rounded, color: Colors.white, size: iconSize),
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
        label: '$label.',
        excludeSemantics: true,
        liveRegion: true,
        child: expanded ? Center(child: row) : row,
      ),
    );
  }
}
