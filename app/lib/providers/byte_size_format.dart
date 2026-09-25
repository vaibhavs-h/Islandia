/// Matches Finder's own "Get Info" convention: binary-based divisions
/// (1024, not 1000) but the decimal-style unit labels Finder actually
/// prints (KB/MB/GB, not KiB/MiB/GiB) — confirmed against Finder's own Get
/// Info panel, which shows e.g. "1.2 MB" for a file `ls -l` reports as
/// 1,258,291 bytes (1,258,291 / 1024 / 1024 ≈ 1.2), not the 1,258,291 /
/// 1000 / 1000 ≈ 1.26 a true decimal-KB scheme would produce. One decimal
/// place once past bytes; bytes themselves are always a whole number
/// (nothing shows "512.0 B").
String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(1)} ${units[unitIndex]}';
}
