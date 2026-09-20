import 'package:flutter/services.dart';

/// One running countdown from the macOS Clock app's Timers tab — see
/// ClockPreferencesReader.swift for where this actually comes from (there is
/// no public API; it's read straight out of Clock's own preferences plist).
///
/// [remaining] and [asOf] together work the same way as
/// NowPlayingSnapshot.elapsedSeconds/timestamp: native only pushes once a
/// second (see ClockActivityChannel.pollInterval), not continuously, so
/// [currentRemaining] extrapolates locally between pushes rather than
/// showing [remaining] as a static, second-stale value the whole time.
/// [asOf] is nullable (defaulting to just [remaining] itself, no
/// extrapolation) rather than defaulted to `DateTime.now()` in the
/// constructor — that call isn't a constant expression, so every `const
/// ClockRunningTimer(...)` this provider's own tests construct would stop
/// compiling; the real provider always supplies it, only tests that don't
/// care about ticking behavior omit it.
class ClockRunningTimer {
  const ClockRunningTimer({required this.id, required this.remaining, required this.title, this.duration, this.asOf});

  final String id;
  final Duration remaining;
  final String title;

  /// The timer's original, full duration — see
  /// ClockPreferencesReader.RunningTimer.durationSeconds. Nullable and
  /// optional for the same reason [asOf] is: existing `const
  /// ClockRunningTimer(...)` test constructions that don't care about
  /// progress-fraction display shouldn't need to supply it. Falls back to
  /// [remaining] itself in [progressFraction] when absent, reading as "just
  /// started" rather than crashing or dividing by zero.
  final Duration? duration;

  final DateTime? asOf;

  Duration currentRemaining() {
    final baseline = asOf;
    if (baseline == null) return remaining;
    final sinceUpdate = DateTime.now().difference(baseline);
    if (sinceUpdate.isNegative) return remaining;
    final projected = remaining - sinceUpdate;
    return projected.isNegative ? Duration.zero : projected;
  }

  /// How much of the timer is left, 0.0 (just fired) to 1.0 (just started)
  /// — for a radial progress ring drawn depleting clockwise, matching
  /// Clock's own Timer tab visual.
  double progressFraction() {
    final total = duration ?? remaining;
    if (total <= Duration.zero) return 0;
    final fraction = currentRemaining().inMilliseconds / total.inMilliseconds;
    return fraction.clamp(0.0, 1.0);
  }
}

/// The macOS Clock app's Stopwatch tab, while running. Clock only ever
/// tracks one.
///
/// See [ClockRunningTimer]'s own doc comment for why [asOf] exists, is
/// nullable, and how [currentElapsed] uses it — same extrapolation, same
/// reasons.
class ClockRunningStopwatch {
  const ClockRunningStopwatch({required this.id, required this.elapsed, this.laps = const [], this.asOf});

  final String id;
  final Duration elapsed;

  /// Recorded lap splits, oldest first — straight off Clock's own
  /// `MTStopwatchLaps` (see ClockPreferencesReader.RunningStopwatch.laps).
  /// Does not include whatever's elapsed since the last lap; that's
  /// [currentElapsed] minus the sum of this list, computed where it's
  /// actually displayed rather than stored here as a value that would
  /// itself need the same extrapolation [currentElapsed] already does.
  final List<Duration> laps;

  final DateTime? asOf;

  Duration currentElapsed() {
    final baseline = asOf;
    if (baseline == null) return elapsed;
    final sinceUpdate = DateTime.now().difference(baseline);
    return sinceUpdate.isNegative ? elapsed : elapsed + sinceUpdate;
  }
}

/// One entry from the macOS Clock app's Alarms tab — see
/// ClockPreferencesReader.Alarm for where this comes from. Unlike a timer
/// or stopwatch, an alarm just *is* (a fixed daily wall-clock time,
/// enabled or not) until deleted — there's no "running"/"remaining" to
/// extrapolate, so this carries no [asOf]/current-value method the way
/// [ClockRunningTimer]/[ClockRunningStopwatch] do.
class ClockAlarm {
  const ClockAlarm({required this.id, required this.title, required this.hour, required this.minute, required this.enabled});

  final String id;
  final String title;

