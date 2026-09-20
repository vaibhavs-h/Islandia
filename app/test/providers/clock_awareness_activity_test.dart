import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/providers/clock_awareness_activity.dart';
import 'package:islandia/providers/clock_awareness_provider.dart';

void main() {
  Future<void> pump(WidgetTester tester, Activity activity) {
    return tester.pumpWidget(
      MaterialApp(
        home: Material(child: Builder(builder: (context) => activity.collapsedBuilder(context, LifecycleState.collapsed))),
      ),
    );
  }

  group('selectClockAwarenessView', () {
    test('a running timer alone shows the timer view', () {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 5), title: '')],
        stopwatch: null,
      );
      expect(selectClockAwarenessView(snapshot, null), ClockAwarenessView.timer);
    });

    test('a running stopwatch alone shows the stopwatch view', () {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [],
        stopwatch: ClockRunningStopwatch(id: 'a', elapsed: Duration(seconds: 30)),
      );
      expect(selectClockAwarenessView(snapshot, null), ClockAwarenessView.stopwatch);
    });

    test('nothing running shows nothing', () {
      const snapshot = ClockAwarenessSnapshot(isAlarmRinging: false, timers: [], stopwatch: null);
      expect(selectClockAwarenessView(snapshot, ClockAwarenessView.stopwatch), isNull);
    });

    test('a stopwatch running alongside a timer with time to spare shows the stopwatch', () {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 5), title: '')],
        stopwatch: ClockRunningStopwatch(id: 'b', elapsed: Duration(seconds: 30)),
      );
      expect(selectClockAwarenessView(snapshot, ClockAwarenessView.stopwatch), ClockAwarenessView.stopwatch);
    });

    test('a timer entering its last 10 seconds preempts a running stopwatch', () {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(seconds: 10), title: '')],
        stopwatch: ClockRunningStopwatch(id: 'b', elapsed: Duration(seconds: 30)),
      );
      expect(selectClockAwarenessView(snapshot, ClockAwarenessView.stopwatch), ClockAwarenessView.timer);
    });

    test('a ringing alarm holds the timer view even past the preempt window (still-ringing case)', () {
      // The plist alone cannot tell "still ringing" apart from "dismissed"
      // (see ClockAlarmRingingWatcher) — isAlarmRinging is the only signal
      // trusted for this, deliberately not re-derived from remaining time.
      // The fired timer itself is still present here — native guarantees
      // that for as long as isAlarmRinging stays true (see
      // ClockActivityChannel.emit()); this snapshot reflects that
      // guarantee rather than the empty-timers shape it exists to prevent.
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: true,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(seconds: 0), title: '')],
        stopwatch: ClockRunningStopwatch(id: 'b', elapsed: Duration(seconds: 30)),
      );
      expect(selectClockAwarenessView(snapshot, ClockAwarenessView.timer), ClockAwarenessView.timer);
    });

    test('the alarm being dismissed hands back to a still-running stopwatch', () {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [],
        stopwatch: ClockRunningStopwatch(id: 'b', elapsed: Duration(seconds: 45)),
      );
      expect(selectClockAwarenessView(snapshot, ClockAwarenessView.timer), ClockAwarenessView.stopwatch);
    });

    test('the alarm being dismissed with no stopwatch running shows nothing', () {
      const snapshot = ClockAwarenessSnapshot(isAlarmRinging: false, timers: [], stopwatch: null);
      expect(selectClockAwarenessView(snapshot, ClockAwarenessView.timer), isNull);
    });

    test('ringing with no timer to show falls back to the stopwatch rather than a blank timer view', () {
      // Regression: native is responsible for keeping soonest non-null for
      // as long as isAlarmRinging is true (see ClockActivityChannel's
      // emit()), but this must never trust that blindly — a snapshot
      // violating it once left the pill occupying the top slot while
      // rendering nothing (see selectClockAwarenessView's own comment).
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: true,
        timers: [],
        stopwatch: ClockRunningStopwatch(id: 'b', elapsed: Duration(seconds: 30)),
      );
      expect(selectClockAwarenessView(snapshot, ClockAwarenessView.stopwatch), ClockAwarenessView.stopwatch);
    });

    test('ringing with no timer and no stopwatch to show falls back to nothing rather than a blank timer view', () {
      const snapshot = ClockAwarenessSnapshot(isAlarmRinging: true, timers: [], stopwatch: null);
      expect(selectClockAwarenessView(snapshot, null), isNull);
    });
  });

  group('collapsed view', () {
    testWidgets('the soonest of several timers drives the countdown, with a "+N" count for the rest', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [
          ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2), title: ''),
          ClockRunningTimer(id: 'b', remaining: Duration(minutes: 5), title: ''),
          ClockRunningTimer(id: 'c', remaining: Duration(minutes: 8), title: ''),
        ],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pump(tester, activity);

      // Always HH:MM:SS, zero-padded hour included (see
      // formatTimerDuration) — Clock's own Timer tab caps at 23:59:59, so
      // there's no short form to fall back to.
      expect(find.text('00:02:00'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(find.bySemanticsLabel('Timer, 00:02:00 remaining, and 2 other timers running.'), findsOneWidget);
    });

    testWidgets('a single timer shows no "+N" count', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2), title: '')],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pump(tester, activity);

      expect(find.text('00:02:00'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('an untitled timer shows the fallback "Timer" label', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2), title: '')],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pump(tester, activity);

      expect(find.text('Timer'), findsOneWidget);
    });

    testWidgets('a titled timer shows its own name instead of the word "Timer"', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2), title: 'Pasta')],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pump(tester, activity);

      expect(find.text('Pasta'), findsOneWidget);
      expect(find.text('Timer'), findsNothing);
    });

    testWidgets('a ringing timer shows its name + "done", not a stale 00:00:00 countdown', (tester) async {
      // Regression: native keeps reporting the fired timer's last-read
      // remaining time (near/at zero) for the whole ringing window (see
      // ClockActivityChannel.emit()) — rendering that number as a
      // countdown reads as broken.
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: true,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration.zero, title: 'Pasta')],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pump(tester, activity);

      expect(find.text('Pasta'), findsOneWidget);
      expect(find.text('done'), findsOneWidget);
      expect(find.text('00:00:00'), findsNothing);
      expect(find.bySemanticsLabel('Pasta done.'), findsOneWidget);
    });

    testWidgets('a long timer name ellipsizes rather than overflowing the collapsed pill', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [
          ClockRunningTimer(
            id: 'a',
            remaining: Duration(hours: 1, minutes: 2, seconds: 3),
            title: 'Bread proofing second rise before the oven',
          ),
        ],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      // The real collapsed pill (IslandShell._collapsedSize) — a plain
      // MaterialApp/Material surface with no width limit (the [pump]
      // helper above) would never actually exercise the overflow this
      // checks for.
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: SizedBox(
                width: 253,
                height: 41,
                child: Builder(builder: (context) => activity.collapsedBuilder(context, LifecycleState.collapsed)),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.textContaining('Bread proofing'));
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('the stopwatch view shows the icon, "Stopwatch" label, and elapsed time with centiseconds', (
      tester,
    ) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [],
        stopwatch: ClockRunningStopwatch(id: 'a', elapsed: Duration(minutes: 1, seconds: 5, milliseconds: 430)),
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.stopwatch, generation: 0);
      await pump(tester, activity);

      expect(find.text('Stopwatch'), findsOneWidget);
      expect(find.text('01:05.43'), findsOneWidget);
      expect(find.bySemanticsLabel('Stopwatch, 01:05.43 elapsed.'), findsOneWidget);
    });

    testWidgets('the stopwatch view is center-aligned', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [],
        stopwatch: ClockRunningStopwatch(id: 'a', elapsed: Duration(seconds: 5)),
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.stopwatch, generation: 0);
      await pump(tester, activity);

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.mainAxisAlignment, MainAxisAlignment.center);
    });

    testWidgets('the stopwatch view expands to show an hour column once elapsed crosses an hour', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [],
        stopwatch: ClockRunningStopwatch(id: 'a', elapsed: Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 40)),
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.stopwatch, generation: 0);
      await pump(tester, activity);

      expect(find.text('1:02:03.04'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d{2}:\d{2}\.\d{2}$')), findsNothing);
    });
  });

  group('expanded stopwatch view lap coloring', () {
    Future<void> pumpExpanded(WidgetTester tester, Activity activity) {
      return tester.pumpWidget(
        MaterialApp(
          home: Material(child: Builder(builder: (context) => activity.expandedBuilder(context, LifecycleState.expanded))),
        ),
      );
    }

    // A lap's split and total render as the same text whenever they're
    // numerically equal (e.g. an unlapped in-progress row, or lap 1's own
    // split/total) — both are always colored the same way regardless
    // (they're the same row, the same rank), so this checks every match
    // shares one color rather than assuming there's exactly one.
    Color colorOf(WidgetTester tester, String text) {
      final colors = tester.widgetList<Text>(find.text(text)).map((t) => t.style!.color!).toSet();
      expect(colors, hasLength(1), reason: 'expected all instances of "$text" to share one color, found: $colors');
      return colors.single;
    }

    // Regression test: an earlier version ranked fastest/slowest only across
    // whichever (up to) 3 rows happened to be visible, so a real fastest or
    // slowest lap that had scrolled out of the visible window was never
    // colored, and whichever row merely happened to be slowest *among the
    // visible 3* got colored as if it were the true slowest. 6 recorded
    // laps here (7 rows total counting the in-progress one), trimmed to the
    // last 3 shown — lap 5 (3s), lap 6 (2s), lap 7/in-progress (3s) — with
    // the true fastest (lap 2, 1s) and slowest (lap 1, 12s) both scrolled
    // out of that visible window.
    testWidgets('ranks fastest/slowest across the full lap history, not just the visible last 3', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [],
        stopwatch: ClockRunningStopwatch(
          id: 'a',
          elapsed: Duration(seconds: 30),
          laps: [
            Duration(seconds: 12), // lap 1: slowest overall, not visible
            Duration(seconds: 1), // lap 2: fastest overall, not visible
            Duration(seconds: 5), // lap 3, not visible
            Duration(seconds: 4), // lap 4, not visible
            Duration(seconds: 3), // lap 5 (visible)
            Duration(seconds: 2), // lap 6 (visible)
          ],
        ),
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.stopwatch, generation: 0);
      await pumpExpanded(tester, activity);

      // Lap 6 (2s) would be "fastest visible" and lap 5/in-progress (3s
      // each) would tie for "slowest visible" if ranking only looked at
      // what's on screen — none of them is the true fastest/slowest overall,
      // so none should be colored.
      expect(colorOf(tester, '00:03.00'), Colors.white);
      expect(colorOf(tester, '00:02.00'), Colors.white);
    });

    // Regression test: an earlier version included the in-progress
    // (not-yet-lapped) row in the fastest/slowest comparison, so its own
    // still-growing split could itself get colored — Clock's own behavior
    // (confirmed live against its Accessibility tree: the in-progress row's
    // description carries a distinct "elapsed" suffix Clock never ranks)
    // never colors that row at all, no matter how long or short its split.
    testWidgets('never colors the in-progress row, even when its split would otherwise be the slowest', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [],
        stopwatch: ClockRunningStopwatch(
          id: 'a',
          // Recorded laps are both short; elapsed leaves a huge in-progress
          // span that would "win" slowest if it were included in ranking.
          elapsed: Duration(seconds: 40),
          laps: [Duration(seconds: 2), Duration(seconds: 3)],
        ),
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.stopwatch, generation: 0);
      await pumpExpanded(tester, activity);

      // In-progress row (lap 3): 40 - (2+3) = 35s split, way longer than
      // either recorded lap — must still render white, not red.
      expect(colorOf(tester, '00:35.00'), Colors.white);
      // The two real, finalized laps rank fastest (green) vs slowest (red)
      // against each other, same as if the in-progress row didn't exist.
      expect(colorOf(tester, '00:02.00'), const Color(0xFF32D74B));
      expect(colorOf(tester, '00:03.00'), const Color(0xFFFF453A));
    });

    testWidgets('colors nothing when there is only the in-progress row (nothing lapped yet)', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [],
        stopwatch: ClockRunningStopwatch(id: 'a', elapsed: Duration(seconds: 8)),
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.stopwatch, generation: 0);
      await pumpExpanded(tester, activity);

      expect(colorOf(tester, '00:08.00'), Colors.white);
    });
  });

  group('expanded timer view', () {
    Future<void> pumpExpanded(WidgetTester tester, Activity activity) {
      return tester.pumpWidget(
        MaterialApp(
          home: Material(child: Builder(builder: (context) => activity.expandedBuilder(context, LifecycleState.expanded))),
        ),
      );
    }

    testWidgets('shows a horizontal progress bar reflecting how much time is left', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        // Half the 5-minute duration remains — the bar's value should
        // reflect that same 0.5 fraction (see
        // ClockRunningTimer.progressFraction: 1.0 = just started, 0.0 =
        // about to fire).
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2, seconds: 30), title: 'Pasta', duration: Duration(minutes: 5))],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pumpExpanded(tester, activity);

      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(0.5, 0.01));
      expect(find.text('Pasta'), findsOneWidget);
      expect(find.text('00:02:30'), findsOneWidget);
    });

    testWidgets('Cancel and Pause buttons send the matching command', (tester) async {
      const channel = MethodChannel('islandia/clock-awareness/control');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(seconds: 30), title: '', duration: Duration(seconds: 60))],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pumpExpanded(tester, activity);

      await tester.tap(find.text('Cancel'));
      await tester.tap(find.text('Pause'));
      await tester.pump();

      expect(calls, ['cancelTimer', 'pauseTimer']);
    });

    testWidgets('a failed Pause tap shows a brief "can\'t reach Clock" message instead of silently doing nothing', (tester) async {
      // Regression: ClockAwarenessControl's methods used to return void —
      // native's own controlChannel handler called result(nil)
      // unconditionally, the instant send() was *called*, not once it
      // actually finished, so there was no way for this widget to ever
      // know a command failed. Confirmed live and independently
      // documented: pressing Lap/Stop/Cancel/Pause while Clock's window
      // sits on a macOS Space that isn't currently active (some other app
      // full-screen, or just a different desktop) silently does nothing —
      // a real WindowServer/Accessibility limitation with no public-API
      // workaround (the same root cause yabai and AltTab both hit).
      // Native now reports true/false for whether a real button press
      // actually landed; this is the Dart-side surface for `false`.
      const channel = MethodChannel('islandia/clock-awareness/control');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => false);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(seconds: 30), title: '', duration: Duration(seconds: 60))],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pumpExpanded(tester, activity);

      expect(find.text("Can't Reach Clock Right Now... Switch to Desktop"), findsNothing);
      await tester.tap(find.text('Pause'));
      await tester.pump();

      expect(find.text("Can't Reach Clock Right Now... Switch to Desktop"), findsOneWidget);
    });

    testWidgets('a successful command clears any previously-shown "can\'t reach Clock" message', (tester) async {
      const channel = MethodChannel('islandia/clock-awareness/control');
      var succeeds = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => succeeds);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(seconds: 30), title: '', duration: Duration(seconds: 60))],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pumpExpanded(tester, activity);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text("Can't Reach Clock Right Now... Switch to Desktop"), findsOneWidget);

      succeeds = true;
      await tester.tap(find.text('Resume'));
      await tester.pump();

      expect(find.text("Can't Reach Clock Right Now... Switch to Desktop"), findsNothing);
    });

    testWidgets('a ringing timer shows "done" instead of the progress bar and a stale countdown', (tester) async {
      const snapshot = ClockAwarenessSnapshot(
        isAlarmRinging: true,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration.zero, title: 'Pasta', duration: Duration(minutes: 5))],
        stopwatch: null,
      );
      final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);
      await pumpExpanded(tester, activity);

      expect(find.text('done'), findsOneWidget);
      expect(find.text('Pasta'), findsOneWidget);
      // Regression: an earlier version kept Cancel/Pause visible and fully
      // tappable during ringing — but a ringing timer has no real Clock
      // Timers-tab UI to act on (it's a fired alert, not a live
      // countdown), so a stray "Pause" tap here could freeze this widget
      // permanently using the ringing timer's own already-fired data, with
      // no real timer left for "Resume" to ever un-freeze. Confirmed live:
      // this was the exact stuck-forever bug that motivated hiding them.
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Pause'), findsNothing);
    });

    testWidgets('resolving from ringing back to a real countdown never carries over a frozen-paused state', (tester) async {
      // Regression, end to end: ringing → (in the old, buggy version, a
      // stray Pause tap here would have frozen this widget using the
      // ringing timer's own already-fired data) → the alarm resolves and a
      // fresh, genuinely different countdown becomes soonest. This must
      // show the fresh countdown normally, not a stale "Resume" state
      // left over from anything that happened during ringing.
      const ringingSnapshot = ClockAwarenessSnapshot(
        isAlarmRinging: true,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration.zero, title: 'Pasta', duration: Duration(minutes: 5))],
        stopwatch: null,
      );
      await pumpExpanded(tester, buildClockAwarenessActivity(ringingSnapshot, ClockAwarenessView.timer, generation: 0));
      expect(find.text('done'), findsOneWidget);
      // The old Pause button is gone during ringing, so there's no way for
      // a tap to reach _handlePauseButtonTap here at all — confirms the
      // fix at the UI layer, not just the guard clause underneath it.
      expect(find.text('Pause'), findsNothing);

      const freshTimerSnapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'b', remaining: Duration(minutes: 1), title: 'Eggs', duration: Duration(minutes: 3))],
        stopwatch: null,
      );
      // Same generation as the first pump — a real rebuild of the same
      // widget instance (matching how island_shell.dart's own rebuilds
      // work), not a fresh one, so this genuinely exercises whether state
      // carries over incorrectly.
      await pumpExpanded(tester, buildClockAwarenessActivity(freshTimerSnapshot, ClockAwarenessView.timer, generation: 0));

      expect(find.text('Eggs'), findsOneWidget);
      expect(find.text('00:01:00'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
    });

    testWidgets('a running timer that vanishes without ever being paused or canceled renders nothing, not a stale frame', (
      tester,
    ) async {
      // The fallback in build() (widget.timer ?? _lastRealTimer) is now
      // unconditional, not gated on _isPaused — see build()'s own comment
      // for why (a confirmed-live black flash on Resume otherwise). That
      // fix only clears _lastRealTimer explicitly on a real Cancel tap
      // (_handleCancelButtonTap) or a fresh real arrival (didUpdateWidget)
      // — this covers the third way a timer can stop being widget.timer:
      // it simply drops out of native's own list with no ringing and no
      // button tap in between at all (the same shape a real Cancel *from
      // Clock itself*, not this island's own button, would produce). If
      // _lastRealTimer were ever a truly unconditional memory with no
      // clearing path for this case, this would incorrectly go on
      // rendering the vanished timer forever.
      const runningSnapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2), title: 'Pasta', duration: Duration(minutes: 5))],
        stopwatch: null,
      );
      await pumpExpanded(tester, buildClockAwarenessActivity(runningSnapshot, ClockAwarenessView.timer, generation: 0));
      expect(find.text('Pasta'), findsOneWidget);

      const goneSnapshot = ClockAwarenessSnapshot(isAlarmRinging: false, timers: [], stopwatch: null);
      await pumpExpanded(tester, buildClockAwarenessActivity(goneSnapshot, ClockAwarenessView.timer, generation: 0));

      expect(find.text('Pasta'), findsNothing);
      expect(find.text('Resume'), findsNothing);
      expect(find.text('Pause'), findsNothing);
    });

    // Regression tests for the pause/resume/cancel-while-frozen redesign —
    // see _TimerExpanded's own doc comment for why this moved from an
    // island_shell.dart-level data override (which got permanently stuck
    // live) to local widget state. pumpExpanded re-pumps the *same*
    // MaterialApp/Material/Builder shape each "poll tick" rather than a
    // fresh pumpWidget, matching how island_shell.dart's own rebuilds
    // preserve _TimerExpandedState across real snapshot changes.
    testWidgets('pausing keeps the timer frozen on screen once it drops out of live data', (tester) async {
      // Mocked as a success (not `null`, which _invoke's own `?? false`
      // coerces to a *failure* and would show the unrelated "can't reach
      // Clock" banner on top of everything this test actually checks —
      // see clock_awareness_activity.dart's own _ClockCommandFeedback).
      // Originally just `null` here, written before that banner existed;
      // this test isn't about it, so a real success avoids it entirely
      // rather than asserting around it.
      const channel = MethodChannel('islandia/clock-awareness/control');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => true);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

      // asOf deliberately non-null — the real production shape
      // (ClockAwarenessProvider always supplies a genuine DateTime.now()
      // at parse time, paired with whatever `remaining` was *as of that
      // same instant*, never independently offset from it). Regression:
      // an earlier version's freeze aliased the live timer object
      // directly rather than capturing a static snapshot, so asOf
      // survived into the "frozen" state — currentRemaining()/
      // progressFraction() kept extrapolating forward from it on every
      // later rebuild regardless of _isPaused, and the progress bar
      // visibly kept draining even though the button correctly showed
      // "Resume". A const-literal asOf (omitted, defaulting to null)
      // would have hidden this bug entirely, since there'd have been
      // nothing live to extrapolate from in the first place — this test
      // exists specifically to not repeat that mistake.
      final runningSnapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [
          ClockRunningTimer(
            id: 'a',
            remaining: const Duration(minutes: 2, seconds: 30),
            title: 'Pasta',
            duration: const Duration(minutes: 5),
            asOf: DateTime.now(),
          ),
        ],
        stopwatch: null,
      );
      await pumpExpanded(tester, buildClockAwarenessActivity(runningSnapshot, ClockAwarenessView.timer, generation: 0));
      expect(find.text('Pause'), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);

      // The frozen value is captured via currentRemaining() at the exact
      // tap instant (see _handlePauseButtonTap), not the nominal 2:30
      // literal — any real wall-clock time between constructing
      // runningSnapshot's asOf and the tap above (test setup, widget
      // pumps, the tap itself all take real, if small, time) legitimately
      // shaves a little off, and formatTimerDuration's whole-second
      // truncation can tip that into showing 00:02:29 rather than
      // 00:02:30 depending on exactly how much elapsed — not a bug, the
      // same "one-time handoff adjustment" already documented below for
      // the *next* transition. Capturing whatever it actually reads right
      // after the tap, rather than asserting the pre-pause literal, is
      // what makes this test robust to that real variance instead of
      // fragile to it.
      final textAfterPauseTap = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).firstWhere((d) => d != null && d.contains(':'))!;

      // Real wall-clock delay, not just a rebuild — this is exactly the
      // dimension the original bug lived in: nothing about this rebuild
      // changes any input data, only time actually passing does, and
      // DateTime.now() doesn't advance under tester.pump()'s own fake
      // clock the way animations/timers do. runAsync briefly steps
      // outside testWidgets' fake-async zone so a real delay can
      // actually elapse. widget.timer is still the live object throughout
      // this step (island_shell.dart hasn't yet rebuilt with the timer
      // gone), so this specifically exercises whether _isPaused correctly
      // holds displaying widget.timer's own already-static `remaining`
      // field steady, not yet the handoff to _lastRealTimer below.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await tester.pump();
      expect(find.text(textAfterPauseTap), findsOneWidget);

      // Simulate the real poll tick a moment later: Clock's plist now
      // reports this timer as gone (paused looks identical to canceled at
      // the data layer — see ClockPreferencesReader's own doc comment),
      // same shape island_shell.dart would rebuild with mid-freeze-window.
      // This is the point control genuinely passes from widget.timer to
      // _lastRealTimer (see build()'s own `??` fallback) — the captured
      // frozen value can legitimately differ from the pre-pause literal
      // by up to ~1s here (currentRemaining() correctly accounts for the
      // real gap between the snapshot's own asOf and the moment Pause
      // was actually tapped, which the raw widget.timer.remaining field
      // never did) — that one-time handoff adjustment is not the bug;
      // what matters, and what the rest of this test actually checks, is
      // that this newly-frozen value then holds steady afterward.
      const goneSnapshot = ClockAwarenessSnapshot(isAlarmRinging: false, timers: [], stopwatch: null);
      await pumpExpanded(tester, buildClockAwarenessActivity(goneSnapshot, ClockAwarenessView.timer, generation: 0));

      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Pasta'), findsOneWidget);
      final valueAfterHandoff = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value;
      final textAfterHandoff = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).firstWhere((d) => d != null && d.contains(':'))!;

      // Real time passes, then island_shell.dart re-registers the Activity
      // on its next poll tick regardless of whether anything changed —
      // rebuilding with a brand-new widget instance is what actually
      // forces _TimerExpanded.build() to run again here. A bare
      // tester.pump() with no new widget and no setState firing (nothing
      // here has its own periodic ticker while paused — see build()'s own
      // comment on why _TimerTicker is deliberately not used in this
      // branch) does not re-invoke build() at all, so it could never have
      // caught this regression: it would silently keep re-displaying the
      // previous frame's own Text/LinearProgressIndicator widgets whether
      // the underlying code was buggy or fixed. Re-pumping with the same
      // goneSnapshot is what actually exercises the "did build() get
      // called again, and if so, did it drift" question.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await pumpExpanded(tester, buildClockAwarenessActivity(goneSnapshot, ClockAwarenessView.timer, generation: 0));

      // Still frozen at exactly the post-handoff value — no further
      // drift now that _lastRealTimer (not widget.timer) is the thing
      // being displayed.
      expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, valueAfterHandoff);
      expect(find.text(textAfterHandoff), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('resuming clears the freeze once fresh live data confirms it', (tester) async {
      const runningSnapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2, seconds: 30), title: 'Pasta', duration: Duration(minutes: 5))],
        stopwatch: null,
      );
      await pumpExpanded(tester, buildClockAwarenessActivity(runningSnapshot, ClockAwarenessView.timer, generation: 0));
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pump();
      // Local state flips back to Pause immediately on tap, even before
      // any fresh data confirms the resume actually landed — same
      // optimistic trust model as every other AX-driven command here.
      expect(find.text('Pause'), findsOneWidget);

      // Fresh live data now confirms it's genuinely running again, at a
      // real, different remaining value than what was frozen.
      const runningAgainSnapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2, seconds: 25), title: 'Pasta', duration: Duration(minutes: 5))],
        stopwatch: null,
      );
      await pumpExpanded(tester, buildClockAwarenessActivity(runningAgainSnapshot, ClockAwarenessView.timer, generation: 0));
      expect(find.text('00:02:25'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
    });

    testWidgets('tapping Resume never renders a blank frame before fresh live data arrives', (tester) async {
      // Regression: _handleResumeButtonTap clears _isPaused synchronously
      // in the same tap that requests a real Resume from Clock, but the
      // next live ClockRunningTimer (island_shell.dart's next poll tick,
      // delivered here as a fresh pumpExpanded call) hasn't arrived yet.
      // The old build() fallback only consulted _lastRealTimer while
      // _isPaused was still true — so for the frame(s) between the tap
      // and that fresh arrival, widget.timer was null (live data hadn't
      // caught up) AND _isPaused was already false (cleared by the tap),
      // leaving neither source with anything to show: a real, confirmed
      // black flash on every Resume tap (frame-captured live via temporary
      // debug logging on the actual running app, not just theorized).
      // Checking immediately after tester.pump() (not pumpAndSettle,
      // which would let time pass this test doesn't control) is what
      // actually exercises that exact single-frame gap.
      const runningSnapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2, seconds: 30), title: 'Pasta', duration: Duration(minutes: 5))],
        stopwatch: null,
      );
      await pumpExpanded(tester, buildClockAwarenessActivity(runningSnapshot, ClockAwarenessView.timer, generation: 0));
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);

      // Matches the real live sequence exactly (frame-captured on the
      // actual running app): island_shell.dart's _timerHeldByPause holds
      // this same view open while the timer has already dropped out of
      // native's own list (paused looks identical to gone at the data
      // layer — see ClockPreferencesReader's own doc comment), so
      // widget.timer is genuinely null on screen *before* Resume is even
      // tapped, same as it is in production the whole time a pause holds.
      const goneWhileHeldSnapshot = ClockAwarenessSnapshot(isAlarmRinging: false, timers: [], stopwatch: null);
      await pumpExpanded(tester, buildClockAwarenessActivity(goneWhileHeldSnapshot, ClockAwarenessView.timer, generation: 0));
      expect(find.text('Resume'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pump();

      // The exact frame the old code went blank on: widget.timer is still
      // null here (no fresh pumpExpanded has happened since the tap) and
      // _isPaused is already false (cleared by the tap itself). The
      // frozen title/countdown must still be visible — not a
      // SizedBox.shrink() with nothing painted.
      expect(find.text('Pasta'), findsOneWidget);
      expect(find.text('00:02:30'), findsOneWidget);
    });

    testWidgets('canceling while frozen clears the freeze instead of leaving a stale frame', (tester) async {
      const runningSnapshot = ClockAwarenessSnapshot(
        isAlarmRinging: false,
        timers: [ClockRunningTimer(id: 'a', remaining: Duration(minutes: 2, seconds: 30), title: 'Pasta', duration: Duration(minutes: 5))],
        stopwatch: null,
      );
      await pumpExpanded(tester, buildClockAwarenessActivity(runningSnapshot, ClockAwarenessView.timer, generation: 0));
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);

      // The real poll tick lands before Cancel is tapped, same as the
      // "stays frozen" test above — by the time a person could actually
      // see and tap the island's own Cancel button here, Clock's plist has
      // already stopped reporting this timer (frozen only because this
      // widget's own memory is filling that gap, not because the real data
      // is still there).
      const goneSnapshot = ClockAwarenessSnapshot(isAlarmRinging: false, timers: [], stopwatch: null);
      await pumpExpanded(tester, buildClockAwarenessActivity(goneSnapshot, ClockAwarenessView.timer, generation: 0));
      expect(find.text('00:02:30'), findsOneWidget); // still frozen, confirmed by the test above

      // Regression: an earlier version left this permanently stuck — even
      // a real Cancel from Clock itself couldn't remove it, since nothing
      // ever cleared the old design's shell-level override. Tapping the
      // island's own Cancel here must clear the local freeze immediately.
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.text('Resume'), findsNothing);
      expect(find.text('00:02:30'), findsNothing);
      expect(find.text('Pasta'), findsNothing);
    });
  });
}
