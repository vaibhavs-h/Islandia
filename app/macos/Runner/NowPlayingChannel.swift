import ApplicationServices
import Cocoa
import FlutterMacOS

/// Real Now Playing (§04/§05, alpha) via MediaRemote — a private, undocumented
/// framework that macOS 15.4 locked down to processes Apple itself signs.
/// The vendored `mediaremote-adapter` (github.com/ungive/mediaremote-adapter,
/// BSD-3-Clause) works around this by having `/usr/bin/perl` — which macOS
/// treats as `com.apple.perl` and does trust — dynamically load a small
/// bundled framework and print JSON to stdout. Islandia never touches
/// MediaRemote directly; this whole file just manages that subprocess and
/// relays its output, isolating anything Apple changes out from under us to
/// this one file (§01's "helper process" pattern, minus a second binary to
/// code-sign since Perl itself is doing the trusted call).
final class NowPlayingAdapter {
  private var process: Process?
  private var stdoutPipe: Pipe?
  private var lineBuffer = Data()
  private var currentState: [String: Any] = [:]
  private var restartAttempt = 0
  private var stoppedIntentionally = false
  private var eventSink: FlutterEventSink?

  private static let newline = Data([0x0A])

  private var resourcesDirectory: URL? {
    Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter")
  }

  private var scriptPath: String? {
    resourcesDirectory?.appendingPathComponent("mediaremote-adapter.pl").path
  }

  private var frameworkPath: String? {
    resourcesDirectory?.appendingPathComponent("MediaRemoteAdapter.framework").path
  }

  func start(eventSink: @escaping FlutterEventSink) {
    self.eventSink = eventSink
    stoppedIntentionally = false
    currentState = [:]
    restartAttempt = 0
    launch()
  }

  func stop() {
    stoppedIntentionally = true
    eventSink = nil
    teardownProcess()
  }

  func sendCommand(_ commandId: Int) {
    guard let script = scriptPath, let framework = frameworkPath else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = [script, framework, "send", String(commandId)]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
  }

  private func launch() {
    guard
      let script = scriptPath, let framework = frameworkPath,
      FileManager.default.fileExists(atPath: script),
      FileManager.default.fileExists(atPath: framework)
    else { return }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    // debounce: some apps fire several metadata events per real change;
    // 250ms smooths that into one update without feeling laggy.
    process.arguments = [script, framework, "stream", "--debounce=250"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    // `readabilityHandler` fires on a background dispatch queue, not the
    // main/platform thread — Flutter's engine requires every platform
    // channel call (the eventSink invocation inside handle(line:)) to
    // happen on the platform thread, and violating that crashes the
    // connection outright. Hopping to main here, rather than deeper in,
    // also means lineBuffer/currentState are only ever touched from one
    // thread, so no separate locking is needed either.
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      DispatchQueue.main.async {
        self?.consume(data)
      }
    }

    // A crash here (MediaRemote access narrowing further, a malformed
    // response) must never take the rest of Islandia down with it — restart
    // with backoff instead, same rule as every other helper process (§10).
    process.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async { self?.handleExit() }
    }

    do {
      try process.run()
      self.process = process
      stdoutPipe = pipe
    } catch {
      scheduleRestart()
    }
  }

  private func consume(_ data: Data) {
    lineBuffer.append(data)
    while let range = lineBuffer.range(of: Self.newline) {
      let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<range.lowerBound)
      lineBuffer.removeSubrange(lineBuffer.startIndex..<range.upperBound)
      handle(line: lineData)
    }
  }

  private func handle(line: Data) {
    guard
      !line.isEmpty,
      let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
      let payload = json["payload"] as? [String: Any]
    else { return }

    // `diff:false` is a full snapshot (a new track, or "nothing playing" as
    // an empty dict) and replaces everything; `diff:true` only carries what
    // changed (an elapsed-time tick) and merges into what we already have.
    if (json["diff"] as? Bool) == true {
      for (key, value) in payload { currentState[key] = value }
    } else {
      currentState = payload
    }
    eventSink?(currentState)
  }

  private func handleExit() {
    teardownProcess()
    guard !stoppedIntentionally else { return }
    scheduleRestart()
  }

  private func teardownProcess() {
    process?.terminationHandler = nil
    process?.terminate()
    process = nil
    stdoutPipe?.fileHandleForReading.readabilityHandler = nil
    stdoutPipe = nil
    lineBuffer.removeAll()
  }

  private func scheduleRestart() {
    restartAttempt += 1
    let delaySeconds = min(30.0, pow(2.0, Double(restartAttempt)))
    DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
      guard let self, !self.stoppedIntentionally else { return }
      self.launch()
    }
  }
}

/// Bridges [NowPlayingAdapter] to Dart: one EventChannel for the live
/// now-playing state, one MethodChannel for playback commands. No activity
/// data is interpreted here — "is anything playing" is a Dart-side decision
/// based on whether the payload has the fields it needs.
final class NowPlayingChannel: NSObject, FlutterStreamHandler {
  private let adapter = NowPlayingAdapter()
  private var controlChannel: FlutterMethodChannel?
  private var mediaKeyGlobalMonitor: Any?
  private var mediaKeyLocalMonitor: Any?

  // From IOKit's ev_keymap.h — not part of any public Swift/ObjC module, so
  // hardcoded; these have been ABI-stable since Mac OS X 10.x.
  private static let NX_KEYTYPE_PLAY: Int32 = 16
  private static let NX_KEYTYPE_NEXT: Int32 = 17
  private static let NX_KEYTYPE_PREVIOUS: Int32 = 18
  private static let NX_KEYTYPE_FAST: Int32 = 19
  private static let NX_KEYTYPE_REWIND: Int32 = 20

