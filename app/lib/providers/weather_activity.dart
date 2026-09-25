import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../engine/activity.dart';
import 'weather_provider.dart';

/// Same sequencing rule as buildWiFiConnectionActivity — a fresh id per
/// alert so a second severe reading (e.g. thunderstorm following heavy
/// rain, both still "severe") reads as a new arrival rather than the
/// engine silently updating the first one in place.
int _severeWeatherNotificationSequence = 0;

/// Current conditions (§05, Phase 3) — Dashboard tier, persistent, same
/// shape as buildBatteryActivity: a normal resting background state,
/// always available, updated in place via the engine's register()-by-id
/// path.
Activity buildWeatherActivity(WeatherSnapshot snapshot) {
  return Activity(
    id: 'weather',
    priority: ActivityPriority.dashboard,
    collapsedBuilder: (context, state) => _WeatherCollapsed(snapshot: snapshot),
    expandedBuilder: (context, state) => _WeatherExpanded(snapshot: snapshot),
  );
}

/// A self-defined "severe" reading (see WeatherChannel.swift's
/// severeWeatherCodes — Open-Meteo itself has no real alerts endpoint) —
/// Alert tier, transient, same shape as buildWiFiConnectionActivity:
/// announces itself once and ages out after 5s via the engine's own
/// timeout handling.
Activity buildSevereWeatherAlertActivity(WeatherSnapshot snapshot) {
  _severeWeatherNotificationSequence++;
  return Activity(
    id: 'severe-weather-$_severeWeatherNotificationSequence',
    priority: ActivityPriority.alert,
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

/// Which continuous motion [_AnimatedWeatherIcon] runs for a given
/// condition — one per weather state: rotate (sun), pulse (moon), a
/// drifting second cloud, falling droplets, drifting flakes, an
/// occasional lightning flicker, and a drifting second fog layer.
enum _WeatherMotion { rotate, pulse, cloudDrift, rain, snow, flicker, mistDrift }

_WeatherMotion _motionFor(int weatherCode, {required bool isDay}) {
  if (weatherCode <= 1) return isDay ? _WeatherMotion.rotate : _WeatherMotion.pulse;
  if (weatherCode == 45 || weatherCode == 48) return _WeatherMotion.mistDrift;
  if (weatherCode >= 51 && weatherCode <= 67) return _WeatherMotion.rain;
  if (weatherCode >= 71 && weatherCode <= 86) return _WeatherMotion.snow;
  if (weatherCode >= 95) return _WeatherMotion.flicker;
  return _WeatherMotion.cloudDrift;
}

/// The expanded card's weather icon, with a small looping motion layered
/// on top matching the condition — a slow rotation for a sun, a gentle
/// pulse for a moon, a drifting second cloud, drifting droplets/flakes
/// under rain/snow, an occasional flicker for a thunderstorm, a drifting
/// second fog layer. Deliberately subtle and slow (60s per sun rotation,
/// not the kind of snappy motion a button press would use) — this is a P3
/// ambient background activity seen many times a day, not a one-off
/// celebration; the motion should read as alive, not draw the eye.
///
/// Isolated into its own StatefulWidget rather than making the whole
/// [_WeatherExpanded] card stateful — every other activity card in this
/// app is stateless (only the Clock timer/stopwatch views need real state,
/// for a live countdown), so keeping the ticking contained to just the
/// icon itself, not the surrounding stats/layout, matches that convention
/// as closely as the new requirement allows.
class _AnimatedWeatherIcon extends StatefulWidget {
  const _AnimatedWeatherIcon({required this.weatherCode, required this.isDay, required this.size});

  final int weatherCode;
  final bool isDay;
  final double size;

  @override
  State<_AnimatedWeatherIcon> createState() => _AnimatedWeatherIconState();
}

class _AnimatedWeatherIconState extends State<_AnimatedWeatherIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = _iconFor(widget.weatherCode, isDay: widget.isDay);
    final motion = _motionFor(widget.weatherCode, isDay: widget.isDay);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        switch (motion) {
          case _WeatherMotion.rotate:
            return Transform.rotate(angle: t * 2 * math.pi, child: child);
          case _WeatherMotion.pulse:
            // The shared controller's own cycle (60s, matching the sun's
            // rotation/other motions) is far too slow for a symmetric
            // grow-shrink to read as motion at all — a pulse needs real
            // speed to register as breathing rather than just sitting
            // still. Matches a 2s period, ±5% scale. `pulsePhase` derives
            // its own faster, seamlessly-looping 0→1 cycle from the same
            // shared `t` (elapsedSeconds is a real wall-clock value here,
            // so % never needs to account for t's own 60s wraparound)
            // rather than needing a second AnimationController just for
            // this.
            final elapsedSeconds = t * 60;
            final pulsePhase = (elapsedSeconds % 2.0) / 2.0;
            final scale = 1.0 + 0.05 * (0.5 - 0.5 * math.cos(pulsePhase * 2 * math.pi));
            return Transform.scale(scale: scale, child: child);
          case _WeatherMotion.rain:
          case _WeatherMotion.snow:
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                child!,
                ..._fallingParticles(motion: motion, t: t, iconSize: widget.size),
              ],
            );
          case _WeatherMotion.flicker:
            // Three short loops per 60s cycle, each a quick brighten-dim —
            // reads as an occasional flash, not a strobe, since most of
            // each loop has no flicker happening at all.
            final cyclePosition = (t * 3) % 1.0;
            final opacity = cyclePosition < 0.08 ? 0.5 + 0.5 * (1 - (cyclePosition / 0.08 - 0.5).abs() * 2) : 1.0;
            return Opacity(opacity: opacity, child: child);
          case _WeatherMotion.cloudDrift:
            // A second, smaller cloud sliding side to side beneath the
            // main one — one continuous drift.
            final driftX = widget.size * 0.18 * math.sin(t * 2 * math.pi);
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                child!,
                Positioned(
                  left: -widget.size * 0.28 + driftX,
                  top: widget.size * 0.1,
                  child: Icon(LucideIcons.cloud, color: Colors.white38, size: widget.size * 0.62),
                ),
              ],
            );
          case _WeatherMotion.mistDrift:
            // A second fog layer drifting left-right with its own opacity
            // pulse — position AND opacity both animating, not just one.
            final driftX = widget.size * 0.35 * math.sin(t * 2 * math.pi);
            final layerOpacity = 0.3 + 0.3 * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                child!,
                Positioned(
                  left: driftX,
                  child: Opacity(opacity: layerOpacity, child: Icon(icon, color: Colors.white, size: widget.size)),
                ),
              ],
            );
        }
      },
      child: Icon(icon, color: Colors.white, size: widget.size),
    );
  }

  List<Widget> _fallingParticles({required _WeatherMotion motion, required double t, required double iconSize}) {
    final isRain = motion == _WeatherMotion.rain;
    final count = 3;
    return List.generate(count, (i) {
      // Each particle offset in its own phase of the loop, so they don't
      // all fall in lockstep — a real (if light) rain/snow feel rather
      // than one droplet repeated three times.
      final phase = (t + i / count) % 1.0;
      final dy = -iconSize * 0.3 + phase * iconSize * 1.1;
      final dx = isRain ? 0.0 : (i.isEven ? 1 : -1) * 3 * math.sin(phase * 2 * math.pi);
      final opacity = phase < 0.15 ? phase / 0.15 : (phase > 0.85 ? (1.0 - phase) / 0.15 : 1.0);
      return Positioned(
        left: iconSize / 2 - (isRain ? 8 : 10) + i * (isRain ? 6 : 8) - (count - 1) * (isRain ? 3 : 4),
        top: iconSize / 2 + dy,
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: isRain
                ? Container(width: 2, height: 6, decoration: BoxDecoration(color: Colors.lightBlueAccent, borderRadius: BorderRadius.circular(1)))
                : Container(width: 3, height: 3, decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle)),
          ),
        ),
      );
    });
  }
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
        '$tempRounded degrees, $condition'
        '${snapshot.placeName != null ? ', ${snapshot.placeName}' : ''}'
        ', feels like $feelsLikeRounded degrees. '
        '${snapshot.humidityPercent.round()} percent humidity. '
        'Wind ${snapshot.windSpeedKmh.round()} kilometers per hour from the ${_compassDirection(snapshot.windDirectionDegrees)}. '
        'UV index ${snapshot.uvIndex.round()}.';

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
                _AnimatedWeatherIcon(weatherCode: snapshot.weatherCode, isDay: snapshot.isDay, size: 40),
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
                      // Only rendered once CLGeocoder has actually
                      // resolved a name (LocationProvider.swift) — omitted
                      // entirely rather than showing a placeholder for the
                      // brief window right after a fresh launch where the
                      // coordinate fix has arrived but the separate
                      // reverse-geocode round-trip hasn't yet.
                      if (snapshot.placeName != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.mapPin, color: Colors.white60, size: 11),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                snapshot.placeName!,
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
                _WeatherStat(value: 'UV ${snapshot.uvIndex.round()}', caption: 'UV Index'),
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
