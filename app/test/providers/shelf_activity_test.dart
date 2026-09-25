import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/providers/shelf_activity.dart';
import 'package:islandia/providers/shelf_provider.dart';

void main() {
  Future<void> pumpCollapsed(WidgetTester tester, Activity activity) {
    return tester.pumpWidget(
      MaterialApp(
        home: Material(child: Builder(builder: (context) => activity.collapsedBuilder(context, LifecycleState.collapsed))),
      ),
    );
  }

  Future<void> pumpExpanded(WidgetTester tester, Activity activity) {
    return tester.pumpWidget(
      MaterialApp(
        home: Material(child: Builder(builder: (context) => activity.expandedBuilder(context, LifecycleState.expanded))),
      ),
    );
  }

  testWidgets('is shelf tier, fixed id — a new drop replaces in place rather than arriving as a second entry', (tester) async {
    const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
    final activity = buildShelfActivity(snapshot, onExitAnimationComplete: () {});

    expect(activity.priority, ActivityPriority.shelf);
    expect(activity.id, 'shelf');
    expect(activity.isTransient, isFalse);
    expect(activity.autoDismissAfter, isNull);
  });

  testWidgets('collapsed view shows the file-type icon and the display name', (tester) async {
    const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
    await pumpCollapsed(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
  });

  testWidgets('collapsed view uses the folder icon for a held folder', (tester) async {
    const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.folder, displayName: 'Screenshots');
    await pumpCollapsed(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

    expect(find.text('Screenshots'), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
  });

  testWidgets('collapsed view uses the text-snippet icon for held text, with the text itself as the display name', (tester) async {
    const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.text, displayName: 'a copied sentence');
    await pumpCollapsed(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

    expect(find.text('a copied sentence'), findsOneWidget);
    expect(find.byIcon(Icons.text_snippet), findsOneWidget);
  });

  testWidgets('collapsed view shows a Finder-icon thumbnail instead of the generic glyph when one is available', (tester) async {
    final thumbnail = Uint8List.fromList(_onePixelPng);
    final snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'photo.png', thumbnailPng: thumbnail);
    await pumpCollapsed(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.insert_drive_file), findsNothing);
  });

  testWidgets('expanded view shows type and size together, per the confirmed "type, size, etc." detail spec', (tester) async {
    const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf', sizeBytes: 2 * 1024 * 1024);
    await pumpExpanded(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('File · 2.0 MB'), findsOneWidget);
  });

  testWidgets('expanded view omits the size segment entirely for held text, which has no on-disk size', (tester) async {
    const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.text, displayName: 'a copied sentence');
    await pumpExpanded(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

    expect(find.text('Text'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  testWidgets('a copying snapshot shows the in-progress state, not the held-item preview', (tester) async {
    const snapshot = ShelfSnapshot.copying('bigfile.zip');
    await pumpCollapsed(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

    expect(find.textContaining('Copying bigfile.zip'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a pendingDelete snapshot shows the bin icon and delete text instead of the held-item preview', (tester) async {
    const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf', pendingDelete: true);
    await pumpCollapsed(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

    expect(find.byIcon(Icons.delete), findsOneWidget);
    expect(find.text('Release to delete'), findsOneWidget);
    expect(find.text('report.pdf'), findsNothing);
  });

  testWidgets('pendingDelete also replaces the expanded view content, not just the collapsed pill', (tester) async {
    const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.folder, displayName: 'Screenshots', pendingDelete: true);
    await pumpExpanded(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

    expect(find.byIcon(Icons.delete), findsOneWidget);
    expect(find.text('Screenshots'), findsNothing);
  });

  // Matrix4.getMaxScaleOnAxis() is unreliable at exactly 0.0 scale — it
  // reports 1.0 for a genuinely zero-scaled matrix (confirmed directly:
  // Transform.scale(scale: 0.0).transform.getMaxScaleOnAxis() == 1.0, even
  // though the matrix's own raw storage is provably all-zero on that
  // axis), which is a real quirk of that method for a degenerate matrix,
  // not anything wrong with the widget under test. Reading storage[0]
  // directly (the X-axis scale term) sidesteps that entirely and reflects
  // the actual value CurvedAnimation/Transform.scale were built with.
  double xScale(WidgetTester tester) {
    final transform = tester.widget<Transform>(find.byKey(const ValueKey('shelf-arrival-scale')));
    return transform.transform.storage[0];
  }

  group('animations', () {
    testWidgets('a fresh arrival starts the scale-and-settle entrance at less than full scale', (tester) async {
      const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      await pumpCollapsed(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

      // Not yet pumped forward in time — the very first frame, right as
      // the AnimationController starts from 0.
      expect(xScale(tester), lessThan(1.0));
    });

    testWidgets('the arrival entrance settles to full scale once its duration elapses', (tester) async {
      const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      await pumpCollapsed(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));

      await tester.pump(const Duration(milliseconds: 500));

      expect(xScale(tester), closeTo(1.0, 0.01));
    });

    testWidgets('re-registering the exact same held item does not replay the arrival entrance', (tester) async {
      const snapshot = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      await pumpCollapsed(tester, buildShelfActivity(snapshot, onExitAnimationComplete: () {}));
      await tester.pump(const Duration(milliseconds: 500));

      // An idempotent re-register of the identical item (e.g. a
      // pendingDelete-unrelated refresh) — same kind/name/size, so
      // _ItemIdentity treats this as the same arrival, not a new one.
      const sameSnapshot = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      await pumpCollapsed(tester, buildShelfActivity(sameSnapshot, onExitAnimationComplete: () {}));

      expect(xScale(tester), closeTo(1.0, 0.01), reason: 'should still read as fully settled, not restarted');
    });

    testWidgets('a genuinely different held item replacing the current one replays the arrival entrance', (tester) async {
      const first = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      await pumpCollapsed(tester, buildShelfActivity(first, onExitAnimationComplete: () {}));
      await tester.pump(const Duration(milliseconds: 500));

      const second = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'other.pdf');
      await pumpCollapsed(tester, buildShelfActivity(second, onExitAnimationComplete: () {}));

      expect(xScale(tester), lessThan(1.0), reason: 'a different item arriving should restart the entrance from 0');
    });

    testWidgets('a successful drag-out plays the exit animation and calls onExitAnimationComplete once it finishes', (tester) async {
      const held = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      var completed = false;
      await pumpCollapsed(tester, buildShelfActivity(held, onExitAnimationComplete: () => completed = true));
      await tester.pump(const Duration(milliseconds: 500));

      const empty = ShelfSnapshot.empty(reason: ShelfEmptyReason.draggedOut);
      await pumpCollapsed(tester, buildShelfActivity(empty, onExitAnimationComplete: () => completed = true));

      expect(completed, isFalse, reason: 'should not fire on the very first frame of the exit');
      await tester.pump(const Duration(milliseconds: 600));
      expect(completed, isTrue);
    });

    testWidgets('a successful drag-out shows the confirming checkmark partway through the exit', (tester) async {
      const held = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      await pumpCollapsed(tester, buildShelfActivity(held, onExitAnimationComplete: () {}));
      await tester.pump(const Duration(milliseconds: 500));

      const empty = ShelfSnapshot.empty(reason: ShelfEmptyReason.draggedOut);
      await pumpCollapsed(tester, buildShelfActivity(empty, onExitAnimationComplete: () {}));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('a delete shows no checkmark, unlike a successful drag-out', (tester) async {
      const held = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      var completed = false;
      await pumpCollapsed(tester, buildShelfActivity(held, onExitAnimationComplete: () => completed = true));
      await tester.pump(const Duration(milliseconds: 500));

      const empty = ShelfSnapshot.empty(reason: ShelfEmptyReason.deleted);
      await pumpCollapsed(tester, buildShelfActivity(empty, onExitAnimationComplete: () => completed = true));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.check), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));
      expect(completed, isTrue, reason: 'the delete exit is shorter than the drag-out one, should already be done by 400ms total');
    });

    testWidgets('the collapsed pill dims and shrinks slightly while a drag-out is in flight', (tester) async {
      const notDragging = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      await pumpCollapsed(tester, buildShelfActivity(notDragging, onExitAnimationComplete: () {}));
      await tester.pump(const Duration(milliseconds: 500));

      const dragging = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf', isDragging: true);
      await pumpCollapsed(tester, buildShelfActivity(dragging, onExitAnimationComplete: () {}));
      await tester.pump(const Duration(milliseconds: 400));

      final opacityWidget = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacityWidget.opacity, lessThan(1.0));
      final scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, lessThan(1.0));
    });

    testWidgets('a drag-out ending (isDragging back to false) restores full opacity and scale', (tester) async {
      const dragging = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf', isDragging: true);
      await pumpCollapsed(tester, buildShelfActivity(dragging, onExitAnimationComplete: () {}));
      await tester.pump(const Duration(milliseconds: 500));

      const notDragging = ShelfSnapshot.holding(kind: ShelfItemKind.file, displayName: 'report.pdf');
      await pumpCollapsed(tester, buildShelfActivity(notDragging, onExitAnimationComplete: () {}));
      await tester.pump(const Duration(milliseconds: 400));

      final opacityWidget = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacityWidget.opacity, 1.0);
      final scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 1.0);
    });
  });
}

/// The smallest possible valid PNG (1x1, transparent) — enough for
/// Image.memory to accept without throwing, which is all these tests need.
const List<int> _onePixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
];
