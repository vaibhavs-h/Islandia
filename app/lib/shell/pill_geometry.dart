import 'dart:math' as math;
import 'dart:ui';

import 'island_window_channel.dart';

/// §02's requirement, stated precisely: the Island sits ~0.2mm below the
/// physical notch. That's a physical distance, not a point count, so it's
/// computed rather than hardcoded — the same logical-point gap looks right
/// on one density and vanishes into anti-aliasing on another.
const double _targetGapMm = 0.2;
const double _pointsPerMm = 72 / 25.4;

/// A minimum-perceptible floor: the raw 0.2mm conversion (~0.57pt) is right
/// at the edge of anti-aliasing away to nothing, so it's clamped up to a
/// gap that reliably renders instead. This is the value actually in effect
/// day to day (0.57pt never exceeds it) — doubled from 1.0 to 2.0pt because
/// the pill was reading as fused to the notch rather than clearly separate
/// from it.
const double _minGapPt = 2.0;

/// Rounds the floored gap to the nearest whole device pixel for the current
/// display's backing scale, so it reads as "almost touching" consistently
/// rather than looking sloppy on one panel density and crisp on another.
double gapForScreen(NotchGeometry screen) {
  final rawGapPt = _targetGapMm * _pointsPerMm;
  final flooredGapPt = math.max(rawGapPt, _minGapPt);
  final scale = screen.backingScaleFactor > 0 ? screen.backingScaleFactor : 1.0;
  return (flooredGapPt * scale).round() / scale;
}

/// Anchored top-center, directly under the notch (or under the menu bar on
/// notch-less displays, per §07 — same rule, no special case).
Rect collapsedFrame(NotchGeometry screen, Size collapsedSize) {
  final originX = (screen.screenWidth - collapsedSize.width) / 2;
  final originY = screen.topInset + gapForScreen(screen);
  return Rect.fromLTWH(originX, originY, collapsedSize.width, collapsedSize.height);
}

/// Grows down and outward from the same anchor the collapsed pill used —
/// top edge fixed, width centered — never sideways into the menu bar's ears.
Rect expandedFrame(Rect collapsed, Size expandedSize) {
  final originX = collapsed.center.dx - expandedSize.width / 2;
  return Rect.fromLTWH(originX, collapsed.top, expandedSize.width, expandedSize.height);
}
