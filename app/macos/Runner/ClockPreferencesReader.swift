import Foundation

/// Reads the macOS Clock app's timer/stopwatch state straight out of its
/// preferences domain — there is no public API for either (confirmed via
/// research before attempting this, same as camera/screen-capture). This is
/// a private, undocumented plist schema; Apple could change or redact it on
/// any OS update with no notice, same trade-off already made and accepted
/// for WindowServerStatusIndicatorAdapter.
///
/// Every array entry is itself a single-key dict — `{"$MTTimer": {...}}` /
/// `{"$MTStopwatch": {...}}` — an NSKeyedArchiver object-wrapper, not a
/// plain record. `unwrap` strips exactly that one layer; nothing here
/// attempts full keyed-unarchiving, since everything needed is a plain
/// number/string/date one level under the wrapper.
enum ClockPreferencesReader {
  private static let domain = "com.apple.mobiletimerd" as CFString

  struct RunningTimer {
    let id: String
    let remainingSeconds: Double
    let title: String

    /// The timer's original, full duration — straight off `MTTimerDuration`,
    /// a plain number present alongside `MTTimerFireTime` (confirmed live in
    /// the same raw plist dump used to identify `MTTimerFireTime`'s two
    /// shapes; it does not itself change as the timer counts down). Needed
    /// for a radial progress indicator (`remainingSeconds / durationSeconds`),
    /// which nothing here previously required.
    let durationSeconds: Double
  }

  struct RunningStopwatch {
    let id: String
    let elapsedSeconds: Double

    /// Recorded lap splits in the order they were taken (lap 1 first) —
    /// straight off `MTStopwatchLaps`, a plain array of per-lap durations in
    /// seconds, nothing to unwrap or interpret (confirmed live: this is the
    /// one stopwatch field that isn't itself an NSKeyedArchiver-wrapped
    /// value). Does not include whatever's elapsed on the current,
    /// not-yet-lapped span — that's `elapsedSeconds` minus this array's sum.
    let laps: [Double]
  }

  /// Soonest-firing timer first.
  ///
  /// `MTTimerFireTime` comes in two different shapes, confirmed live, and
  /// only one of them belongs to an actually-running timer:
  /// - `$MTTimerTimeInterval` (a plain relative-seconds number, equal to
  ///   `MTTimerDuration`): an idle, never-started timer. Verified live —
  ///   every freshly-created-but-not-started timer has this shape, and the
  ///   value never changes on its own no matter how long it sits idle.
  /// - `$MTTimerDate` (an absolute future date, paired with
  ///   `MTTimerFireTimerClass == "MTTimerDate"`): an actually-running
  ///   timer. Verified live by starting a real 60s timer and finding
  ///   exactly this shape, with the date landing 60s after start —
  ///   remaining time is that date minus now, not a stored countdown.
  /// A running timer is therefore identified by having the *date* shape at
  /// all, not by matching a specific `MTTimerState` integer — live testing
  /// found more than one non-idle value in use (2 and 3) with no confirmed
  /// exhaustive list.
  static func runningTimers() -> [RunningTimer] {
    guard let timers = dictArray(key: "MTTimers", innerKey: "MTTimers") else { return [] }
    let running = timers.compactMap { entry -> RunningTimer? in
      guard let timer = unwrap(entry, wrapperKey: "$MTTimer") else { return nil }
      guard
        let id = timer["MTTimerID"] as? String,
        let fireDate = fireDate(timer["MTTimerFireTime"])
      else { return nil }
      let remaining = fireDate.timeIntervalSinceNow
      guard remaining > 0 else { return nil }
      let title = timer["MTTimerTitle"] as? String ?? ""
      let duration = number(timer["MTTimerDuration"]) ?? remaining
      return RunningTimer(id: id, remainingSeconds: remaining, title: title, durationSeconds: duration)
    }
    return running.sorted { $0.remainingSeconds < $1.remainingSeconds }
  }

