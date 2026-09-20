import 'package:flutter/material.dart';

import '../engine/activity.dart';

/// Screen capture indicator (§04/§05, v1 tier) — see
/// ScreenCaptureActivityProvider for the source. "Screen Recording" is
/// macOS's own label for this indicator regardless of whether it's an
/// actual recording, a screen share, or a one-off screenshot — matched here
/// on purpose rather than trying to word it more precisely than the system
/// indicator does.
Activity buildScreenCaptureActivity() {
  return Activity(
    id: 'screen-capture-activity',
    priority: ActivityPriority.p2Important,
    collapsedBuilder: (context, state) => const _ScreenCaptureActiveContent(),
    expandedBuilder: (context, state) => const _ScreenCaptureActiveContent(),
  );
}

class _ScreenCaptureActiveContent extends StatelessWidget {
  const _ScreenCaptureActiveContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        label: 'Screen Recording.',
        excludeSemantics: true,
        liveRegion: true,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.screen_share, color: Color(0xFFBF5AF2), size: 18),
            SizedBox(width: 9),
            Text('Screen Recording', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
