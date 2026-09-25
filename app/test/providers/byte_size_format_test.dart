import 'package:flutter_test/flutter_test.dart';
import 'package:islandia/providers/byte_size_format.dart';

void main() {
  group('formatByteSize', () {
    test('bytes render as a whole number with no decimal', () {
      expect(formatByteSize(512), '512 B');
    });

    test('exactly 1024 bytes crosses into KB', () {
      expect(formatByteSize(1024), '1.0 KB');
    });

    test('one byte under a KB stays in bytes', () {
      expect(formatByteSize(1023), '1023 B');
    });

    test('a Finder-style fractional MB value, matching Get Info (binary division, decimal-style label)', () {
      // 1,258,291 bytes / 1024 / 1024 ≈ 1.2 — a true decimal-KB scheme
      // (/1000/1000) would instead read ≈1.26, confirmed against Finder's
      // own Get Info panel as the wrong answer for this exact byte count.
      expect(formatByteSize(1258291), '1.2 MB');
    });

    test('crosses into GB at exactly 1024 MB', () {
      expect(formatByteSize(1024 * 1024 * 1024), '1.0 GB');
    });

    test('caps at TB rather than escalating further', () {
      expect(formatByteSize(1024 * 1024 * 1024 * 1024 * 5), '5.0 TB');
    });
  });
}
