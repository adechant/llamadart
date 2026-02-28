/// Parsed and validated request payload for `POST /v1/embeddings`.
class OpenAiEmbeddingsRequest {
  /// Requested model ID.
  final String model;

  /// Input strings to embed.
  final List<String> inputs;

  /// Output encoding format.
  ///
  /// This example currently supports only `float`.
  final String encodingFormat;

  /// Creates a validated embeddings request model.
  const OpenAiEmbeddingsRequest({
    required this.model,
    required this.inputs,
    required this.encodingFormat,
  });
}
