import Cocoa
import FlutterMacOS

/// The one native bridge for the Island shell itself: everything about *being
/// a window* that Flutter can't do on its own (frame, focus, always-on-top,
/// live display geometry). Per-activity content and all animation stay on
/// the Dart side — this channel only ever hands over numbers (a frame, a
/// focus flag, a screen's raw geometry), never activity data.
enum IslandWindowChannel {
  private static let channelName = "islandia/window"

  // The window IS the pill, so any click AppKit reports through a *global*
  // monitor (which only ever sees events outside our own app's windows) is
  // by definition a click somewhere else on the screen.
  private static var outsideClickMonitor: Any?
  private static var screenParametersObserver: Any?

  /// Falls back to the primary display if there's momentarily no "main"
  /// screen — our window is non-key most of the time, so `NSScreen.main`
  /// (keyed off keyboard focus) can't always be trusted to resolve.
  private static var targetScreen: NSScreen? {
    NSScreen.main ?? NSScreen.screens.first
  }

  private static func geometryPayload(for screen: NSScreen) -> [String: Any] {
    // menuBarHeight only means something on a notch-less screen (safeAreaTop
    // is 0 there); it's the reserved strip at the very top of `frame` that
    // `visibleFrame` excludes.
    let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
    return [
      "screenWidth": screen.frame.width,
      "screenHeight": screen.frame.height,
      "safeAreaTop": screen.safeAreaInsets.top,
      "menuBarHeight": menuBarHeight,
      "backingScaleFactor": screen.backingScaleFactor,
    ]
  }

  static func register(on window: MainFlutterWindow, controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: controller.engine.binaryMessenger)

    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
      channel.invokeMethod("outsideClick", arguments: nil)
    }

    // Connecting/disconnecting a display, or changing resolution/arrangement,
    // fires this — the one live signal behind "drag the app between a
    // notched MacBook and an external monitor with no manual restart."
    screenParametersObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { _ in
      guard let screen = targetScreen else { return }
      channel.invokeMethod("screenParametersChanged", arguments: geometryPayload(for: screen))
    }

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "animateToFrame":
        guard
          let args = call.arguments as? [String: Any],
          let x = args["x"] as? Double,
          let y = args["y"] as? Double,
          let width = args["width"] as? Double,
          let height = args["height"] as? Double,
          let durationMs = args["durationMs"] as? Double,
          let screen = targetScreen
        else {
          result(FlutterError(code: "bad_args", message: "Expected x, y, width, height, durationMs", details: nil))
          return
        }
        // Dart works in top-left-origin logical coordinates (screen-relative,
        // matching how it reasons about "distance below the notch"); AppKit's
        // screen space is bottom-left-origin, so the y-flip happens right here
        // at the one seam between the two coordinate systems.
        let originY = screen.frame.maxY - y - height
        let targetFrame = NSRect(x: x, y: originY, width: width, height: height)
        window.setPillFrame(targetFrame, animated: durationMs > 0, durationSeconds: durationMs / 1000.0)
        result(nil)

      case "setInteractive":
        guard let interactive = call.arguments as? Bool else {
          result(FlutterError(code: "bad_args", message: "Expected a bool", details: nil))
          return
        }
        window.isInteractive = interactive
        result(nil)

      case "notchGeometry":
        guard let screen = targetScreen else {
          result(FlutterError(code: "no_screen", message: "No screen available", details: nil))
          return
        }
        result(geometryPayload(for: screen))

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
