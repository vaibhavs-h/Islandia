import Cocoa
import FlutterMacOS
import QuartzCore

/// The Island's own window. This is not a normal app window: its frame is the
/// pill itself, not a canvas around it, so anything outside the frame is
/// click-through for free — there's simply no window there. `.nonactivatingPanel`
/// keeps clicking it from stealing focus from whatever app the user is in;
/// `isInteractive` is the one escape hatch, flipped from Dart when the Island
/// genuinely needs keyboard/text input (see IslandWindowChannel).
class MainFlutterWindow: NSWindow {
  private var flutterViewController: FlutterViewController!
  private let batteryStreamHandler = BatteryStreamHandler()
  private let nowPlayingChannel = NowPlayingChannel()
  private let audioRouteChannel = AudioRouteChannel()

  override func awakeFromNib() {
    flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    IslandWindowChannel.register(on: self, controller: flutterViewController)

    let batteryChannel = FlutterEventChannel(
      name: "islandia/battery/updates",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    batteryChannel.setStreamHandler(batteryStreamHandler)
    nowPlayingChannel.register(on: flutterViewController)
    audioRouteChannel.register(on: flutterViewController)

    configureAsIslandPanel()

    super.awakeFromNib()
  }

  private func configureAsIslandPanel() {
    styleMask = [.borderless, .nonactivatingPanel]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isMovableByWindowBackground = false
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

    contentView?.wantsLayer = true
    contentView?.layer?.backgroundColor = NSColor.clear.cgColor

    positionUnderNotch()
  }

  /// A rough first-paint fallback before Dart's own bootstrap fetches real
  /// geometry (the exact 0.2mm gap math, live screen-change tracking) and
  /// repositions properly — see `pill_geometry.dart`. This only needs to be
  /// in the neighborhood so there's no visible flash of an unpositioned window.
  private func positionUnderNotch() {
    guard let screen = NSScreen.main else { return }
    let pillSize = NSSize(width: 220, height: 32)
    let topInset = screen.safeAreaInsets.top
    let gap: CGFloat = topInset > 0 ? 6 : 10
    let originX = screen.frame.midX - pillSize.width / 2
    let originY = screen.frame.maxY - topInset - gap - pillSize.height
    setFrame(NSRect(x: originX, y: originY, width: pillSize.width, height: pillSize.height), display: true)
  }

  /// Never a main window — the Island never owns the app's document/menu state.
  override var canBecomeMain: Bool { return false }

  /// Only key when Dart has explicitly asked for interactive input; otherwise
  /// hover/hit-testing works fine on a non-key window and we avoid stealing
  /// keystrokes from whatever the user was typing into.
  override var canBecomeKey: Bool { return isInteractive }

  var isInteractive: Bool = false {
    didSet {
      guard isInteractive != oldValue else { return }
      if isInteractive {
        makeKey()
      } else if isKeyWindow {
        resignKey()
      }
    }
  }

  /// The window resize *is* the shell's expand/collapse animation — the
  /// Flutter content underneath is laid out at its full target size the
  /// whole time (see IslandShell's OverflowBox) and simply gets revealed as
  /// this frame grows, rather than reflowing every intermediate frame.
  /// `durationSeconds <= 0` snaps instantly (first layout, or a caller that
  /// wants no animation). Keep this timing function in sync with
  /// `IslandMotion.expansionDuration`/`expansionCurve` on the Dart side —
  /// they're meant to read as one motion, not two.
  func setPillFrame(_ rect: NSRect, animated: Bool, durationSeconds: TimeInterval) {
    guard animated, durationSeconds > 0 else {
      setFrame(rect, display: true)
      return
    }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = durationSeconds
      // Pure ease-out, no overshoot — even a subtle bounce is a brief
      // reversal in velocity, which reads as snappy rather than smooth.
      // Keep in sync with IslandMotion.expansionCurve on the Dart side.
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
      self.animator().setFrame(rect, display: true)
    }
  }
}
