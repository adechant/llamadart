/// Exposes embedding generation capability.
abstract class EngineEmbeddingPort {
  /// Generates a single embedding vector for [input].
  Future<List<double>> embed(String input, {bool normalize = true});

  /// Generates embedding vectors for all [inputs] in order.
  Future<List<List<double>>> embedBatch(
    List<String> inputs, {
    bool normalize = true,
  });
}
