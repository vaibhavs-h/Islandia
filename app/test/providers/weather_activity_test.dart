import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/providers/weather_activity.dart';
import 'package:islandia/providers/weather_provider.dart';

/// A fully-populated, plausible snapshot with sensible defaults for every
/// field — tests override only the ones they actually care about, rather
/// than repeating all 13 named params in every single test.
WeatherSnapshot _snapshot({
  double temperatureCelsius = 22,
  double apparentTemperatureCelsius = 22,
  double humidityPercent = 50,
  int weatherCode = 0,
  bool isSevere = false,
  bool isDay = true,
  double precipitationMillimeters = 0,
  double cloudCoverPercent = 20,
  double pressureMsl = 1013,
  double windSpeedKmh = 10,
  double windDirectionDegrees = 0,
  double windGustsKmh = 15,
  double dewPointCelsius = 12,
  double uvIndex = 3,
}) {
  return WeatherSnapshot(
    temperatureCelsius: temperatureCelsius,
    apparentTemperatureCelsius: apparentTemperatureCelsius,
    humidityPercent: humidityPercent,
    weatherCode: weatherCode,
    isSevere: isSevere,
    isDay: isDay,
    precipitationMillimeters: precipitationMillimeters,
    cloudCoverPercent: cloudCoverPercent,
    pressureMsl: pressureMsl,
    windSpeedKmh: windSpeedKmh,
    windDirectionDegrees: windDirectionDegrees,
    windGustsKmh: windGustsKmh,
    dewPointCelsius: dewPointCelsius,
    uvIndex: uvIndex,
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
      expect(find.byIcon(Icons.wb_sunny), findsOneWidget);
      expect(find.bySemanticsLabel('30 degrees, Clear.'), findsOneWidget);
    });

    testWidgets('a clear sky at night shows the moon icon, not the sun', (tester) async {
      final activity = buildWeatherActivity(_snapshot(weatherCode: 0, isDay: false));
      await pumpCollapsed(tester, activity);

      expect(find.byIcon(Icons.nights_stay), findsOneWidget);
      expect(find.byIcon(Icons.wb_sunny), findsNothing);
    });

    testWidgets('"mainly clear" (code 1) gets the same sun/moon treatment as "clear" (code 0)', (tester) async {
      final activity = buildWeatherActivity(_snapshot(weatherCode: 1, isDay: true));
      await pumpCollapsed(tester, activity);
      expect(find.byIcon(Icons.wb_sunny), findsOneWidget);
    });

    testWidgets('a non-clear condition (rain) shows the same icon regardless of day or night', (tester) async {
      final activity = buildWeatherActivity(_snapshot(weatherCode: 61, isDay: false));
      await pumpCollapsed(tester, activity);

      // No day/night variant exists for rain — should still be the plain
      // rain-drop icon, never a moon, since is_day only ever branches the
      // clear-sky case.
      expect(find.byIcon(Icons.water_drop), findsOneWidget);
      expect(find.byIcon(Icons.nights_stay), findsNothing);
    });

    testWidgets('always registers under the fixed "weather" id, like battery', (tester) async {
      final activity = buildWeatherActivity(_snapshot());

      expect(activity.id, 'weather');
      expect(activity.priority, ActivityPriority.p3Ambient);
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
      expect(find.byIcon(Icons.water_drop), findsWidgets);
    });

    testWidgets('a thunderstorm code maps to the thunderstorm icon and label', (tester) async {
      final activity = buildWeatherActivity(_snapshot(weatherCode: 95, isSevere: true));
      await pumpExpanded(tester, activity);

      expect(find.text('Thunderstorm'), findsOneWidget);
      expect(find.byIcon(Icons.thunderstorm), findsOneWidget);
    });

    testWidgets('shows all 7 stats across the two rows, each with its own icon', (tester) async {
      final activity = buildWeatherActivity(
        _snapshot(humidityPercent: 65, windSpeedKmh: 12, windDirectionDegrees: 90, pressureMsl: 1008, precipitationMillimeters: 1.5),
      );
      await pumpExpanded(tester, activity);

      expect(find.text('65%'), findsOneWidget);
      expect(find.text('12 km/h E'), findsOneWidget);
      expect(find.text('1008 hPa'), findsOneWidget);
      expect(find.text('1.5 mm'), findsOneWidget);
      expect(find.byIcon(Icons.water_drop), findsWidgets);
      expect(find.byIcon(Icons.air), findsOneWidget);
      expect(find.byIcon(Icons.speed), findsOneWidget);
      expect(find.byIcon(Icons.opacity), findsOneWidget);
      expect(find.byIcon(Icons.thermostat), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
      expect(find.byIcon(Icons.storm), findsOneWidget);
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

      expect(activity.priority, ActivityPriority.p2Important);
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
}
