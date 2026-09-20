import Cocoa
import FlutterMacOS

/// Camera-in-use indicator (§04/§05, v1 tier — fragile by design, knowingly
/// shipped that way). There is no public API for detecting another app's
/// camera session at all — confirmed via research before attempting this.
/// Built on WindowServer's own `StatusIndicator` logging — the same
/// subsystem that drives macOS's built-in menu-bar camera dot — via the
/// shared WindowServerStatusIndicatorAdapter (backfill + live watching +
/// crash-restart; see its own doc comment for the details and the history
/// behind why each of those exists).
/// An earlier version watched CMIOExtensionProvider's
/// startStreamForClientID/stopStreamForClientID instead, scraped from the
/// per-driver `appleh13camerad` process — that caught native AVFoundation
/// apps (verified live via Photo Booth) but never fired for browser-based
/// WebRTC camera access (verified live: Brave Browser running a Google Meet
/// preview produced zero matching lines). WindowServer's StatusIndicator is
/// upstream of both — it's already doing the multi-client accounting for its
/// own UI, so this is a strictly better signal, not just a broader one.
/// Confirmed live on this machine (macOS 26, Apple Silicon) against both
/// Photo Booth and Brave/Meet.
final class CameraActivityChannel: NSObject, FlutterStreamHandler {
  private let adapter = WindowServerStatusIndicatorAdapter(keyword: "camera")

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/camera-activity/updates",
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
