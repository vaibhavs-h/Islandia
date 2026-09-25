import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/shell/island_shell.dart';

void main() {
  group('resolveClockTierWinner', () {
    test('stopwatch alone (no timer, Now Playing irrelevant) wins', () {
      expect(
        resolveClockTierWinner(hasStopwatch: true, timerRemaining: null, nowPlayingVisible: true),
        ClockTierWinner.stopwatch,
      );
    });

    test('stopwatch running beats a timer with plenty of time left', () {
      expect(
        resolveClockTierWinner(hasStopwatch: true, timerRemaining: const Duration(minutes: 2), nowPlayingVisible: true),
        ClockTierWinner.stopwatch,
      );
    });

    test('a timer at exactly the 10s preempt boundary beats a running stopwatch', () {
      expect(
        resolveClockTierWinner(hasStopwatch: true, timerRemaining: const Duration(seconds: 10), nowPlayingVisible: false),
        ClockTierWinner.timer,
      );
    });

    test('a timer with 11s left does not yet beat a running stopwatch', () {
      expect(
        resolveClockTierWinner(hasStopwatch: true, timerRemaining: const Duration(seconds: 11), nowPlayingVisible: false),
        ClockTierWinner.stopwatch,
      );
    });

    test('Now Playing is irrelevant whenever the stopwatch is running, even with nothing else contesting', () {
      expect(
        resolveClockTierWinner(hasStopwatch: true, timerRemaining: null, nowPlayingVisible: true),
        ClockTierWinner.stopwatch,
      );
    });

    test('no stopwatch: a timer at exactly the 1-minute boundary beats Now Playing', () {
      expect(
        resolveClockTierWinner(hasStopwatch: false, timerRemaining: const Duration(minutes: 1), nowPlayingVisible: true),
        ClockTierWinner.timer,
      );
    });

    test('no stopwatch: a timer with 61s left does not yet beat Now Playing', () {
      expect(
        resolveClockTierWinner(hasStopwatch: false, timerRemaining: const Duration(seconds: 61), nowPlayingVisible: true),
        ClockTierWinner.nowPlaying,
      );
    });

    test('no stopwatch, no timer within a minute: Now Playing wins if visible', () {
      expect(
        resolveClockTierWinner(hasStopwatch: false, timerRemaining: null, nowPlayingVisible: true),
        ClockTierWinner.nowPlaying,
      );
    });

    test('no stopwatch, idle timer (>1min) and no Now Playing: the timer still wins by default', () {
      expect(
        resolveClockTierWinner(hasStopwatch: false, timerRemaining: const Duration(minutes: 5), nowPlayingVisible: false),
        ClockTierWinner.timer,
      );
    });

    test('nothing running at all: no winner, Dashboard shows through', () {
      expect(
        resolveClockTierWinner(hasStopwatch: false, timerRemaining: null, nowPlayingVisible: false),
        ClockTierWinner.none,
      );
    });

    test('all three at once: stopwatch running, timer far from either window, Now Playing visible — stopwatch wins', () {
      expect(
        resolveClockTierWinner(hasStopwatch: true, timerRemaining: const Duration(minutes: 3), nowPlayingVisible: true),
        ClockTierWinner.stopwatch,
      );
    });

    test('all three at once, timer inside the 10s stopwatch-preempt window — timer wins even over Now Playing', () {
      expect(
        resolveClockTierWinner(hasStopwatch: true, timerRemaining: const Duration(seconds: 3), nowPlayingVisible: true),
        ClockTierWinner.timer,
      );
    });
  });
}
