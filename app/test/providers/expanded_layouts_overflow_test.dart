import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/providers/battery_activity.dart';
import 'package:islandia/providers/battery_provider.dart';
import 'package:islandia/providers/clock_awareness_activity.dart';
import 'package:islandia/providers/clock_awareness_provider.dart';

/// Every activity's expanded content is rendered into the same fixed
/// 360x136 box (IslandShell._expandedSize) — this pumps each one at those
/// exact dimensions and checks none of them overflow, the same regression
/// shape as now_playing_activity_test.dart's dense-layout check.
///
/// This was 140 (not the real 136) until a stopwatch layout tight enough for
/// the 4px gap to matter caught it live — every prior layout here had enough
/// slack that the difference was never actually exercised.
void main() {
  Future<void> pumpExpanded(WidgetTester tester, Activity activity) async {
    final boxKey = UniqueKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          // See now_playing_activity_test.dart: Material's child gets tight
          // constraints, so a SizedBox alone can't actually shrink below the
          // test surface size — Center gives it loose constraints so it can.
          child: Center(
            child: SizedBox(
              key: boxKey,
              width: 360,
              height: 136,
              child: Builder(
                builder: (context) => activity.expandedBuilder(context, LifecycleState.expanded),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(boxKey)), const Size(360, 136));
  }

  testWidgets('battery expanded view does not overflow', (tester) async {
    const snapshot = BatterySnapshot(percentage: 0.42, isCharging: false, isCharged: false, isOnACPower: false);
    final activity = buildBatteryActivity(snapshot);

    await pumpExpanded(tester, activity);

    expect(tester.takeException(), isNull);
  });

  testWidgets('clock awareness timer view does not overflow', (tester) async {
    const snapshot = ClockAwarenessSnapshot(
      isAlarmRinging: false,
      timers: [
        ClockRunningTimer(id: 'a', remaining: Duration(minutes: 1, seconds: 30), title: 'Pasta'),
        ClockRunningTimer(id: 'b', remaining: Duration(minutes: 5), title: ''),
      ],
      stopwatch: null,
    );
    final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);

    await pumpExpanded(tester, activity);

    expect(tester.takeException(), isNull);
  });

  testWidgets('clock awareness timer view with a long title does not overflow', (tester) async {
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

    await pumpExpanded(tester, activity);

    expect(tester.takeException(), isNull);
  });

  testWidgets('clock awareness ringing timer view does not overflow', (tester) async {
    const snapshot = ClockAwarenessSnapshot(
      isAlarmRinging: true,
      timers: [ClockRunningTimer(id: 'a', remaining: Duration.zero, title: 'Pasta')],
      stopwatch: null,
    );
    final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.timer, generation: 0);

    await pumpExpanded(tester, activity);

    expect(tester.takeException(), isNull);
  });

  testWidgets('clock awareness stopwatch view does not overflow', (tester) async {
    const snapshot = ClockAwarenessSnapshot(
      isAlarmRinging: false,
      timers: [],
      stopwatch: ClockRunningStopwatch(id: 'a', elapsed: Duration(hours: 1, minutes: 2, seconds: 3)),
    );
    final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.stopwatch, generation: 0);

    await pumpExpanded(tester, activity);

    expect(tester.takeException(), isNull);
  });

  testWidgets('clock awareness stopwatch view with recorded laps does not overflow', (tester) async {
    const snapshot = ClockAwarenessSnapshot(
      isAlarmRinging: false,
      timers: [],
      stopwatch: ClockRunningStopwatch(
        id: 'a',
        elapsed: Duration(minutes: 8, seconds: 15, milliseconds: 840),
        laps: [
          Duration(seconds: 7, milliseconds: 540),
          Duration(milliseconds: 390),
          Duration(milliseconds: 320),
          Duration(milliseconds: 470),
        ],
      ),
    );
    final activity = buildClockAwarenessActivity(snapshot, ClockAwarenessView.stopwatch, generation: 0);

    await pumpExpanded(tester, activity);

    expect(tester.takeException(), isNull);
  });
}
