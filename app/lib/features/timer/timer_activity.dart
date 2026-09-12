import 'package:flutter/material.dart';

import '../../engine/activity.dart';
import '../../shell/island_button.dart';
import 'timer_controller.dart';

/// A running countdown, ambient like Now Playing while it counts down.
Activity buildTimerActivity({
  required TimerController controller,
  required VoidCallback onCancel,
}) {
  return Activity(
    id: 'timer',
    priority: ActivityPriority.p3Ambient,
    collapsedBuilder: (context, state) => _TimerCollapsed(controller: controller),
    expandedBuilder: (context, state) => _TimerExpanded(controller: controller, onCancel: onCancel),
  );
}

/// What a completed timer becomes (§05/§12): P2 important, transient — it
/// announces itself once and ages out on its own after [autoDismissAfter],
/// via the engine's own timeout handling, not a UI-layer workaround.
Activity buildTimerCompleteActivity() {
  return Activity(
    id: 'timer-complete',
    priority: ActivityPriority.p2Important,
    isTransient: true,
    autoDismissAfter: const Duration(seconds: 5),
    collapsedBuilder: (context, state) => const _TimerCompleteContent(),
    expandedBuilder: (context, state) => const _TimerCompleteContent(),
  );
}

class _TimerCollapsed extends StatelessWidget {
  const _TimerCollapsed({required this.controller});

  final TimerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Semantics(
          label: 'Timer, ${controller.formatted} remaining.',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 9),
                Text(controller.formatted, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TimerExpanded extends StatelessWidget {
  const _TimerExpanded({required this.controller, required this.onCancel});

  final TimerController controller;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Semantics(
            label: 'Timer, ${controller.formatted} remaining.',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(Icons.timer_outlined, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Timer', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(controller.formatted, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300)),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: IslandButton(label: 'Cancel', color: const Color(0xFF33363C), onTap: onCancel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TimerCompleteContent extends StatelessWidget {
  const _TimerCompleteContent();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Semantics(
        label: 'Timer complete.',
        excludeSemantics: true,
        liveRegion: true,
        child: const Row(
          children: [
            Icon(Icons.timer_outlined, color: Colors.white, size: 18),
            SizedBox(width: 9),
            Text('Timer complete', style: TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
