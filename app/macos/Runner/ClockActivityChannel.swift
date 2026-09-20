import Cocoa
import FlutterMacOS

/// Bridges the macOS Clock app's timer/stopwatch state to Dart — see
/// ClockPreferencesReader (values) and ClockAlarmRingingWatcher (the
/// ringing-vs-dismissed signal neither the plist nor AppleScript can give)
/// for where each half of the payload actually comes from.
final class ClockActivityChannel: NSObject, FlutterStreamHandler {
  private let ringingWatcher = ClockAlarmRingingWatcher(kind: .timer)
  /// Independent from [ringingWatcher] — see ClockAlarmRingingWatcher's own
  /// doc comment for why a timer ringing and an alarm ringing need two
  /// separately-resolvable facts rather than one shared bool.
  private let alarmRingingWatcher = ClockAlarmRingingWatcher(kind: .alarm)
  private var pollTimer: Timer?
  private var eventSink: FlutterEventSink?
  private var isRinging = false
  /// Unlike a fired timer, a fired alarm never drops out of
  /// ClockPreferencesReader.alarms() at all — confirmed live: it stays in
  /// MTAlarms with MTAlarmEnabled flipped to 0 (for a one-off alarm) and an
  /// MTAlarmFireDate/MTAlarmDismissDate pair added, not removed the way a
  /// completed timer disappears from MTTimers. There's also no per-alarm
  /// identifier in the ToneLibrary log line the way there would need to be
  /// to know *which* alarm is ringing (the same limitation
  /// ClockAlarmRingingWatcher's timer side already accepts — see its own
  /// doc comment) — so this is deliberately a plain "something is
  /// ringing" bool, no lastFiredTimer-style remembered identity to pair
  /// with it, and no `alarms` list filtering tied to it either.
  private var isAlarmRinging = false

  /// The instant a timer's remaining time reaches zero,
  /// `ClockPreferencesReader.runningTimers()` correctly stops reporting it —
  /// it's not "running" anymore by that method's own definition. But the
  /// alarm keeps ringing for as long as it takes the user to dismiss it
  /// (isRinging stays true that whole time — see ClockAlarmRingingWatcher),
  /// so there's a real gap to bridge: whichever fired first — the plist
  /// dropping the timer, or the ringing watcher's log line — the *other*
  /// signal hasn't caught up yet. `emit()` is called independently from two
  /// uncoordinated sources (the poll timer and the ringing watcher's own
  /// callback), so a poll tick landing in that gap would otherwise emit
  /// `(timers: [], isRinging: false)` — a legitimate-looking but stale
  /// reading — one tick before the ringing watcher's `true` arrives.
  /// Verified live: this raced in exactly this order once, and Dart's own
  /// memory of the fired timer (a first attempt at this same fix, one
  /// layer up) cleared itself on that single stale tick before the correct
  /// `true` signal ever got a chance to matter.
  ///
  /// Keeping this fix here, at the one place both signals actually
  /// converge, closes the gap for good — no second signal arrives after
  /// this point for Dart to race against; it only ever sees one, already
  /// self-consistent, reading.
  private var lastFiredTimer: [String: Any]?

  /// Matches the old (removed) TimerController's tick rate — the plist has
  /// no push notification for plain preference writes, so this is polled,
  /// unlike the ringing watcher's live log stream.
  private static let pollInterval: TimeInterval = 1.0

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/clock-activity/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setStreamHandler(self)

    // A separate MethodChannel for the one-shot Lap/Stop commands, matching
    // NowPlayingChannel's split between a state-streaming EventChannel and a
    // command-sending MethodChannel — the stopwatch card's buttons are a
    // side effect (drive the real Clock app), not a change to what this
    // class itself reports, so they don't belong on the updates stream.
    let controlChannel = FlutterMethodChannel(
      name: "islandia/clock-awareness/control",
      binaryMessenger: controller.engine.binaryMessenger
    )
    // Each command's own completion reports whether a real button press
    // actually reached Clock — see ClockUIController.onMainWindow's doc
    // comment for the one confirmed way this fails (Clock's window not on
    // the currently-active Space, a real macOS limitation, not a bug to
    // silently swallow). Returning that as the method call's own result,
    // rather than the unconditional `result(nil)` this used to send the
    // instant `send` was *called* rather than once it actually finished,
    // is what lets clock_awareness_provider.dart's ClockAwarenessControl
    // tell its caller the command genuinely failed instead of assuming
    // every tap always works.
    controlChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "lap":
        ClockStopwatchController.send(.lap) { result($0) }
      case "stop":
        ClockStopwatchController.send(.stop) { result($0) }
      case "cancelTimer":
        ClockTimerController.send(.cancel) { result($0) }
      case "pauseTimer":
        ClockTimerController.send(.pause) { result($0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    ringingWatcher.start { [weak self] ringing in
      guard let self else { return }
      self.isRinging = ringing
      self.emit()
    }
    alarmRingingWatcher.start { [weak self] ringing in
      guard let self else { return }
      self.isAlarmRinging = ringing
      self.emit()
    }
    emit()
    let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      self?.emit()
    }
    RunLoop.main.add(timer, forMode: .common)
    pollTimer = timer
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    ringingWatcher.stop()
    alarmRingingWatcher.stop()
    pollTimer?.invalidate()
    pollTimer = nil
    eventSink = nil
    return nil
  }

  private func emit() {
    guard let sink = eventSink else { return }
    let timers = ClockPreferencesReader.runningTimers()
    let stopwatch = ClockPreferencesReader.runningStopwatch()
    let alarms = ClockPreferencesReader.alarms()

    let timerPayloads: [[String: Any]] = timers.map { timer in
      ["id": timer.id, "remainingSeconds": timer.remainingSeconds, "title": timer.title, "durationSeconds": timer.durationSeconds]
    }

    let effectiveTimerPayloads: [[String: Any]]
    if let first = timerPayloads.first {
      lastFiredTimer = first
      effectiveTimerPayloads = timerPayloads
    } else if !isRinging {
      lastFiredTimer = nil
      effectiveTimerPayloads = []
    } else if let remembered = lastFiredTimer {
      effectiveTimerPayloads = [remembered]
    } else {
      effectiveTimerPayloads = []
    }

    sink([
      // NB: "isRinging" (below) is about a fired *timer*'s alarm sound —
      // an unfortunately-established name from before scheduled Alarms
      // were tracked at all; see ClockAwarenessSnapshot.isAlarmRinging's
      // own doc comment on the Dart side. "isScheduledAlarmRinging" is
      // deliberately a different word entirely, not "isAlarmRinging2" or
      // similar, so the two are never confused reading either side.
      "isRinging": isRinging,
      "isScheduledAlarmRinging": isAlarmRinging,
      "timers": effectiveTimerPayloads,
      "stopwatch": stopwatch.map { stopwatch -> [String: Any] in
        [
          "id": stopwatch.id,
          "elapsedSeconds": stopwatch.elapsedSeconds,
          "laps": stopwatch.laps,
        ]
      } as Any,
      "alarms": alarms.map { alarm -> [String: Any] in
        [
          "id": alarm.id,
          "title": alarm.title,
          "hour": alarm.hour,
          "minute": alarm.minute,
          "enabled": alarm.enabled,
          "repeatSchedule": alarm.repeatSchedule,
        ]
      },
    ])
  }
}
