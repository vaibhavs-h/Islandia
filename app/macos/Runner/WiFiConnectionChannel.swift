import Cocoa
import CoreLocation
import CoreWLAN
import FlutterMacOS

/// Wi-Fi network join/leave (§05, v1 tier) — the same connect/disconnect
/// notification shape Bluetooth already has, for the other kind of thing a
/// Mac can connect to. CoreWLAN's `CWEventDelegate` is the real-time push
/// API for this — `.ssidDidChange`/`.linkDidChange` — matching every other
/// provider here's push-not-poll convention (BluetoothClassicChannel's own
/// IOBluetooth notifications, WindowServerStatusIndicatorAdapter's log
/// stream).
///
/// Reading the actual network name needs Location Services authorization —
/// confirmed live, this is not a sandboxing/entitlement matter (this app
/// isn't sandboxed at all) but a runtime gate Apple added specifically to
/// stop SSID-based location tracking: `CWInterface.ssid()` returns nil
/// until `CLLocationManager` authorization is granted, verified by reading
/// it before and after requesting authorization from an unauthorized
/// process and seeing nil both times without a real Info.plist usage
/// string + app bundle behind the request (a bare script can't produce the
/// actual system prompt at all). `NSLocationWhenInUseUsageDescription` is
/// declared in Info.plist for exactly this.
final class WiFiConnectionChannel: NSObject, FlutterStreamHandler, CWEventDelegate, CLLocationManagerDelegate {
  private var eventSink: FlutterEventSink?
  private let locationManager = CLLocationManager()
  private let wifiClient = CWWiFiClient.shared()
  private var isMonitoring = false

  /// The network name last reported as connected — not just "is Wi-Fi
  /// connected," since a fast network-switch (moving between two known
  /// APs) is a disconnect-then-connect pair, same as Bluetooth's own
  /// devices-by-name diffing, not an update in place.
  private var lastKnownSSID: String?

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/wifi-connection/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    locationManager.delegate = self
    // requestWhenInUseAuthorization() is a no-op if already determined
    // (granted or denied) — this is what triggers the one-time system
    // prompt on a fresh install, and locationManagerDidChangeAuthorization
    // below is what actually starts monitoring once (or if) it resolves.
    locationManager.requestWhenInUseAuthorization()
    startMonitoringIfAuthorized()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    stopMonitoring()
    return nil
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    startMonitoringIfAuthorized()
  }

  private func startMonitoringIfAuthorized() {
    guard !isMonitoring else { return }
    let status = locationManager.authorizationStatus
    guard status == .authorized || status == .authorizedAlways else { return }

    wifiClient.delegate = self
    do {
      try wifiClient.startMonitoringEvent(with: .ssidDidChange)
      try wifiClient.startMonitoringEvent(with: .linkDidChange)
      isMonitoring = true
    } catch {
      // No fallback if this fails — same trade-off already accepted for
      // every other private/gated log-based provider here: the feature
      // just stays silent rather than crashing or polling around it.
      return
    }

    // Whatever network is already joined the instant authorization
    // resolves is existing state, not a fresh join — same
    // "don't announce what was already true" rule
    // BluetoothClassicChannel's onListen follows for already-connected
    // devices. Only emitted internally (lastKnownSSID), never to eventSink.
    lastKnownSSID = wifiClient.interface()?.ssid()
  }

  private func stopMonitoring() {
    guard isMonitoring else { return }
    wifiClient.delegate = nil
    try? wifiClient.stopMonitoringAllEvents()
    isMonitoring = false
    lastKnownSSID = nil
  }

  func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
    handleSSIDChange()
  }

  func linkDidChangeForWiFiInterface(withName interfaceName: String) {
    handleSSIDChange()
  }

  /// Both `.ssidDidChange` and `.linkDidChange` land here rather than
  /// trying to reason about which one means what — a join, a leave, and a
  /// switch between two networks can each surface through either event
  /// depending on the exact transition (verified live: switching networks
  /// fired both events, in an order not worth depending on), so this just
  /// re-reads the interface's current SSID and diffs it against what was
  /// last known, the same snapshot-diffing shape
  /// _detectBluetoothConnectionChanges already uses in island_shell.dart.
  private func handleSSIDChange() {
    let currentSSID = wifiClient.interface()?.ssid()
    let previousSSID = lastKnownSSID
    lastKnownSSID = currentSSID
    guard currentSSID != previousSSID else { return }

    if let previousSSID {
      eventSink?(["name": previousSSID, "connected": false])
    }
    if let currentSSID {
      eventSink?(["name": currentSSID, "connected": true])
    }
  }
}
