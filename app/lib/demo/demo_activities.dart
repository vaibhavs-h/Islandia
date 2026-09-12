import 'package:flutter/material.dart';

import '../engine/activity.dart';
import '../shell/island_button.dart';

/// A fake P1 activity the dev triggers in [buildBatteryActivity] can summon,
/// to prove priority preemption + restoration end-to-end. Real CallProvider
/// integration (§05, "later" tier — no reliable public API exists yet)
/// replaces this eventually; nothing about the shell above needs to change
/// when it does.
Activity buildIncomingCallDemoActivity({
  required VoidCallback onResolve,
}) {
  return Activity(
    id: 'fake-call-demo',
    priority: ActivityPriority.p1Immediate,
    collapsedBuilder: (context, state) => const SizedBox.shrink(),
    expandedBuilder: (context, state) => _IncomingCallContent(onResolve: onResolve),
  );
}

class _IncomingCallContent extends StatelessWidget {
  const _IncomingCallContent({required this.onResolve});

  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // liveRegion: a priority activity taking over the surface should
          // announce itself proactively, the same way an interruption would
          // on a phone — the user shouldn't have to go looking for it.
          Semantics(
            label: 'Incoming call. Caller Name demo. Priority activity, preempting whatever was showing.',
            excludeSemantics: true,
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.call, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Incoming Call', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
                SizedBox(height: 4),
                Text('Caller Name (demo) — P1, preempting whatever was showing', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(child: IslandButton(label: 'Decline', color: const Color(0xFF7A2323), onTap: onResolve)),
              const SizedBox(width: 8),
              Expanded(child: IslandButton(label: 'Answer', color: const Color(0xFF1F6B2E), onTap: onResolve)),
            ],
          ),
        ],
      ),
    );
  }
}
