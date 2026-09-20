import Cocoa
import FlutterMacOS

/// Shared engine behind every WindowServer `StatusIndicator`-based indicator
/// (camera, screen capture) — both watch the same log subsystem for their
/// own `"<keyword> added"` / `"<keyword> removed"` pair, and both need the
/// same two things a plain `log stream` doesn't give you for free:
///
/// 1. Current-state backfill. `log stream` only ever reports *future*
///    events — launched mid-call, after the camera/share already started,
///    it would otherwise show nothing until the *next* transition. Every
///    (re)launch runs a one-shot `log show --last 60m` lookback first and
///    takes whichever of "added"/"removed" appears last in it as the
///    starting state, before switching over to the live stream for
///    anything after that. Verified live: triggering a real camera session
///    and then querying `log show --last` after the fact does find it, with
///    no "removed" following, exactly as this relies on.
/// 2. Crash-restart with backoff. A `log stream` subprocess dying
///    mid-session — from an OS hiccup, or literally anything killing it —
///    otherwise silently strands the indicator on stale state, with
///    nothing left watching for the eventual "removed" event (this
///    happened for real once, during development, from human error).
///    Restarting re-runs the same backfill step too, so a restart doesn't
///    reintroduce the exact blind spot backfill exists to close.
///
/// This is still a log *message format*, not a documented API — Apple could
/// change or redact it on any OS update with no notice, and there is no
/// fallback if that happens: the indicator just goes quiet. That trade-off
/// was made explicitly for camera first, then reused here rather than
/// re-litigated, not discovered after the fact.
final class WindowServerStatusIndicatorAdapter {
  private let keyword: String
  private var streamProcess: Process?
  private var backfillProcess: Process?
  private var eventSink: FlutterEventSink?
  private var lineBuffer = Data()
  private var restartAttempt = 0
  private var stoppedIntentionally = false

  private static let newline = Data([0x0A])
  /// Generous enough to catch "I've been on this call for a while" (the
  /// case this exists for), short enough that the one-shot lookback stays
  /// fast. A session older than this at launch time is a known, accepted
  /// gap — the indicator would only pick it up on the next transition.
  private static let backfillWindow = "60m"

  init(keyword: String) {
    self.keyword = keyword
  }

  private var predicate: String {
    "subsystem == \"com.apple.SkyLight\" AND category == \"StatusIndicator\" AND eventMessage CONTAINS \"\(keyword)\""
  }

  func start(eventSink: @escaping FlutterEventSink) {
    self.eventSink = eventSink
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
        self.eventSink?(Self.mostRecentState(in: text, keyword: self.keyword))
        self.launchStream()
      }
    }

    do {
      try backfill.run()
      backfillProcess = backfill
    } catch {
      // No history to go on — same safe default as if the lookback simply
      // found nothing, then fall straight through to live watching.
      eventSink?(false)
      launchStream()
    }
  }

  /// `log show`'s output is chronological — the last "added"/"removed" seen
  /// while scanning forward is whatever's true right now.
  private static func mostRecentState(in text: String, keyword: String) -> Bool {
    var active = false
    for line in text.split(separator: "\n") {
      if line.contains("\(keyword) added") {
        active = true
      } else if line.contains("\(keyword) removed") {
        active = false
      }
    }
    return active
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

    // readabilityHandler fires on a background queue, and every eventSink
    // call has to happen on the platform thread or the Flutter engine
    // connection crashes — same rule as every other log-backed provider.
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
      // same "what's true right now" blind spot a fresh launch does.
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
    // WindowServer already tracks multi-client use for its own indicator —
    // "added" only fires on the 0→1 transition and "removed" only on 1→0 —
    // so this can just forward the two states directly, no refcounting.
    if line.contains("\(keyword) added") {
      eventSink?(true)
    } else if line.contains("\(keyword) removed") {
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
