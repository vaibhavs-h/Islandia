import ApplicationServices
import Cocoa

/// Drives the real Clock app's Stopwatch tab from the island's own Lap/Stop
/// buttons — see ClockPreferencesReader's doc comment for why reading state
/// has to go through the private mobiletimerd plist; *writing* has no
/// equivalent private API at all (confirmed: `sdef Clock.app` returns no
/// dictionary, it isn't AppleScript-scriptable beyond the generic
/// `application` suite every app gets for free). Accessibility UI-scripting
/// — finding Clock's actual Lap/Stop AXButtons and performing kAXPress on
/// them, the same way a person clicking the real buttons would — is the
/// only way to make the island's buttons genuinely control Clock, not just
/// Islandia's own read of it. See ClockUIController for the shared AX-tree
/// walk, tab-switch, and minimized-window handling this and
/// ClockTimerController both build on.
enum ClockStopwatchController {
  enum Command {
    case lap
    case stop
  }

  /// [completion] reports whether a real button press actually reached
  /// Clock — see ClockUIController.onMainWindow's own doc comment for the
  /// one confirmed way this can genuinely fail (Clock's window not on the
  /// currently-active Space) versus every other exit here, which would
  /// only trip on a state so broken (Accessibility revoked, Clock
  /// uninstalled, its whole UI restructured) that Islandia already has
  /// bigger problems than this one button.
  static func send(_ command: Command, completion: @escaping (Bool) -> Void = { _ in }) {
    guard ClockUIController.accessibilityIsAvailable() else {
      completion(false)
      return
    }
    guard let app = ClockUIController.launchOrActivateClock() else {
      completion(false)
      return
    }

    // Clock needs a moment to finish opening/activating before its window
    // exists in the AX tree at all — matching the same
    // "just-launched-app-has-no-window-yet" race every other AX-scripting
    // caller here has to account for (NowPlayingChannel's raise-window path
    // only ever runs against an already-running app, so it didn't need
    // this; a fresh Clock launch does).
    let attempt = { perform(command, for: app, completion: completion) }
    if app.isFinishedLaunching {
      attempt()
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: attempt)
    }
  }

  private static func perform(_ command: Command, for app: NSRunningApplication, completion: @escaping (Bool) -> Void) {
    ClockUIController.onMainWindow(
      of: app,
      selectTab: "Stopwatch",
      then: { window in
        let title = command == .lap ? "Lap" : "Stop"
        guard let button = ClockUIController.findButton(titled: title, in: window) else {
          completion(false)
          return
        }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        completion(true)
      },
      onUnreachable: { completion(false) }
    )
  }
}
