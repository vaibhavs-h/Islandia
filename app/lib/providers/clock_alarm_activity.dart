import 'package:flutter/material.dart';

import '../engine/activity.dart';
import 'clock_awareness_provider.dart';

/// Each call gets its own id — same reasoning as
/// wifi_connection_activity.dart's own sequence counter: a set-then-delete
/// in quick succession (or two different alarms created back to back)
/// needs to read as distinct arrivals, not one activity quietly changing
/// its mind mid-display.
int _alarmNotificationSequence = 0;

/// What actually happened to an alarm — an edit reuses the alarm's own
/// id (confirmed live: changing an existing alarm's time keeps its
/// MTAlarmID unchanged), so a plain created/deleted bool can't represent
/// it; a third state, not a second bool, is what this needs. [enabled]
/// and [disabled] are a fourth/fifth: island_shell.dart's own diffing
/// specifically excludes the one case that would otherwise look
/// identical to a user's own toggle — a one-off alarm auto-disabling
/// itself the instant it fires (confirmed live: MTAlarmEnabled flips
/// straight from 1 to 0 right as it rings) — so every [disabled] this
/// produces really is the user's own action, not Clock's.
enum AlarmChangeKind { created, deleted, edited, enabled, disabled }

/// An alarm being created, deleted, edited, or toggled on/off in the
/// macOS Clock app — same Alert tier, transient, 5s-auto-dismiss shape as
/// the Wi-Fi/Bluetooth connection alerts (see wifi_connection_activity.dart),
/// since this is the same kind of thing: a short-lived fact about
/// something that just happened, not an ongoing state to keep displaying.
///
/// Detection itself lives in island_shell.dart, diffing successive
/// ClockAwarenessSnapshot.alarms lists the same way Bluetooth
/// connect/disconnect already diffs successive device lists — there's no
/// native push for "an alarm was just created/edited/toggled," only
/// polled snapshots of what currently exists.
Activity buildAlarmAlertActivity({required ClockAlarm alarm, required AlarmChangeKind kind}) {
  _alarmNotificationSequence++;
  return Activity(
    id: 'alarm-alert-$_alarmNotificationSequence',
    priority: ActivityPriority.alert,
    isTransient: true,
    autoDismissAfter: const Duration(seconds: 5),
    collapsedBuilder: (context, state) => _AlarmAlertContent(alarm: alarm, kind: kind, expanded: false),
    expandedBuilder: (context, state) => _AlarmAlertContent(alarm: alarm, kind: kind, expanded: true),
  );
}

/// A scheduled alarm actively ringing, unresolved by the user — a
/// persistent activity (no `isTransient`/`autoDismissAfter`), unlike the
/// created/deleted/edited alerts above: its lifetime is tied to the real
/// ringing state (island_shell.dart registers it the instant
/// ClockAwarenessSnapshot.isScheduledAlarmRinging goes true and removes
/// it the instant that goes false again), not a fixed timeout.
///
/// `p4RingingEvent` — the same tier a completed/ringing timer also uses
/// (see clock_awareness_activity.dart's own timer/stopwatch resolver),
/// and the tier the shell's own dark-red backdrop and "priority already
/// owns the surface" guard exist for (see island_shell.dart) — since a
/// ringing alarm is exactly that kind of thing: it should preempt
/// whatever else is showing, the same way an incoming call would, not
/// queue politely behind Now Playing or battery. Below only the Shelf,
/// which always wins regardless of what's ringing.
///
/// No specific alarm name shown, deliberately — see
/// ClockAwarenessSnapshot.isScheduledAlarmRinging's own doc comment for
/// why there's no reliable way to know *which* alarm from `alarms` is
/// the one currently ringing (a fired alarm never drops out of that
/// list, and the underlying log line carries no per-alarm identifier).
Activity buildAlarmRingingActivity() {
  return Activity(
    id: 'alarm-ringing',
    priority: ActivityPriority.ringingEvent,
    collapsedBuilder: (context, state) => const _AlarmRingingContent(expanded: false),
    expandedBuilder: (context, state) => const _AlarmRingingContent(expanded: true),
  );
}

