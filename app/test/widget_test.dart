import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:islandia/main.dart';

const _channel = MethodChannel('islandia/window');
const _batteryChannel = EventChannel('islandia/battery/updates');

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(_batteryChannel, null);
  });

  testWidgets('Island shell boots and shows the collapsed pill (battery, since nothing is playing)', (
    WidgetTester tester,
  ) async {
    _mockChannels();

    await tester.pumpWidget(const IslandiaApp());
    await _pumpPastBootstrap(tester);

    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('the collapsed pill exposes an accessible label and expand hint', (WidgetTester tester) async {
    _mockChannels();
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(const IslandiaApp());
    await _pumpPastBootstrap(tester);

    expect(find.bySemanticsLabel(RegExp('Battery, 100 percent, Charged')), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('Battery, 100 percent, Charged'))),
      // isFocusable/focus: the shell now takes keyboard focus once expanded
      // (space toggles play/pause, media keys work) — see IslandShell's
      // Focus widget.
      matchesSemantics(hint: 'Double tap to expand', hasTapAction: true, isFocusable: true, hasFocusAction: true),
    );

    semantics.dispose();
  });
}

/// Registered inside each test body, not in `setUp()`: `testWidgets` runs its
/// body in a special fake-async zone that `pump()` drains, but `setUp()`
/// callbacks run outside that zone. A mock's response scheduled from
/// `setUp()` can end up on the wrong zone's microtask queue and never get
/// flushed by pumping inside the test body — registering here keeps
/// everything on the same zone the pumps actually control.
void _mockChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    _channel,
    (call) async {
      switch (call.method) {
        case 'notchGeometry':
          return {
            'screenWidth': 1512.0,
            'screenHeight': 982.0,
            'safeAreaTop': 32.0,
            'menuBarHeight': 0.0,
            'backingScaleFactor': 2.0,
          };
        default:
          return null;
      }
    },
  );
  // The now-playing EventChannel is deliberately left unmocked — a
  // MissingPluginException (swallowed by NowPlayingProvider's own
  // handleError) is exactly what "nothing playing anywhere" looks like in
  // production too, so this doubles as that test case for free. Battery
  // becomes the visible default, same as when no music is playing on a
  // real Mac.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
    _batteryChannel,
    MockStreamHandler.inline(
      onListen: (arguments, events) {
        events.success({
          'percentage': 1.0,
          'isCharging': false,
          'isCharged': true,
          'isOnACPower': true,
        });
      },
    ),
  );
}

/// `IslandShell._bootstrap` awaits a mocked MethodChannel round-trip
/// (notchGeometry), then separately listens for battery — both resolve via
/// a few chained microtasks/timers, not a single frame, so `pumpAndSettle()`
/// alone can return before they're done (nothing's marked the tree dirty yet
/// for it to notice). Advancing time explicitly, then settling again,
/// reliably gets past it regardless of exactly how many hops are involved.
Future<void> _pumpPastBootstrap(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}
