import 'package:flutter/material.dart';

import '../engine/activity.dart';
import '../shell/motion.dart';
import 'byte_size_format.dart';
import 'shelf_provider.dart';

/// The Shelf (§05, Phase 3) — highest tier there is (see
/// ActivityPriority's own doc comment): once something is dragged onto the
/// island, it can never be overlaid by anything else until dragged back
/// out. Collapsed shows a plain icon + filename; the detailed type/size
/// view only exists in the expanded card, per the confirmed spec ("in
/// normal view the island would display a normal icon of the file type...
/// and then the file name and only in shelf case there will be a hover
/// thing... [that] would contain more detailed information about the item
/// like type, size, etc").
///
/// A `copying` snapshot (see ShelfSnapshot's own doc comment — only real
/// for a cross-volume drop, never a same-volume clone) still registers
/// this same activity/id, just rendering the in-progress state instead of
/// the held-item preview; there is no separate "copying" tier or activity.
///
/// [onExitAnimationComplete] fires once the Shelf's own exit transition
/// (see _ShelfExitAnimated) has genuinely finished playing on a real,
/// still-registered snapshot — island_shell.dart's own Shelf listener
/// deliberately does NOT call `_stack.remove('shelf')` the instant an
/// empty/reasoned snapshot arrives; it keeps this activity registered
/// (still rendering the exit animation against the last real content)
/// until this callback says it's safe, then removes it and collapses. See
/// that listener's own doc comment for the full sequencing.
Activity buildShelfActivity(ShelfSnapshot snapshot, {required VoidCallback onExitAnimationComplete}) {
  return Activity(
    id: 'shelf',
    priority: ActivityPriority.shelf,
    collapsedBuilder: (context, state) => _ShelfContent(
      snapshot: snapshot,
      expanded: false,
      onExitAnimationComplete: onExitAnimationComplete,
    ),
    expandedBuilder: (context, state) => _ShelfContent(
      snapshot: snapshot,
      expanded: true,
      onExitAnimationComplete: onExitAnimationComplete,
    ),
  );
}

IconData _iconFor(ShelfItemKind kind) {
  return switch (kind) {
    ShelfItemKind.file => Icons.insert_drive_file,
    ShelfItemKind.folder => Icons.folder,
    ShelfItemKind.text => Icons.text_snippet,
  };
}

String _kindLabel(ShelfItemKind kind) {
  return switch (kind) {
    ShelfItemKind.file => 'File',
    ShelfItemKind.folder => 'Folder',
    ShelfItemKind.text => 'Text',
  };
}

/// The held item's own preview — a 64x64 Finder-icon thumbnail for
/// `.file`/`.folder` (never present for `.text`, which has no on-disk file
/// to render one from — see ShelfSnapshot.thumbnailPng's own comment), a
/// generic type glyph otherwise.
class _ItemPreview extends StatelessWidget {
  const _ItemPreview({required this.snapshot, required this.size});

  final ShelfSnapshot snapshot;
  final double size;

  @override
  Widget build(BuildContext context) {
    final thumbnail = snapshot.thumbnailPng;
    if (thumbnail != null) {
      return Image.memory(thumbnail, width: size, height: size, gaplessPlayback: true);
    }
    return Icon(_iconFor(snapshot.kind!), color: Colors.white70, size: size * 0.75);
  }
}

/// Press-and-drag directly on the item's own preview turns into a real
/// native drag-out — the one gesture the confirmed spec asks for ("the
/// file would be draggable from the expanded view also not just the
/// normal view"), so this same wrapper is reused by both the collapsed and
/// expanded renders rather than each hooking up its own copy. Only
/// `onPanStart` is claimed here (never `onTap`) — island_shell.dart's own
/// outer GestureDetector still owns the tap gesture for everything else on
/// the pill; Flutter's gesture arena resolves the two independently since
/// they listen for different gesture families, not competing claims on the
/// same one.
class _DragOutHandle extends StatelessWidget {
  const _DragOutHandle({required this.enabled, required this.child});

