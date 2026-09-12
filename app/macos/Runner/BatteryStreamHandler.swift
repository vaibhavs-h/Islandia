import Cocoa
import FlutterMacOS
import IOKit.ps

/// The first real (non-fake) provider: Mac battery/charging status via
/// IOKit's power-source APIs, per §04/§05 (native, alpha tier). Pushed via
/// `IOPSNotificationCreateRunLoopSource`, not polled — the OS tells us when
/// something changes (plugged in, percentage ticks, fully charged) rather
/// than us asking on a timer, matching §09's performance budget.
class BatteryStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var runLoopSource: CFRunLoopSource?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emitCurrentState()

    let context = Unmanaged.passUnretained(self).toOpaque()
    let callback: IOPowerSourceCallbackType = { context in
      guard let context = context else { return }
      Unmanaged<BatteryStreamHandler>.fromOpaque(context).takeUnretainedValue().emitCurrentState()
    }
    if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
      runLoopSource = source
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
    }
    runLoopSource = nil
    eventSink = nil
    return nil
  }

  private func emitCurrentState() {
    guard let sink = eventSink else { return }

    guard
      let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
      let source = sources.first,
      let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
    else {
      // No battery (e.g. a desktop Mac) — fail quiet per §10, not a crash.
      sink(FlutterError(code: "no_power_source", message: "No battery on this Mac", details: nil))
      return
    }

    let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
    let maxCapacity = description[kIOPSMaxCapacityKey] as? Int ?? 100
    let percentage = maxCapacity > 0 ? Double(currentCapacity) / Double(maxCapacity) : 0.0
    let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
    let isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
    let isOnACPower = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

    sink([
      "percentage": percentage,
      "isCharging": isCharging,
      "isCharged": isCharged,
      "isOnACPower": isOnACPower,
    ])
  }
}
