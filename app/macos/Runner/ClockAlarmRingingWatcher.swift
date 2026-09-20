import Cocoa

/// Whether a Clock-app timer OR alarm is currently ringing, unresolved by
/// the user yet — the one thing com.apple.mobiletimerd's own preferences
/// plist cannot tell you. Live testing found the plist collapses "just
/// fired, still ringing" and "fired, already dismissed" into the exact
/// same state within a single second — both AppleScript's window list and
/// the plist's own fields were checked and ruled out first.
///
/// What *does* distinguish them, confirmed live via a captured
/// `log stream` session across an actual ring-then-dismiss: the system
/// notification's alert tone is played and stopped as two distinct,
/// separately-timestamped `com.apple.ToneLibrary:Playback` log lines —
/// `-play…` when the alert starts (`shouldRepeat = YES`, matching Clock's
/// own "rings until dismissed" behavior), and `-stop…` the instant the
/// notification banner is clicked. The line's own `type = timer` /
/// `type = alarm` segment (confirmed live for both: a real fired timer
/// logs the former, a real fired alarm the latter — same play/stop marker
/// convention either way) is what lets one instance of this watcher
/// ignore every other app's notification sounds *and* every fired thing
/// of the other kind — [kind] parameterizes which.
///
/// Two independent instances (one per [Kind]) are run side by side rather
/// than one watcher reporting a single bool for "something is ringing" —
/// a timer firing while an alarm is also ringing (or the reverse) needs
/// two independently-resolvable facts, not one shared flag that would
/// either collide or arbitrarily prefer one over the other.
///
/// Same log-message-format caveat as WindowServerStatusIndicatorAdapter:
/// this is not a documented API and could change or go silent on any OS
/// update with no notice. Modeled directly on that adapter's
/// backfill-then-stream-with-crash-restart shape (and, now, its
/// keyword-parameterization) rather than inventing a new one — same
/// reasons, so not re-explained here; see its own doc comment.
final class ClockAlarmRingingWatcher {
  enum Kind: String {
    case timer
    case alarm
  }

  private let kind: Kind
  private var streamProcess: Process?
  private var backfillProcess: Process?
  private var eventSink: ((Bool) -> Void)?
  private var lineBuffer = Data()
  private var restartAttempt = 0
  private var stoppedIntentionally = false

  private static let newline = Data([0x0A])
  private static let backfillWindow = "2m"

  init(kind: Kind) {
    self.kind = kind
  }

  private var predicate: String {
    "subsystem == \"com.apple.ToneLibrary\" AND category == \"Playback\" AND eventMessage CONTAINS \"type = \(kind.rawValue)\""
  }

  /// Apple's logger appends a literal ellipsis (U+2026, not three periods)
  /// and a colon right after the method name on its own summary line —
  /// `-play…: completionHandler != NULL.` / `-stop…: options = (null).`,
  /// confirmed byte-for-byte live. A bare `"-play"`/`"-stop"` substring
  /// check (an earlier version of this) also matched unrelated prose
  /// elsewhere in the same log burst — "audio volume: queue-**play**er."
  /// contains "-play" too — and flipped ringing state on that false
  /// positive; confirmed live by finding this exact line as the culprit.
  /// The ellipsis-colon suffix is specific to the real method-entry log
  /// line and wasn't found anywhere else across every captured session.
  private static let playMarker = "-play\u{2026}:"
  private static let stopMarker = "-stop\u{2026}:"

  func start(onChange: @escaping (Bool) -> Void) {
    eventSink = onChange
    stoppedIntentionally = false
    restartAttempt = 0
    launch()
  }

  func stop() {
    stoppedIntentionally = true
    eventSink = nil
    backfillProcess?.terminationHandler = nil
    backfillProcess?.terminate()
    backfillProcess = nil
    teardownStream()
  }

  private func launch() {
    let backfill = Process()
    backfill.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    backfill.arguments = [
      "show", "--last", Self.backfillWindow, "--info", "--style", "compact",
      "--predicate", predicate,
    ]
    let pipe = Pipe()
    backfill.standardOutput = pipe
    backfill.standardError = FileHandle.nullDevice

    backfill.terminationHandler = { [weak self] _ in
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      let text = String(data: data, encoding: .utf8) ?? ""
      DispatchQueue.main.async {
        guard let self else { return }
        self.eventSink?(Self.mostRecentState(in: text))
        self.launchStream()
      }
    }

    do {
      try backfill.run()
      backfillProcess = backfill
    } catch {
      // No history to go on — a fresh alarm firing right after launch is
      // still caught live by the stream below; this only misses one that
      // was already ringing before Islandia started watching.
      eventSink?(false)
      launchStream()
    }
  }

  /// Chronological like `log show` always is — the last play/stop seen
  /// while scanning forward is whatever's true right now. A short (2m)
  /// backfill window is enough since a ringing alarm this old would already
  /// be well past any timer's realistic max duration without being
  /// dismissed, and keeps the lookback itself fast.
  private static func mostRecentState(in text: String) -> Bool {
    var ringing = false
    for line in text.split(separator: "\n") {
      if line.contains(Self.playMarker) {
        ringing = true
      } else if line.contains(Self.stopMarker) {
        ringing = false
      }
    }
    return ringing
  }

  private func launchStream() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
      "stream", "--info", "--style", "compact",
      "--predicate", predicate,
    ]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    // readabilityHandler fires on a background queue; every callback into
    // Dart has to happen on the platform thread, same rule as every other
    // log-backed provider here.
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      DispatchQueue.main.async {
        self?.consume(data)
      }
    }

    process.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async { self?.handleExit() }
    }

    do {
      try process.run()
      streamProcess = process
    } catch {
      scheduleRestart()
    }
  }

  private func handleExit() {
    teardownStream()
    guard !stoppedIntentionally else { return }
    scheduleRestart()
  }

  private func scheduleRestart() {
    restartAttempt += 1
    let delaySeconds = min(30.0, pow(2.0, Double(restartAttempt)))
    DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
      guard let self, !self.stoppedIntentionally else { return }
      // Full relaunch, backfill included — a restart faces exactly the
      // same "is it ringing right now" blind spot a fresh launch does.
      self.launch()
    }
  }

  private func consume(_ data: Data) {
    lineBuffer.append(data)
    while let range = lineBuffer.range(of: Self.newline) {
      let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<range.lowerBound)
      lineBuffer.removeSubrange(lineBuffer.startIndex..<range.upperBound)
      guard let line = String(data: lineData, encoding: .utf8) else { continue }
      handle(line: line)
    }
  }

  private func handle(line: String) {
    if line.contains(Self.playMarker) {
      eventSink?(true)
    } else if line.contains(Self.stopMarker) {
      eventSink?(false)
    }
  }

  private func teardownStream() {
    streamProcess?.terminationHandler = nil
    streamProcess?.terminate()
    streamProcess = nil
    lineBuffer.removeAll()
  }
}
