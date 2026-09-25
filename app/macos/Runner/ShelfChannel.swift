import Cocoa
import FlutterMacOS

/// The Shelf (§05, Phase 3) — drag any file, folder, or text onto the
/// island (collapsed or expanded) and it's held there until dragged back
/// out, exactly like the real macOS clipboard except by drag gesture
/// instead of Cmd-C/Cmd-V, and holding the actual item rather than routing
/// through NSPasteboard's own general pasteboard. Holds exactly one item;
/// a new drop replaces whatever was already held.
///
/// `NSDraggingDestination`'s callbacks only ever fire on the object
/// `registerForDraggedTypes` was called on — confirmed live via a smoke
/// test that this exact window (borderless, nonactivatingPanel,
/// `.statusBar` level) receives them with zero friction once
/// `MainFlutterWindow` itself subclasses `NSPanel` (see that file's own
/// doc comment for why NSPanel, not NSWindow, was required). That means
/// `MainFlutterWindow` has to hold the actual protocol conformance, but
/// every method body there is a single line forwarding here — this file
/// owns all the real logic (reading the pasteboard, the copy-or-clone
/// decision, thumbnail generation, notifying Dart), matching the
/// one-file-per-integration shape every other feature here already
/// follows.
final class ShelfChannel: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  /// What's currently held, if anything — the Shelf's one and only slot.
  private var heldItem: HeldItem?

  /// The one drag-out gesture in flight, if any — tracked so a second
  /// mouseDown while a drag session is already running can't start a
  /// conflicting one.
  private var isDragSessionActive = false

  /// The island's own window, captured only for the duration of a drag-out
  /// session — draggingSession(_:movedTo:) needs *some* window to hit-test
  /// screenPoint against, and re-querying `NSApp.windows.first(where:)` on
  /// every single mouse-move callback (this can fire dozens of times a
  /// second) is needless work when startDragOut already looked it up once.
  private weak var dragSourceWindow: NSWindow?

  /// Whether the bin-icon/"delete" overlay is currently being shown to
  /// Dart — deduped against redundant emits so movedTo's frequent callback
  /// only actually notifies Dart on a real enter/exit transition, not on
  /// every intermediate point still inside (or still outside) the window.
  private var isPendingDeleteOverIsland = false

  /// True the instant a drag-out ends in a successful drop anywhere, until
  /// the next real drag-in (or explicit clear) replaces it — see
  /// NSDraggingSource's own endedAt:operation: doc comment for why the
  /// underlying `heldItem`/file are deliberately NOT also cleared at that
  /// same moment (a real, reproduced delete-race bug). This flag lets
  /// `emit()` show Dart an "empty" Shelf right away regardless, matching
  /// what the user actually sees happen (the item just got moved
  /// somewhere else, so the island should look empty) without touching the
  /// real held file that acceptFile/acceptText still need to clean up
  /// later. Reset to false the moment anything real changes heldItem
  /// again (a fresh drag-in, an explicit clear, or the self-drop delete).
  private var isDisplayedAsEmptyAfterDragOut = false

  private struct HeldItem {
    enum Kind {
      case file
      case folder
      case text
    }

    let kind: Kind
    /// Where this item's own copy lives inside the Shelf's storage
    /// directory — nil for `.text`, which has no on-disk file at all,
    /// just the attributed string kept in memory.
    let fileURL: URL?
    /// Only populated for `.text` — an RTF/HTML source keeps its real
    /// formatting; a plain-text source becomes a plain `NSAttributedString`
    /// with no special attributes, which still round-trips correctly
    /// through `NSDraggingItem(pasteboardWriter:)` on drag-out.
    let attributedText: NSAttributedString?
    let displayName: String
    /// Total bytes on disk — nil for `.text` (see [attributedText]'s own
    /// comment, same reasoning: nothing on disk to measure). For `.folder`
    /// this is the real recursive total of everything inside it, not just
    /// the directory entry's own few-KB size — see [Self.recursiveSize].
    let sizeBytes: Int64?
  }

  /// `~/Library/Caches/<bundle id>/Shelf/` — Caches, not Application
  /// Support: the Shelf is explicitly a temporary, session-scoped holding
  /// spot (never persisted across a restart, capacity of exactly one item),
  /// which is exactly what Caches is for. macOS may clear this under real
  /// disk pressure, an acceptable tradeoff for something this transient.
  private static let storageDirectory: URL = {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let dir = caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.islandia.islandia").appendingPathComponent("Shelf")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  func register(on controller: FlutterViewController) {
    let channel = FlutterEventChannel(
      name: "islandia/shelf/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setStreamHandler(self)

    // A separate MethodChannel for Dart-initiated commands — matching
    // ClockActivityChannel's own split between a state-streaming
    // EventChannel and a command MethodChannel. `startDragOut` is the one
    // real command: Dart detects the press-and-drag gesture on the held
    // item's own preview (it owns that rendering), then asks native to
    // turn that into a genuine NSDraggingSession using the file that
    // already fully exists in the Shelf's storage.
    let controlChannel = FlutterMethodChannel(
      name: "islandia/shelf/control",
      binaryMessenger: controller.engine.binaryMessenger
    )
    controlChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startDragOut":
        self?.startDragOut()
        result(nil)
      case "clear":
        self?.clearHeldItem()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emit()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - NSDraggingDestination (called from MainFlutterWindow's own
  // 1-line forwarding methods)

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    acceptedOperation(for: sender)
  }

  func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    acceptedOperation(for: sender)
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    // `draggingSource` is documented (NSDraggingInfo) to return nil "if the
    // source is not in the same application as the destination" — so a
    // non-nil value that's specifically *this* object means the Shelf just
    // dropped its own held item back onto itself mid-drag-out. Per the
    // confirmed spec ("if the user drops that back into the island then
    // that copy gets deleted and the storage is freed"), that's a delete,
    // not a fresh incoming drop — critically, NOT the same thing as
    // acceptFile/acceptText re-copying the same file onto itself, which
    // would leave the Shelf still holding it (a no-op from the user's
    // perspective, not the delete they asked for by dropping it back on).
    if sender.draggingSource as? ShelfChannel === self {
      clearHeldItem(reason: "deleted")
      return true
    }

    let pasteboard = sender.draggingPasteboard

    // Priority order: a real file/folder first, then rich text, then
    // plain text — a drag can technically offer more than one type at
    // once (e.g. Finder offers both a file URL and its path as a
    // string), so file/folder wins whenever it's genuinely on offer.
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let sourceURL = urls.first {
      acceptFile(at: sourceURL)
      return true
    }

    if let rtfData = pasteboard.data(forType: .rtf), let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
      acceptText(attributed)
      return true
    }
    if let htmlData = pasteboard.data(forType: .html), let attributed = NSAttributedString(html: htmlData, documentAttributes: nil) {
      acceptText(attributed)
      return true
    }
    if let plainString = pasteboard.string(forType: .string) {
      acceptText(NSAttributedString(string: plainString))
      return true
    }

    return false
  }

  /// Only decides yes/no and which `NSDragOperation` to report — reads
  /// nothing from the pasteboard yet (some senders don't finalize their
  /// full type list until `performDragOperation` itself), matching the
  /// standard AppKit contract that entered/updated only ever inspect
  /// `pasteboardTypes`, never the actual payload.
  private func acceptedOperation(for sender: NSDraggingInfo) -> NSDragOperation {
    let types = sender.draggingPasteboard.types ?? []
    let offersSomethingUsable = types.contains(.fileURL) || types.contains(.rtf) || types.contains(.html) || types.contains(.string)
    return offersSomethingUsable ? .copy : []
  }

  // MARK: - Accepting a drop

  private func acceptFile(at sourceURL: URL) {
    let isDirectory = (try? sourceURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    let destinationURL = Self.storageDirectory.appendingPathComponent(sourceURL.lastPathComponent)

    clearStorageDirectory()

    let isSameVolume = sameVolume(sourceURL, Self.storageDirectory)
    if !isSameVolume {
      // A cross-volume copy is real disk I/O, not instant — tell Dart so
      // it can show an in-progress state rather than the pill silently
      // doing nothing for however long the copy takes.
      emit(copyingDisplayName: sourceURL.lastPathComponent)
    }

    // FileManager.copyItem already transparently uses APFS's
    // copy-on-write clone for a same-volume copy (confirmed empirically:
    // a 200MB same-volume copy completed in ~1.6ms) and falls back to a
    // real byte-for-byte copy cross-volume with no special flag needed —
    // nothing here has to touch the raw clonefile() syscall directly.
    // Off the main thread either way, since even the "instant" case is a
    // real syscall and the cross-volume case can be genuinely slow.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        // Measured on the already-copied destination, not the source — the
        // Shelf's own storage is what actually counts against the user's
        // disk, and measuring post-copy also means a folder whose contents
        // changed between drag-start and copy-finish still reports what's
        // really sitting in Shelf right now, not a stale pre-copy guess.
        let size = Self.recursiveSize(of: destinationURL, isDirectory: isDirectory)
        DispatchQueue.main.async {
          self?.heldItem = HeldItem(
            kind: isDirectory ? .folder : .file,
            fileURL: destinationURL,
            attributedText: nil,
            displayName: sourceURL.lastPathComponent,
            sizeBytes: size
          )
          self?.emit()
        }
      } catch {
        // Same silent-failure convention as every other provider here —
        // a failed copy just means the Shelf stays (or goes back to)
        // empty, not a crash.
        DispatchQueue.main.async {
          self?.heldItem = nil
          self?.emit()
        }
      }
    }
  }

  private func acceptText(_ attributed: NSAttributedString) {
    clearStorageDirectory()
    heldItem = HeldItem(kind: .text, fileURL: nil, attributedText: attributed, displayName: attributed.string, sizeBytes: nil)
    emit()
  }

  /// A single file's own `.fileSize` for the non-directory case; a real
  /// recursive walk (`FileManager.enumerator`, which descends into every
  /// subdirectory on its own) summing every regular file's `.fileSize`
  /// for a directory — `attributesOfItem` on a directory URL directly
  /// would report only that directory entry's own few-KB metadata size,
  /// not the actual total of what's inside it.
  private static func recursiveSize(of url: URL, isDirectory: Bool) -> Int64? {
    if !isDirectory {
      return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
    }
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) else {
      return nil
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
      total += Int64(size)
    }
    return total
  }

  /// [reason] exists purely for Dart's own exit-animation choice
  /// (shelf_activity.dart plays a different transition for "deleted" vs.
  /// "the drag-out itself already succeeded, this is just the underlying
  /// cleanup catching up" vs. a plain, unremarkable clear) — it carries no
  /// other meaning and is never read back or stored past the one emit()
  /// call below.
  private func clearHeldItem(reason: String? = nil) {
    clearStorageDirectory()
    heldItem = nil
    emit(emptyReason: reason)
  }

  private func clearStorageDirectory() {
    // Every real change to heldItem funnels through here (both
    // acceptFile/acceptText call this directly before assigning a fresh
    // HeldItem, and clearHeldItem calls it too) — resetting the flag in
    // this one shared spot means it's never missed at a call site that
    // genuinely does change what's held, regardless of which of those
    // paths triggered it.
    isDisplayedAsEmptyAfterDragOut = false
    guard let contents = try? FileManager.default.contentsOfDirectory(at: Self.storageDirectory, includingPropertiesForKeys: nil) else { return }
    for url in contents {
      try? FileManager.default.removeItem(at: url)
    }
  }

  /// Compares `st_dev` (via `.systemNumber`) for the two paths — confirmed
  /// empirically live (two paths on the same real volume report identical
  /// device numbers; a genuinely separate APFS volume reports a different
  /// one) rather than assumed from documentation alone.
  private func sameVolume(_ a: URL, _ b: URL) -> Bool {
    guard
      let aDevice = (try? FileManager.default.attributesOfItem(atPath: a.path))?[.systemNumber] as? Int,
      let bDevice = (try? FileManager.default.attributesOfItem(atPath: b.path))?[.systemNumber] as? Int
    else { return false }
    return aDevice == bDevice
  }

  // MARK: - Drag-out (NSDraggingSource)

  private func startDragOut() {
    guard let heldItem, !isDragSessionActive else { return }
    // `beginDraggingSession` is declared on BOTH NSWindow and NSView — the
    // NSWindow one (confirmed directly against the real AppKit header) is
    // gated `API_AVAILABLE(macos(15.0))`, but the NSView one has been
    // available since 10.7 with no gating at all. This project's
    // deployment target is 12.0, so the call has to go through
    // `contentView`, not the window itself, or it silently resolves to
    // the wrong (too-new) overload.
    guard
      let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }),
      let contentView = window.contentView
    else { return }
    guard let currentEvent = NSApp.currentEvent else { return }

    let draggingItem: NSDraggingItem
    switch heldItem.kind {
    case .file, .folder:
      guard let fileURL = heldItem.fileURL else { return }
      // A plain NSURL pasteboard writer, not NSFilePromiseProvider —
      // NSFilePromiseProvider was tried and reverted: its promise-specific
      // pasteboard types turned out to be recognized by Finder ALONE
      // (confirmed live: Mail, Messages, VS Code, and a Chromium browser
      // all silently failed to recognize the drag at all). A plain, eager
      // NSURL is universally recognized, which matters more than the
      // safe-delete signal NSFilePromiseProvider would have given — see
      // endedAt:operation:'s own doc comment, below, for the full story
      // and how the resulting delete-timing race is instead avoided.
      draggingItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
      let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
      draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 64, height: 64), contents: icon)
    case .text:
      guard let attributedText = heldItem.attributedText else { return }
      draggingItem = NSDraggingItem(pasteboardWriter: attributedText)
      draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 200, height: 40), contents: nil)
    }

    isDragSessionActive = true
    dragSourceWindow = window
    // Tells Dart the drag-out gesture has genuinely started (there was no
    // signal for this at all before — shelf_activity.dart used to have no
    // way to know a drag was in flight beyond isPendingDeleteOverIsland,
    // which only ever turns on once the drag has hovered back over the
    // island specifically). Drives the collapsed pill's own subtle
    // dim/recede-while-held look for as long as isDragging stays true.
    emit()
    _ = contentView.beginDraggingSession(with: [draggingItem], event: currentEvent, source: self)
  }
}

