import CoreLocation
import FlutterMacOS

/// Nearby natural-disaster alerts (§05, Phase 3) — earthquakes/tsunami risk
/// from USGS, plus floods/cyclones/volcanoes/wildfires/droughts from
/// GDACS (the UN OCHA + EU Joint Research Centre's Global Disaster Alert
/// and Coordination System). Neither is itself "alerts near me" — both
/// return global event lists — so this is the one place that fetches both,
/// filters by distance from LocationProvider's shared coordinate, and
/// emits only what's actually nearby.
///
/// No single free source covers this whole category (confirmed by
/// research before building this): Open-Meteo has no alerts endpoint at
/// all; OpenWeather's Alerts product is real but paid-only (no free tier);
/// NWS's alerts are free and genuinely government-issued but US-only.
/// USGS + GDACS are both free, keyless, and genuinely global — this is
/// the best available combination, not a complete one. Notably: neither
/// source covers landslides specifically — no free global source for that
/// hazard was found to exist at all.
///
/// GDACS's flood/cyclone/tsunami-risk data is itself aggregated and
/// risk-scored by GDACS from other feeds (GLOFAS, JTWC, seismic networks),
/// not verbatim government warning text the way NWS's alerts are — kept
/// distinct in the payload's `source` field so Dart can label these
/// honestly rather than implying they're official bulletins.
final class CalamityAlertChannel: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var usgsPollTimer: Timer?
  private var gdacsPollTimer: Timer?
  private var usgsTask: URLSessionDataTask?
  private var gdacsTask: URLSessionDataTask?

  /// Matches USGS's own documented 60-second server-side cache (confirmed
  /// against their feed policy) — polling faster returns identical data
  /// and risks their rate limit. This is the fastest polling that's ever
  /// meaningful, not an arbitrary choice.
  private static let usgsPollInterval: TimeInterval = 60

  /// GDACS publishes no documented rate limit or recommended cadence.
  /// These are slow-developing disaster events, not real-time ticks, so
  /// 5 minutes is responsive without hammering an API that states no
  /// ceiling of its own.
  private static let gdacsPollInterval: TimeInterval = 300

  /// How far from the user's own location an event still counts as
  /// "nearby" enough for a P2 alert — wide enough to catch a genuinely
  /// relevant regional event (an offshore quake with tsunami risk, a
  /// major flood in the broader area) without alerting on things
  /// happening in an unrelated neighboring region.
  private static let alertRadiusMeters: CLLocationDistance = 300_000

  /// Earthquakes below this magnitude aren't disaster-alert-worthy even
  /// within range — USGS's own feed tiers go down to M1.0+ (routine,
  /// often unfelt), so this filters to the tier that's actually
  /// significant: M4.5+, USGS's own "moderate and above" threshold.
  private static let minimumMagnitude = 4.5

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/calamity-alert/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    LocationProvider.shared.start()

    LocationProvider.shared.addListener { [weak self] _, _ in
      self?.pollUSGS()
      self?.pollGDACS()
    }

    let usgsTimer = Timer.scheduledTimer(withTimeInterval: Self.usgsPollInterval, repeats: true) { [weak self] _ in
      self?.pollUSGS()
    }
    RunLoop.main.add(usgsTimer, forMode: .common)
    usgsPollTimer = usgsTimer

    let gdacsTimer = Timer.scheduledTimer(withTimeInterval: Self.gdacsPollInterval, repeats: true) { [weak self] _ in
      self?.pollGDACS()
    }
    RunLoop.main.add(gdacsTimer, forMode: .common)
    gdacsPollTimer = gdacsTimer
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    usgsPollTimer?.invalidate()
    usgsPollTimer = nil
    gdacsPollTimer?.invalidate()
    gdacsPollTimer = nil
    usgsTask?.cancel()
    usgsTask = nil
    gdacsTask?.cancel()
    gdacsTask = nil
    eventSink = nil
    return nil
  }

  private func pollUSGS() {
    guard let userCoordinate = LocationProvider.shared.latestCoordinate else { return }
    usgsTask?.cancel()
    // The pre-generated, server-cached feed USGS itself recommends for
    // polling clients over the query service (see their Feed Life Cycle
    // Policy) — "significant" magnitude+timeframe combinations like this
    // one are cached and can't overload their database the way an
    // arbitrary custom query could.
    let url = URL(string: "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/4.5_day.geojson")!

    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
      guard let self, error == nil, let data else { return }
      guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let features = json["features"] as? [[String: Any]]
      else { return }

      let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
      for feature in features {
        guard
          let properties = feature["properties"] as? [String: Any],
          let geometry = feature["geometry"] as? [String: Any],
          let coordinates = geometry["coordinates"] as? [Double],
          coordinates.count >= 2,
          let magnitude = properties["mag"] as? Double,
          magnitude >= Self.minimumMagnitude,
          let place = properties["place"] as? String
        else { continue }

        // GeoJSON order is [longitude, latitude, depth] — not the more
        // common [lat, lon] — confirmed against USGS's own format docs.
        let eventLocation = CLLocation(latitude: coordinates[1], longitude: coordinates[0])
        guard userLocation.distance(from: eventLocation) <= Self.alertRadiusMeters else { continue }

        let isTsunami = (properties["tsunami"] as? Int ?? 0) == 1
        let id = (properties["code"] as? String) ?? (properties["ids"] as? String) ?? place
        self.emit(
          id: "usgs-\(id)",
          kind: isTsunami ? "tsunami" : "earthquake",
          headline: isTsunami ? "Tsunami risk: M\(magnitude) earthquake" : "M\(magnitude) earthquake",
          place: place,
          source: "usgs"
        )
      }
    }
    usgsTask = task
    task.resume()
  }

  private func pollGDACS() {
    guard let userCoordinate = LocationProvider.shared.latestCoordinate else { return }
    gdacsTask?.cancel()
    let url = URL(string: "https://www.gdacs.org/gdacsapi/api/events/geteventlist/SEARCH")!

    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
      guard let self, error == nil, let data else { return }
      guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let features = json["features"] as? [[String: Any]]
      else { return }

      let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
      for feature in features {
        guard
          let properties = feature["properties"] as? [String: Any],
          let geometry = feature["geometry"] as? [String: Any],
          let coordinates = geometry["coordinates"] as? [Double],
          coordinates.count >= 2,
          // Green-level GDACS events are informational/low-impact by
          // GDACS's own alertlevel scale — only Orange/Red are genuinely
          // alert-worthy, matching how GDACS's own dashboard highlights
          // events.
          let alertLevel = properties["alertlevel"] as? String,
          alertLevel == "Orange" || alertLevel == "Red",
          let eventType = properties["eventtype"] as? String,
          let eventId = properties["eventid"]
        else { continue }

        let eventLocation = CLLocation(latitude: coordinates[1], longitude: coordinates[0])
        guard userLocation.distance(from: eventLocation) <= Self.alertRadiusMeters else { continue }

        // Confirmed live against the real API — "country" is always a
        // plain string across every event type (EQ/FL/TC/VO/WF/DR),
        // sometimes a single name, sometimes several comma-joined for a
        // multi-country event. "affectedcountries" also exists but is a
        // structured array of {iso2, iso3, countryname} objects, not a
        // string — not what's needed for a one-line headline.
        let country = (properties["country"] as? String) ?? ""
        self.emit(
          id: "gdacs-\(eventId)",
          kind: Self.kind(forGdacsEventType: eventType),
          headline: Self.headline(forGdacsEventType: eventType, alertLevel: alertLevel),
          place: country,
          source: "gdacs"
        )
      }
    }
    gdacsTask = task
    task.resume()
  }

  private static func kind(forGdacsEventType eventType: String) -> String {
    switch eventType {
    case "EQ": return "earthquake"
    case "TC": return "cyclone"
    case "FL": return "flood"
    case "VO": return "volcano"
    case "WF": return "wildfire"
    case "DR": return "drought"
    default: return "disaster"
    }
  }

  private static func headline(forGdacsEventType eventType: String, alertLevel: String) -> String {
    let severity = alertLevel == "Red" ? "Severe" : "Warning:"
    switch eventType {
    case "EQ": return "\(severity) earthquake"
    case "TC": return "\(severity) cyclone"
    case "FL": return "\(severity) flood"
    case "VO": return "\(severity) volcanic activity"
    case "WF": return "\(severity) wildfire"
    case "DR": return "\(severity) drought"
    default: return "\(severity) disaster event"
    }
  }

  private func emit(id: String, kind: String, headline: String, place: String, source: String) {
    DispatchQueue.main.async {
      self.eventSink?([
        "id": id,
        "kind": kind,
        "headline": headline,
        "place": place,
        "source": source,
      ])
    }
  }
}
