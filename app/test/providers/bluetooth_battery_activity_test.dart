import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/providers/bluetooth_battery_activity.dart';

void main() {
  Future<void> pump(WidgetTester tester, Activity activity) {
    return tester.pumpWidget(
      MaterialApp(
        home: Material(child: Builder(builder: (context) => activity.collapsedBuilder(context, LifecycleState.collapsed))),
      ),
    );
  }

  testWidgets('a connect notification with a battery reading shows the percent', (tester) async {
    final activity = buildBluetoothConnectionActivity(deviceName: 'Magic Mouse', connected: true, batteryPercent: 72);
    await pump(tester, activity);

    expect(find.text('72%'), findsOneWidget);
    expect(find.bySemanticsLabel('Magic Mouse connected, 72 percent.'), findsOneWidget);
  });

  testWidgets('a connect notification with no battery reading (a Classic device) omits it', (tester) async {
    final activity = buildBluetoothConnectionActivity(deviceName: 'WH-CH520', connected: true);
    await pump(tester, activity);

    expect(find.textContaining('%'), findsNothing);
    expect(find.bySemanticsLabel('WH-CH520 connected.'), findsOneWidget);
  });

  testWidgets('a disconnect notification never shows a battery reading, even if one is passed', (tester) async {
    final activity = buildBluetoothConnectionActivity(deviceName: 'Magic Mouse', connected: false, batteryPercent: 72);
    await pump(tester, activity);

    expect(find.textContaining('%'), findsNothing);
    expect(find.bySemanticsLabel('Magic Mouse disconnected.'), findsOneWidget);
  });
}
