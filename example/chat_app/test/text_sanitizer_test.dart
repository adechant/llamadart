import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart_chat_example/utils/text_sanitizer.dart';

void main() {
  group('sanitizeForTextLayout', () {
    test('keeps valid text unchanged', () {
      const input = 'Hello, world!';
      expect(sanitizeForTextLayout(input), input);
    });

    test('preserves valid surrogate pairs', () {
      const input = 'A😀B';
      expect(sanitizeForTextLayout(input), input);
    });

    test('replaces lone leading surrogate', () {
      final input = '${String.fromCharCode(0xD83D)}abc';
      final sanitized = sanitizeForTextLayout(input);
      expect(sanitized.codeUnits.first, 0xFFFD);
      expect(sanitized.substring(1), 'abc');
    });

    test('replaces lone trailing surrogate', () {
      final input = 'abc${String.fromCharCode(0xDC00)}';
      final sanitized = sanitizeForTextLayout(input);
      expect(sanitized.substring(0, 3), 'abc');
      expect(sanitized.codeUnits.last, 0xFFFD);
    });
  });
}