  /// Clock only ever shows one stopwatch's UI, but the schema is an array.
  ///
  /// `MTStopwatchCurrentInterval` is *not* a live-updating value while
  /// running — verified live: it sits frozen at 0 for the entire running
  /// span and only gets written with the true elapsed value at the instant
  /// the stopwatch is paused (confirmed by pausing one running ~296s in and
  /// watching it jump straight from 0 to 296.39 in the same write). The
  /// field that *is* live while running is `MTStopwatchStartDate` — present
  /// only then (confirmed absent once paused) — so elapsed has to be
  /// computed as wall-clock time since that date, not read off a stored
  /// counter, whenever the stopwatch is actually still running.
  ///
  /// A *paused* stopwatch (state 1, live-tested) is deliberately not
  /// reported as running here — its CurrentInterval is correct but frozen,
  /// which is exactly "not currently running," matching what this provider
  /// is asked for. State 0 (live-tested: fully idle/reset) is excluded the
  /// same way. Not a confirmed-exhaustive enum, same caveat as
  /// runningTimers() — only 0, 1, and 2 have been observed.
  static func runningStopwatch() -> RunningStopwatch? {
    guard let stopwatches = dictArray(key: "MTStopwatches", innerKey: "MTStopwatches") else { return nil }
    for entry in stopwatches {
      guard let stopwatch = unwrap(entry, wrapperKey: "$MTStopwatch") else { continue }
      guard
        let id = stopwatch["MTStopwatchIdentifier"] as? String,
        let startDate = stopwatch["MTStopwatchStartDate"] as? Date
      else { continue }
      let previousLaps = number(stopwatch["MTStopwatchPreviousLapsTotalInterval"]) ?? 0
      let offset = number(stopwatch["MTStopwatchOffset"]) ?? 0
      let elapsed = -startDate.timeIntervalSinceNow + previousLaps + offset
      let laps = (stopwatch["MTStopwatchLaps"] as? [NSNumber])?.map { $0.doubleValue } ?? []
      return RunningStopwatch(id: id, elapsedSeconds: elapsed, laps: laps)
    }
    return nil
  }

  struct Alarm {
    let id: String
    let title: String
    let hour: Int
    let minute: Int
    let enabled: Bool

    /// 0 confirmed live for a plain, one-off (non-repeating) alarm — not a
    /// confirmed-exhaustive enum otherwise (no repeating alarm has been
    /// created to observe a non-zero value), same open caveat as
    /// MTTimerState/MTStopwatch's own state ints above. Not currently
    /// interpreted into anything beyond being carried through as-is.
    let repeatSchedule: Int
  }

  /// Every alarm Clock knows about, in whatever order `MTAlarms` stores
  /// them — unlike runningTimers()/runningStopwatch(), there's no
  /// "currently active" filter to apply here: an alarm just *is*, whether
  /// enabled or not, until the user deletes it. Confirmed live via a real
  /// created alarm ("App Testing", 21:48): the wrapper key is `$MTAlarm`
  /// (same NSKeyedArchiver single-key-dict shape as $MTTimer/$MTStopwatch),
  /// and MTAlarmHour/MTAlarmMinute are plain 24-hour-clock integers, not a
  /// wrapped date the way MTTimerFireTime is — this alarm fires at a fixed
  /// wall-clock time every day it's scheduled for, not a relative offset
  /// from when it was created, so there's no "remaining" to compute the
  /// way a timer has.
  static func alarms() -> [Alarm] {
    guard let entries = dictArray(key: "MTAlarms", innerKey: "MTAlarms") else { return [] }
    return entries.compactMap { entry -> Alarm? in
      guard let alarm = unwrap(entry, wrapperKey: "$MTAlarm") else { return nil }
      guard
        let id = alarm["MTAlarmID"] as? String,
        let hour = number(alarm["MTAlarmHour"]),
        let minute = number(alarm["MTAlarmMinute"])
      else { return nil }
      let title = alarm["MTAlarmTitle"] as? String ?? ""
      let enabled = (number(alarm["MTAlarmEnabled"]) ?? 0) != 0
      let repeatSchedule = Int(number(alarm["MTAlarmRepeatSchedule"]) ?? 0)
      return Alarm(id: id, title: title, hour: Int(hour), minute: Int(minute), enabled: enabled, repeatSchedule: repeatSchedule)
    }
  }

  private static func unwrap(_ entry: [String: Any], wrapperKey: String) -> [String: Any]? {
    entry[wrapperKey] as? [String: Any]
  }

  private static func fireDate(_ raw: Any?) -> Date? {
    guard let fireTime = raw as? [String: Any] else { return nil }
    guard let inner = fireTime["$MTTimerDate"] as? [String: Any] else { return nil }
    return inner["MTTimerTimeDate"] as? Date
  }

  private static func number(_ raw: Any?) -> Double? {
    if let n = raw as? NSNumber { return n.doubleValue }
    return nil
  }

  private static func dictArray(key: String, innerKey: String) -> [[String: Any]]? {
    guard
      let outer = CFPreferencesCopyAppValue(key as CFString, domain) as? [String: Any],
      let array = outer[innerKey] as? [[String: Any]]
    else { return nil }
    return array
  }
}
