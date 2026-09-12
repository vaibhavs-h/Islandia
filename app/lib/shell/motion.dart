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
}
