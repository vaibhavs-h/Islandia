import Cocoa
import FlutterMacOS

/// Screen capture indicator (§04/§05, v1 tier) — same WindowServer
/// `StatusIndicator` mechanism as CameraActivityChannel, via the shared
/// WindowServerStatusIndicatorAdapter (backfill + live watching +
/// crash-restart; see its own doc comment for the details), watching for
/// `"screen capture added"` / `"screen capture removed"` instead of
/// `"camera added"` / `"camera removed"`.
/// Deliberately unfiltered, matching macOS's own purple indicator exactly:
/// confirmed live that this signal fires identically for a screen
/// *recording* (`screencapture -V`, held for the recording's full duration)
/// and a plain one-off *screenshot* (`screencapture -x`, added/removed
/// ~20ms apart) — the real menu-bar indicator does the same thing (flashes
/// briefly for a screenshot), so this intentionally does not try to filter
/// momentary captures out. The existing `PrivacyIndicatorController`
/// already produces the right visual result either way: a brief flash for
/// a screenshot's near-simultaneous added/removed pair, a full
/// prominent-then-dot sequence for anything sustained, with no
/// special-casing needed here.
/// Screen-recording detection was investigated once before (a different,
/// wrong signal — `replayd`/`RPRecordingManager` — was tried and abandoned)
/// and marked unresolved; this WindowServer signal, found via the same
/// investigation that fixed camera, is what actually works.
final class ScreenCaptureActivityChannel: NSObject, FlutterStreamHandler {
  private let adapter = WindowServerStatusIndicatorAdapter(keyword: "screen capture")

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/screen-capture-activity/updates",
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
