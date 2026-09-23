import CoreLocation

/// The one shared source of "where is this Mac right now" — a single
/// `CLLocationManager` here means one authorization prompt and one
/// location-fetch cadence for the whole app, rather than each consumer
/// independently requesting its own fix (which would also mean Location
/// Services showing the app as actively tracking location more than once
/// per cycle).
///
/// A one-shot `requestLocation()` on a timer, not continuous updates —
/// nothing here needs live tracking, and this avoids holding location
/// services continuously active for the whole time the app runs.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
  static let shared = LocationProvider()

  private let locationManager = CLLocationManager()
  private var pollTimer: Timer?
  private var listeners: [(CLLocationCoordinate2D) -> Void] = []

  /// 30 minutes — fresher than an hour-old fix while still avoiding
  /// constant re-fetching for something that rarely changes.
  private static let pollInterval: TimeInterval = 1800

  private(set) var latestCoordinate: CLLocationCoordinate2D?

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

  /// Registers to be called with each fresh coordinate as it arrives. Not
  /// a Combine/EventChannel-style stream since this is native-internal
  /// plumbing, never itself exposed to Dart — WeatherChannel reports its
  /// own derived data over its own FlutterEventChannel, this is just how
  /// it learns where to ask about.
  func addListener(_ listener: @escaping (CLLocationCoordinate2D) -> Void) {
    listeners.append(listener)
    if let latestCoordinate {
      listener(latestCoordinate)
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
    for listener in listeners {
      listener(location.coordinate)
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // Same silent-failure convention as every other provider here — a
    // denied/unavailable fix just means listeners don't hear from this
    // tick, not a crash. The next scheduled poll tries again on its own.
  }
}
