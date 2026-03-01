import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite_vector/sqlite_vector.dart';

/// Supported quantization types for sqlite-vector.
const Set<String> supportedQuantizeTypes = <String>{'UINT8', 'INT8', '1BIT'};

/// Service that manages sqlite-vector storage and retrieval operations.
class SqliteVectorSearchService {
  /// Loads the sqlite-vector extension into the current SQLite runtime.
  void loadExtension() {
    sqlite3.loadSqliteVectorExtension();
  }

  /// Opens a SQLite database at [path], using in-memory DB for `:memory:`.
  Database openDatabase(String path) {
    if (path == ':memory:') {
      return sqlite3.openInMemory();
    }

    return sqlite3.open(path);
  }

  /// Seeds [documents] and [embeddings] into a table and initializes vector search.
  void seedVectorTable(
    Database database, {
    required List<String> documents,
    required List<List<double>> embeddings,
    required String distanceMetric,
  }) {
    if (documents.length != embeddings.length) {
      throw ArgumentError(
        'documents and embeddings must have the same length.',
      );
    }
    if (embeddings.isEmpty) {
      throw ArgumentError('embeddings must not be empty.');
    }

    final int dimensions = embeddings.first.length;
    if (dimensions == 0) {
      throw ArgumentError('embedding vectors must not be empty.');
    }

    for (int i = 0; i < embeddings.length; i++) {
      if (embeddings[i].length != dimensions) {
        throw ArgumentError(
          'all embeddings must use the same vector length. '
          'Expected $dimensions, got ${embeddings[i].length} at index $i.',
        );
      }
    }

    database.execute('DROP TABLE IF EXISTS documents');
    database.execute(
      'CREATE TABLE documents ('
      'id INTEGER PRIMARY KEY, '
      'content TEXT NOT NULL, '
      'embedding BLOB NOT NULL'
      ')',
    );

    database.execute('BEGIN');
    try {
      final PreparedStatement insert = database.prepare(
        'INSERT INTO documents (id, content, embedding) '
        'VALUES (?, ?, vector_as_f32(?))',
      );
      try {
        for (int i = 0; i < documents.length; i++) {
          insert.execute(<Object?>[
            i + 1,
            documents[i],
            jsonEncode(embeddings[i]),
          ]);
        }
      } finally {
        insert.close();
      }

      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }

    database.select(
      "SELECT vector_init('documents', 'embedding', ?)",
      <Object?>['dimension=$dimensions,type=FLOAT32,distance=$distanceMetric'],
    );
  }

  /// Prepares quantized ANN structures and optionally preloads them.
  int prepareQuantizedSearch(
    Database database, {
    required bool preload,
    required String qtype,
    String? maxMemory,
  }) {
    final List<String> options = <String>['qtype=$qtype'];
    if (maxMemory != null) {
      options.add('max_memory=$maxMemory');
    }

    final Row quantizeRow = database.select(
      "SELECT vector_quantize('documents', 'embedding', ?) AS rows",
      <Object?>[options.join(',')],
    ).first;

    final Object? rowsValue = quantizeRow['rows'];
    final int rows = switch (rowsValue) {
      final int value => value,
      final num value => value.toInt(),
      _ => int.parse(rowsValue.toString()),
    };

    if (preload) {
      database.select(
        "SELECT vector_quantize_preload('documents', 'embedding')",
      );
    }

    return rows;
  }

  /// Queries nearest documents for [queryVector] with either exact or ANN search.
  List<SqliteVectorMatch> searchNearestDocuments(
    Database database, {
    required List<double> queryVector,
    required int topK,
    required bool quantized,
  }) {
    final String scanFunction = quantized
        ? 'vector_quantize_scan'
        : 'vector_full_scan';

    final List<Row> rows = database.select(
      'SELECT d.id AS id, d.content AS content, v.distance AS distance '
      "FROM $scanFunction('documents', 'embedding', vector_as_f32(?), ?) AS v "
      'JOIN documents AS d ON d.id = v.rowid',
      <Object?>[jsonEncode(queryVector), topK],
    );

    return rows
        .map((Row row) {
          final Object? distanceValue = row['distance'];
          final double distance = switch (distanceValue) {
            final num value => value.toDouble(),
            _ => double.parse(distanceValue.toString()),
          };

          return SqliteVectorMatch(
            id: row['id'] as int,
            content: row['content'] as String,
            distance: distance,
          );
        })
        .toList(growable: false);
  }

  /// Converts a raw distance into a normalized score and relevance label.
  ScoreInterpretation interpretDistance({
    required double distance,
    required String distanceMetric,
  }) {
    if (distanceMetric == 'COSINE') {
      final double similarity = (1.0 - distance).clamp(-1.0, 1.0);
      return ScoreInterpretation(
        similarity: similarity,
        relevance: _relevanceLabel(similarity),
      );
    }

    final double similarity = 1.0 / (1.0 + distance);
    return ScoreInterpretation(
      similarity: similarity,
      relevance: _relevanceLabel(similarity),
    );
  }

  /// Attaches score interpretations to raw vector matches.
  List<ScoredSqliteVectorMatch> scoreMatches(
    List<SqliteVectorMatch> matches, {
    required String distanceMetric,
  }) {
    return matches
        .map(
          (SqliteVectorMatch match) => ScoredSqliteVectorMatch(
            match: match,
            interpretation: interpretDistance(
              distance: match.distance,
              distanceMetric: distanceMetric,
            ),
          ),
        )
        .toList(growable: false);
  }

