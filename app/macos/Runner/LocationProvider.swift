import CoreLocation

/// The one shared source of "where is this Mac right now" — originally
/// lived inside WeatherChannel alone, pulled out once CalamityAlertChannel
/// needed the same coordinate too. A single `CLLocationManager` here means
/// one authorization prompt and one location-fetch cadence for the whole
/// app, rather than each consumer independently requesting its own fix
/// (which would also mean Location Services showing the app as actively
/// tracking location more than once per cycle).
///
/// A one-shot `requestLocation()` on a timer, not continuous updates — the
/// same reasoning WeatherChannel originally had: nothing here needs live
/// tracking, and this avoids holding location services continuously
/// active for the whole time the app runs.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
  static let shared = LocationProvider()

  private let locationManager = CLLocationManager()
  private let geocoder = CLGeocoder()
  private var pollTimer: Timer?
  private var listeners: [(CLLocationCoordinate2D, String?) -> Void] = []

  /// 30 minutes — fresher than Weather alone ever needed (conditions don't
  /// change with the user's position that often), but calamity alerts
  /// benefit from a closer-to-current fix than an hour-old one, since the
  /// whole point is knowing what's actually nearby right now.
  private static let pollInterval: TimeInterval = 1800

  private(set) var latestCoordinate: CLLocationCoordinate2D?

  /// The reverse-geocoded city/locality name for [latestCoordinate], once
  /// resolved — nil until the first `CLGeocoder` callback returns (a real,
  /// separate async step after the coordinate fix itself arrives, not
  /// something CoreLocation bundles into the location update). Re-resolved
  /// on the same cadence as the coordinate itself, so this stays correct
  /// if the Mac actually moves rather than freezing to wherever it first
  /// resolved.
  private(set) var latestPlaceName: String?

  private override init() {
    super.init()
  }

  /// Starts location tracking on first call; safe to call from multiple
  /// consumers — only the first actually starts anything.
  func start() {
    guard pollTimer == nil else { return }
    locationManager.delegate = self
    locationManager.requestWhenInUseAuthorization()
    startPollingIfAuthorized()
  }

  /// Registers to be called with each fresh coordinate (and, once resolved,
  /// place name) as it arrives. Not a Combine/EventChannel-style stream
  /// since this is native-internal plumbing, never itself exposed to Dart
  /// — WeatherChannel and CalamityAlertChannel each report their own
  /// derived data over their own FlutterEventChannel, this is just how
  /// they learn where to ask about. The place name arg is nil on the
  /// initial coordinate callback (geocoding hasn't resolved yet) and again
  /// whenever geocoding itself fails — callers that don't care about the
  /// name (CalamityAlertChannel) simply ignore it.
  func addListener(_ listener: @escaping (CLLocationCoordinate2D, String?) -> Void) {
    listeners.append(listener)
    if let latestCoordinate {
      listener(latestCoordinate, latestPlaceName)
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    startPollingIfAuthorized()
  }

  private func startPollingIfAuthorized() {
    guard pollTimer == nil else { return }
    let status = locationManager.authorizationStatus
    guard status == .authorized || status == .authorizedAlways else { return }

    locationManager.requestLocation()
    let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      self?.locationManager.requestLocation()
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    latestCoordinate = location.coordinate
    // Notify with the coordinate immediately — Weather/CalamityAlertChannel
    // shouldn't wait on the separate, slower geocoding round-trip just to
    // fetch conditions or nearby events. The place name arrives as its own
    // follow-up notification once resolved, below.
    for listener in listeners {
      listener(location.coordinate, latestPlaceName)
    }

    geocoder.cancelGeocode()
    geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
      guard let self, error == nil, let placemark = placemarks?.first else { return }
      // `locality` is the city name in the vast majority of placemarks;
      // `subAdministrativeArea` (county/borough-ish) as a fallback for the
      // rarer case for a coordinate CLGeocoder can't resolve down to city
      // level — same fallback chain Apple's own Maps/Weather apps use.
      let name = placemark.locality ?? placemark.subAdministrativeArea
      guard let name else { return }
      self.latestPlaceName = name
      for listener in self.listeners {
        listener(location.coordinate, name)
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // Same silent-failure convention as every other provider here — a
    // denied/unavailable fix just means listeners don't hear from this
    // tick, not a crash. The next scheduled poll tries again on its own.
  }
}