  /// False while pendingDelete/copying/empty/already-dragging — there is
  /// no real held item to hand over yet (or it's already mid-drag), so a
  /// stray press must not ask native to start a second, conflicting drag
  /// session (native's own `isDragSessionActive` guard would already
  /// refuse it, but skipping the call here means no round-trip at all for
  /// a press that could never have done anything).
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return GestureDetector(onPanStart: (_) => ShelfControl.startDragOut(), child: child);
  }
}

/// The one stateful root both collapsed and expanded renders go through —
/// owns three independent, purely presentational animations layered on top
/// of whatever the plain content would otherwise be, none of which change
/// any real state, all of which are keyed off nothing but [snapshot] and
/// [expanded] changing from one build to the next (Flutter preserves this
/// State across those rebuilds — see island_shell.dart's own
/// _crossFadedContent/KeyedSubtree doc comment for exactly why: the Shelf's
/// activity id never changes, so this widget's identity in the tree never
/// changes either, snapshot to snapshot):
///
/// - Arrival: the held item's own identity ([_ItemIdentity]) changing to a
///   genuinely different one plays a scale-and-settle entrance on the new
///   content (see [_ArrivalAnimated]).
/// - Exit: [snapshot] going empty with a real [ShelfSnapshot.emptyReason]
///   plays an exit transition (see [_ShelfExitAnimated]) against the *last*
///   real (non-empty) snapshot this widget saw — by the time a snapshot is
///   truly empty there's nothing left in it to animate, which is exactly
///   why [_lastRealSnapshot] exists.
/// - Mid-drag dim: [ShelfSnapshot.isDragging] simply drives a continuous
///   opacity/scale tween for as long as it stays true — no discrete
///   trigger needed, just a direct function of the current value.
class _ShelfContent extends StatefulWidget {
  const _ShelfContent({required this.snapshot, required this.expanded, required this.onExitAnimationComplete});

  final ShelfSnapshot snapshot;
  final bool expanded;
  final VoidCallback onExitAnimationComplete;

  @override
  State<_ShelfContent> createState() => _ShelfContentState();
}

class _ShelfContentState extends State<_ShelfContent> {
  /// The last snapshot this widget saw that had real content to show
  /// (holding or copying) — kept around specifically so an exit animation
  /// has something to render against once the live [ShelfSnapshot] itself
  /// has already gone empty. Never null after the first real snapshot
  /// arrives; only ever read while actually exiting.
  ShelfSnapshot? _lastRealSnapshot;

  @override
  void didUpdateWidget(covariant _ShelfContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.snapshot.isEmpty) {
      _lastRealSnapshot = widget.snapshot;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.snapshot.isEmpty) {
      _lastRealSnapshot ??= widget.snapshot;
    }

    final exitReason = widget.snapshot.isEmpty ? widget.snapshot.emptyReason : null;
    if (exitReason != null && _lastRealSnapshot != null) {
      return _ShelfExitAnimated(
        snapshot: _lastRealSnapshot!,
        expanded: widget.expanded,
        reason: exitReason,
        onComplete: widget.onExitAnimationComplete,
      );
    }

    // A plain, unremarkable empty snapshot (launch, or an explicit
    // ShelfControl.clear() with no reason worth animating — see
    // ShelfEmptyReason's own doc comment) — nothing to render at all;
    // island_shell.dart never even registers this activity for that case
    // in the first place (see its own listener), so in practice this only
    // renders for one single frame right as a real exit is just starting
    // (the very first empty-with-reason snapshot, before _lastRealSnapshot
    // has had a chance to be read above — impossible given the ??= runs
    // first in this same build, but kept as a safe, inert fallback rather
    // than an assumption).
    if (widget.snapshot.isEmpty) {
      return const SizedBox.shrink();
    }

