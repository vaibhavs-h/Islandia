import 'package:flutter/animation.dart';

/// §02/§13's shared motion primitives. One set of constants, used by every
/// activity — no activity hand-rolls its own animation.
class IslandMotion {
  IslandMotion._();

  /// Shared by the native window-frame animation (MainFlutterWindow's
  /// CAMediaTimingFunction bezier — keep the two in sync if either changes)
  /// and every Dart-side decoration transition, so chrome and content move
  /// as one surface. §13's default is 280ms; bumped up further still (this
  /// is the third increase) for a noticeably slower, smoother feel.
  static const Duration expansionDuration = Duration(milliseconds: 700);

  /// Pure ease-out, no overshoot — a bounce is itself a small reversal in
  /// velocity, which reads as "snappy," not "smooth." The native side
  /// dropped its overshoot to match (see MainFlutterWindow.setPillFrame).
  static const Curve expansionCurve = Curves.easeOutCubic;

  /// A *different* activity taking the top slot (Now Playing stopping,
  /// battery resuming its place; a Bluetooth notification arriving over
  /// whatever was showing) — no box resize is usually involved, just a
  /// content swap, so this is its own, shorter fade rather than reusing
  /// [expansionDuration]. See IslandShell._crossFadedContent.
  static const Duration activitySwapDuration = Duration(milliseconds: 350);

  /// The Shelf's own arrival entrance (scale-and-settle) — see
  /// shelf_activity.dart's _ArrivalAnimated. Deliberately allowed a touch of
  /// overshoot ([shelfArrivalCurve]), unlike every other motion constant
  /// here: an item *landing* with a little weight reads as more premium
  /// than a plain ease-in, and this is the one Shelf moment confirmed as
  /// wanting exactly that (a scale-up-then-settle, not a flat fade) rather
  /// than matching the rest of the app's deliberately bounce-free house
  /// style.
  static const Duration shelfArrivalDuration = Duration(milliseconds: 450);
  static const Curve shelfArrivalCurve = Curves.easeOutBack;

  /// The Shelf's two exit transitions — a successful drag-out (calmer,
  /// confirms with a brief checkmark) vs. a delete (snappier, sharper) —
  /// see shelf_activity.dart's _ShelfExitAnimated. island_shell.dart's own
  /// Shelf listener waits exactly one of these durations (matching
  /// [emptyReason]) before actually removing the activity from the stack,
  /// so the animation has time to play out on real, still-registered
  /// content instead of being cut off by an immediate removal.
  static const Duration shelfDragOutExitDuration = Duration(milliseconds: 550);
  static const Duration shelfDeleteExitDuration = Duration(milliseconds: 260);
  static const Curve shelfExitCurve = Curves.easeInCubic;
}
