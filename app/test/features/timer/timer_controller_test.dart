import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/features/timer/timer_controller.dart';

void main() {
  group('TimerController', () {
    test('counts down one second at a time and formats mm:ss', () {
      fakeAsync((async) {
        final controller = TimerController(const Duration(minutes: 1, seconds: 5));

        expect(controller.formatted, '01:05');

        async.elapse(const Duration(seconds: 5));
        expect(controller.formatted, '01:00');
        expect(controller.isComplete, isFalse);

        controller.dispose();
      });
    });

    test('reaches zero and marks itself complete without going negative', () {
      fakeAsync((async) {
        final controller = TimerController(const Duration(seconds: 3));

        async.elapse(const Duration(seconds: 3));
        expect(controller.remaining, Duration.zero);
        expect(controller.isComplete, isTrue);

        // The internal ticker cancels itself on completion — elapsing
        // further must not push it negative or notify again unexpectedly.
        async.elapse(const Duration(seconds: 5));
        expect(controller.remaining, Duration.zero);

        controller.dispose();
      });
    });

    test('notifies listeners on every tick', () {
      fakeAsync((async) {
        final controller = TimerController(const Duration(seconds: 3));
        var notifications = 0;
        controller.addListener(() => notifications++);

        async.elapse(const Duration(seconds: 3));

        expect(notifications, 3);
        controller.dispose();
      });
    });
  });
}
