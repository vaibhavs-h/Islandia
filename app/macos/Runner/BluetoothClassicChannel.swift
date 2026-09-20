import Cocoa
import FlutterMacOS
import IOBluetooth

/// Bluetooth Classic connect/disconnect (§04/§05, v1 tier). Audio accessories
/// — headphones, earbuds, speakers — pair over Bluetooth Classic (A2DP), which
/// CoreBluetooth's CBCentralManager cannot see at all: confirmed live on this
/// machine that `retrieveConnectedPeripherals` returns nothing for a Classic
/// device regardless of GATT support (the same symptom other developers have
/// hit with AirPods — it's a BLE-only API, not a battery-service scoping
/// issue). BluetoothBatteryChannel stays BLE-only; this is a separate source
/// for the one thing IOBluetooth *does* expose cleanly for Classic devices.
/// Verified live on this machine (macOS 26) with a real headphone
/// disconnect/reconnect before shipping — including a first pass that fired
/// each event twice from a duplicate notification registration, fixed below
/// by only ever holding one outstanding disconnect registration per device.
///
/// Battery, for the connect event specifically: initially believed to have
/// no available API at all (mainstream Bluetooth Classic accessories don't
/// implement the GATT battery service CoreBluetooth-based devices use, and
/// there's no equivalent on IOBluetoothDevice) — revisited after being asked
/// "but this is a normal Sony headset, not some obscure device," which was a
/// fair challenge given macOS's own Bluetooth menu *does* show battery for
/// mainstream accessories, so something has to be feeding it. Found live:
/// `bluetoothd` itself logs it — subsystem `com.apple.bluetooth`, category
/// `CBPowerSource`, e.g. `Power source updated CBPowerSource Nm 'WH-CH520',
/// ..., Battery 100% (FullyCharged)` — no root or private HCI packet
/// sniffing needed (unlike e.g. the abandoned community tool Akku, which
/// required exactly that before Monterey added this native support). On a
/// fresh connect, confirmed live: a `-100%` placeholder ("Publishing...")
/// is immediately followed, ~1ms later, by the real reading flagged
/// `BatteryInfo`. This also self-refreshes roughly every 60s for as long as
/// the device stays connected. Battery stays deliberately absent from the
/// *disconnect* notification — a device that just left doesn't have a
/// current reading worth showing.
final class BluetoothClassicChannel: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var connectNotification: IOBluetoothUserNotification?
  private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
  /// De-dupes IOBluetooth's own occasionally-doubled delivery (observed
  /// live: a single real disconnect/reconnect each produced two identical
  /// notifications) into the clean on/off transitions the UI wants — same
  /// role as PrivacyIndicatorController's off/on check, just on the native
  /// side since this channel emits discrete events, not a polled snapshot.
  private var connectedAddresses: Set<String> = []

  private var batteryLogProcess: Process?
  private var batteryLineBuffer = Data()
  private static let batteryLogNewline = Data([0x0A])
  /// Device name -> most recently seen battery percent, from CBPowerSource.
  /// Kept around across a disconnect rather than cleared — a slightly stale
  /// reading from before the device left is still far more useful than
  /// nothing while waiting for a fresh one to land on the next connect.
  private var lastKnownBattery: [String: Int] = [:]
  /// How long a connect event waits to see whether a matching CBPowerSource
  /// reading shows up before emitting without one. CBPowerSource is a fully
  /// independent log stream from the IOBluetooth connect notification, so
  /// there's no way to know in advance which one fires first — confirmed
  /// live the real reading typically lands within ~1ms of the connect, so
  /// this is generous headroom, not a delay anyone will perceive.
  private static let batteryGracePeriod: TimeInterval = 0.5

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/bluetooth-classic/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    // Devices already connected when we start listening are existing state,
    // not a fresh arrival — same "don't announce what was already true"
    // rule every other provider here follows. Just watch them for the next
    // disconnect.
    for case let device as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] {
      if device.isConnected() {
        connectedAddresses.insert(device.addressString ?? "")
        watchForDisconnect(device)
      }
    }
    connectNotification = IOBluetoothDevice.register(
      forConnectNotifications: self,
      selector: #selector(handleConnect(_:device:))
    )
    startWatchingBattery()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    connectNotification?.unregister()
    connectNotification = nil
    for notification in disconnectNotifications.values { notification.unregister() }
    disconnectNotifications.removeAll()
    connectedAddresses.removeAll()
    stopWatchingBattery()
    return nil
  }

  private func startWatchingBattery() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
      "stream", "--info", "--debug", "--style", "compact",
      "--predicate", "subsystem == \"com.apple.bluetooth\" AND category == \"CBPowerSource\"",
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      DispatchQueue.main.async { self?.consumeBatteryLog(data) }
    }
    // No crash-restart here, deliberately, unlike the camera/screen-capture
    // adapters — battery is a best-effort enrichment of the connect
    // notification, not a signal the UI otherwise depends on. If this dies,
    // connect notifications simply stop including a battery reading until
    // the app restarts; nothing gets stuck or shows stale state, so the
    // extra complexity of a restart loop isn't earning its keep here.
    try? process.run()
    batteryLogProcess = process
  }

  private func stopWatchingBattery() {
    batteryLogProcess?.terminationHandler = nil
    batteryLogProcess?.terminate()
    batteryLogProcess = nil
    batteryLineBuffer.removeAll()
  }

  private func consumeBatteryLog(_ data: Data) {
    batteryLineBuffer.append(data)
    while let range = batteryLineBuffer.range(of: Self.batteryLogNewline) {
      let lineData = batteryLineBuffer.subdata(in: batteryLineBuffer.startIndex..<range.lowerBound)
      batteryLineBuffer.removeSubrange(batteryLineBuffer.startIndex..<range.upperBound)
      guard let line = String(data: lineData, encoding: .utf8) else { continue }
      handleBatteryLine(line)
    }
  }

  /// A line looks like: `... CBPowerSource Nm 'WH-CH520', ..., Battery
  /// 100% (FullyCharged)`. The very first line for a freshly (re)connecting
  /// device reports `Battery -100%` — a "not known yet" placeholder, not a
  /// real reading — so that's explicitly rejected rather than cached.
  private func handleBatteryLine(_ line: String) {
    guard let name = Self.extractQuoted(after: "Nm '", in: line) else { return }
    guard let percent = Self.extractBatteryPercent(in: line), percent >= 0 else { return }
    lastKnownBattery[name] = percent
  }

  private static func extractQuoted(after marker: String, in line: String) -> String? {
    guard let start = line.range(of: marker)?.upperBound else { return nil }
    guard let end = line[start...].firstIndex(of: "'") else { return nil }
    return String(line[start..<end])
  }

  private static func extractBatteryPercent(in line: String) -> Int? {
    guard let start = line.range(of: "Battery ")?.upperBound else { return nil }
    guard let end = line[start...].firstIndex(of: "%") else { return nil }
    return Int(line[start..<end])
  }

  private func watchForDisconnect(_ device: IOBluetoothDevice) {
    let address = device.addressString ?? ""
    // Registering a second disconnect notification on top of an existing
    // one is exactly what caused the double-firing during testing.
    guard disconnectNotifications[address] == nil else { return }
    disconnectNotifications[address] = device.register(
      forDisconnectNotification: self,
      selector: #selector(handleDisconnect(_:device:))
    )
  }

  @objc private func handleConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
    watchForDisconnect(device)
    guard connectedAddresses.insert(device.addressString ?? "").inserted else { return }
    let name = device.name ?? "Bluetooth device"
    // See batteryGracePeriod's doc comment — CBPowerSource's reading for
    // this same connect is a separate, independent log line that may not
    // have arrived yet.
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.batteryGracePeriod) { [weak self] in
      guard let self, self.connectedAddresses.contains(device.addressString ?? "") else { return }
      var payload: [String: Any] = ["name": name, "connected": true]
      if let percent = self.lastKnownBattery[name] {
        payload["batteryPercent"] = percent
      }
      self.eventSink?(payload)
    }
  }

  @objc private func handleDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
    let address = device.addressString ?? ""
    disconnectNotifications.removeValue(forKey: address)
    guard connectedAddresses.remove(address) != nil else { return }
    eventSink?(["name": device.name ?? "Bluetooth device", "connected": false])
  }
}
