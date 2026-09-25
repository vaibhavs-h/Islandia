import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/engine/activity_stack.dart';
import 'package:islandia/providers/now_playing_activity.dart';
import 'package:islandia/providers/now_playing_provider.dart';
import 'package:islandia/shell/privacy_indicator.dart';

Activity _activity() {
  return Activity(
    id: 'test-activity',
    priority: ActivityPriority.alert,
    collapsedBuilder: (context, state) => const SizedBox.shrink(),
    expandedBuilder: (context, state) => const SizedBox.shrink(),
  );
}

void main() {
  // AnimationController.forward()/reverse() reach into SemanticsBinding for
  // an adaptive-animations check — needs a real test binding even though
  // nothing here pumps a widget tree.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrivacyIndicatorController', () {
    test('a source active for less than the prominent window skips the banner for the dot instead', () {
      fakeAsync((async) {
        final stack = ActivityStack();
        final controller = PrivacyIndicatorController(
          activityId: 'test-activity',
          buildActivity: _activity,
          stack: stack,
          vsync: const TestVSync(),
          prominentDuration: const Duration(seconds: 5),
          briefDotDuration: const Duration(seconds: 2),
        );

        // A screenshot's underlying signal can go true->false only a few
        // milliseconds apart — faster than a real frame callback, and far
        // too brief to read as text even if it somehow did render. This
        // should swap straight to the dot rather than showing the banner.
        controller.handle(true);
        async.elapse(const Duration(milliseconds: 5));
        controller.handle(false);

        expect(stack.top, isNull, reason: 'banner skipped, not held — too brief to read as text');
        expect(controller.dotTransition.status, AnimationStatus.forward, reason: 'dot fading in');

        // Short of the 2s mark — must still be the same forward() from
        // above, not yet reversed.
        async.elapse(const Duration(milliseconds: 1995));
        expect(controller.dotTransition.status, AnimationStatus.forward, reason: 'still within the 2s hold');

        // Past the 2s mark — reverse() should have been called. Nothing
        // under plain fakeAsync (no real frame pumping) ever actually ticks
        // the controller's value away from where forward() left it without
        // pumping, so reverse() here has nothing to animate *from* and
        // resolves straight to dismissed — still a reliable signal that it
        // was actually called, since status never changes on its own.
        async.elapse(const Duration(milliseconds: 10));
        expect(controller.dotTransition.status, AnimationStatus.dismissed, reason: '2s hold elapsed, reverse() called');

        controller.dispose();
      });
    });

    test('a flicker back on while the brief dot is showing brings the banner back', () {
      fakeAsync((async) {
        final stack = ActivityStack();
        var registrations = 0;
        final controller = PrivacyIndicatorController(
          activityId: 'test-activity',
          buildActivity: () {
            registrations++;
            return _activity();
          },
          stack: stack,
          vsync: const TestVSync(),
          prominentDuration: const Duration(seconds: 5),
          briefDotDuration: const Duration(seconds: 2),
        );

        controller.handle(true);
        async.elapse(const Duration(milliseconds: 5));
        controller.handle(false); // swaps to the brief dot
        async.elapse(const Duration(milliseconds: 50));
        controller.handle(true); // a second, genuinely new activation

        expect(stack.top?.id, 'test-activity', reason: 'a fresh activation re-shows the banner');
        expect(registrations, 2);

        controller.dispose();
      });
    });

    test('a sustained activation still recedes to a dot after the prominent window', () {
      fakeAsync((async) {
        final stack = ActivityStack();
        final controller = PrivacyIndicatorController(
          activityId: 'test-activity',
          buildActivity: _activity,
          stack: stack,
          vsync: const TestVSync(),
          prominentDuration: const Duration(seconds: 5),
        );

        controller.handle(true);
        async.elapse(const Duration(seconds: 5));

        expect(stack.top, isNull, reason: 'prominent window elapsed, receded to the dot');
        expect(controller.dotTransition.status, AnimationStatus.forward);

        controller.dispose();
      });
    });

    test('deactivating after receding to the dot still reverses the dot transition', () {
      fakeAsync((async) {
        final stack = ActivityStack();
        final controller = PrivacyIndicatorController(
          activityId: 'test-activity',
          buildActivity: _activity,
          stack: stack,
          vsync: const TestVSync(),
          prominentDuration: const Duration(seconds: 5),
        );

        controller.handle(true);
        async.elapse(const Duration(seconds: 5));
        controller.dotTransition.value = 1;
        controller.handle(false);
        async.elapse(const Duration(milliseconds: 200));

        expect(controller.dotTransition.status, AnimationStatus.reverse);

        controller.dispose();
      });
    });
  });

  group('PrivacyIndicatorDot', () {
    // Live verification of this one kept getting confounded by unrelated
    // WindowServer signal flakiness from this same session's earlier rapid
    // testing (see ROADMAP_PROGRESS.md) rather than anything about the dot
    // itself — this measures the actual rendered geometry directly instead,
    // which is more precise than a screenshot could be anyway.
    testWidgets('compact mode shifts the dot up and shrinks it, relative to normal', (tester) async {
      final dotKey = UniqueKey();

      Future<Rect> pump(double compactT) async {
        final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 900))
          ..value = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: Center(
                child: SizedBox(
                  width: 200,
                  height: 36,
                  child: Stack(
                    children: [
                      PrivacyIndicatorDot(
                        key: dotKey,
                        transition: controller,
                        color: const Color(0xFFFF9F0A),
                        label: 'Test dot',
                        rightOffset: 12,
                        compactT: compactT,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        // find.byKey(dotKey) itself resolves to the Positioned's own box,
        // which is stretched to the full pill height (top: 0, bottom: 0)
        // regardless of compactT — the actual circle is the Container
        // inside it, which is what needs measuring here.
        final rect = tester.getRect(find.descendant(of: find.byKey(dotKey), matching: find.byType(Container)));
        controller.dispose();
        return rect;
      }

      final normalRect = await pump(0);
      final compactRect = await pump(1);

      expect(compactRect.height, lessThan(normalRect.height), reason: 'compact mode shrinks the dot');
      expect(compactRect.width, lessThan(normalRect.width), reason: 'compact mode shrinks the dot');
      expect(
        compactRect.center.dy,
        lessThan(normalRect.center.dy),
        reason: 'compact mode shifts the dot toward the top edge',
      );
      // Both use the same rightOffset — compact mode is a vertical shift and
      // a resize only, never a horizontal one (a sub-pixel difference here
      // is just rounding from the circle's own width shrinking while still
      // centered, not an actual horizontal shift).
      expect(compactRect.center.dx, closeTo(normalRect.center.dx, 1));
    });

    testWidgets('compactT defaults to normal (uncompacted) when not specified', (tester) async {
      final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 900))
        ..value = 1;
      final dotKey = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: SizedBox(
                width: 200,
                height: 36,
                child: Stack(
                  children: [
                    PrivacyIndicatorDot(
                      key: dotKey,
                      transition: controller,
                      color: const Color(0xFFFF9F0A),
                      label: 'Test dot',
                      rightOffset: 12,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.descendant(of: find.byKey(dotKey), matching: find.byType(Container)));
      final pillCenter = tester.getRect(find.byType(Stack).first).center.dy;
      expect(rect.center.dy, closeTo(pillCenter, 1), reason: 'centered, same as passing compactT: 0 explicitly');

      controller.dispose();
    });

    testWidgets('at full compact, the top and right insets land on their own independent targets', (tester) async {
      // Deliberately different numbers, and deliberately not derived from
      // rightOffset at all — an earlier version forced topInset to equal
      // rightOffset for a "true symmetric corner margin," until measuring
      // against the pill's actual rounded corner (ClipRRect) proved that
      // impossible to satisfy at the same time as clearing real content
      // (see this test file's Now Playing overlap test, and
      // ROADMAP_PROGRESS.md, for the two conflicting measurements that
      // killed the symmetric version). compactRightOffset and
      // compactTopInset are independent for exactly that reason now.
      const homeRightOffset = 12.0;
      const compactRightOffset = 9.0;
      const compactTopInset = 4.0;
      final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 900))
        ..value = 1;
      final dotKey = UniqueKey();
      final stackKey = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: SizedBox(
                width: 200,
                height: 41,
                child: Stack(
                  key: stackKey,
                  children: [
                    PrivacyIndicatorDot(
                      key: dotKey,
                      transition: controller,
                      color: const Color(0xFFFF9F0A),
                      label: 'Test dot',
                      rightOffset: homeRightOffset,
                      compactRightOffset: compactRightOffset,
                      compactTopInset: compactTopInset,
                      compactT: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final pillRect = tester.getRect(find.byKey(stackKey));
      final dotRect = tester.getRect(find.descendant(of: find.byKey(dotKey), matching: find.byType(Container)));
      final topInset = dotRect.top - pillRect.top;
      final rightInset = pillRect.right - dotRect.right;

      expect(rightInset, closeTo(compactRightOffset, 1), reason: 'uses compactRightOffset, not the home rightOffset');
      expect(topInset, closeTo(compactTopInset, 1), reason: 'lands on its own explicit target, independent of rightInset');

      controller.dispose();
    });

    testWidgets('at full compact, the corner dot does not overlap Now Playing\'s own play/pause icon', (
      tester,
    ) async {
      // The actual scenario that prompted compact mode in the first place:
      // real content underneath, not a bare SizedBox — this is what kept
      // getting reported as "still merging with the content" through a few
      // rounds of guessing at the margin by eye instead of checking against
      // the actual layout it needs to clear.
      final nowPlaying = buildNowPlayingActivity(
        // isPlaying: false is what shows the play_arrow glyph being checked
        // below — matches the actual screenshot this test is chasing,
        // which showed a paused track (the glyph is reversed: a play arrow
        // while paused, since it shows what tapping it would do).
        NowPlayingSnapshot(
          bundleIdentifier: 'com.spotify.client',
          title: 'Test Track',
          isPlaying: false,
          timestamp: DateTime.now(),
        ),
        onControlPressed: () {},
      );
      final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 900))
        ..value = 1;
      final dotKey = UniqueKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              // The shell's own real collapsed size (island_shell.dart's
              // _collapsedSize) — not a guessed round number. Getting this
              // wrong is exactly what made an earlier hand-calculation
              // here (assuming 36 instead of the real 41) worthless.
              child: SizedBox(
                width: 253,
                height: 41,
                child: Stack(
                  children: [
                    Positioned.fill(child: Builder(builder: (context) => nowPlaying.collapsedBuilder(context, LifecycleState.collapsed))),
                    PrivacyIndicatorDot(
                      key: dotKey,
                      transition: controller,
                      color: const Color(0xFFFF9F0A),
                      label: 'Test dot',
                      // island_shell's current values for the closest dot.
                      rightOffset: 12,
                      compactRightOffset: 13,
                      compactTopInset: 4,
                      compactT: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final dotRect = tester.getRect(find.descendant(of: find.byKey(dotKey), matching: find.byType(Container)));
      final iconRect = tester.getRect(find.byIcon(Icons.play_arrow));

      // Not just "doesn't technically overlap" — a mere rect-overlap check
      // passed at an earlier, tighter margin (6) that still looked merged,
      // because the two rects only missed each other by a sliver in one
      // axis. Inflating the dot's rect by a real margin before checking
      // catches that: if it still doesn't overlap after growing by 1px in
      // every direction, there's genuine breathing room, not a fluke.
      final dotWithBreathingRoom = dotRect.inflate(1);
      expect(
        dotWithBreathingRoom.overlaps(iconRect),
        isFalse,
        reason: 'dot: $dotRect, play icon: $iconRect — need real clearance, not just a technical non-overlap',
      );

      controller.dispose();
    });

    testWidgets('at full compact, the closest dot stays fully clear of the pill\'s own rounded corner', (
      tester,
    ) async {
      // The actual bug report this chases: with the corner-margin/inset
      // dropped low enough to clear real content (see the Now Playing test
      // above), the dot itself ended up mostly clipped away by the pill's
      // own ClipRRect — a plain rect-overlap check against content doesn't
      // catch this at all, since the corner is a property of the pill's
      // shape, not of anything else on screen.
      const pillWidth = 253.0;
      const pillHeight = 41.0; // island_shell's real collapsed size
      // Mirrors island_shell's own radius formula exactly:
      // math.min(24.0, math.min(constraints.maxWidth, constraints.maxHeight) / 2)
      final radius = math.min(24.0, math.min(pillWidth, pillHeight) / 2);
      final pillRRect = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, pillWidth, pillHeight),
        Radius.circular(radius),
      );

      final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 900))
        ..value = 1;
      final dotKey = UniqueKey();
      final stackKey = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: SizedBox(
                width: pillWidth,
                height: pillHeight,
                child: Stack(
                  key: stackKey,
                  children: [
                    PrivacyIndicatorDot(
                      key: dotKey,
                      transition: controller,
                      color: const Color(0xFFFF9F0A),
                      label: 'Test dot',
                      rightOffset: 12,
                      compactT: 1,
                      // island_shell's current values for the closest dot.
                      compactRightOffset: 13,
                      compactTopInset: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final stackRect = tester.getRect(find.byKey(stackKey));
      final dotRect = tester.getRect(find.descendant(of: find.byKey(dotKey), matching: find.byType(Container)));
      final localDotRect = dotRect.shift(-stackRect.topLeft);

      for (final corner in [
        localDotRect.topLeft,
        localDotRect.topRight,
        localDotRect.bottomLeft,
        localDotRect.bottomRight,
      ]) {
        expect(pillRRect.contains(corner), isTrue, reason: 'corner $corner of $localDotRect falls outside the rounded pill');
      }

      controller.dispose();
    });
  });
}
