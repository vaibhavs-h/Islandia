import 'package:flutter/widgets.dart';

/// The five-tier total order the Activity Stack sorts by. **Declaration
/// order is what matters, not the name** — `ActivityStack.register` sorts
/// by `priority.index`, and a *lower* index sorts earlier in the stack's
/// own list (`top` is `_entries.first`), so whatever's declared **first**
/// here is the **highest** priority, closer to the top. (An earlier
/// version of this enum used a `p1`...`p5` numeric prefix and got bitten
/// by exactly this — `p1` read as "first/top priority" but the intended
/// meaning was "lowest tier"; plain names avoid that trap entirely.)
///
/// - `shelf`: the Shelf, holding a dragged-in file/folder/text. Always
///   wins — never overlaid by anything else in this stack (the privacy
///   dots are a separate, independent overlay outside this priority
///   system entirely; see island_shell.dart's own `_privacyDots()`).
/// - `ringingEvent`: a ringing alarm OR a completed/ringing timer — both
///   share the same real behavior (no auto-dismiss, blocks taps, resolved
///   only by the actual external event ending), so they share this one
///   tier rather than each inventing its own.
/// - `alert`: a brief, self-dismissing notification — Wi-Fi connect/
///   disconnect, low battery, a mic/camera/screen-capture indicator, an
///   alarm created/deleted/edited/enabled/disabled, a severe-weather or
///   calamity alert.
/// - `clock`: **Now Playing lives at this tier too** — it doesn't get its
///   own named value because neither it nor the Clock's timer/stopwatch
///   view has one FIXED priority relative to each other; which ONE of
///   {Now Playing, a running stopwatch, a running timer} actually gets
///   registered at `clock` on any given tick is decided dynamically by
///   island_shell.dart's own resolver (a timer close to completing can
///   outrank a running stopwatch; see that resolver's own doc comment for
///   the exact ordering) — a single static enum value can't express that,
///   so this tier is a shared slot all three compete for, not "the Clock
///   activity's" tier alone.
/// - `dashboard`: the normal resting state — Weather, Battery, Wi-Fi,
///   Bluetooth. Shows whenever nothing higher is currently relevant.
enum ActivityPriority { shelf, ringingEvent, alert, clock, dashboard }

/// The five states every activity's collapsed/expanded content is built for.
/// `collapsing` exists so a hover that resolves mid-expand can reverse
/// smoothly instead of jumping straight back to collapsed.
enum LifecycleState { collapsed, hover, expanded, interactive, collapsing }

typedef ActivityContentBuilder = Widget Function(BuildContext context, LifecycleState state);

/// One activity, the same object moving through the same five states
/// regardless of whether it's Now Playing, a call, or (here) a demo pill.
/// Deliberately just the fields this spike's fake activities need — the full
/// struct in §03 (progress, actions, timeout, persistence…) grows this out
/// once real providers exist.
class Activity {
  Activity({
    required this.id,
    required this.priority,
    required this.collapsedBuilder,
    required this.expandedBuilder,
    this.isTransient = false,
    this.autoDismissAfter,
  });

  final String id;
  final ActivityPriority priority;
  final ActivityContentBuilder collapsedBuilder;
  final ActivityContentBuilder expandedBuilder;

  /// Emits once and resolves itself — never queues behind a priority
  /// activity waiting for the surface (§03). A transient activity is
  /// expected to also set [autoDismissAfter]; the flag alone doesn't expire it.
  final bool isTransient;

  /// §03's `timeout` field: ages the activity out of the stack automatically
  /// this long after it's (re-)registered, no user action needed. The
  /// ActivityStack owns the timer — an activity never dismisses itself.
  final Duration? autoDismissAfter;
}
