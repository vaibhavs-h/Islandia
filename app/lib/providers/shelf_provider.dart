import 'package:flutter/services.dart';

enum ShelfItemKind { file, folder, text }

/// Why the Shelf just became empty — purely a hint for
/// shelf_activity.dart's own exit-animation choice (a confirming
/// checkmark-flash for [draggedOut], a sharp collapse for [deleted]); it
/// has no bearing on any real state. `null` means "just empty, unremarkably"
/// (the very first snapshot on launch, or the MethodChannel's own explicit
/// `clear` command — see ShelfControl.clear — neither of which has
/// anything worth animating).
enum ShelfEmptyReason {
  /// A drag-out completed successfully somewhere (or, for held text,
  /// completed via the same real, immediate clear — see
  /// ShelfChannel.swift's endedAt:operation: for exactly which of its two
  /// paths reports this).
  draggedOut,

  /// The held item was dropped back onto the island itself specifically to
  /// delete it — see ShelfChannel.swift's performDragOperation, the
  /// `draggingSource === self` self-drop check.
  deleted,
}

/// One reading of the Shelf's own state — see ShelfChannel.swift for where
/// this comes from. Holds exactly one item at a time; a new drag-in
/// replaces whatever was already there.
class ShelfSnapshot {
  const ShelfSnapshot._({
    required this.isEmpty,
    required this.isCopying,
    this.kind,
    this.displayName,
    this.thumbnailPng,
    this.sizeBytes,
    this.pendingDelete = false,
    this.isDragging = false,
    this.emptyReason,
  });

  const ShelfSnapshot.empty({ShelfEmptyReason? reason}) : this._(isEmpty: true, isCopying: false, emptyReason: reason);

  const ShelfSnapshot.copying(String displayName) : this._(isEmpty: false, isCopying: true, displayName: displayName);

  const ShelfSnapshot.holding({
    required ShelfItemKind kind,
    required String displayName,
    Uint8List? thumbnailPng,
    int? sizeBytes,
    bool pendingDelete = false,
    bool isDragging = false,
  }) : this._(
         isEmpty: false,
         isCopying: false,
         kind: kind,
         displayName: displayName,
         thumbnailPng: thumbnailPng,
         sizeBytes: sizeBytes,
         pendingDelete: pendingDelete,
         isDragging: isDragging,
       );

  final bool isEmpty;

  /// True only for the brief window a cross-volume drag is actually
  /// copying (never true for a same-volume drop, which clones instantly
  /// via APFS and skips straight to holding) — see ShelfChannel.swift's
  /// own doc comment on why this state exists at all.
  final bool isCopying;

  final ShelfItemKind? kind;
  final String? displayName;

  /// A 64x64 PNG of the item's Finder icon — present for `.file`/`.folder`,
  /// never for `.text` (which has no on-disk file to generate an icon
  /// from at all).
  final Uint8List? thumbnailPng;

  /// Total bytes on disk — null for `.text` (nothing on-disk to measure).
  /// For `.folder` this is the real recursive total of everything inside
  /// it, computed natively (see ShelfChannel.swift's own recursiveSize),
  /// not just the directory entry's own few-KB metadata size.
  final int? sizeBytes;

  /// True only while a drag-out is in flight and currently hovering back
  /// over the island's own window (see ShelfChannel.swift's
  /// draggingSession(_:movedTo:)) — the moment shelf_activity.dart should
  /// swap the ordinary preview for the bin-icon/"delete" affordance, per
  /// the confirmed spec: "if the user drops that back into the island then
  /// that copy gets deleted." Never true while [isEmpty] or [isCopying].
  final bool pendingDelete;

  /// True for the entire span of a drag-out gesture, from the moment
  /// ShelfControl.startDragOut() is called until the drag ends one way or
  /// another (success, delete, or returned) — see ShelfChannel.swift's
  /// own startDragOut/endedAt:operation:. Drives the collapsed pill's
  /// subtle dim/recede look while the item is "out of the island's hands."
  /// Never true while [isEmpty] or [isCopying].
  final bool isDragging;

  /// See [ShelfEmptyReason]'s own doc comment. Only ever meaningful
  /// alongside [isEmpty] — always null on a `.holding`/`.copying` snapshot.
  final ShelfEmptyReason? emptyReason;
}

/// The Shelf (§05, Phase 3) — native already hands over one complete
/// reading per state change, nothing to diff here, just forward each one.
class ShelfProvider {
  ShelfProvider._();

  static const EventChannel _channel = EventChannel('islandia/shelf/updates');

  static Stream<ShelfSnapshot> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      final map = (event as Map).cast<String, Object?>();
      final state = map['state'] as String;
      switch (state) {
        case 'copying':
          return ShelfSnapshot.copying(map['displayName'] as String);
        case 'holding':
          final kindString = map['kind'] as String;
          final kind = ShelfItemKind.values.firstWhere((k) => k.name == kindString);
          final thumbnailData = map['thumbnailPng'];
          return ShelfSnapshot.holding(
            kind: kind,
            displayName: map['displayName'] as String,
            thumbnailPng: thumbnailData is Uint8List ? thumbnailData : null,
            sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
            pendingDelete: map['pendingDelete'] as bool? ?? false,
            isDragging: map['isDragging'] as bool? ?? false,
          );
        case 'empty':
        default:
          final reasonString = map['reason'] as String?;
          ShelfEmptyReason? reason;
          for (final candidate in ShelfEmptyReason.values) {
            if (candidate.name == reasonString) {
              reason = candidate;
              break;
            }
          }
          return ShelfSnapshot.empty(reason: reason);
      }
    }).handleError((Object _) {});
  }
}

/// Dart-initiated commands — mirrors ClockAwarenessControl's own split
/// between a state-streaming EventChannel (above) and this separate
/// command MethodChannel. Dart owns rendering the held item's preview, so
/// it's the one that detects the press-and-drag gesture on it; when that
/// happens, `startDragOut` asks native to turn it into a genuine
/// NSDraggingSession using the file that already fully exists in the
/// Shelf's own storage.
class ShelfControl {
  ShelfControl._();

  static const MethodChannel _channel = MethodChannel('islandia/shelf/control');

  static Future<void> startDragOut() => _channel.invokeMethod('startDragOut');
  static Future<void> clear() => _channel.invokeMethod('clear');
}
