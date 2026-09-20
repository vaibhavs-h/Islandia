import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/activity.dart';
import '../engine/activity_stack.dart';

/// Shared "prominent pill, then recede to a persistent corner dot" behavior
/// — mic and camera both use this, matching iOS's own privacy-indicator
/// pattern: a few seconds of full, unmissable prominence when it turns on,
/// then it steps back to a small dot that just sits alongside whatever else
/// the pill is showing rather than continuing to occupy the whole surface
/// for as long as it stays active.
class PrivacyIndicatorController {
  PrivacyIndicatorController({
    required this.activityId,
    required this.buildActivity,
    required this.stack,
    required TickerProvider vsync,
    this.prominentDuration = const Duration(seconds: 5),
    this.briefDotDuration = const Duration(seconds: 2),
  }) : dotTransition = AnimationController(
         vsync: vsync,
         // Slower than the expand/collapse motion on purpose — this is a
         // passive ambient cue, not something the user just acted on.
         duration: const Duration(milliseconds: 900),
       );

  final String activityId;
  final Activity Function() buildActivity;
  final ActivityStack stack;
  final Duration prominentDuration;
  /// How long the small dot stays up on its own for an activation that
  /// ends before the full banner's own prominent window would have — see
  /// [handle]. Long enough to actually register as "something happened,"
  /// short enough to clearly read as a one-off rather than the ongoing
  /// presence the persistent dot otherwise means.
  final Duration briefDotDuration;
  final AnimationController dotTransition;

  Timer? _prominentTimer;
  Timer? _briefDotTimer;
  bool _active = false;
  /// True only while the full banner is genuinely the thing on screen —
  /// from registering it until either the prominent window closes on its
  /// own (receding to the dot normally) or a brief deactivation swaps it
  /// for the dot early. This is what lets [handle] tell those two cases
  /// apart when `false` arrives.
  bool _showingBanner = false;

  /// Only acts on a genuine off↔on transition — the underlying provider can
  /// fire more than once for the same state, and re-entering this on every
  /// one of those would restart the prominent window (or re-trigger the dot
  /// fade-in) for no real reason.
  void handle(bool isActive) {
    if (isActive) {
      _briefDotTimer?.cancel();
      _briefDotTimer = null;
      if (_active) return;
      _active = true;
      _showingBanner = true;
      _prominentTimer?.cancel();
      stack.register(buildActivity());
      dotTransition.value = 0;
      _prominentTimer = Timer(prominentDuration, () {
        _showingBanner = false;
        stack.remove(activityId);
        dotTransition.forward();
      });
    } else {
      if (!_active) return;
      _active = false;

      if (_showingBanner) {
        // Ending before the banner's own prominent window closed on its
        // own means this was too brief to read as text in the first
        // place — a screenshot's underlying signal can be on and off
        // again in single-digit milliseconds. Skip straight to the same
        // small dot a sustained activation recedes to, held for a fixed,
        // actually-perceptible duration instead of whatever the real
        // (likely imperceptible) duration happened to be.
        _showingBanner = false;
        _prominentTimer?.cancel();
        stack.remove(activityId);
        dotTransition.forward();
        _briefDotTimer = Timer(briefDotDuration, () {
          _briefDotTimer = null;
          dotTransition.reverse();
        });
      } else {
        // Already receded to the dot on its own — a real, sustained
        // activation actually ending now.
        dotTransition.reverse();
      }
    }
  }

  void dispose() {
    _prominentTimer?.cancel();
    _briefDotTimer?.cancel();
    dotTransition.dispose();
  }
}

/// The small dot a [PrivacyIndicatorController] recedes to — driven by the
/// controller's own [transition] value rather than the box's geometry, same
/// reasoning as the shell's content-transition clock: this is a small
/// decoration, not a resize, so it gets its own independent clock.
/// [rightOffset] lets more than one of these coexist side by side (mic,
/// camera) without overlapping.
/// [compactT] (0 = normal, 1 = fully compact) shifts the dot from vertically
/// centered up toward the top edge and shrinks it slightly — driven by
/// island_shell's own `_dotsCompactTransition`, for whenever something other
/// than the plain battery fallback is showing underneath: a centered dot
/// otherwise sits right on top of that content's own elements (a media
/// control, a Bluetooth alert, ...), which is the whole reason this exists
/// rather than just always centering.
/// [compactRightOffset] and [compactTopInset] are this dot's *own*
/// independent horizontal/vertical margins once fully compact — genuinely
/// independent, not mirrors of each other. An earlier version forced them
/// equal (a "true symmetric corner margin," on request) until measuring
/// against the pill's actual rounded corner (`ClipRRect`, not a plain
/// rectangle) proved that constraint impossible to satisfy at all: the
/// horizontal room needed to clear the corner's own curve (~9px, measured)
/// and the vertical room needed to clear real content sitting close to the
/// top (~3px, also measured, against Now Playing's play/pause icon) are
/// just different numbers — forcing them equal meant picking a value that
/// satisfied neither. [compactRightOffset] defaults to [rightOffset] itself
/// (unaffected home-state spacing) unless a caller with the same collision
/// needs a different one; [compactTopInset] defaults to a value verified
/// clear of both constraints at this pill's actual corner radius and a
/// worst-case real icon.
class PrivacyIndicatorDot extends StatelessWidget {
  const PrivacyIndicatorDot({
    super.key,
    required this.transition,
    required this.color,
    required this.label,
    required this.rightOffset,
    this.compactT = 0,
    double? compactRightOffset,
    this.compactTopInset = 4,
  }) : compactRightOffset = compactRightOffset ?? rightOffset;

  final Animation<double> transition;
  final Color color;
  final String label;
  final double rightOffset;
  final double compactT;
  final double compactRightOffset;
  final double compactTopInset;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: transition,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(transition.value);
        if (t <= 0) return const SizedBox.shrink();
        final size = 6.0 - (2.0 * compactT);
        // Both axes interpolate the same direct, linear way now — right as
        // a plain pixel lerp between rightOffset and compactRightOffset,
        // top the same way between "centered" and compactTopInset. An
        // earlier version drove the vertical axis through Align's own
        // alignment-fraction math instead, whose pixel effect depends on
        // the (also-changing) size and available height terms — technically
        // still continuous, but enough of a different curve shape from the
        // horizontal axis's plain lerp to read as a less clean slide than
        // the two axes moving in visible lockstep.
        final effectiveRightOffset = rightOffset + (compactRightOffset - rightOffset) * compactT;
        return Positioned(
          right: effectiveRightOffset,
          top: 0,
          bottom: 0,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final centeredTop = (constraints.maxHeight - size) / 2;
              final double effectiveTop = (centeredTop + (compactTopInset - centeredTop) * compactT).clamp(
                0.0,
                math.max(0.0, constraints.maxHeight - size),
              );
              return Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: effectiveTop),
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: 0.4 + (0.6 * t),
                      child: Semantics(
                        label: label,
                        excludeSemantics: true,
                        liveRegion: true,
                        child: Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
