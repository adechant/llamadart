import 'package:llamadart_basic_example/services/sqlite_vector_cli_options.dart';
import 'package:test/test.dart';

void main() {
  group('parseSqliteVectorCliOptions', () {
    test('uses defaults and corpus fallback', () {
      final parser = createSqliteVectorArgParser(
        defaultModelUrl: 'https://example.com/model.gguf',
      );
      final results = parser.parse(<String>[]);

      final options = parseSqliteVectorCliOptions(
        results,
        defaultCorpus: <String>['doc-a', 'doc-b'],
      );

      expect(options.modelUrlOrPath, 'https://example.com/model.gguf');
      expect(options.query, 'How do I improve embedding throughput?');
      expect(options.documents, orderedEquals(<String>['doc-a', 'doc-b']));
      expect(options.topK, 3);
      expect(options.distanceMetric, cosineMetric);
      expect(options.maxParallelSequences, 2);
      expect(options.threads, 0);
      expect(options.threadsBatch, 0);
    });

    test('respects explicit thread and max-seq flags', () {
      final parser = createSqliteVectorArgParser(defaultModelUrl: 'm.gguf');
      final results = parser.parse(<String>[
        '--threads',
        '8',
        '--threads-batch',
        '6',
        '--max-seq',
        '11',
      ]);

      final options = parseSqliteVectorCliOptions(
        results,
        defaultCorpus: <String>['doc-a', 'doc-b'],
      );

      expect(options.threads, 8);
      expect(options.threadsBatch, 6);
      expect(options.maxParallelSequences, 11);
    });

    test('parses min similarity in valid range', () {
      final parser = createSqliteVectorArgParser(defaultModelUrl: 'm.gguf');
      final results = parser.parse(<String>['--min-similarity', '0.42']);

      final options = parseSqliteVectorCliOptions(
        results,
        defaultCorpus: <String>['doc-a'],
      );

      expect(options.minSimilarity, closeTo(0.42, 1e-9));
    });

    test('throws for unsupported quantized qtype', () {
      final parser = createSqliteVectorArgParser(defaultModelUrl: 'm.gguf');
      final results = parser.parse(<String>['--quantized-qtype', 'fp16']);

      expect(
        () => parseSqliteVectorCliOptions(
          results,
          defaultCorpus: <String>['doc-a'],
        ),
        throwsFormatException,
      );
    });

    test('throws for out-of-range min similarity', () {
      final parser = createSqliteVectorArgParser(defaultModelUrl: 'm.gguf');
      final results = parser.parse(<String>['--min-similarity', '1.5']);

      expect(
        () => parseSqliteVectorCliOptions(
          results,
          defaultCorpus: <String>['doc-a'],
        ),
        throwsFormatException,
      );
    });
  });

  group('buildSqliteVectorHelpText', () {
    test('contains usage heading and examples', () {
      final parser = createSqliteVectorArgParser(defaultModelUrl: 'm.gguf');

      final String text = buildSqliteVectorHelpText(parser);

      expect(text, contains('llamadart SQLite Vector Example'));
      expect(text, contains('Example:'));
      expect(text, contains('--quantized --compare-exact'));
    });
  });
}
