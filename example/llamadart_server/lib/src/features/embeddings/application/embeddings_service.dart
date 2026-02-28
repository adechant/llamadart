import '../../server_engine/server_engine.dart';
import '../domain/openai_embeddings_request.dart';

/// Builds OpenAI-compatible embeddings responses.
class EmbeddingsService {
  final EngineEmbeddingPort _embeddingEngine;
  final EngineTokenCountPort _tokenCountEngine;

  /// Creates an embeddings service using [engine] capabilities.
  EmbeddingsService({required ApiServerEngine engine})
    : _embeddingEngine = engine,
      _tokenCountEngine = engine;

  /// Generates embeddings and returns an OpenAI-style response payload.
  Future<Map<String, dynamic>> create(
    OpenAiEmbeddingsRequest request, {
    required String modelId,
  }) async {
    final embeddings = await _embeddingEngine.embedBatch(
      request.inputs,
      normalize: request.encodingFormat == 'float',
    );

    final usage = await _buildUsage(request.inputs);
    final data = <Map<String, dynamic>>[];
    for (var i = 0; i < embeddings.length; i++) {
      data.add(<String, dynamic>{
        'object': 'embedding',
        'embedding': embeddings[i],
        'index': i,
      });
    }

    return <String, dynamic>{
      'object': 'list',
      'data': data,
      'model': modelId,
      'usage': usage,
    };
  }

  Future<Map<String, int>> _buildUsage(List<String> inputs) async {
    var promptTokens = 0;
    for (final input in inputs) {
      promptTokens += await _tokenCountEngine.getTokenCount(input);
    }
    return <String, int>{
      'prompt_tokens': promptTokens,
      'total_tokens': promptTokens,
    };
  }
}
