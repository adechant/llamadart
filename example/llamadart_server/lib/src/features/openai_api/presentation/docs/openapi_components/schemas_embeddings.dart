Map<String, dynamic> buildEmbeddingsSchemas({required String modelId}) {
  return <String, dynamic>{
    'EmbeddingsRequest': <String, dynamic>{
      'type': 'object',
      'required': <String>['model', 'input'],
      'properties': <String, dynamic>{
        'model': <String, dynamic>{'type': 'string', 'example': modelId},
        'input': <String, dynamic>{
          'oneOf': <dynamic>[
            <String, dynamic>{
              'type': 'string',
              'example': 'Seoul is the capital of South Korea.',
            },
            <String, dynamic>{
              'type': 'array',
              'items': <String, dynamic>{'type': 'string'},
            },
          ],
        },
        'encoding_format': <String, dynamic>{
          'type': 'string',
          'enum': <String>['float'],
          'default': 'float',
          'description':
              'This example currently supports only `float` output format.',
        },
        'user': <String, dynamic>{
          'type': 'string',
          'description': 'Optional user identifier (accepted but not used).',
        },
      },
      'additionalProperties': true,
    },
    'EmbeddingData': <String, dynamic>{
      'type': 'object',
      'required': <String>['object', 'embedding', 'index'],
      'properties': <String, dynamic>{
        'object': <String, dynamic>{'type': 'string', 'example': 'embedding'},
        'embedding': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{'type': 'number'},
        },
        'index': <String, dynamic>{'type': 'integer'},
      },
    },
    'EmbeddingsUsage': <String, dynamic>{
      'type': 'object',
      'required': <String>['prompt_tokens', 'total_tokens'],
      'properties': <String, dynamic>{
        'prompt_tokens': <String, dynamic>{'type': 'integer'},
        'total_tokens': <String, dynamic>{'type': 'integer'},
      },
    },
    'EmbeddingsResponse': <String, dynamic>{
      'type': 'object',
      'required': <String>['object', 'data', 'model', 'usage'],
      'properties': <String, dynamic>{
        'object': <String, dynamic>{'type': 'string', 'example': 'list'},
        'data': <String, dynamic>{
          'type': 'array',
          'items': <String, dynamic>{
            r'$ref': '#/components/schemas/EmbeddingData',
          },
        },
        'model': <String, dynamic>{'type': 'string', 'example': modelId},
        'usage': <String, dynamic>{
          r'$ref': '#/components/schemas/EmbeddingsUsage',
        },
      },
    },
  };
}
