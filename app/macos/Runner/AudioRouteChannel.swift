import Cocoa
import CoreAudio
import FlutterMacOS

/// Output device / AirPlay / Bluetooth-audio status (§04/§05, alpha) — a
/// stable public API (CoreAudio), unlike Now Playing's MediaRemote detour.
/// Reports the current default output device's name and pushes an update
/// whenever the user switches devices (AirPods connect, HomePod selected,
/// headphones plugged in).
final class AudioRouteAdapter {
  private var eventSink: FlutterEventSink?
  private var isListening = false

  private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

  private static var defaultOutputDeviceAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  func start(eventSink: @escaping FlutterEventSink) {
    self.eventSink = eventSink
    emitCurrentDevice()

    guard !isListening else { return }
    isListening = true
    AudioObjectAddPropertyListenerBlock(Self.systemObject, &Self.defaultOutputDeviceAddress, DispatchQueue.main) { [weak self] _, _ in
      self?.emitCurrentDevice()
    }
  }

  func stop() {
    eventSink = nil
    guard isListening else { return }
    isListening = false
    AudioObjectRemovePropertyListenerBlock(Self.systemObject, &Self.defaultOutputDeviceAddress, DispatchQueue.main) { _, _ in }
  }

  private func emitCurrentDevice() {
    guard let sink = eventSink else { return }
    guard let deviceId = Self.currentOutputDeviceId(), let name = Self.deviceName(for: deviceId) else {
      sink(FlutterError(code: "no_output_device", message: "No default output device", details: nil))
      return
    }
    sink([
      "name": name,
      "isBuiltIn": Self.isBuiltIn(deviceId),
    ])
  }

  private static func currentOutputDeviceId() -> AudioDeviceID? {
    var deviceId = AudioDeviceID()
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = defaultOutputDeviceAddress
    let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceId)
    return status == noErr ? deviceId : nil
  }

  private static func deviceName(for deviceId: AudioDeviceID) -> String? {
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = withUnsafeMutablePointer(to: &name) { pointer -> OSStatus in
      AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, pointer)
    }
    return status == noErr ? (name as String) : nil
  }

  /// The built-in speakers/headphone jack transport type — everything else
  /// (Bluetooth, AirPlay, USB, HDMI) is something the user deliberately
  /// switched to.
  private static func isBuiltIn(_ deviceId: AudioDeviceID) -> Bool {
    var transportType: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &transportType)
    return status == noErr && transportType == kAudioDeviceTransportTypeBuiltIn
  }
}

final class AudioRouteChannel: NSObject, FlutterStreamHandler {
  private let adapter = AudioRouteAdapter()

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/audio-route/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    adapter.start(eventSink: events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    adapter.stop()
    return nil
  }
}
