import 'package:flutter/material.dart';

import '../engine/activity.dart';

/// Real mic-in-use indicator (§04/§05, v1 tier) — persists for as long as
/// MicrophoneActivityProvider reports the mic active, unlike a transient
/// notification; a privacy-relevant indicator should stay up the whole time,
/// same as macOS's own orange dot.
Activity buildMicrophoneActivity() {
  return Activity(
    id: 'microphone-activity',
    priority: ActivityPriority.alert,
    collapsedBuilder: (context, state) => const _MicrophoneActiveContent(),
    expandedBuilder: (context, state) => const _MicrophoneActiveContent(),
  );
}

class _MicrophoneActiveContent extends StatelessWidget {
  const _MicrophoneActiveContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        label: 'Microphone in use.',
        excludeSemantics: true,
        liveRegion: true,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic, color: Color(0xFFFF9F0A), size: 18),
            SizedBox(width: 9),
            Text('Microphone in use', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
