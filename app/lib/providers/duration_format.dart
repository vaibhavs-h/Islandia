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
