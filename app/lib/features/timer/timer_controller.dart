import 'dart:async';

import 'package:flutter/foundation.dart';

/// Native to Islandia — no OS dependency (§05). One running countdown;
/// §00A's "multiple concurrent timers" is a later increment on top of this,
/// not a reason to complicate the first one.
class TimerController extends ChangeNotifier {
  TimerController(this.totalDuration) : remaining = totalDuration {
    _ticker = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  final Duration totalDuration;
  Duration remaining;
  Timer? _ticker;

  bool get isComplete => remaining <= Duration.zero;

  void _tick(Timer timer) {
    final next = remaining - const Duration(seconds: 1);
    remaining = next <= Duration.zero ? Duration.zero : next;
    if (remaining == Duration.zero) {
      timer.cancel();
    }
    notifyListeners();
  }

  String get formatted {
    final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
