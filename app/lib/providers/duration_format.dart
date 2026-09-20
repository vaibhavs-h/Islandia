/// `H:MM:SS` once there's an hour to show, `MM:SS` otherwise — the same
/// switch every media player (YouTube included) makes. Naively formatting
/// with `inMinutes.remainder(60)` and no hours segment at all silently
/// drops the hour count for anything over 59 minutes (72 minutes would
/// render as "12:39", not "1:12:39").
String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

/// The stopwatch's own format — centiseconds shown, same precision as
/// macOS's own Clock app stopwatch (confirmed against its UI: "00:05.43",
/// two digits after the decimal, not three/true milliseconds). A separate
/// function rather than an option on [formatDuration] since nothing else
/// that shares it — the Timer view, Now Playing's elapsed/duration — should
/// ever gain this precision; keeping it a distinct name makes that a
/// deliberate choice at each call site, not a flag someone could flip on
/// the wrong screen.
String formatStopwatchDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final centiseconds = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds.$centiseconds';
  }
  return '$minutes:$seconds.$centiseconds';
}

/// The Timer view's own format — always `HH:MM:SS`, hour column included
/// even at zero and always two digits, unlike [formatDuration]'s
/// conditional hour segment. macOS Clock's own Timer tab caps at 23:59:59
/// (confirmed: no timer can be set longer than that), so the hour value
/// itself never needs a third digit — but it's still zero-padded to two
/// (explicitly requested: always "00:MM:SS" for anything under an hour,
/// not a bare single digit), matching the fixed-width look of Clock's own
/// on-screen countdown.
String formatTimerDuration(Duration d) {
  final hours = d.inHours.toString().padLeft(2, '0');
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}
