import 'package:llamadart_tui_coding_agent/src/model_source_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('HfModelSpec.parse', () {
    test('parses owner/repo spec without hint', () {
      final spec = HfModelSpec.parse('unsloth/GLM-4.7-Flash-GGUF');

      expect(spec.repository, equals('unsloth/GLM-4.7-Flash-GGUF'));
      expect(spec.fileHint, isNull);
    });

    test('parses owner/repo with file hint', () {
      final spec = HfModelSpec.parse('unsloth/GLM-4.7-Flash-GGUF:UD-Q4_K_XL');

      expect(spec.repository, equals('unsloth/GLM-4.7-Flash-GGUF'));
      expect(spec.fileHint, equals('UD-Q4_K_XL'));
    });
  });

  group('selectBestGgufFile', () {
    test('prefers exact match when hint provides full file name', () {
      final selected = selectBestGgufFile(<String>[
        'model-Q4_K_M.gguf',
        'model-Q8_0.gguf',
      ], hint: 'model-Q8_0.gguf');

      expect(selected, equals('model-Q8_0.gguf'));
    });

    test('uses normalized partial match for shorthand hints', () {
      final selected = selectBestGgufFile(<String>[
        'GLM-4.7-Flash-UD-Q4_K_XL.gguf',
        'GLM-4.7-Flash-Q8_0.gguf',
      ], hint: 'ud-q4_k_xl');

      expect(selected, equals('GLM-4.7-Flash-UD-Q4_K_XL.gguf'));
    });
  });
}
