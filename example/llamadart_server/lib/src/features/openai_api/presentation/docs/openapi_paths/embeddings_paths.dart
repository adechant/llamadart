import 'path_security.dart';

Map<String, dynamic> buildEmbeddingsPaths({
  required bool apiKeyEnabled,
  required String modelId,
}) {
  return <String, dynamic>{
    '/v1/embeddings': <String, dynamic>{
      'post': <String, dynamic>{
        'tags': <String>['Embeddings'],
        'summary': 'Create embeddings',
        'operationId': 'createEmbeddings',
        'security': operationSecurity(apiKeyEnabled),
        'requestBody': <String, dynamic>{
          'required': true,
          'content': <String, dynamic>{
            'application/json': <String, dynamic>{
              'schema': <String, dynamic>{
                r'$ref': '#/components/schemas/EmbeddingsRequest',
              },
              'examples': _buildEmbeddingsExamples(modelId),
            },
          },
        },
        'responses': <String, dynamic>{
          '200': <String, dynamic>{
            'description': 'Embedding vectors for the requested input.',
            'content': <String, dynamic>{
              'application/json': <String, dynamic>{
                'schema': <String, dynamic>{
                  r'$ref': '#/components/schemas/EmbeddingsResponse',
                },
              },
            },
          },
          '400': <String, dynamic>{
            r'$ref': '#/components/responses/BadRequestError',
          },
          '401': <String, dynamic>{
            r'$ref': '#/components/responses/UnauthorizedError',
          },
          '429': <String, dynamic>{
            r'$ref': '#/components/responses/RateLimitError',
          },
          '500': <String, dynamic>{
            r'$ref': '#/components/responses/ServerError',
          },
        },
      },
    },
  };
}

Map<String, dynamic> _buildEmbeddingsExamples(String modelId) {
  return <String, dynamic>{
    'single_input': <String, dynamic>{
      'summary': 'Single-string input',
      'value': <String, dynamic>{
        'model': modelId,
        'input': 'Seoul is the capital of South Korea.',
        'encoding_format': 'float',
      },
    },
    'batch_input': <String, dynamic>{
      'summary': 'Batch string input',
      'value': <String, dynamic>{
        'model': modelId,
        'input': <String>[
          'llamadart supports local inference.',
          'Embeddings are useful for semantic search.',
        ],
        'encoding_format': 'float',
      },
    },
  };
}
