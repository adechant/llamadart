import 'package:llamadart_basic_example/services/sqlite_vector_search_service.dart';
import 'package:test/test.dart';

void main() {
  group('SqliteVectorSearchService.interpretDistance', () {
    final SqliteVectorSearchService service = SqliteVectorSearchService();

    test('maps cosine distance to similarity and relevance', () {
      final ScoreInterpretation result = service.interpretDistance(
        distance: 0.08,
        distanceMetric: 'COSINE',
      );

      expect(result.similarity, closeTo(0.92, 1e-9));
      expect(result.relevance, equals('very-high'));
    });

    test('clamps cosine similarity to -1..1', () {
      final ScoreInterpretation result = service.interpretDistance(
        distance: -0.5,
        distanceMetric: 'COSINE',
      );

      expect(result.similarity, equals(1.0));
      expect(result.relevance, equals('very-high'));
    });

    test('maps l2 distance to bounded similarity', () {
      final ScoreInterpretation result = service.interpretDistance(
        distance: 1.0,
        distanceMetric: 'L2',
      );

      expect(result.similarity, closeTo(0.5, 1e-9));
      expect(result.relevance, equals('medium'));
    });
  });

  group('SqliteVectorSearchService.filterByMinSimilarity', () {
    final SqliteVectorSearchService service = SqliteVectorSearchService();

    test('filters out rows below threshold and reports filtered count', () {
      final List<SqliteVectorMatch> matches = <SqliteVectorMatch>[
        const SqliteVectorMatch(id: 1, content: 'a', distance: 0.10),
        const SqliteVectorMatch(id: 2, content: 'b', distance: 0.40),
        const SqliteVectorMatch(id: 3, content: 'c', distance: 0.75),
      ];

      final List<ScoredSqliteVectorMatch> scored = service.scoreMatches(
        matches,
        distanceMetric: 'COSINE',
      );

      final FilteredScoredMatches filtered = service.filterByMinSimilarity(
        scored,
        minSimilarity: 0.60,
      );

      expect(
        filtered.matches.map((ScoredSqliteVectorMatch m) => m.match.id),
        orderedEquals(<int>[1, 2]),
      );
      expect(filtered.filteredCount, equals(1));
    });
  });

  group('SqliteVectorSearchService.computeQuantizedRecallAtK', () {
    final SqliteVectorSearchService service = SqliteVectorSearchService();

    test('calculates overlap recall and distance deltas', () {
      final List<SqliteVectorMatch> exact = <SqliteVectorMatch>[
        const SqliteVectorMatch(id: 1, content: 'a', distance: 0.10),
        const SqliteVectorMatch(id: 2, content: 'b', distance: 0.20),
        const SqliteVectorMatch(id: 3, content: 'c', distance: 0.30),
      ];

      final List<SqliteVectorMatch> quantized = <SqliteVectorMatch>[
        const SqliteVectorMatch(id: 2, content: 'b', distance: 0.21),
        const SqliteVectorMatch(id: 3, content: 'c', distance: 0.31),
        const SqliteVectorMatch(id: 4, content: 'd', distance: 0.50),
      ];

      final QuantizedComparisonStats stats = service.computeQuantizedRecallAtK(
        exactMatches: exact,
        quantizedMatches: quantized,
      );

      expect(stats.k, equals(3));
      expect(stats.overlapCount, equals(2));
      expect(stats.recall, closeTo(2 / 3, 1e-9));
      expect(stats.meanDistanceDelta, closeTo(0.01, 1e-9));
      expect(stats.maxAbsoluteDistanceDelta, closeTo(0.01, 1e-9));
    });

    test('returns null deltas when there is no ID overlap', () {
      final List<SqliteVectorMatch> exact = <SqliteVectorMatch>[
        const SqliteVectorMatch(id: 1, content: 'a', distance: 0.10),
        const SqliteVectorMatch(id: 2, content: 'b', distance: 0.20),
      ];

      final List<SqliteVectorMatch> quantized = <SqliteVectorMatch>[
        const SqliteVectorMatch(id: 3, content: 'c', distance: 0.31),
        const SqliteVectorMatch(id: 4, content: 'd', distance: 0.50),
      ];

      final QuantizedComparisonStats stats = service.computeQuantizedRecallAtK(
        exactMatches: exact,
        quantizedMatches: quantized,
      );

      expect(stats.k, equals(2));
      expect(stats.overlapCount, equals(0));
      expect(stats.recall, equals(0.0));
      expect(stats.meanDistanceDelta, isNull);
      expect(stats.maxAbsoluteDistanceDelta, isNull);
    });
  });
}
