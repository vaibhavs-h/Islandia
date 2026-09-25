import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/providers/weather_activity.dart';
import 'package:islandia/providers/weather_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A fully-populated, plausible snapshot with sensible defaults for every
/// field — tests override only the ones they actually care about, rather
/// than repeating all 10 named params in every single test. placeName
/// defaults to null (unresolved), matching the real first-reading-after-
/// launch case, not an arbitrary placeholder city.
WeatherSnapshot _snapshot({
  double temperatureCelsius = 22,
  double apparentTemperatureCelsius = 22,
  double humidityPercent = 50,
  int weatherCode = 0,
  bool isSevere = false,
  bool isDay = true,
  double uvIndex = 3,
  double windSpeedKmh = 10,
  double windDirectionDegrees = 0,
  String? placeName,
}) {
  return WeatherSnapshot(
    temperatureCelsius: temperatureCelsius,
    apparentTemperatureCelsius: apparentTemperatureCelsius,
    humidityPercent: humidityPercent,
    weatherCode: weatherCode,
    isSevere: isSevere,
    isDay: isDay,
    uvIndex: uvIndex,
    windSpeedKmh: windSpeedKmh,
    windDirectionDegrees: windDirectionDegrees,
    placeName: placeName,
  );
}

void main() {
  Future<void> pumpCollapsed(WidgetTester tester, Activity activity) {
    return tester.pumpWidget(
      MaterialApp(
        home: Material(child: Builder(builder: (context) => activity.collapsedBuilder(context, LifecycleState.collapsed))),
      ),
    );
  }

  Future<void> pumpExpanded(WidgetTester tester, Activity activity) {
    return tester.pumpWidget(
      MaterialApp(
        home: Material(child: Builder(builder: (context) => activity.expandedBuilder(context, LifecycleState.expanded))),
      ),
    );
  }

  group('current conditions — collapsed view', () {
    testWidgets('shows a rounded temperature and condition icon', (tester) async {
      final activity = buildWeatherActivity(_snapshot(temperatureCelsius: 30.4, weatherCode: 0, isDay: true));
      await pumpCollapsed(tester, activity);

      expect(find.text('30°'), findsOneWidget);
      expect(find.byIcon(LucideIcons.sun), findsOneWidget);
      expect(find.bySemanticsLabel('30 degrees, Clear.'), findsOneWidget);
    });

    testWidgets('a clear sky at night shows the moon icon, not the sun', (tester) async {
      final activity = buildWeatherActivity(_snapshot(weatherCode: 0, isDay: false));
      await pumpCollapsed(tester, activity);

      expect(find.byIcon(LucideIcons.moon), findsOneWidget);
      expect(find.byIcon(LucideIcons.sun), findsNothing);
    });

    testWidgets('"mainly clear" (code 1) gets the same sun/moon treatment as "clear" (code 0)', (tester) async {
      final activity = buildWeatherActivity(_snapshot(weatherCode: 1, isDay: true));
      await pumpCollapsed(tester, activity);
      expect(find.byIcon(LucideIcons.sun), findsOneWidget);
    });

    testWidgets('a non-clear condition (rain) shows the same icon regardless of day or night', (tester) async {
      final activity = buildWeatherActivity(_snapshot(weatherCode: 61, isDay: false));
      await pumpCollapsed(tester, activity);

      // No day/night variant exists for rain — should still be the plain
      // rain-cloud icon, never a moon, since is_day only ever branches the
      // clear-sky case.
      expect(find.byIcon(LucideIcons.cloudRain), findsOneWidget);
      expect(find.byIcon(LucideIcons.moon), findsNothing);
    });

    testWidgets('always registers under the fixed "weather" id, like battery', (tester) async {
      final activity = buildWeatherActivity(_snapshot());

      expect(activity.id, 'weather');
      expect(activity.priority, ActivityPriority.dashboard);
      expect(activity.isTransient, isFalse);
    });
  });

  group('current conditions — expanded view', () {
    testWidgets('shows temperature, condition name, and feels-like', (tester) async {
      final activity = buildWeatherActivity(
        _snapshot(temperatureCelsius: 11.6, apparentTemperatureCelsius: 9.2, weatherCode: 61),
      );
      await pumpExpanded(tester, activity);

      expect(find.text('12°'), findsOneWidget);
      expect(find.text('Rain'), findsOneWidget);
      expect(find.text('Feels like 9°'), findsOneWidget);
      expect(find.byIcon(LucideIcons.cloudRain), findsWidgets);
    });

    testWidgets('shows the resolved place name, with a pin icon, between the condition and feels-like', (tester) async {
      final activity = buildWeatherActivity(_snapshot(placeName: 'Seattle'));
      await pumpExpanded(tester, activity);

      expect(find.text('Seattle'), findsOneWidget);
      expect(find.byIcon(LucideIcons.mapPin), findsOneWidget);
    });

    testWidgets('omits the location row entirely when the place name has not resolved yet', (tester) async {
      final activity = buildWeatherActivity(_snapshot(placeName: null));
      await pumpExpanded(tester, activity);

      expect(find.byIcon(LucideIcons.mapPin), findsNothing);
    });

    testWidgets('a thunderstorm code maps to the thunderstorm icon and label', (tester) async {
      final activity = buildWeatherActivity(_snapshot(weatherCode: 95, isSevere: true));
      await pumpExpanded(tester, activity);

      expect(find.text('Thunderstorm'), findsOneWidget);
      expect(find.byIcon(LucideIcons.cloudLightning), findsOneWidget);
    });

    testWidgets('shows humidity, wind (with compass direction), and UV index, each with a caption', (tester) async {
      final activity = buildWeatherActivity(
        _snapshot(humidityPercent: 65, windSpeedKmh: 12, windDirectionDegrees: 90, uvIndex: 7.6),
      );
      await pumpExpanded(tester, activity);

      expect(find.text('65%'), findsOneWidget);
      expect(find.text('Humidity'), findsOneWidget);
      expect(find.text('12 km/h E'), findsOneWidget);
      expect(find.text('Wind'), findsOneWidget);
      expect(find.text('UV 8'), findsOneWidget);
      expect(find.text('UV Index'), findsOneWidget);
    });

    testWidgets('shows "UV 0" at night, not a blank value or a hidden stat', (tester) async {
      final activity = buildWeatherActivity(_snapshot(isDay: false, uvIndex: 0));
      await pumpExpanded(tester, activity);

      expect(find.text('UV 0'), findsOneWidget);
    });

    testWidgets('compass direction rounds to the nearest 16-point heading', (tester) async {
      final activity = buildWeatherActivity(_snapshot(windDirectionDegrees: 178, windSpeedKmh: 5));
      await pumpExpanded(tester, activity);

      // 178° is closest to due south (180°) on the 16-point rose.
      expect(find.text('5 km/h S'), findsOneWidget);
    });
  });

  group('severe weather alert', () {
    testWidgets('is P2 important, transient, and auto-dismisses after 5s', (tester) async {
      final activity = buildSevereWeatherAlertActivity(_snapshot(weatherCode: 65, isSevere: true));

      expect(activity.priority, ActivityPriority.alert);
      expect(activity.isTransient, isTrue);
      expect(activity.autoDismissAfter, const Duration(seconds: 5));
    });

    testWidgets('each call gets a distinct id, like the Wi-Fi/Bluetooth notifications', (tester) async {
      final snapshot = _snapshot(weatherCode: 65, isSevere: true);
      final first = buildSevereWeatherAlertActivity(snapshot);
      final second = buildSevereWeatherAlertActivity(snapshot);

      expect(first.id, isNot(second.id));
    });

    testWidgets('collapsed view reads as a warning, left-aligned', (tester) async {
      final activity = buildSevereWeatherAlertActivity(_snapshot(weatherCode: 65, isSevere: true));
      await pumpCollapsed(tester, activity);

      expect(find.text('Rain warning'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('expanded view centers the warning text', (tester) async {
      final activity = buildSevereWeatherAlertActivity(_snapshot(weatherCode: 75, isSevere: true));
      await pumpExpanded(tester, activity);

      expect(find.text('Snow warning'), findsOneWidget);
      expect(find.byType(Center), findsWidgets);
    });
  });

  group('moon pulse animation', () {
    double pulseScaleAt(WidgetTester tester) {
      final transform = tester.widget<Transform>(find.byKey(const ValueKey('weather-pulse-scale')));
      // The X-axis scale term, read directly from the matrix's own raw
      // storage — Matrix4.getMaxScaleOnAxis() is unreliable exactly at
      // 0.0 scale (reports 1.0 for a genuinely zero-scaled matrix), a real
      // quirk confirmed while writing shelf_activity_test.dart's own
      // animation tests; reading storage[0] sidesteps it and reflects the
      // actual value the pulse was built with. Not load-bearing here (the
      // pulse never actually reaches exactly 0.0 scale — its range is
      // 1.0–1.05, nowhere near the degenerate case), but kept as the same
      // reliable technique either way rather than two different patterns
      // for what's really the same kind of assertion.
      return transform.transform.storage[0];
    }

    Future<void> pumpMoonAt(WidgetTester tester, Duration elapsed) async {
      final activity = buildWeatherActivity(_snapshot(weatherCode: 0, isDay: false));
      await tester.pumpWidget(
        MaterialApp(
          home: Material(child: Builder(builder: (context) => activity.expandedBuilder(context, LifecycleState.expanded))),
        ),
      );
      await tester.pump(elapsed);
    }

    testWidgets('starts at rest (scale 1.0) right at the cycle boundary', (tester) async {
      await pumpMoonAt(tester, Duration.zero);
      expect(pulseScaleAt(tester), closeTo(1.0, 0.001));
    });

    testWidgets('is at its largest partway through the expansion segment', (tester) async {
      // pulsePhase cycles every 2s; the expand segment is its first 35%,
      // i.e. the first 700ms — comfortably inside that window, not right
      // at either edge.
      await pumpMoonAt(tester, const Duration(milliseconds: 400));
      final scale = pulseScaleAt(tester);
      expect(scale, greaterThan(1.0));
      expect(scale, lessThan(1.05));
    });

    testWidgets('peaks at the full 5% right at the expand/contract seam, with no jump across it', (tester) async {
      // The seam is at exactly 35% of the 2s cycle = 700ms. Both readings
      // come from the SAME pump/controller, advanced incrementally from
      // 699ms to 701ms — calling pumpMoonAt a second time here would spin
      // up a completely independent controller/ticker rather than
      // advancing the existing one, which measures something else
      // entirely (confirmed while writing this test: two independent
      // 699ms-then-701ms pumpMoonAt calls do NOT read as 2ms apart on the
      // pulse's own timeline at all).
      await pumpMoonAt(tester, const Duration(milliseconds: 699));
      final justBefore = pulseScaleAt(tester);
      await tester.pump(const Duration(milliseconds: 2));
      final justAfter = pulseScaleAt(tester);

      expect(justBefore, closeTo(1.05, 0.002));
      expect(justAfter, closeTo(1.05, 0.002));
      // The whole point of splitting expand/contract into two curves
      // sharing one seam value — this must never read as a visible snap.
      expect((justAfter - justBefore).abs(), lessThan(0.002));
    });

    testWidgets('settles back down through the contract segment, past its halfway point', (tester) async {
      // 1500ms is 75% through the 2s cycle — well into the contract
      // segment (which runs from 700ms to 2000ms), past its own midpoint.
      await pumpMoonAt(tester, const Duration(milliseconds: 1500));
      final scale = pulseScaleAt(tester);
      expect(scale, greaterThan(1.0));
      expect(scale, lessThan(1.03), reason: 'should already be noticeably settled back down, not still near the 1.05 peak');
    });

    testWidgets('returns to rest with no jump across the 2s cycle wraparound', (tester) async {
      // Same reasoning as the expand/contract seam test above — one
      // controller, advanced incrementally, not two independent ones.
      await pumpMoonAt(tester, const Duration(milliseconds: 1999));
      final justBefore = pulseScaleAt(tester);
      await tester.pump(const Duration(milliseconds: 2));
      final justAfter = pulseScaleAt(tester);

      expect(justBefore, closeTo(1.0, 0.002));
      expect(justAfter, closeTo(1.0, 0.002));
      expect((justAfter - justBefore).abs(), lessThan(0.002));
    });
  });
}
