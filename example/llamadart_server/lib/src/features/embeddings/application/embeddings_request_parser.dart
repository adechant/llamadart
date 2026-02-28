import '../../shared/openai_http_exception.dart';
import '../domain/openai_embeddings_request.dart';

/// Parses and validates an OpenAI embeddings request body.
OpenAiEmbeddingsRequest parseEmbeddingsRequest(
  Map<String, dynamic> json, {
  required String configuredModelId,
}) {
  final model = json['model'];
  if (model is! String || model.trim().isEmpty) {
    throw OpenAiHttpException.invalidRequest(
      'Missing required `model` field.',
      param: 'model',
    );
  }

  if (model != configuredModelId) {
    throw OpenAiHttpException.modelNotFound(model);
  }

  final inputs = _parseInputList(json['input']);
  final encodingFormat = _parseEncodingFormat(json['encoding_format']);

  return OpenAiEmbeddingsRequest(
    model: model,
    inputs: inputs,
    encodingFormat: encodingFormat,
  );
}

List<String> _parseInputList(Object? rawInput) {
  if (rawInput is String) {
    if (rawInput.trim().isEmpty) {
      throw OpenAiHttpException.invalidRequest(
        '`input` must not be empty.',
        param: 'input',
      );
    }
    return <String>[rawInput];
  }

  if (rawInput is List) {
    if (rawInput.isEmpty) {
      throw OpenAiHttpException.invalidRequest(
        '`input` must be a non-empty string or array of strings.',
        param: 'input',
      );
    }

    final inputs = <String>[];
    for (var i = 0; i < rawInput.length; i++) {
      final value = rawInput[i];
      if (value is! String || value.trim().isEmpty) {
        throw OpenAiHttpException.invalidRequest(
          '`input[$i]` must be a non-empty string.',
          param: 'input',
        );
      }
      inputs.add(value);
    }
    return inputs;
  }

  throw OpenAiHttpException.invalidRequest(
    '`input` must be a string or an array of strings.',
    param: 'input',
  );
}

String _parseEncodingFormat(Object? rawEncodingFormat) {
  if (rawEncodingFormat == null) {
    return 'float';
  }

  if (rawEncodingFormat is! String || rawEncodingFormat.trim().isEmpty) {
    throw OpenAiHttpException.invalidRequest(
      '`encoding_format` must be a non-empty string when provided.',
      param: 'encoding_format',
    );
  }

  if (rawEncodingFormat != 'float') {
    throw OpenAiHttpException.invalidRequest(
      'Only `encoding_format = "float"` is supported in this example server.',
      param: 'encoding_format',
      code: 'unsupported_value',
    );
  }

  return rawEncodingFormat;
}
