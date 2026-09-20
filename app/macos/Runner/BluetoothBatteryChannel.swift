import Cocoa
import CoreBluetooth
import FlutterMacOS

/// Bluetooth accessory battery (§04/§05, alpha) — scoped to the public GATT
/// Battery Service (0x180F/0x2A19), a stable CoreBluetooth API. This is what
/// actually powers macOS's own battery display for Magic Mouse/Keyboard/
/// Trackpad, and works for any third-party accessory that implements the
/// same standard service. AirPods don't: their battery is reported through
/// a different, undocumented Apple protocol, deliberately out of scope here
/// until there's real AirPods hardware to verify a decoder against.
final class BluetoothBatteryChannel: NSObject, FlutterStreamHandler, CBCentralManagerDelegate, CBPeripheralDelegate {
  private static let batteryServiceUUID = CBUUID(string: "180F")
  private static let batteryLevelUUID = CBUUID(string: "2A19")

  /// Cheap enough to poll — this isn't a scan, just "what's already
  /// connected." CoreBluetooth on macOS has no push notification for "a
  /// previously-unseen peripheral connected somewhere" (unlike iOS's
  /// registerForConnectionEvents, unavailable here), so this is what catches
  /// a device that was off/out of range at launch and turns on later.
  private static let pollInterval: TimeInterval = 15

  private var centralManager: CBCentralManager?
  private var eventSink: FlutterEventSink?
  private var pollTimer: Timer?
  private var connectedPeripherals: [UUID: CBPeripheral] = [:]
  private var batteryLevels: [UUID: Int] = [:]

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/bluetooth-battery/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    if centralManager == nil {
      centralManager = CBCentralManager(delegate: self, queue: nil)
    } else if centralManager?.state == .poweredOn {
      refreshConnectedPeripherals()
    }
    startPolling()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    pollTimer?.invalidate()
    pollTimer = nil
    return nil
  }

  private func startPolling() {
    pollTimer?.invalidate()
    pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      self?.refreshConnectedPeripherals()
    }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    guard central.state == .poweredOn else { return }
    refreshConnectedPeripherals()
  }

  private func refreshConnectedPeripherals() {
    guard let central = centralManager, central.state == .poweredOn else { return }
    for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.batteryServiceUUID]) {
      connect(peripheral)
    }
  }

  private func connect(_ peripheral: CBPeripheral) {
    guard connectedPeripherals[peripheral.identifier] == nil else { return }
    connectedPeripherals[peripheral.identifier] = peripheral
    peripheral.delegate = self
    centralManager?.connect(peripheral, options: nil)
  }

  private func forget(_ peripheral: CBPeripheral) {
    connectedPeripherals.removeValue(forKey: peripheral.identifier)
    batteryLevels.removeValue(forKey: peripheral.identifier)
    emit()
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    peripheral.discoverServices([Self.batteryServiceUUID])
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    forget(peripheral)
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    forget(peripheral)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard let services = peripheral.services else { return }
    for service in services where service.uuid == Self.batteryServiceUUID {
      peripheral.discoverCharacteristics([Self.batteryLevelUUID], for: service)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard let characteristics = service.characteristics else { return }
    for characteristic in characteristics where characteristic.uuid == Self.batteryLevelUUID {
      peripheral.readValue(for: characteristic)
      // Not every accessory pushes updates on its own; the poll above is the
      // backstop for those, this is the fast path for the ones that do.
      peripheral.setNotifyValue(true, for: characteristic)
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == Self.batteryLevelUUID, let byte = characteristic.value?.first else { return }
    batteryLevels[peripheral.identifier] = Int(byte)
    emit()
  }

  private func emit() {
    guard let sink = eventSink else { return }
    let payload = connectedPeripherals.compactMap { identifier, peripheral -> [String: Any]? in
      guard let percent = batteryLevels[identifier] else { return nil }
      return ["name": peripheral.name ?? "Bluetooth device", "batteryPercent": percent]
    }
    sink(payload)
  }
}
