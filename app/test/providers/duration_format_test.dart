import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/providers/duration_format.dart';

void main() {
  group('formatDuration', () {
    test('formats under an hour as MM:SS', () {
      expect(formatDuration(const Duration(minutes: 22, seconds: 59)), '22:59');
      expect(formatDuration(const Duration(minutes: 5, seconds: 3)), '05:03');
      expect(formatDuration(Duration.zero), '00:00');
    });

    test('does not silently drop the hour once past 59 minutes', () {
      // The exact regression reported: a 72-minute podcast/video used to
      // render as "12:39" (minutes naively wrapped via remainder(60) with
      // no hour segment at all), not "1:12:39".
      expect(formatDuration(const Duration(minutes: 72, seconds: 39)), '1:12:39');
    });

    test('formats multi-hour durations correctly', () {
      expect(formatDuration(const Duration(hours: 2, minutes: 5, seconds: 9)), '2:05:09');
    });
  });

  group('formatStopwatchDuration', () {
    test('formats under an hour as MM:SS.cc (centiseconds, matching macOS Clock)', () {
      expect(formatStopwatchDuration(const Duration(minutes: 1, seconds: 5, milliseconds: 430)), '01:05.43');
      expect(formatStopwatchDuration(Duration.zero), '00:00.00');
    });

    test('truncates rather than rounds the centiseconds, same as a real stopwatch', () {
      // 999ms is 99.9 centiseconds — a real stopwatch reads this as .99 at
      // that instant, not .00 from a naive round-up to the next second.
      expect(formatStopwatchDuration(const Duration(seconds: 1, milliseconds: 999)), '00:01.99');
    });

    test('expands to show an hour column once elapsed crosses an hour', () {
      expect(
        formatStopwatchDuration(const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 40)),
        '1:02:03.04',
      );
    });

    test('multi-hour durations keep the hour column and centiseconds together', () {
      expect(
        formatStopwatchDuration(const Duration(hours: 2, minutes: 5, seconds: 9, milliseconds: 500)),
        '2:05:09.50',
      );
    });
  });

  group('formatTimerDuration', () {
    test('always shows the hour column, zero-padded, even at zero hours', () {
      // Unlike formatDuration, which drops the hour segment entirely under
      // an hour — a Timer's hour column is always shown, and always two
      // digits (explicitly requested: "00:MM:SS", not a bare "0:MM:SS").
      expect(formatTimerDuration(const Duration(minutes: 5, seconds: 3)), '00:05:03');
      expect(formatTimerDuration(Duration.zero), '00:00:00');
    });

    test('shows the real hour digit once past an hour, still zero-padded', () {
      expect(formatTimerDuration(const Duration(hours: 1, minutes: 30)), '01:30:00');
    });

    test('handles the max Clock timer duration (23:59:59) without a third hour digit', () {
      expect(formatTimerDuration(const Duration(hours: 23, minutes: 59, seconds: 59)), '23:59:59');
    });
  });
}
