import ApplicationServices
import Cocoa

/// Shared Accessibility UI-scripting core for driving any one of Clock's
/// tabs from the island's own buttons — the same underlying approach
/// ClockStopwatchController pioneered for Lap/Stop, generalized here so
/// ClockTimerController (Cancel/Pause) doesn't duplicate the whole AX-tree
/// walk, tab-switch race handling, and minimized-window handling a second
/// time. See ClockStopwatchController's own (now slimmer) doc comment for
/// the specific findings this is built on — AXDescription over AXTitle for
/// labels, kAXValueAttribute for whether a tab is already selected, etc.
enum ClockUIController {
  private static let clockBundleIdentifier = "com.apple.clock"
  private static var didPromptForAccessibility = false

  static func accessibilityIsAvailable() -> Bool {
    if AXIsProcessTrusted() { return true }
    guard !didPromptForAccessibility else { return false }
    didPromptForAccessibility = true
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// Returns the already-running Clock, or launches it and returns the new
  /// instance — either way, without stealing focus from whatever app the
  /// user is actually working in (`.async` activation policy), since a
  /// button tap here is meant to be a quick background action, not a
  /// context switch.
  static func launchOrActivateClock() -> NSRunningApplication? {
    if let running = NSRunningApplication.runningApplications(withBundleIdentifier: clockBundleIdentifier).first {
      return running
    }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: clockBundleIdentifier) else { return nil }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    var launched: NSRunningApplication?
    let semaphore = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
      launched = app
      semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 3)
    return launched
  }

  /// Runs [afterTabSelected] against Clock's main window, having first
  /// un-minimized it (see [unminimizeIfNeeded]'s own doc comment) and
  /// selected [tabTitle] in the World Clock/Alarms/Stopwatch/Timers tab
  /// bar. The 0.15s wait before [afterTabSelected] only happens when a real
  /// tab switch occurred — see [selectTabIfNeeded]'s doc comment for why
  /// that distinction (not merely whether the press action dispatched) is
  /// what actually makes this conditional in practice, not just in name.
  ///
  /// [onUnreachable] fires instead, synchronously, when Clock's own window
  /// can't be read via Accessibility at all — confirmed live (and
  /// independently documented: WindowServer/AX only populates
  /// `kAXWindowsAttribute` for a window whose Space is currently active,
  /// same root cause `yabai` and `AltTab` both hit and neither can work
  /// around; see their own docs/issue trackers) that this is *not* about
  /// Clock being minimized or closed — both of those still report a
  /// (unminimizable-if-needed, or absent-window) result just fine. It's
  /// specifically "Clock's window exists somewhere, but not on the Space
  /// that's currently active" (e.g. some other app is full-screen, or the
  /// user is simply on a different virtual desktop) — a real macOS
  /// limitation with no known public-API workaround, not a bug in this
  /// code to keep chasing further.
  static func onMainWindow(
    of app: NSRunningApplication,
    selectTab tabTitle: String,
    then afterTabSelected: @escaping (AXUIElement) -> Void,
    onUnreachable: @escaping () -> Void
  ) {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var windowsRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
      let windows = windowsRef as? [AXUIElement], let window = windows.first
    else {
      onUnreachable()
      return
    }

    unminimizeIfNeeded(window)

    if selectTabIfNeeded(titled: tabTitle, in: window) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { afterTabSelected(window) }
    } else {
      afterTabSelected(window)
    }
  }

  /// A minimized window's AXButtons still resolve and report success, but
  /// pressing them has no visible or logical effect — confirmed live
  /// against the Stopwatch's Lap/Stop buttons: they worked correctly right
  /// up until Clock was minimized, at which point they silently did
  /// nothing despite every AX call still reporting success. Un-minimizing
  /// first (never raising/activating — this only needs the window to be a
  /// live target, not focused; these are background actions, not a context
  /// switch) matches NowPlayingChannel.unminimizeAndRaiseWindows'
  /// precedent for the exact same underlying AX quirk.
  @discardableResult
  private static func unminimizeIfNeeded(_ window: AXUIElement) -> Bool {
    var minimizedRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
      let isMinimized = minimizedRef as? Bool, isMinimized
    else { return false }
    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    return true
  }

  /// Clock's World Clock / Alarms / Stopwatch / Timers tab bar is a row of
  /// AXRadioButtons. The return value has to reflect whether a switch
  /// actually *happened*, not whether the press action merely dispatched —
  /// confirmed live that `AXUIElementPerformAction` on an already-selected
  /// `AXRadioButton` still reports `.success` even though nothing changed,
  /// which is exactly why an earlier version of this method (using that
  /// return value directly, with no prior value check at all) always
  /// reported `true` on every single press regardless of which tab was
  /// already showing — the real cause of a reported ~0.5s lag on every
  /// button press that persisted no matter how the delay itself was gated.
  /// Checking `kAXValueAttribute` first (1 = selected, the standard
  /// AXRadioButton convention) and skipping the press entirely when
  /// already selected is the actual fix.
  @discardableResult
  private static func selectTabIfNeeded(titled tabTitle: String, in window: AXUIElement) -> Bool {
    guard let tab = findElement(titled: tabTitle, role: kAXRadioButtonRole, in: window) else { return false }
    var valueRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(tab, kAXValueAttribute as CFString, &valueRef) == .success,
      let value = valueRef as? Int, value == 1 {
      return false // already selected — nothing to switch, no race to wait out
    }
    AXUIElementPerformAction(tab, kAXPressAction as CFString)
    return true
  }

  static func findButton(titled title: String, in element: AXUIElement) -> AXUIElement? {
    findElement(titled: title, role: kAXButtonRole, in: element)
  }

  /// Description first, title as a fallback that nothing here actually
  /// depends on ever firing for Clock specifically — confirmed live (a
  /// temporary AX-tree dump caught this directly): Clock's own buttons and
  /// its tab bar's radio buttons all report `AXTitle == nil`, with their
  /// real visible text only in `AXDescription`.
  private static func elementLabel(_ element: AXUIElement) -> String? {
    var descRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
      let description = descRef as? String, !description.isEmpty {
      return description
    }
    var titleRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
      let title = titleRef as? String, !title.isEmpty {
      return title
    }
    return nil
  }

  /// Depth-first search over the whole AX subtree — Clock's exact view
  /// nesting was never directly inspected any other way (no sdef, no
  /// scripting bridge at all), so this makes no assumption about how many
  /// levels deep any particular button or tab sits, and degrades safely: a
  /// label Apple changes in some future OS just makes this silently find
  /// nothing rather than crash or click the wrong control.
  private static func findElement(titled title: String, role: String, in element: AXUIElement) -> AXUIElement? {
    var roleRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
      let actualRole = roleRef as? String, actualRole == role {
      if elementLabel(element) == title {
        return element
      }
    }

    var childrenRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
      let children = childrenRef as? [AXUIElement]
    else { return nil }

    for child in children {
      if let found = findElement(titled: title, role: role, in: child) {
        return found
      }
    }
    return nil
  }

  /// Temporary live-debugging aid — prints every element's role/title/
  /// description, the same way the original Stopwatch AX-tree dump that
  /// caught the AXDescription-not-AXTitle quirk worked. Not meant to ship
  /// long-term; callers wire it in only while chasing a specific "button
  /// not found" report, same as ClockStopwatchController's own now-removed
  /// prints during its earlier debugging round.
  static func dumpTree(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 8) {
    guard depth <= maxDepth else { return }
    var roleRef: CFTypeRef?
    var titleRef: CFTypeRef?
    var descRef: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    _ = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
    let indent = String(repeating: "  ", count: depth)
    print("\(indent)\(String(describing: roleRef)) title=\(String(describing: titleRef)) desc=\(String(describing: descRef))")
    var childrenRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
      let children = childrenRef as? [AXUIElement]
    else { return }
    for child in children {
      dumpTree(child, depth: depth + 1, maxDepth: maxDepth)
    }
  }
}
