import 'package:flutter/services.dart';

/// One current-conditions reading — see WeatherChannel.swift for where
/// this comes from (Open-Meteo, gated behind Location Services
/// authorization, polled hourly since the API has no push mechanism).
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureCelsius,
    required this.apparentTemperatureCelsius,
    required this.humidityPercent,
    required this.weatherCode,
    required this.isSevere,
    required this.isDay,
    required this.uvIndex,
    required this.windSpeedKmh,
    required this.windDirectionDegrees,
    this.placeName,
  });

  final double temperatureCelsius;

  /// "Feels like" — Open-Meteo's own apparent_temperature, which factors
  /// in humidity and wind rather than just the raw air reading.
  final double apparentTemperatureCelsius;

  final double humidityPercent;
  final int weatherCode;

  /// True when [weatherCode] falls in WeatherChannel's own severeWeatherCodes
  /// set — a self-defined approximation from conditions data, not real
  /// government alert data (Open-Meteo exposes no alerts endpoint at all).
  final bool isSevere;

  /// Real day/night state for the reading's own location, from Open-
  /// Meteo's own `is_day` field (computed against that location's actual
  /// sunrise/sunset for the day) — not derived from the device's own
  /// clock, which would be wrong the instant this is read anywhere but
  /// the user's own timezone.
  final bool isDay;

  final double uvIndex;
  final double windSpeedKmh;
  final double windDirectionDegrees;

  /// The reverse-geocoded city name for this reading's coordinates, via
  /// CLGeocoder (LocationProvider.swift) — nil on the very first reading
  /// after a fresh launch (a real, separate async round-trip from the
  /// coordinate fix itself, so it can legitimately not have resolved yet)
  /// or whenever CLGeocoder's own reverse-geocode fails for that tick.
  final String? placeName;
}

/// Current weather (§05, Phase 3) via Open-Meteo — the app's first
/// networked data source; every other provider here reads purely local
/// system state. Native already hands over one complete reading per poll
/// tick, nothing to diff here, just forward each one — same shape as
/// WiFiConnectionProvider.
class WeatherProvider {
  WeatherProvider._();

  static const EventChannel _channel = EventChannel('islandia/weather/updates');

  static Stream<WeatherSnapshot> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<String, Object?>();
      return WeatherSnapshot(
        temperatureCelsius: (map['temperatureCelsius'] as num).toDouble(),
        apparentTemperatureCelsius: (map['apparentTemperatureCelsius'] as num).toDouble(),
        humidityPercent: (map['humidityPercent'] as num).toDouble(),
        weatherCode: map['weatherCode'] as int,
        isSevere: map['isSevere'] as bool,
        isDay: map['isDay'] as bool,
        uvIndex: (map['uvIndex'] as num).toDouble(),
        windSpeedKmh: (map['windSpeedKmh'] as num).toDouble(),
        windDirectionDegrees: (map['windDirectionDegrees'] as num).toDouble(),
        placeName: map['placeName'] as String?,
      );
    }).handleError((Object _) {});
  }
}
