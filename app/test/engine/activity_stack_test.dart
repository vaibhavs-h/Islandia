import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/engine/activity_stack.dart';

Activity _activity(String id, ActivityPriority priority, {Duration? autoDismissAfter}) {
  return Activity(
    id: id,
    priority: priority,
    autoDismissAfter: autoDismissAfter,
    collapsedBuilder: (context, state) => const SizedBox.shrink(),
    expandedBuilder: (context, state) => const SizedBox.shrink(),
  );
}

void main() {
  group('ActivityStack', () {
    test('top is null when nothing is registered', () {
      expect(ActivityStack().top, isNull);
    });

    test('a higher-priority activity preempts — takes the top slot without removing the other', () {
      final stack = ActivityStack()
        ..register(_activity('now-playing', ActivityPriority.p3Ambient))
        ..register(_activity('call', ActivityPriority.p1Immediate));

      expect(stack.top!.id, 'call');
      expect(stack.entries.map((e) => e.id), ['call', 'now-playing']);
    });

    test('a lower-priority activity does not preempt the current top', () {
      final stack = ActivityStack()
        ..register(_activity('call', ActivityPriority.p1Immediate))
        ..register(_activity('now-playing', ActivityPriority.p3Ambient));

      expect(stack.top!.id, 'call');
    });

    test('equal priority: most-recently-registered wins the top slot', () {
      final stack = ActivityStack()
        ..register(_activity('weather', ActivityPriority.p3Ambient))
        ..register(_activity('now-playing', ActivityPriority.p3Ambient));

      expect(stack.top!.id, 'now-playing');
      expect(stack.entries.map((e) => e.id), ['now-playing', 'weather']);
    });

    test('removing the top restores whatever is now highest-priority — never recreated, just re-shown', () {
      final stack = ActivityStack()
        ..register(_activity('now-playing', ActivityPriority.p3Ambient))
        ..register(_activity('call', ActivityPriority.p1Immediate));

      stack.remove('call');

      expect(stack.top!.id, 'now-playing');
    });

    test('removing an id that is not present is a no-op and does not notify listeners', () {
      final stack = ActivityStack()..register(_activity('now-playing', ActivityPriority.p3Ambient));
      var notified = false;
      stack.addListener(() => notified = true);

      stack.remove('does-not-exist');

      expect(notified, isFalse);
      expect(stack.top!.id, 'now-playing');
    });

    test('re-registering an existing id updates it in place instead of jumping the queue', () {
      final stack = ActivityStack()
        ..register(_activity('battery', ActivityPriority.p3Ambient))
        ..register(_activity('now-playing', ActivityPriority.p3Ambient));

      // A provider pushing a fresh value for something already on the stack
      // (a battery percentage ticking down) must not steal the top slot back
      // from whatever legitimately holds it via recency.
      stack.register(_activity('battery', ActivityPriority.p3Ambient));

      expect(stack.entries.map((e) => e.id), ['now-playing', 'battery']);
      expect(stack.entries.length, 2);
    });

    test('register and remove notify listeners', () {
      final stack = ActivityStack();
      var notifications = 0;
      stack.addListener(() => notifications++);

      stack.register(_activity('now-playing', ActivityPriority.p3Ambient));
      stack.remove('now-playing');

      expect(notifications, 2);
    });

    test('an activity with autoDismissAfter ages out on its own, no action needed', () {
      fakeAsync((async) {
        final stack = ActivityStack()
          ..register(_activity('timer-complete', ActivityPriority.p2Important, autoDismissAfter: const Duration(seconds: 5)));

        expect(stack.top!.id, 'timer-complete');

        async.elapse(const Duration(seconds: 4));
        expect(stack.top!.id, 'timer-complete', reason: 'not yet due');

        async.elapse(const Duration(seconds: 2));
        expect(stack.top, isNull, reason: 'aged out on its own after 5s total, no remove() call');
      });
    });

    test('re-registering the same id restarts its auto-dismiss clock instead of stacking a second timer', () {
      fakeAsync((async) {
        final stack = ActivityStack();
        stack.register(_activity('timer-complete', ActivityPriority.p2Important, autoDismissAfter: const Duration(seconds: 5)));

        async.elapse(const Duration(seconds: 4));
        // A fresh push (e.g. an updated value) resets the countdown rather
        // than letting the original timer fire out from under the new value.
        stack.register(_activity('timer-complete', ActivityPriority.p2Important, autoDismissAfter: const Duration(seconds: 5)));

        async.elapse(const Duration(seconds: 4));
        expect(stack.top!.id, 'timer-complete', reason: 'clock restarted, so only 4s has elapsed since the refresh');

        async.elapse(const Duration(seconds: 1));
        expect(stack.top, isNull);
      });
    });

    test('removing an activity before it ages out cancels the pending timer', () {
      fakeAsync((async) {
        final stack = ActivityStack()
          ..register(_activity('timer-complete', ActivityPriority.p2Important, autoDismissAfter: const Duration(seconds: 5)));

        stack.remove('timer-complete');
        var notifications = 0;
        stack.addListener(() => notifications++);

        async.elapse(const Duration(seconds: 5));

        expect(notifications, 0, reason: 'the cancelled timer must not fire a stray remove() later');
      });
    });
  });
}
