import Cocoa
import FlutterMacOS

/// Current conditions via Open-Meteo (§05, Phase 3) — the app's first
/// outbound network call of any kind; every other provider here reads
/// purely local system state. No API key/account needed on Open-Meteo's
/// free tier (non-commercial use only — see open-meteo.com/en/terms), so
/// this is a plain unauthenticated HTTPS GET.
///
/// Location comes from LocationProvider (shared with CalamityAlertChannel,
/// see that file's own doc comment for why the fetch was pulled out into
/// one shared owner) rather than this file running its own
/// `CLLocationManager` — this only reads the latest coordinate LocationProvider
/// already has, on its own separate hourly cadence for re-fetching the
/// weather API itself (conditions don't need to be re-checked as often as
/// position does).
final class WeatherChannel: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var pollTimer: Timer?
  private var urlSessionTask: URLSessionDataTask?
  private var hasStartedListening = false

  /// The city name for wherever the weather fetch's own coordinates came
  /// from — held here so a poll-timer-triggered refetch (no fresh
  /// LocationProvider callback involved) still has a name to include in
  /// its payload, not just the listener-triggered ones.
  private var latestPlaceName: String?

  /// Matches ClockActivityChannel's own poll-rate doc-comment convention:
  /// Open-Meteo has no push API, so this is necessarily polled. Once an
  /// hour is far more than enough for how often conditions meaningfully
  /// change, and stays trivially under the free tier's 5,000/hour limit
  /// even accounting for retries.
  private static let pollInterval: TimeInterval = 3600

  /// The WMO weather codes (open-meteo.com/en/docs) treated as "severe"
  /// for the P2 alert activity — the genuinely disruptive/hazardous end
  /// of the scale (heavy/freezing rain, heavy snow, violent showers,
  /// thunderstorms), not routine light/moderate conditions. Open-Meteo
  /// itself exposes no alerts/warnings endpoint at all (confirmed against
  /// their docs and an open, unaddressed feature request in their own
  /// GitHub discussions) — this is a deliberate approximation derived
  /// from conditions data already being fetched, not real government
  /// alert data.
  private static let severeWeatherCodes: Set<Int> = [65, 66, 67, 75, 82, 95, 96, 99]

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/weather/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    LocationProvider.shared.start()
    guard !hasStartedListening else { return nil }
    hasStartedListening = true

    LocationProvider.shared.addListener { [weak self] coordinate, placeName in
      self?.latestPlaceName = placeName
      self?.fetchWeather(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      guard let coordinate = LocationProvider.shared.latestCoordinate else { return }
      self?.latestPlaceName = LocationProvider.shared.latestPlaceName
      self?.fetchWeather(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    pollTimer?.invalidate()
    pollTimer = nil
    urlSessionTask?.cancel()
    urlSessionTask = nil
    eventSink = nil
    return nil
  }

  private func fetchWeather(latitude: Double, longitude: Double) {
    urlSessionTask?.cancel()
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    components.queryItems = [
      URLQueryItem(name: "latitude", value: String(latitude)),
      URLQueryItem(name: "longitude", value: String(longitude)),
      URLQueryItem(
        name: "current",
        value: [
          "temperature_2m", "apparent_temperature", "relative_humidity_2m", "weather_code", "is_day",
          "uv_index", "wind_speed_10m", "wind_direction_10m",
        ].joined(separator: ",")
      ),
      // Celsius is Open-Meteo's own default (no temperature_unit param
      // needed) — explicit here anyway so a future reader doesn't have to
      // know that to be sure this isn't accidentally Fahrenheit.
      URLQueryItem(name: "temperature_unit", value: "celsius"),
    ]
    guard let url = components.url else { return }

    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
      guard let self, error == nil, let data else { return }
      guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let current = json["current"] as? [String: Any],
        // JSONSerialization gives some of these back as Int and others as
        // Double depending on whether Open-Meteo happened to serialize
        // that particular value with a decimal point (confirmed live:
        // relative_humidity_2m/wind_direction_10m come back as bare ints,
        // temperature/wind_speed etc. as doubles) — going through
        // NSNumber.doubleValue instead of a strict `as? Double`/`as? Int`
        // cast means neither shape can silently fail this whole guard
        // chain if Open-Meteo's own serialization for a field ever shifts
        // between the two.
        let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
        let apparentTemperature = (current["apparent_temperature"] as? NSNumber)?.doubleValue,
        let humidity = (current["relative_humidity_2m"] as? NSNumber)?.doubleValue,
        let weatherCode = (current["weather_code"] as? NSNumber)?.intValue,
        // 1 if the current time step has daylight, 0 at night — Open-
        // Meteo's own field, computed per-location from real sunrise/
        // sunset for that day, not a client-side clock-time guess.
        let isDay = (current["is_day"] as? NSNumber)?.intValue,
        let uvIndex = (current["uv_index"] as? NSNumber)?.doubleValue,
        let windSpeed = (current["wind_speed_10m"] as? NSNumber)?.doubleValue,
        let windDirection = (current["wind_direction_10m"] as? NSNumber)?.doubleValue
      else { return }

      DispatchQueue.main.async {
        self.eventSink?([
          "temperatureCelsius": temperature,
          "apparentTemperatureCelsius": apparentTemperature,
          "humidityPercent": humidity,
          "weatherCode": weatherCode,
          "isSevere": Self.severeWeatherCodes.contains(weatherCode),
          "isDay": isDay == 1,
          "uvIndex": uvIndex,
          "windSpeedKmh": windSpeed,
          "windDirectionDegrees": windDirection,
          // May still be nil here — CLGeocoder's reverse-geocode is a
          // separate, slower round-trip than the coordinate fix itself,
          // so the very first weather reading after a fresh launch can
          // legitimately arrive before a name has resolved. Dart's own
          // side just omits the location row for that one reading.
          "placeName": self.latestPlaceName as Any,
        ])
      }
    }
    urlSessionTask = task
    task.resume()
  }
}