    final identity = _ItemIdentity.of(widget.snapshot);
    return _ArrivalAnimated(
      // Keyed on the identity itself — without this, Flutter has no reason
      // to ever create a fresh State here at all (same widget type, same
      // position in the tree, on every single rebuild regardless of
      // [identity] changing), so the AnimationController from the FIRST
      // arrival would just keep living forever, already-settled at 1.0,
      // and a genuinely different item replacing it would silently skip
      // the entrance entirely instead of replaying it — confirmed as a
      // real, reproduced gap (not just a hypothetical) via this exact
      // scenario in shelf_activity_test.dart's own animation tests.
      key: ValueKey(identity),
      identity: identity,
      child: _MidDragDimmed(
        isDragging: widget.snapshot.isDragging,
        child: _PlainShelfContent(snapshot: widget.snapshot, expanded: widget.expanded),
      ),
    );
  }
}

/// What actually identifies "a genuinely different held item," for the
/// arrival animation's own purposes — the Shelf holds exactly one item at
/// a time, so a change in kind/name/size is as reliable a proxy for "a new
/// drag-in just landed" as an id would be. Deliberately excludes
/// isDragging/pendingDelete/thumbnailPng: none of those changing means a
/// *different item* arrived, just the same one's transient state shifting,
/// which must NOT replay the arrival entrance.
class _ItemIdentity {
  const _ItemIdentity({required this.kind, required this.displayName, required this.sizeBytes});

  factory _ItemIdentity.of(ShelfSnapshot snapshot) {
    return _ItemIdentity(kind: snapshot.kind, displayName: snapshot.displayName, sizeBytes: snapshot.sizeBytes);
  }

  final ShelfItemKind? kind;
  final String? displayName;
  final int? sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is _ItemIdentity && other.kind == kind && other.displayName == displayName && other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(kind, displayName, sizeBytes);
}

/// Plays a scale-and-settle entrance (see IslandMotion.shelfArrivalDuration/
/// shelfArrivalCurve) whenever [identity] changes to a genuinely different
/// value from the last build — a fresh AnimationController is (re)built via
/// a fresh State only when [identity] itself changes (see the ValueKey
/// below), which is exactly the "only replay on a real new arrival, never
/// on an unrelated rebuild of the same item" behavior this needs.
class _ArrivalAnimated extends StatefulWidget {
  const _ArrivalAnimated({super.key, required this.identity, required this.child});

  final _ItemIdentity identity;
  final Widget child;

  @override
  State<_ArrivalAnimated> createState() => _ArrivalAnimatedState();
}

class _ArrivalAnimatedState extends State<_ArrivalAnimated> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: IslandMotion.shelfArrivalDuration)..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: IslandMotion.shelfArrivalCurve);
    return AnimatedBuilder(
      animation: curved,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          // Clamped — easeOutBack's whole point is overshooting past 1.0
          // before settling back, which Opacity can't represent (values
          // outside 0..1 throw), so only the scale transform gets the real
          // overshoot; opacity itself just eases to fully visible over the
          // same span, never itself overshooting.
          opacity: curved.value.clamp(0.0, 1.0),
          // Keyed so tests can target this specific Transform unambiguously
          // — find.byType(Transform) alone is fragile here, since
          // AnimatedScale (see _MidDragDimmed, always somewhere in this
          // same subtree) builds its own internal Transform too, and their
          // relative order in a find.byType query is not something worth
          // depending on.
          child: Transform.scale(key: const ValueKey('shelf-arrival-scale'), scale: curved.value, child: child),
        );
      },
    );
  }
}

/// A direct, continuous function of [isDragging] — no discrete trigger, no
/// controller of its own beyond the implicit one AnimatedOpacity/
/// AnimatedScale already own; it's simply always tweening toward whichever
/// value [isDragging] currently says. Signals "this item is currently out
/// of the island's hands, being dragged elsewhere" per the confirmed
/// preference for a subtle dim/recede while a drag-out is in flight.
class _MidDragDimmed extends StatelessWidget {
  const _MidDragDimmed({required this.isDragging, required this.child});