extension ShelfChannel: NSDraggingSource {
  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    // `.copy` regardless of context — dropping the held item onto Finder/
    // Mail/Slack should hand over a copy, never move-and-delete the
    // Shelf's own file out from under it.
    .copy
  }

  /// Live hit-test while the drag-out is in flight, hovering the island's
  /// own window — screenPoint is documented (NSDraggingSource) as screen
  /// coordinates, the same space `NSWindow.frame` is already in, so no
  /// conversion is needed. Drives the bin-icon/"delete" overlay per the
  /// confirmed spec ("dragging it outside the island window then at that
  /// time the island window should show a bin icon and delete text kind of
  /// while the user is still holding the file"): the overlay should show
  /// only once the drag has actually LEFT the island (this fires
  /// continuously from the very start of the gesture, including the first
  /// moments still directly over the pill the user started dragging from,
  /// which must NOT show a delete affordance for a drag that hasn't gone
  /// anywhere yet).
  func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
    guard let window = dragSourceWindow else { return }
    let isOverIsland = window.frame.contains(screenPoint)
    if isOverIsland == isPendingDeleteOverIsland { return }
    isPendingDeleteOverIsland = isOverIsland
    emit()
  }

  func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    isDragSessionActive = false
    dragSourceWindow = nil
    isPendingDeleteOverIsland = false
    // Dropped nowhere valid (or the release point technically missed the
    // island's own accepting region while still hovering it) — the item
    // returns to being shown exactly as it was, just no longer dragging.
    // This is the ONLY branch of this method that both needs an emit AND
    // has no more specific follow-up emit coming right after — the
    // success/self-drop/delete paths below each already end in their own
    // emit() or clearHeldItem() call and must NOT also get this generic
    // one first (that would emit twice in a row for the one gesture,
    // "still holding, not dragging" immediately followed by "empty" —
    // pointless even if harmless, and worth avoiding rather than relying
    // on Flutter happening to collapse the two into one frame).
    guard operation != [] else {
      emit()
      return
    }
    // `.file`/`.folder` deliberately do NOT clearHeldItem() here, even on
    // a successful drop — two real, reproduced bugs in a row narrowed this
    // down to the only correct answer:
    //
    // 1. The original code called clearHeldItem() unconditionally right
    //    here. `NSDraggingItem(pasteboardWriter: fileURL as NSURL)` hands
    //    the destination a file-URL *reference* into this app's own Caches
    //    storage, not embedded bytes — the destination reads that path
    //    itself, and nothing about NSDraggingSource tells the SOURCE when
    //    that read has actually finished. Reproduced live dragging a video
    //    file onto the Desktop: Finder's own copy was still reading the
    //    file when this callback fired, and deleting it here raced that
    //    read, producing Finder's genuine "file not found, Error code -43."
    //
    // 2. The fix for #1 was NSFilePromiseProvider, which DOES give a real
    //    completion signal (its writePromiseTo:completionHandler:) — but
    //    reproduced live as its own regression: its promise-specific
    //    pasteboard types are recognized by Finder ALONE. Mail, Messages,
    //    VS Code, and a Chromium browser all silently failed to recognize
    //    the drag as a file at all (no drop-target UI, nothing) — an
    //    independent third-party project (github.com/ryanleonduty/shotndrop
    //    PR #13) hit and reverted this exact same regression for the same
    //    reason. There is no sanctioned way to offer one drag as "either a
    //    plain NSURL or a promise, whichever the destination understands" —
    //    NSDraggingItem's pasteboardWriter is one or the other, and multiple
    //    NSDraggingItems in one session represent separate dragged objects,
    //    not alternative forms of the same one.
    //
    // Given a safe-delete signal and universal destination compatibility
    // are mutually exclusive with the tools AppKit actually provides here,
    // compatibility wins — a Shelf that only works dragging into Finder
    // isn't a usable feature. So the file itself is simply left in place
    // after a successful drag-out; clearStorageDirectory() (called
    // unconditionally at the top of both acceptFile and acceptText, before
    // copying/storing whatever comes in next) is what actually frees it,
    // the next time anything is dragged into the Shelf. The one exception
    // is the self-drop case in performDragOperation, which deletes
    // immediately and safely — that delete is synchronous with a real drop
    // this app itself just accepted, with no external consumer's read to
    // race at all.
    //
    // What Dart SEES is a separate question from what's actually kept on
    // disk, though — confirmed live as its own real (if minor) UX bug: the
    // island kept showing the item as still held even after the user
    // watched it land successfully somewhere else, which reads as broken
    // even though no storage was actually being wasted. isDisplayedAsEmptyAfterDragOut
    // exists purely to fix that: emit() shows Dart "empty" immediately on
    // any successful drop, while heldItem/the real file stay completely
    // untouched underneath until the next genuine change actually replaces
    // them (see clearStorageDirectory()'s own comment for where that flag
    // gets reset).
    //
    // heldItem is already nil here specifically for the self-drop case —
    // performDragOperation's own draggingSource check runs and calls
    // clearHeldItem(reason: "deleted") BEFORE this method ever runs (always
    // the destination-side callback first, then this source-side one), so
    // by the time this line is reached for that gesture, heldItem is
    // already gone and Dart has already correctly received "deleted".
    // Falling into the `else` branch below in that case would incorrectly
    // stomp that already-correct reason with "draggedOut" a moment later —
    // heldItem == nil is exactly the signal that's already happened here,
    // so there's nothing left for this method to do for that gesture.
    guard heldItem != nil else { return }
    // `.text` has no on-disk file at all (see HeldItem.attributedText's own
    // comment — it's held entirely in memory) and no delete to defer, so
    // it still just clears for real, immediately, via the ordinary
    // clearHeldItem() path — "draggedOut", same success reason the
    // isDisplayedAsEmptyAfterDragOut branch below reports for `.file`/
    // `.folder`, since this genuinely is the same kind of event, just
    // handled via an immediate real clear instead of a deferred one.
    if heldItem?.kind == .text {
      clearHeldItem(reason: "draggedOut")
    } else {
      isDisplayedAsEmptyAfterDragOut = true
      emit()
    }
  }
}

