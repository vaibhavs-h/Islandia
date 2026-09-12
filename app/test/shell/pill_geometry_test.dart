import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/shell/island_window_channel.dart';
import 'package:islandia/shell/pill_geometry.dart';

NotchGeometry _screen({
  double screenWidth = 1512,
  double screenHeight = 982,
  double safeAreaTop = 32,
  double menuBarHeight = 24,
  double backingScaleFactor = 2,
}) {
  return NotchGeometry(
    screenWidth: screenWidth,
    screenHeight: screenHeight,
    safeAreaTop: safeAreaTop,
    menuBarHeight: menuBarHeight,
    backingScaleFactor: backingScaleFactor,
  );
}

void main() {
  group('NotchGeometry', () {
    test('hasNotch and topInset follow safeAreaTop', () {
      final notched = _screen(safeAreaTop: 32, menuBarHeight: 24);
      expect(notched.hasNotch, isTrue);
      expect(notched.topInset, 32);

      final notchless = _screen(safeAreaTop: 0, menuBarHeight: 24);
      expect(notchless.hasNotch, isFalse);
      expect(notchless.topInset, 24); // falls back to the menu bar, not 0
    });
  });

  group('gapForScreen', () {
    // The raw 0.2mm-in-points conversion (~0.57pt) is always below the 2.0pt
    // floor for any real display, so the floor is what should show up here —
    // not 0.2mm's literal point value.
    test('is floored to a minimum-perceptible 2.0pt on a Retina (2x) display', () {
      expect(gapForScreen(_screen(backingScaleFactor: 2)), 2.0);
    });

    test('is floored to 2.0pt on a non-Retina (1x) display too', () {
      expect(gapForScreen(_screen(backingScaleFactor: 1)), 2.0);
    });

    test('rounds to a whole device pixel at an odd backing scale', () {
      // floor 2.0pt * 1.4 = 2.8 device px -> rounds to 3 -> back to points: 3/1.4
      expect(gapForScreen(_screen(backingScaleFactor: 1.4)), closeTo(3 / 1.4, 1e-9));
    });
  });

  group('collapsedFrame', () {
    test('centers horizontally and anchors just under the notch', () {
      final screen = _screen(screenWidth: 1512, safeAreaTop: 32, backingScaleFactor: 2);
      const collapsedSize = Size(253, 41);

      final frame = collapsedFrame(screen, collapsedSize);

      expect(frame.width, collapsedSize.width);
      expect(frame.height, collapsedSize.height);
      expect(frame.left, (1512 - 253) / 2);
      expect(frame.top, 32 + gapForScreen(screen));
    });

    test('anchors under the menu bar, not the top edge, when there is no notch', () {
      final screen = _screen(safeAreaTop: 0, menuBarHeight: 24, backingScaleFactor: 2);
      const collapsedSize = Size(253, 41);

      final frame = collapsedFrame(screen, collapsedSize);

      expect(frame.top, 24 + gapForScreen(screen));
    });
  });

  group('expandedFrame', () {
    test('keeps the same top edge and horizontal center as the collapsed frame', () {
      final screen = _screen();
      const collapsedSize = Size(253, 41);
      const expandedSize = Size(360, 190);
      final collapsed = collapsedFrame(screen, collapsedSize);

      final expanded = expandedFrame(collapsed, expandedSize);

      expect(expanded.top, collapsed.top);
      expect(expanded.center.dx, closeTo(collapsed.center.dx, 1e-9));
      expect(expanded.width, expandedSize.width);
      expect(expanded.height, expandedSize.height);
    });
  });
}