  final bool isDragging;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isDragging ? 0.45 : 1.0,
      duration: IslandMotion.activitySwapDuration,
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: isDragging ? 0.94 : 1.0,
        duration: IslandMotion.activitySwapDuration,
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

/// Plays exactly once against a fixed, already-final [snapshot] (the last
/// real content _ShelfContentState remembered — this never re-triggers
/// itself, since its own parent doesn't rebuild it with a new snapshot
/// once it's showing) and calls [onComplete] the instant it finishes —
/// island_shell.dart's own Shelf listener is what's actually waiting on
/// that callback before it calls `_stack.remove('shelf')`/collapses (see
/// buildShelfActivity's own doc comment for the full sequencing this
/// enables: the animation plays against real, still-registered content
/// instead of being cut off by an immediate removal).
///
/// [reason] picks between the two confirmed, deliberately different exit
/// feels: [ShelfEmptyReason.draggedOut] is calmer and confirms success
/// with a brief checkmark morph; [ShelfEmptyReason.deleted] is snappier
/// and sharper, with no checkmark (a delete isn't a success to confirm,
/// it's a removal), matching the same collapse-and-fade shape but faster
/// and without the confirming icon swap.
class _ShelfExitAnimated extends StatefulWidget {
  const _ShelfExitAnimated({
    required this.snapshot,
    required this.expanded,
    required this.reason,
    required this.onComplete,
  });

  final ShelfSnapshot snapshot;
  final bool expanded;
  final ShelfEmptyReason reason;
  final VoidCallback onComplete;

  @override
  State<_ShelfExitAnimated> createState() => _ShelfExitAnimatedState();
}

class _ShelfExitAnimatedState extends State<_ShelfExitAnimated> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final duration = widget.reason == ShelfEmptyReason.draggedOut
        ? IslandMotion.shelfDragOutExitDuration
        : IslandMotion.shelfDeleteExitDuration;
    _controller = AnimationController(vsync: this, duration: duration)
      ..addStatusListener((status) {
        // Guarded on _completed rather than trusting a single
        // AnimationStatus.completed callback to fire only once — belt and
        // suspenders around exactly the kind of double-invocation bug that
        // bit ShelfChannel.swift's own endedAt:operation: earlier this same
        // feature (a genuinely reachable double-emit there); calling
        // onComplete twice here would ask island_shell.dart to
        // _stack.remove('shelf') a second time, harmless on its own
        // (ActivityStack.remove no-ops on a missing id) but not a pattern
        // worth relying on staying harmless.
        if (status == AnimationStatus.completed && !_completed) {
          _completed = true;
          widget.onComplete();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: IslandMotion.shelfExitCurve);
    // Only draggedOut gets the checkmark morph — see this widget's own
    // doc comment for why deleted deliberately skips it. Timed to finish
    // partway through the exit (0.0–0.55 of it), leaving the back half
    // purely for the fade/scale-down to finish reading as "gone," rather
    // than the icon swap itself still be mid-morph right as the content
    // vanishes.
    final showsCheckmark = widget.reason == ShelfEmptyReason.draggedOut;
    final checkmarkT = showsCheckmark ? (curved.value / 0.55).clamp(0.0, 1.0) : 0.0;

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final fadeOpacity = (1.0 - curved.value).clamp(0.0, 1.0);
        final scale = 1.0 - (curved.value * 0.18);
        return Opacity(
          opacity: fadeOpacity,
          child: Transform.scale(
            scale: scale,
            child: showsCheckmark
                ? _CheckmarkMorph(t: checkmarkT, snapshot: widget.snapshot, expanded: widget.expanded)
                : _PlainShelfContent(snapshot: widget.snapshot, expanded: widget.expanded),
          ),
        );
      },
    );
  }
}

/// Cross-fades the ordinary preview into a small filled checkmark circle as
/// [t] goes 0→1 — the "brief checkmark flash" confirming a successful
/// drag-out, deliberately not a full state swap (both are laid out via the
/// same Stack, one fading out as the other fades in) so there's no layout
/// jump mid-transition.
class _CheckmarkMorph extends StatelessWidget {
  const _CheckmarkMorph({required this.t, required this.snapshot, required this.expanded});

  final double t;
  final ShelfSnapshot snapshot;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final checkmarkSize = expanded ? 32.0 : 22.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 1.0 - t, child: _PlainShelfContent(snapshot: snapshot, expanded: expanded)),
        Opacity(
          opacity: t,
          child: Container(
            width: checkmarkSize,
            height: checkmarkSize,
            decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
            child: Icon(Icons.check, color: Colors.black, size: checkmarkSize * 0.65),
          ),
        ),
      ],
    );
  }
}