// MARK: - Emitting state to Dart

extension ShelfChannel {
  /// [emptyReason] only matters when this call is the one that's actually
  /// reporting "empty" (heldItem is nil, or isDisplayedAsEmptyAfterDragOut
  /// is masking a still-real heldItem — see that flag's own doc comment) —
  /// it's silently ignored on a "holding" emit, since there's nothing to
  /// explain an absence of yet. `isDisplayedAsEmptyAfterDragOut` being true
  /// always means "draggedOut" specifically (see endedAt:operation:, the
  /// only place that sets it) regardless of what's passed in here, since
  /// nothing else ever sets that flag.
  private func emit(emptyReason: String? = nil) {
    guard let heldItem, !isDisplayedAsEmptyAfterDragOut else {
      var payload: [String: Any] = ["state": "empty"]
      let reason = isDisplayedAsEmptyAfterDragOut ? "draggedOut" : emptyReason
      if let reason {
        payload["reason"] = reason
      }
      eventSink?(payload)
      return
    }

    let kindString: String
    switch heldItem.kind {
    case .file: kindString = "file"
    case .folder: kindString = "folder"
    case .text: kindString = "text"
    }

    var payload: [String: Any] = [
      "state": "holding",
      "kind": kindString,
      "displayName": heldItem.displayName,
      // True only while a drag-out is in flight AND currently hovering
      // back over the island's own window — see draggingSession(_:movedTo:)
      // — never true otherwise. A flag on the ordinary "holding" payload,
      // not a separate state value: the held item itself hasn't changed at
      // all yet (it's only deleted if the user actually releases here), so
      // Dart shouldn't have to reconcile a different snapshot shape for
      // what's really just one extra piece of transient UI state layered
      // on top of the same held item.
      "pendingDelete": isPendingDeleteOverIsland,
      // Same reasoning as pendingDelete above — a flag layered on the
      // still-holding payload, not a separate state, since the held item
      // itself is completely unchanged while a drag-out is merely in
      // flight. Drives the collapsed pill's own subtle dim/recede look
      // (see shelf_activity.dart) for as long as this stays true.
      "isDragging": isDragSessionActive,
    ]

    if let sizeBytes = heldItem.sizeBytes {
      payload["sizeBytes"] = sizeBytes
    }

    if let fileURL = heldItem.fileURL {
      let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
      icon.size = NSSize(width: 64, height: 64)
      if let thumbnailData = pngData(from: icon) {
        payload["thumbnailPng"] = FlutterStandardTypedData(bytes: thumbnailData)
      }
    }

    eventSink?(payload)
  }

  /// A transient "copy in progress" state — no file/thumbnail yet, just
  /// enough for Dart to show a brief in-progress affordance instead of the
  /// pill silently doing nothing while a cross-volume copy (never
  /// instant, unlike the same-volume clone case) actually runs.
  private func emit(copyingDisplayName: String) {
    eventSink?(["state": "copying", "displayName": copyingDisplayName])
  }

  private func pngData(from image: NSImage) -> Data? {
    guard
      let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let png = bitmap.representation(using: .png, properties: [:])
    else { return nil }
    return png
  }
}