class _AlarmRingingContent extends StatelessWidget {
  const _AlarmRingingContent({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final iconSize = expanded ? 20.0 : 18.0;
    final fontSize = expanded ? 17.0 : 15.0;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.alarm, color: Colors.white, size: iconSize),
        SizedBox(width: expanded ? 10 : 9),
        Text(
          'Alarm ringing',
          style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: expanded ? FontWeight.w600 : FontWeight.normal),
          textAlign: TextAlign.center,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        label: 'Alarm ringing.',
        excludeSemantics: true,
        liveRegion: true,
        // Centered in both the collapsed pill and the expanded card —
        // deliberately, explicitly asked for as different from
        // wifi_connection_activity.dart's own convention (collapsed
        // left-aligned, expanded centered), specifically for alarms.
        child: Center(child: row),
      ),
    );
  }
}

class _AlarmAlertContent extends StatelessWidget {
  const _AlarmAlertContent({required this.alarm, required this.kind, required this.expanded});

  final ClockAlarm alarm;
  final AlarmChangeKind kind;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final time = alarm.formattedTime();
    // A named alarm reads "Alarm <alarm's own title> Set For 9:48 PM" —
    // an unnamed one must NOT fall back to a literal "Alarm" for the name
    // segment, or it doubles up with the leading "Alarm" label itself
    // ("Alarm Alarm Set For..." — reported live as looking wrong).
    // Omitting the name segment entirely for an empty title instead reads
    // as a clean, single "Alarm Set For 9:48 PM".
    //
    // Confirmed live: Clock itself never actually leaves MTAlarmTitle
    // empty for an unnamed alarm — it defaults the field to the literal
    // string "Alarm" (that IS its own displayed default name in Clock's
    // own UI, not a sentinel for "no title"). Checking for emptiness
    // alone therefore missed this exact case: a default alarm's own
    // title genuinely equals the word this app already prefixes every
    // one of these lines with, producing "Alarm Alarm Set For..." (or
    // "...Updated To...") for every alarm the user never bothered to
    // rename — reported live as still looking wrong even after the
    // empty-string fix above. Both spellings of "nothing distinctive to
    // say here" collapse to the same blank namePart now.
    final namePart = (alarm.title.isEmpty || alarm.title == 'Alarm') ? '' : '${alarm.title} ';
    // Deletion and (time-only) edits both have no "for a time" clause the
    // way creation does in one case (nothing left to report) and a
    // different one in the other (the *new* time already reads as the
    // whole point, "Updated To <time>" carrying it the same way "Set
    // For <time>" does for a fresh alarm).
    final statusText = switch (kind) {
      AlarmChangeKind.created => 'Set For $time',
      AlarmChangeKind.deleted => 'Deleted',
      AlarmChangeKind.edited => 'Updated To $time',
      AlarmChangeKind.enabled => 'Enabled',
      AlarmChangeKind.disabled => 'Disabled',
    };
    final label = 'Alarm $namePart${statusText.toLowerCase()}.';
    final iconSize = expanded ? 20.0 : 18.0;
    final fontSize = expanded ? 17.0 : 15.0;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.alarm, color: Colors.white, size: iconSize),
        SizedBox(width: expanded ? 10 : 9),
        Flexible(
          child: Text(
            'Alarm $namePart$statusText',
            style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: expanded ? FontWeight.w600 : FontWeight.normal),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        label: label,
        excludeSemantics: true,
        liveRegion: true,
        // Centered in both the collapsed pill and the expanded card —
        // deliberately, explicitly asked for as different from
        // wifi_connection_activity.dart's own convention (collapsed
        // left-aligned, expanded centered), specifically for alarms.
        child: Center(child: row),
      ),
    );
  }
}