/// The plain, unanimated content for a real held item — everything
/// _ShelfCollapsed/_ShelfExpanded used to render directly, factored out so
/// both the live (non-exiting) path and _ShelfExitAnimated's own frozen
/// last-snapshot path render identically, just wrapped in different
/// surrounding animation.
class _PlainShelfContent extends StatelessWidget {
  const _PlainShelfContent({required this.snapshot, required this.expanded});

  final ShelfSnapshot snapshot;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isCopying) {
      return _CopyingContent(displayName: snapshot.displayName!, expanded: expanded);
    }
    if (snapshot.pendingDelete) {
      return _PendingDeleteContent(expanded: expanded);
    }
    return expanded ? _ShelfExpanded(snapshot: snapshot) : _ShelfCollapsed(snapshot: snapshot);
  }
}

class _ShelfCollapsed extends StatelessWidget {
  const _ShelfCollapsed({required this.snapshot});

  final ShelfSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final displayName = snapshot.displayName!;
    return Semantics(
      label: '${_kindLabel(snapshot.kind!)} on the Shelf: $displayName.',
      excludeSemantics: true,
      child: _DragOutHandle(
        enabled: !snapshot.isDragging,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              _ItemPreview(snapshot: snapshot, size: 22),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfExpanded extends StatelessWidget {
  const _ShelfExpanded({required this.snapshot});

  final ShelfSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final displayName = snapshot.displayName!;
    final kind = snapshot.kind!;
    final sizeBytes = snapshot.sizeBytes;
    return Semantics(
      label:
          '${_kindLabel(kind)} on the Shelf: $displayName.'
          '${sizeBytes != null ? " ${formatByteSize(sizeBytes)}." : ""} '
          'Drag to move it off the Shelf.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: _DragOutHandle(
          enabled: !snapshot.isDragging,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ItemPreview(snapshot: snapshot, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sizeBytes != null ? '${_kindLabel(kind)} · ${formatByteSize(sizeBytes)}' : _kindLabel(kind),
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The transient in-progress state for a real (cross-volume, never
/// same-volume) copy — see ShelfSnapshot.isCopying's own comment. No
/// preview, no drag handle: there's no fully-copied file to hand over to a
/// drag session yet.
class _CopyingContent extends StatelessWidget {
  const _CopyingContent({required this.displayName, required this.expanded});

  final String displayName;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final iconSize = expanded ? 20.0 : 16.0;
    final fontSize = expanded ? 15.0 : 14.0;
    return Semantics(
      label: 'Copying $displayName to the Shelf.',
      excludeSemantics: true,
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 10),
        child: Row(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            SizedBox(
              width: iconSize,
              height: iconSize,
              child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            ),
            SizedBox(width: expanded ? 12 : 9),
            Flexible(
              child: Text(
                'Copying $displayName…',
                style: TextStyle(color: Colors.white, fontSize: fontSize),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bin-icon/"delete" affordance shown while a drag-out is hovering
/// back over the island itself — see ShelfChannel.swift's
/// draggingSession(_:movedTo:) for the native half of this. Deliberately
/// replaces the whole preview rather than overlaying it: the confirmed
/// spec's own wording ("the island window should show a bin icon and
/// delete text kind of") describes this as the island's entire content
/// swapping to communicate "release here to delete," not a small badge
/// added on top of the normal preview.
class _PendingDeleteContent extends StatelessWidget {
  const _PendingDeleteContent({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final iconSize = expanded ? 22.0 : 18.0;
    final fontSize = expanded ? 16.0 : 14.0;
    return Semantics(
      label: 'Release to delete this item from the Shelf.',
      excludeSemantics: true,
      liveRegion: true,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete, color: Colors.redAccent, size: iconSize),
            SizedBox(width: expanded ? 10 : 8),
            Text(
              'Release to delete',
              style: TextStyle(color: Colors.redAccent, fontSize: fontSize, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
