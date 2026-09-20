import ApplicationServices
import Cocoa

/// Drives the real Clock app's Timers tab from the island's own Cancel/Pause
/// buttons — same rationale and approach as ClockStopwatchController for
/// Lap/Stop (no public or private write API for Clock exists at all; this
/// is Accessibility UI-scripting, the same buttons a person clicking them
/// would use). See ClockUIController for the shared AX-tree walk, tab
/// switching, and minimized-window handling both controllers build on.
///
/// Clock's Timer button row toggles between "Pause"/"Resume" depending on
/// whether the timer is currently running or paused — the same physical
/// AXButton either way, confirmed live (pressing it while running pauses;
/// pressing the same element again, now labeled "Resume", resumes). This
/// island always sends [Command.pause] for both directions — its own
/// Dart-side state (island_shell.dart's _pausedTimerOverride) already
/// knows which one is semantically intended and flips its own button's
/// label/color accordingly (see clock_awareness_activity.dart's
/// _TimerExpanded) — but the *native* search here has no such context, so
/// it tries "Pause" first and falls back to "Resume": whichever Clock is
/// actually showing right now is the one that needs pressing, and this
/// island can't know in advance which without inspecting the AX tree
/// anyway. Cancel is unambiguous — its own label never changes.
enum ClockTimerController {
  enum Command {
    case cancel
    case pause
  }

  /// [completion] reports whether a real button press actually reached
  /// Clock — see ClockStopwatchController.send's own doc comment (shared
  /// rationale) and ClockUIController.onMainWindow's for the one confirmed
  /// way this can genuinely fail (Clock's window not on the
  /// currently-active Space).
  static func send(_ command: Command, completion: @escaping (Bool) -> Void = { _ in }) {
    guard ClockUIController.accessibilityIsAvailable() else {
      completion(false)
      return
    }
    guard let app = ClockUIController.launchOrActivateClock() else {
      completion(false)
      return
    }

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
      selectTab: "Timers",
      then: { window in
        switch command {
        case .cancel:
          guard let button = ClockUIController.findButton(titled: "Cancel", in: window) else {
            completion(false)
            return
          }
          AXUIElementPerformAction(button, kAXPressAction as CFString)
          completion(true)
        case .pause:
          let button = ClockUIController.findButton(titled: "Pause", in: window) ?? ClockUIController.findButton(titled: "Resume", in: window)
          guard let button else {
            completion(false)
            return
          }
          AXUIElementPerformAction(button, kAXPressAction as CFString)
          completion(true)
        }
      },
      onUnreachable: { completion(false) }
    )
  }
}
