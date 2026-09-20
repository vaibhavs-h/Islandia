import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/providers/clock_awareness_provider.dart';

void main() {
  group('ClockRunningStopwatch.currentElapsed', () {
    test('extrapolates forward from asOf using real elapsed wall-clock time', () {
      final asOf = DateTime.now().subtract(const Duration(seconds: 3));
      const stopwatch = ClockRunningStopwatch(id: 'a', elapsed: Duration(seconds: 10));
      final withAsOf = ClockRunningStopwatch(id: 'a', elapsed: const Duration(seconds: 10), asOf: asOf);

      // No asOf at all — the exact "native hasn't given a timestamp"
      // shape this provider's own tests construct — returns the static
      // value as-is, the same as before extrapolation existed.
      expect(stopwatch.currentElapsed(), const Duration(seconds: 10));

      // ~3 real seconds have passed since asOf, so the extrapolated result
      // should be noticeably ahead of the static baseline — checked as a
      // range, not an exact value, since the test itself takes nonzero
      // wall-clock time to run.
      final elapsed = withAsOf.currentElapsed();
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(const Duration(seconds: 13).inMilliseconds));
      expect(elapsed.inMilliseconds, lessThan(const Duration(seconds: 14).inMilliseconds));
    });

    test('never goes backwards if asOf is somehow in the future', () {
      // A clock skew / message-ordering edge case, not expected in
      // practice — currentElapsed should fall back to the static baseline
      // rather than subtracting a negative duration into something absurd.
      final asOf = DateTime.now().add(const Duration(seconds: 5));
      final stopwatch = ClockRunningStopwatch(id: 'a', elapsed: const Duration(seconds: 10), asOf: asOf);

      expect(stopwatch.currentElapsed(), const Duration(seconds: 10));
    });
  });

  group('ClockRunningTimer.currentRemaining', () {
    test('counts down from asOf using real elapsed wall-clock time', () {
      final asOf = DateTime.now().subtract(const Duration(seconds: 3));
      final timer = ClockRunningTimer(id: 'a', remaining: const Duration(seconds: 10), title: '', asOf: asOf);

      final remaining = timer.currentRemaining();
      expect(remaining.inMilliseconds, greaterThanOrEqualTo(const Duration(seconds: 6).inMilliseconds));
      expect(remaining.inMilliseconds, lessThan(const Duration(seconds: 7).inMilliseconds));
    });

    test('clamps to zero rather than going negative once past the fire instant', () {
      final asOf = DateTime.now().subtract(const Duration(seconds: 30));
      final timer = ClockRunningTimer(id: 'a', remaining: const Duration(seconds: 10), title: '', asOf: asOf);

      expect(timer.currentRemaining(), Duration.zero);
    });

    test('no asOf returns the static value as-is', () {
      const timer = ClockRunningTimer(id: 'a', remaining: Duration(seconds: 10), title: '');

      expect(timer.currentRemaining(), const Duration(seconds: 10));
    });
  });
}
