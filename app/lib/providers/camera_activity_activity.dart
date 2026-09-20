import 'package:flutter/material.dart';

import '../engine/activity.dart';

/// Camera-in-use indicator (§04/§05, v1 tier) — see CameraActivityProvider
/// for the (fragile, log-based) source. Persists for as long as the camera
/// stays active, same as the mic indicator, not a one-off notification.
Activity buildCameraActivity() {
  return Activity(
    id: 'camera-activity',
    priority: ActivityPriority.p2Important,
    collapsedBuilder: (context, state) => const _CameraActiveContent(),
    expandedBuilder: (context, state) => const _CameraActiveContent(),
  );
}

class _CameraActiveContent extends StatelessWidget {
  const _CameraActiveContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        label: 'Camera in use.',
        excludeSemantics: true,
        liveRegion: true,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam, color: Color(0xFF32D74B), size: 18),
            SizedBox(width: 9),
            Text('Camera in use', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
