import 'dart:async';

import 'package:flutter/foundation.dart';

import 'activity.dart';

/// §03's Activity Stack: every registered activity lives here, ordered by
/// priority then recency. The Island only ever renders [top] — everything
/// below is suspended, not destroyed, so restoring it later never recreates
/// it (a suspended activity is a live value sitting lower in the list).
class ActivityStack extends ChangeNotifier {
  final List<Activity> _entries = [];
  final Map<String, Timer> _autoDismissTimers = {};

  Activity? get top => _entries.isEmpty ? null : _entries.first;

  List<Activity> get entries => List.unmodifiable(_entries);

  /// Inserts at the position its priority earns. Ties go to the new entry —
  /// "most-recently-registered wins the top slot" is the only tiebreaker
  /// that needs no cross-provider negotiation.
  ///
  /// If an activity with the same id is already registered, this instead
  /// replaces it in place: a provider pushing a fresh value for an activity
  /// that already exists (a battery percentage ticking down, say) is an
  /// update, not a new arrival, and shouldn't jump the queue every time it
  /// happens to refresh.
  void register(Activity activity) {
    _scheduleAutoDismiss(activity);

    final existingIndex = _entries.indexWhere((existing) => existing.id == activity.id);
    if (existingIndex != -1) {
      _entries[existingIndex] = activity;
      notifyListeners();
      return;
    }
    final insertIndex = _entries.indexWhere(
      (existing) => existing.priority.index >= activity.priority.index,
    );
    if (insertIndex == -1) {
      _entries.add(activity);
    } else {
      _entries.insert(insertIndex, activity);
    }
    notifyListeners();
  }

  /// Completion, expiration, or dismissal — all pop the same way. Whatever
  /// is now on top (if anything) resumes rendering from its retained state.
  void remove(String id) {
    _autoDismissTimers.remove(id)?.cancel();
    final removed = _entries.any((e) => e.id == id);
    _entries.removeWhere((e) => e.id == id);
    if (removed) notifyListeners();
  }

  /// §03's `timeout`: an activity ages out on its own, no user action and
  /// no provider push required. Re-registering (e.g. a fresh value pushed
  /// mid-countdown) restarts the clock rather than stacking a second timer.
  void _scheduleAutoDismiss(Activity activity) {
    _autoDismissTimers.remove(activity.id)?.cancel();
    final duration = activity.autoDismissAfter;
    if (duration == null) return;
    _autoDismissTimers[activity.id] = Timer(duration, () => remove(activity.id));
  }

  @override
  void dispose() {
    for (final timer in _autoDismissTimers.values) {
      timer.cancel();
    }
    _autoDismissTimers.clear();
    super.dispose();
  }
}
