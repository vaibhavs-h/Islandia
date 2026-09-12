import 'package:flutter/widgets.dart';

/// §03 of the blueprint: the five-tier total order the Activity Stack sorts
/// by. Lower index = higher priority = closer to the top of the stack.
enum ActivityPriority { p0Critical, p1Immediate, p2Important, p3Ambient, p4Background }

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
