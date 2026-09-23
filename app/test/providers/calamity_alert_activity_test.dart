import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/providers/calamity_alert_activity.dart';
import 'package:islandia/providers/calamity_alert_provider.dart';

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

  testWidgets('is P2 important, transient, and auto-dismisses after 5s', (tester) async {
    const alert = CalamityAlert(id: 'usgs-abc123', kind: 'earthquake', headline: 'M5.2 earthquake', place: 'Near Tokyo, Japan', source: 'usgs');
    final activity = buildCalamityAlertActivity(alert);

    expect(activity.priority, ActivityPriority.p2Important);
    expect(activity.isTransient, isTrue);
    expect(activity.autoDismissAfter, const Duration(seconds: 5));
  });

  testWidgets('id is namespaced from the alert id, so two different alerts never collide', (tester) async {
    const first = CalamityAlert(id: 'usgs-abc123', kind: 'earthquake', headline: 'M5.2 earthquake', place: 'Near Tokyo, Japan', source: 'usgs');
    const second = CalamityAlert(id: 'gdacs-987', kind: 'flood', headline: 'Warning: flood', place: 'India', source: 'gdacs');

    expect(buildCalamityAlertActivity(first).id, isNot(buildCalamityAlertActivity(second).id));
  });

  testWidgets('collapsed view shows the headline and place, left-aligned', (tester) async {
    const alert = CalamityAlert(id: 'usgs-abc123', kind: 'earthquake', headline: 'M5.2 earthquake', place: 'Near Tokyo, Japan', source: 'usgs');
    final activity = buildCalamityAlertActivity(alert);
    await pumpCollapsed(tester, activity);

    expect(find.text('M5.2 earthquake, Near Tokyo, Japan'), findsOneWidget);
    expect(find.byIcon(Icons.vibration), findsOneWidget);
  });

  testWidgets('a tsunami-risk earthquake uses the tsunami icon, not the plain earthquake one', (tester) async {
    const alert = CalamityAlert(id: 'usgs-def456', kind: 'tsunami', headline: 'Tsunami risk: M6.5 earthquake', place: 'Alaska', source: 'usgs');
    final activity = buildCalamityAlertActivity(alert);
    await pumpCollapsed(tester, activity);

    expect(find.byIcon(Icons.tsunami), findsOneWidget);
    expect(find.byIcon(Icons.vibration), findsNothing);
  });

  testWidgets('expanded view centers the alert text', (tester) async {
    const alert = CalamityAlert(id: 'gdacs-111', kind: 'wildfire', headline: 'Severe wildfire', place: 'Greece', source: 'gdacs');
    final activity = buildCalamityAlertActivity(alert);
    await pumpExpanded(tester, activity);

    expect(find.text('Severe wildfire, Greece'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(find.byType(Center), findsWidgets);
  });

  testWidgets('an alert with no place still renders, just the headline alone', (tester) async {
    const alert = CalamityAlert(id: 'usgs-noplace', kind: 'earthquake', headline: 'M4.8 earthquake', place: '', source: 'usgs');
    final activity = buildCalamityAlertActivity(alert);
    await pumpCollapsed(tester, activity);

    expect(find.text('M4.8 earthquake'), findsOneWidget);
  });

  testWidgets('a GDACS-sourced alert notes the source distinction in its semantics label', (tester) async {
    const alert = CalamityAlert(id: 'gdacs-222', kind: 'flood', headline: 'Warning: flood', place: 'Nepal', source: 'gdacs');
    final activity = buildCalamityAlertActivity(alert);
    await pumpCollapsed(tester, activity);

    expect(find.bySemanticsLabel('Warning: flood, Nepal. Source: GDACS disaster monitoring.'), findsOneWidget);
  });

  testWidgets('a USGS-sourced alert has a plain semantics label with no source caveat', (tester) async {
    const alert = CalamityAlert(id: 'usgs-333', kind: 'earthquake', headline: 'M5.0 earthquake', place: 'Chile', source: 'usgs');
    final activity = buildCalamityAlertActivity(alert);
    await pumpCollapsed(tester, activity);

    expect(find.bySemanticsLabel('M5.0 earthquake, Chile.'), findsOneWidget);
  });
}
