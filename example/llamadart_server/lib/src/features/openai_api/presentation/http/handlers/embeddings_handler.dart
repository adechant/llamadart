import 'package:llamadart/llamadart.dart';
import 'package:relic/relic.dart';

import '../../../../embeddings/embeddings.dart';
import '../../../../shared/shared.dart';
import '../support/generation_gate.dart';
import '../support/http_json.dart';
import '../support/openai_error_mapper.dart';

/// Handles `POST /v1/embeddings`.
class EmbeddingsHandler {
  /// Public model ID exposed in API responses.
  final String modelId;

  /// Embeddings use case service.
  final EmbeddingsService embeddingsService;

  final GenerationGate _generationGate;

  /// Creates embeddings endpoint handlers.
  EmbeddingsHandler({
    required this.modelId,
    required this.embeddingsService,
    required GenerationGate generationGate,
  }) : _generationGate = generationGate;

  /// Handles one embeddings request.
  Future<Response> handle(Request req) async {
    var acquired = false;
    try {
      final request = parseEmbeddingsRequest(
        await readJsonObjectBody(req),
        configuredModelId: modelId,
      );

      if (!_generationGate.tryAcquire()) {
        return errorJsonResponse(
          OpenAiHttpException.busy(
            'Another request is already in progress. Retry shortly.',
          ),
        );
      }
      acquired = true;

      final responseBody = await embeddingsService.create(
        request,
        modelId: modelId,
      );
      return jsonResponse(responseBody);
    } on OpenAiHttpException catch (error) {
      return errorJsonResponse(error);
    } on LlamaException catch (error) {
      return errorJsonResponse(
        toServerError(error, 'Embedding generation failed'),
      );
    } catch (error) {
      return errorJsonResponse(toServerError(error, 'Server error'));
    } finally {
      if (acquired) {
        _generationGate.release(cancel: false);
      }
    }
  }
}