  /// 24-hour clock, straight off `MTAlarmHour`/`MTAlarmMinute` — see
  /// ClockPreferencesReader.Alarm's own doc comment for why these are
  /// plain integers, not a wrapped date the way a timer's fire time is.
  final int hour;
  final int minute;

  final bool enabled;

  /// `9:48 AM`/`9:48 PM` — matches how Clock's own Alarms tab and the
  /// system's own 12-hour convention display a fixed daily time (never
  /// 24-hour here, regardless of the user's system clock format
  /// preference — this is specifically what the transient alert banner
  /// reads out loud via its own Semantics label, and a 12-hour reading is
  /// the unambiguous, universally-understood one for that purpose).
  String formattedTime() {
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final displayMinute = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMinute $period';
  }
}

/// A snapshot of everything the Clock app is doing right now.
class ClockAwarenessSnapshot {
  const ClockAwarenessSnapshot({
    required this.isAlarmRinging,
    required this.timers,
    required this.stopwatch,
    this.alarms = const [],
    this.isScheduledAlarmRinging = false,
  });

  /// Despite the name, this is about a fired *timer*'s alert sounding —
  /// see ClockAlarmRingingWatcher.swift's own doc comment for why "the
  /// alarm" was the natural word for a timer's ringing sound back when
  /// this field was named, before scheduled Alarms were tracked at all.
  /// Neither the plist nor AppleScript's window list can tell "still
  /// ringing" apart from "already dismissed"; this is one of two fields
  /// here that come from a live log watch instead of a polled preferences
  /// read — see [isScheduledAlarmRinging] for the other, unrelated one.
  final bool isAlarmRinging;

  /// Soonest-firing first — see [soonest].
  final List<ClockRunningTimer> timers;

  final ClockRunningStopwatch? stopwatch;

  /// Every alarm Clock knows about, enabled or not — see
  /// ClockPreferencesReader.alarms()'s own doc comment for why there's no
  /// filtering here the way [timers] filters to only currently-running
  /// ones. Set/deleted detection (a new id appearing/disappearing between
  /// snapshots) happens in island_shell.dart, the same diffing shape
  /// already used for Bluetooth connect/disconnect.
  final List<ClockAlarm> alarms;

  /// Whether a *scheduled* alarm (from [alarms], as opposed to a timer)
  /// is currently ringing — independent of [isAlarmRinging], which is
  /// genuinely about something else despite the similar name (see its own
  /// doc comment). Deliberately just a bool, not paired with which
  /// specific alarm from [alarms] is the one ringing: a fired alarm never
  /// drops out of [alarms] the way a fired timer drops out of [timers]
  /// (confirmed live — it stays present with `enabled` flipped to false
  /// instead), and the underlying ToneLibrary log line carries no
  /// per-alarm identifier either, the same already-accepted limitation
  /// [isAlarmRinging] has for timers.
  final bool isScheduledAlarmRinging;

  ClockRunningTimer? get soonest => timers.isEmpty ? null : timers.first;

  /// How many *other* running timers there are besides [soonest] — the
  /// "+N more timers running" count.
  int get otherTimerCount => timers.isEmpty ? 0 : timers.length - 1;
}

/// Real macOS Clock app awareness (timer + stopwatch) — there is no public
/// API for either; this reads Clock's own preferences plist for values and
/// watches a private log subsystem for the ringing-vs-dismissed signal
/// (see ClockActivityChannel.swift and the two native files it combines).
///
/// Remembering a just-fired timer across the gap between it dropping out of
/// the running list and the ringing signal catching up (so
/// selectClockAwarenessView always has something to render while ringing)
/// is handled entirely on the native side — see
/// ClockActivityChannel.emit()'s own doc comment for why doing it there,
/// not here, is what actually closes the race: two independently-scheduled
/// native callbacks (the poll timer and the ringing watcher) each call
/// `emit()`, so only fixing it at the one place they both funnel through
/// guarantees Dart never receives an inconsistent reading in the first
/// place. An earlier version of this fix lived here instead and only
/// mostly worked — it could still lose the remembered timer to a single
/// stale poll tick landing between the two signals, confirmed live.
class ClockAwarenessProvider {
  ClockAwarenessProvider._();

