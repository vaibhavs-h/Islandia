import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/engine/activity.dart';
import 'package:islandia/providers/audio_route_provider.dart';
import 'package:islandia/providers/now_playing_activity.dart';
import 'package:islandia/providers/now_playing_provider.dart';

void main() {
  testWidgets(
    'expanded view does not overflow with a title, an artist, and a non-built-in audio route all shown',
    (tester) async {
      // The exact combination that overflowed: a browser tab with both a
      // real title/artist and audio routed to a Bluetooth device — three
      // stacked text lines plus artwork, progress, elapsed time, and
      // controls, all inside the one fixed 360x140 expanded box every
      // activity shares (see IslandShell._expandedSize).
      final snapshot = NowPlayingSnapshot(
        bundleIdentifier: 'com.google.Chrome',
        title: 'Flutter Course for Beginners – 37 Hour Complete Course',
        artist: 'freeCodeCamp.org',
        isPlaying: true,
        elapsedSeconds: 3,
        durationSeconds: 131961,
        timestamp: DateTime.now(),
      );
      const audioRoute = AudioRouteSnapshot(name: 'WH-CH520', isBuiltIn: false);

      final activity = buildNowPlayingActivity(snapshot, audioRoute: audioRoute, onControlPressed: () {});

      final boxKey = UniqueKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            // Material's child gets tight (fill-the-screen) constraints from
            // the default route — a SizedBox can't shrink below a tight
            // incoming constraint, so without Center here this would render
            // at the full test-surface size (800x600) and never actually
            // exercise the fixed 360x140 box every real activity is
            // rendered into (see IslandShell._sizedOverlay).
            child: Center(
              child: SizedBox(
                key: boxKey,
                width: 360,
                height: 140,
                child: Builder(
                  builder: (context) => activity.expandedBuilder(context, LifecycleState.expanded),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byKey(boxKey)), const Size(360, 140));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('artwork is truly centered against the whole card height', (tester) async {
    // A Row+Column flow can only ever center whatever's above the controls
    // within the space *left over* above them — never against the card's
    // whole height, since the controls' own height is inherently excluded.
    // The artwork is now positioned independently via a Stack (see the
    // comment on it in now_playing_activity.dart) specifically so this
    // holds exactly, not just approximately.
    final snapshot = NowPlayingSnapshot(
      bundleIdentifier: 'com.google.Chrome',
      title: 'Flutter Course for Beginners – 37 Hour Complete Course',
      artist: 'freeCodeCamp.org',
      isPlaying: true,
      elapsedSeconds: 3,
      durationSeconds: 131961,
      timestamp: DateTime.now(),
    );
    const audioRoute = AudioRouteSnapshot(name: 'WH-CH520', isBuiltIn: false);
    final activity = buildNowPlayingActivity(snapshot, audioRoute: audioRoute, onControlPressed: () {});

    final boxKey = UniqueKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: SizedBox(
              key: boxKey,
              width: 360,
              height: 140,
              child: Builder(
                builder: (context) => activity.expandedBuilder(context, LifecycleState.expanded),
              ),
            ),
          ),
        ),
      ),
    );

    final boxRect = tester.getRect(find.byKey(boxKey));
    final artworkRect = tester.getRect(find.byKey(const ValueKey('now-playing-artwork')));

    // Centering the artwork independently only actually looks right if it
    // doesn't visually collide with the controls row underneath — that's a
    // real risk once the artwork is positioned by the box's geometry alone
    // rather than by flowing above the controls the way it used to.
    final playButtonRect = tester.getRect(find.bySemanticsLabel('Pause'));
    expect(
      artworkRect.bottom,
      lessThanOrEqualTo(playButtonRect.top),
      reason: 'artwork must not visually overlap the controls row below it',
    );

    final boxCenterY = boxRect.top + boxRect.height / 2;
    final artworkCenterY = artworkRect.top + artworkRect.height / 2;

    // A couple px of tolerance for rounding — anything beyond that means
    // the artwork drifted back into being positioned by the text/controls
    // flow instead of independently via the Stack.
    expect(artworkCenterY, closeTo(boxCenterY, 2));
    expect(tester.takeException(), isNull);
  });
}
