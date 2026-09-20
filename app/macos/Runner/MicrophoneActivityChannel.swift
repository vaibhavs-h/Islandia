import Cocoa
import CoreAudio
import FlutterMacOS

/// Mic-in-use indicator (§04/§05, v1 tier) — a public CoreAudio property,
/// kAudioDevicePropertyDeviceIsRunningSomewhere, reports whether *any*
/// process (not just this one) currently has the device's input running.
/// Known caveat: Bluetooth microphones don't report through this property
/// reliably (reads as inactive regardless) — built-in and wired mics do.
/// This only ever reads a HAL property, never opens an audio stream itself,
/// so it needs no microphone permission of its own.
final class MicrophoneActivityAdapter {
  private var eventSink: FlutterEventSink?
  private var isListening = false
  private var observedDeviceId: AudioDeviceID?

  private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

  private static var defaultInputDeviceAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  private static var isRunningSomewhereAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )

  func start(eventSink: @escaping FlutterEventSink) {
    self.eventSink = eventSink
    guard !isListening else { return }
    isListening = true
    attachToDefaultInputDevice()
    // The default *input* device can change independently of output (a USB
    // mic plugged in, an input source picked in Sound settings) — reattach
    // the running-state listener to whichever device is current.
    AudioObjectAddPropertyListenerBlock(Self.systemObject, &Self.defaultInputDeviceAddress, DispatchQueue.main) { [weak self] _, _ in
      self?.attachToDefaultInputDevice()
    }
  }

  func stop() {
    eventSink = nil
    guard isListening else { return }
    isListening = false
    detachFromObservedDevice()
    AudioObjectRemovePropertyListenerBlock(Self.systemObject, &Self.defaultInputDeviceAddress, DispatchQueue.main) { _, _ in }
  }

  private func attachToDefaultInputDevice() {
    detachFromObservedDevice()
    guard let deviceId = Self.currentInputDeviceId() else {
      emit(isActive: false)
      return
    }
    observedDeviceId = deviceId
    var address = Self.isRunningSomewhereAddress
    AudioObjectAddPropertyListenerBlock(deviceId, &address, DispatchQueue.main) { [weak self] _, _ in
      self?.emitCurrentState()
    }
    emitCurrentState()
  }

  private func detachFromObservedDevice() {
    guard let deviceId = observedDeviceId else { return }
    var address = Self.isRunningSomewhereAddress
    AudioObjectRemovePropertyListenerBlock(deviceId, &address, DispatchQueue.main) { _, _ in }
    observedDeviceId = nil
  }

  private func emitCurrentState() {
    guard let deviceId = observedDeviceId else {
      emit(isActive: false)
      return
    }
    emit(isActive: Self.isRunningSomewhere(deviceId))
  }

  private func emit(isActive: Bool) {
    eventSink?(isActive)
  }

  private static func currentInputDeviceId() -> AudioDeviceID? {
    var deviceId = AudioDeviceID()
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = defaultInputDeviceAddress
    let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceId)
    return status == noErr ? deviceId : nil
  }

  private static func isRunningSomewhere(_ deviceId: AudioDeviceID) -> Bool {
    var isRunning: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = isRunningSomewhereAddress
    let status = AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &isRunning)
    return status == noErr && isRunning != 0
  }
}

final class MicrophoneActivityChannel: NSObject, FlutterStreamHandler {
  private let adapter = MicrophoneActivityAdapter()

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/microphone-activity/updates",
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