  /// Filters scored matches by [minSimilarity] if provided.
  FilteredScoredMatches filterByMinSimilarity(
    List<ScoredSqliteVectorMatch> matches, {
    double? minSimilarity,
  }) {
    if (minSimilarity == null) {
      return FilteredScoredMatches(matches: matches, filteredCount: 0);
    }

    final List<ScoredSqliteVectorMatch> visible = matches
        .where(
          (ScoredSqliteVectorMatch scored) =>
              scored.interpretation.similarity >= minSimilarity,
        )
        .toList(growable: false);

    return FilteredScoredMatches(
      matches: visible,
      filteredCount: matches.length - visible.length,
    );
  }

  /// Computes recall and distance deltas between exact and quantized top-k sets.
  QuantizedComparisonStats computeQuantizedRecallAtK({
    required List<SqliteVectorMatch> exactMatches,
    required List<SqliteVectorMatch> quantizedMatches,
  }) {
    final Set<int> exactIds = exactMatches
        .map((SqliteVectorMatch match) => match.id)
        .toSet();
    final Set<int> quantizedIds = quantizedMatches
        .map((SqliteVectorMatch match) => match.id)
        .toSet();
    final int overlapCount = quantizedIds.intersection(exactIds).length;

    final Map<int, double> exactDistanceById = <int, double>{
      for (final SqliteVectorMatch match in exactMatches)
        match.id: match.distance,
    };

    final List<double> deltas = quantizedMatches
        .where(
          (SqliteVectorMatch match) => exactDistanceById.containsKey(match.id),
        )
        .map(
          (SqliteVectorMatch match) =>
              match.distance - exactDistanceById[match.id]!,
        )
        .toList(growable: false);

    final int k = exactMatches.length;
    final double recall = k == 0 ? 0.0 : overlapCount / k;

    if (deltas.isEmpty) {
      return QuantizedComparisonStats(
        k: k,
        overlapCount: overlapCount,
        recall: recall,
        meanDistanceDelta: null,
        maxAbsoluteDistanceDelta: null,
      );
    }

    final double meanDistanceDelta =
        deltas.reduce((double a, double b) => a + b) / deltas.length;
    final double maxAbsoluteDistanceDelta = deltas
        .map((double value) => value.abs())
        .reduce((double a, double b) => a > b ? a : b);

    return QuantizedComparisonStats(
      k: k,
      overlapCount: overlapCount,
      recall: recall,
      meanDistanceDelta: meanDistanceDelta,
      maxAbsoluteDistanceDelta: maxAbsoluteDistanceDelta,
    );
  }

  String _relevanceLabel(double similarity) {
    if (similarity >= 0.85) {
      return 'very-high';
    }
    if (similarity >= 0.70) {
      return 'high';
    }
    if (similarity >= 0.50) {
      return 'medium';
    }
    if (similarity >= 0.30) {
      return 'low';
    }
    return 'very-low';
  }
}

/// Raw row returned from sqlite-vector search.
final class SqliteVectorMatch {
  /// Synthetic document identifier.
  final int id;

  /// Original document content.
  final String content;

  /// Distance score returned by sqlite-vector.
  final double distance;

  /// Creates a sqlite-vector match row.
  const SqliteVectorMatch({
    required this.id,
    required this.content,
    required this.distance,
  });
}

/// User-facing score interpretation for a vector distance.
final class ScoreInterpretation {
  /// Similarity score mapped to roughly `[-1, 1]` or `(0, 1]`.
  final double similarity;

  /// Convenience relevance bucket.
  final String relevance;

  /// Creates score interpretation.
  const ScoreInterpretation({
    required this.similarity,
    required this.relevance,
  });
}

/// Wrapper that includes the raw match and interpreted score.
final class ScoredSqliteVectorMatch {
  /// Raw sqlite-vector row.
  final SqliteVectorMatch match;

  /// Interpreted score fields.
  final ScoreInterpretation interpretation;

  /// Creates a scored wrapper.
  const ScoredSqliteVectorMatch({
    required this.match,
    required this.interpretation,
  });
}

/// Result of applying a minimum similarity filter.
final class FilteredScoredMatches {
  /// Matches that passed filtering.
  final List<ScoredSqliteVectorMatch> matches;

  /// Number of rows removed by filtering.
  final int filteredCount;

  /// Creates filtered result.
  const FilteredScoredMatches({
    required this.matches,
    required this.filteredCount,
  });
}

/// Comparison statistics between exact and quantized top-k results.
final class QuantizedComparisonStats {
  /// Effective `k` used for the comparison.
  final int k;

  /// Number of shared IDs between exact and quantized top-k sets.
  final int overlapCount;

  /// Recall at k (`overlapCount / k`).
  final double recall;

  /// Mean of `(quantizedDistance - exactDistance)` for shared IDs.
  final double? meanDistanceDelta;

  /// Max absolute distance delta for shared IDs.
  final double? maxAbsoluteDistanceDelta;

  /// Creates quantized comparison stats.
  const QuantizedComparisonStats({
    required this.k,
    required this.overlapCount,
    required this.recall,
    required this.meanDistanceDelta,
    required this.maxAbsoluteDistanceDelta,
  });
}
