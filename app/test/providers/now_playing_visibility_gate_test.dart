import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/providers/now_playing_visibility_gate.dart';

void main() {
  group('NowPlayingVisibilityGate', () {
    test('stays visible indefinitely while playing', () {
      fakeAsync((async) {
        var hideCalls = 0;
        final gate = NowPlayingVisibilityGate(
          hideAfterPaused: const Duration(minutes: 5),
          onHide: () => hideCalls++,
        );

        gate.update(isPlaying: true);
        async.elapse(const Duration(minutes: 30));

        expect(gate.isHidden, isFalse);
        expect(hideCalls, 0);
        gate.dispose();
      });
    });

    test('hides after being paused for the full delay with no change', () {
      fakeAsync((async) {
        var hideCalls = 0;
        final gate = NowPlayingVisibilityGate(
          hideAfterPaused: const Duration(minutes: 5),
          onHide: () => hideCalls++,
        );

        gate.update(isPlaying: false);
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(gate.isHidden, isFalse, reason: 'not yet due');

        async.elapse(const Duration(seconds: 1));
        expect(gate.isHidden, isTrue);
        expect(hideCalls, 1);
        gate.dispose();
      });
    });

    test('a still-paused update does not restart the clock', () {
      fakeAsync((async) {
        final gate = NowPlayingVisibilityGate(
          hideAfterPaused: const Duration(minutes: 5),
          onHide: () {},
        );

        gate.update(isPlaying: false);
        async.elapse(const Duration(minutes: 4));
        // e.g. an audio-route change triggering a redundant refresh while
        // still paused — must not push the 5-minute mark further out.
        gate.update(isPlaying: false);
        async.elapse(const Duration(minutes: 1));

        expect(gate.isHidden, isTrue);
        gate.dispose();
      });
    });

    test('resuming playback before the delay cancels the hide', () {
      fakeAsync((async) {
        final gate = NowPlayingVisibilityGate(
          hideAfterPaused: const Duration(minutes: 5),
          onHide: () {},
        );

        gate.update(isPlaying: false);
        async.elapse(const Duration(minutes: 3));
        gate.update(isPlaying: true);
        async.elapse(const Duration(minutes: 10));

        expect(gate.isHidden, isFalse);
        gate.dispose();
      });
    });

    test('pausing again after a resume starts a fresh clock', () {
      fakeAsync((async) {
        var hideCalls = 0;
        final gate = NowPlayingVisibilityGate(
          hideAfterPaused: const Duration(minutes: 5),
          onHide: () => hideCalls++,
        );

        gate.update(isPlaying: false);
        async.elapse(const Duration(minutes: 3));
        gate.update(isPlaying: true);
        gate.update(isPlaying: false);
        async.elapse(const Duration(minutes: 3));
        expect(gate.isHidden, isFalse, reason: 'only 3 of the fresh 5 minutes have passed');

        async.elapse(const Duration(minutes: 2));
        expect(gate.isHidden, isTrue);
        expect(hideCalls, 1);
        gate.dispose();
      });
    });

    test('reset clears a pending or already-fired hide', () {
      fakeAsync((async) {
        final gate = NowPlayingVisibilityGate(
          hideAfterPaused: const Duration(minutes: 5),
          onHide: () {},
        );

        gate.update(isPlaying: false);
        async.elapse(const Duration(minutes: 5));
        expect(gate.isHidden, isTrue);

        gate.reset();
        expect(gate.isHidden, isFalse);

        // A fresh pause after reset gets its own full delay again.
        gate.update(isPlaying: false);
        async.elapse(const Duration(minutes: 4));
        expect(gate.isHidden, isFalse);
        gate.dispose();
      });
    });
  });
}
