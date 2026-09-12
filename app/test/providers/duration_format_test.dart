import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/providers/duration_format.dart';

void main() {
  group('formatDuration', () {
    test('formats under an hour as MM:SS', () {
      expect(formatDuration(const Duration(minutes: 22, seconds: 59)), '22:59');
      expect(formatDuration(const Duration(minutes: 5, seconds: 3)), '05:03');
      expect(formatDuration(Duration.zero), '00:00');
    });

    test('does not silently drop the hour once past 59 minutes', () {
      // The exact regression reported: a 72-minute podcast/video used to
      // render as "12:39" (minutes naively wrapped via remainder(60) with
      // no hour segment at all), not "1:12:39".
      expect(formatDuration(const Duration(minutes: 72, seconds: 39)), '1:12:39');
    });

    test('formats multi-hour durations correctly', () {
      expect(formatDuration(const Duration(hours: 2, minutes: 5, seconds: 9)), '2:05:09');
    });
  });
}