  static const EventChannel _channel = EventChannel('islandia/clock-activity/updates');

  static Stream<ClockAwarenessSnapshot> get updates {
    return _channel.receiveBroadcastStream().map((event) {
      // One timestamp for everything in this emission — both fields are
      // extrapolated from the same native poll, so they should extrapolate
      // from the same "as of" instant rather than two DateTime.now() calls
      // a few microseconds apart.
      final asOf = DateTime.now();
      final map = (event as Map).cast<String, Object?>();
      final rawTimers = (map['timers'] as List).cast<Map>();
      final timers = rawTimers.map((raw) {
        final t = raw.cast<String, Object?>();
        return ClockRunningTimer(
          id: t['id'] as String,
          remaining: Duration(milliseconds: ((t['remainingSeconds'] as num) * 1000).round()),
          title: t['title'] as String,
          duration: Duration(milliseconds: ((t['durationSeconds'] as num) * 1000).round()),
          asOf: asOf,
        );
      }).toList();
      // Native already sorts soonest-first (see
      // ClockPreferencesReader.runningTimers) — not re-sorted here so
      // there's exactly one place that ordering is decided.

      final rawStopwatch = map['stopwatch'] as Map?;
      final stopwatch = rawStopwatch == null
          ? null
          : () {
              final s = rawStopwatch.cast<String, Object?>();
              final rawLaps = (s['laps'] as List?)?.cast<num>() ?? const [];
              return ClockRunningStopwatch(
                id: s['id'] as String,
                elapsed: Duration(milliseconds: ((s['elapsedSeconds'] as num) * 1000).round()),
                laps: rawLaps.map((l) => Duration(milliseconds: (l * 1000).round())).toList(),
                asOf: asOf,
              );
            }();

      final rawAlarms = (map['alarms'] as List?)?.cast<Map>() ?? const [];
      final alarms = rawAlarms.map((raw) {
        final a = raw.cast<String, Object?>();
        return ClockAlarm(
          id: a['id'] as String,
          title: a['title'] as String,
          hour: a['hour'] as int,
          minute: a['minute'] as int,
          enabled: a['enabled'] as bool,
        );
      }).toList();

      return ClockAwarenessSnapshot(
        isAlarmRinging: map['isRinging'] as bool,
        timers: timers,
        stopwatch: stopwatch,
        alarms: alarms,
        isScheduledAlarmRinging: map['isScheduledAlarmRinging'] as bool? ?? false,
      );
    }).handleError((Object _) {});
  }
}

/// Lap/Stop/Cancel/Pause commands for the real Clock app's Stopwatch and
/// Timers tabs — see ClockStopwatchController.swift/ClockTimerController.swift
/// for how these actually reach Clock (Accessibility UI-scripting; there is
/// no public or private API to send commands to it the way
/// ClockPreferencesReader can read its state). Mirrors NowPlayingProvider's
/// split between a state-streaming EventChannel (above) and this separate
/// command-sending MethodChannel.
class ClockAwarenessControl {
  ClockAwarenessControl._();

  static const MethodChannel _channel = MethodChannel('islandia/clock-awareness/control');

  /// `true` only when the native side actually found and pressed a real
  /// button in Clock's own window. `false` covers every way that can fail
  /// — most notably, Clock's window sitting on a macOS Space that isn't
  /// currently active (some other app full-screen, or just a different
  /// virtual desktop): a real, documented Accessibility/WindowServer
  /// limitation with no public-API workaround (confirmed: the same root
  /// cause window-management tools like yabai and AltTab hit and neither
  /// can work around either), not a bug in this app. Callers should treat
  /// `false` as "couldn't reach Clock right now," not silently ignore it —
  /// see clock_awareness_activity.dart's own use of this for how that
  /// surfaces to the user.
  static Future<bool> lap() => _invoke('lap');
  static Future<bool> stop() => _invoke('stop');
  static Future<bool> cancelTimer() => _invoke('cancelTimer');
  static Future<bool> pauseTimer() => _invoke('pauseTimer');

  static Future<bool> _invoke(String method) async {
    final result = await _channel.invokeMethod<bool>(method);
    return result ?? false;
  }
}