  func register(on controller: FlutterViewController) {
    let eventChannel = FlutterEventChannel(
      name: "islandia/now-playing/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    eventChannel.setStreamHandler(self)

    let controlChannel = FlutterMethodChannel(
      name: "islandia/now-playing/control",
      binaryMessenger: controller.engine.binaryMessenger
    )
    self.controlChannel = controlChannel
    controlChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "send":
        guard let commandId = call.arguments as? Int else {
          result(FlutterError(code: "bad_args", message: "Expected a command id", details: nil))
          return
        }
        self?.adapter.sendCommand(commandId)
        result(nil)

      case "activateSourceApp":
        guard let bundleIdentifier = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: "Expected a bundle identifier", details: nil))
          return
        }
        Self.activateApp(bundleIdentifier: bundleIdentifier)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Hardware media keys (the dedicated Previous/Play-Pause/Next keys, e.g.
    // F7/F8/F9) are a `.systemDefined` NSEvent, not a normal keystroke. A
    // *global* monitor only ever observes events destined for *other* apps —
    // covers a press while the pill is collapsed and some other app is
    // focused, and can never fire from (or interfere with) someone typing in
    // this app or any other. But once the pill expands and calls makeKey()
    // (see MainFlutterWindow.isInteractive), Islandia itself becomes the
    // focused app, and the system now delivers the very same key press to
    // *this* app instead. A *local* monitor is the other half, for exactly
    // that case: it only sees events destined for this app. The two are
    // meant to be mutually exclusive by focus state, but a nonactivating
    // panel being key without the app ever becoming the system's
    // frontmost/active one confuses that — both ended up firing for the same
    // physical press while expanded, sending every command twice (a
    // toggle that silently undid itself, a "next" that skipped two tracks).
    // Gating the global monitor on "nothing of ours is key right now" keeps
    // the two states genuinely exclusive instead of just usually exclusive.
    mediaKeyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
      guard NSApp.keyWindow == nil else { return }
      self?.handlePossibleMediaKey(event)
    }
    mediaKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
      self?.handlePossibleMediaKey(event)
      return event
    }
  }

  private func handlePossibleMediaKey(_ event: NSEvent) {
    guard event.subtype.rawValue == 8 else { return }

    let keyCode = Int32((event.data1 & 0xFFFF_0000) >> 16)
    let keyFlags = event.data1 & 0x0000_FFFF
    let isKeyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
    guard isKeyDown else { return }

    let action: String
    switch keyCode {
    case Self.NX_KEYTYPE_PLAY:
      action = "playPause"
    case Self.NX_KEYTYPE_NEXT, Self.NX_KEYTYPE_FAST:
      action = "next"
    case Self.NX_KEYTYPE_PREVIOUS, Self.NX_KEYTYPE_REWIND:
      action = "previous"
    default:
      return
    }
    controlChannel?.invokeMethod("mediaKey", arguments: action)
  }

  /// Brings the app that's actually playing to the front — e.g. tapping the
  /// track's artwork/title in the expanded view. Deliberately just the app,
  /// not a specific browser tab or an artist/channel page: MediaRemote's
  /// payload has no tab or artist-ID info to act on reliably, and guessing
  /// via title-matching would occasionally activate the wrong thing.
  private static func activateApp(bundleIdentifier: String) {
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
      // Plain activate() is macOS's "polite" request — an accessory app with
      // no Dock icon and no prior user focus (exactly what Islandia is) can
      // have it silently deferred by focus-stealing prevention, which reads
      // as "the first click did nothing." .activateIgnoringOtherApps forces
      // it through every time instead of only when the heuristics allow it.
      // .activateAllWindows also brings forward every one of the app's open
      // (non-minimized) windows, not just whichever was already frontmost.
      app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
      // Neither option un-minimizes anything — that's a window-level action
      // NSRunningApplication has no API for on another process at all.
      // Accessibility is the only way to reach it.
      if accessibilityIsAvailable() {
        unminimizeAndRaiseWindows(for: app)
      }
      return
    }
    // Was reporting Now Playing a moment ago but isn't running anymore —
    // rare, but launching it fresh is a reasonable fallback.
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
      NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
  }

  private static var didPromptForAccessibility = false

  /// Prompts for Accessibility access at most once per launch (repeat calls
  /// while still untrusted would otherwise re-trigger the system dialog on
  /// every single tap). Once the user grants it in System Settings, the
  /// plain `AXIsProcessTrusted()` check below picks that up immediately —
  /// no restart or re-prompt needed.
  private static func accessibilityIsAvailable() -> Bool {
    if AXIsProcessTrusted() { return true }
    guard !didPromptForAccessibility else { return false }
    didPromptForAccessibility = true
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// Un-minimizes every one of [app]'s windows and raises one of them.
  /// MediaRemote's payload has no window identifier in it at all, so which
  /// window is actually the one playing audio is unknowable here — raising
  /// "the first one the Accessibility API reports" is a best-effort guess,
  /// not a guarantee, when more than one window is open.
  private static func unminimizeAndRaiseWindows(for app: NSRunningApplication) {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var windowsRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
      let windows = windowsRef as? [AXUIElement], !windows.isEmpty
    else { return }

    for window in windows {
      var minimizedRef: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
        let isMinimized = minimizedRef as? Bool, isMinimized
      else { continue }
      AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }
    AXUIElementPerformAction(windows[0], kAXRaiseAction as CFString)
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
