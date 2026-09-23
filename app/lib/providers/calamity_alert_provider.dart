import 'package:flutter/services.dart';

/// One nearby disaster event — see CalamityAlertChannel.swift for where
/// this comes from (USGS for earthquakes/tsunami risk, GDACS for
/// floods/cyclones/volcanoes/wildfires/droughts), already filtered to
/// within 300km of the user's own location.
class CalamityAlert {
  const CalamityAlert({required this.id, required this.kind, required this.headline, required this.place, required this.source});

  final String id;
  final String kind;
  final String headline;
  final String place;

  /// "usgs" or "gdacs" — see buildCalamityAlertActivity's own doc comment
  /// for why this distinction stays visible rather than presenting both
  /// as equally official.
  final String source;
}

/// Nearby natural-disaster alerts (§05, Phase 3). Native already hands
/// over one complete, already-filtered event per emission, nothing to
/// diff here — same shape as WiFiConnectionProvider/WeatherProvider.
class CalamityAlertProvider {
  CalamityAlertProvider._();

  static const EventChannel _channel = EventChannel('islandia/calamity-alert/updates');

  static Stream<CalamityAlert> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<String, Object?>();
      return CalamityAlert(
        id: map['id'] as String,
        kind: map['kind'] as String,
        headline: map['headline'] as String,
        place: map['place'] as String,
        source: map['source'] as String,
      );
    }).handleError((Object _) {});
  }
}
