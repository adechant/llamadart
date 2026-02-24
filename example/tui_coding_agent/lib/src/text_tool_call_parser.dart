import 'dart:convert';

/// Parsed text-protocol tool call emitted by the model.
class TextToolCall {
  /// Tool name.
  final String name;

  /// Structured tool arguments.
  final Map<String, dynamic> arguments;

  const TextToolCall({required this.name, required this.arguments});
}

/// Heuristic parser for text-protocol tool-call payloads.
///
/// The parser accepts strict JSON blocks and resilient fallbacks that appear in
/// real model output, such as dangling `<tool_call>` tags, `toolName{...}`
/// shorthand, and lightweight XML-like argument wrappers.
class TextToolCallParser {
  final Set<String> _knownToolNames;

  TextToolCallParser({required Set<String> knownToolNames})
    : _knownToolNames = Set<String>.from(knownToolNames);

  /// Extracts tool calls from raw assistant text.
  List<TextToolCall> extract(String content) {
    final calls = <TextToolCall>[];

    final taggedPattern = RegExp(
      r'<tool_call>\s*([\s\S]*?)\s*</tool_call>',
      caseSensitive: false,
    );
    for (final match in taggedPattern.allMatches(content)) {
      final payload = match.group(1) ?? '';
      calls.addAll(_parsePayload(payload));
    }
    if (calls.isNotEmpty) {
      return calls;
    }

    final inlineTaggedPattern = RegExp(
      r'<tool_call>\s*([^\n\r]+)',
      caseSensitive: false,
      multiLine: true,
    );
    for (final match in inlineTaggedPattern.allMatches(content)) {
      final payload = (match.group(1) ?? '').trim();
      if (payload.isEmpty) {
        continue;
      }
      calls.addAll(_parsePayload(payload));
    }
    if (calls.isNotEmpty) {
      return calls;
    }

    final fencedJsonPattern = RegExp(
      r'```json\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    );
    for (final match in fencedJsonPattern.allMatches(content)) {
      final payload = match.group(1) ?? '';
      final parsed = _parsePayload(payload);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    return _parsePayload(content);
  }

  List<TextToolCall> _parsePayload(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) {
      return const <TextToolCall>[];
    }

    try {
      final decoded = jsonDecode(trimmed);
      final normalized = _normalizeCalls(decoded);
      if (normalized.isNotEmpty) {
        return normalized;
      }
    } catch (_) {
      // Fall through to heuristic parser.
    }

    return _parseHeuristicCalls(trimmed);
  }

  List<TextToolCall> _parseHeuristicCalls(String payload) {
    final cleaned = payload
        .trim()
        .replaceAll(RegExp(r'^`+|`+$'), '')
        .replaceAll(
          RegExp(r'^<tool_call>|</tool_call>$', caseSensitive: false),
          '',
        )
        .trim();
    if (cleaned.isEmpty) {
      return const <TextToolCall>[];
    }

    final xmlTaggedCall = _parseXmlTaggedToolCall(cleaned);
    if (xmlTaggedCall != null) {
      return <TextToolCall>[xmlTaggedCall];
    }

    final directCall = _parseHeuristicFunctionCall(cleaned);
    if (directCall != null) {
      return <TextToolCall>[directCall];
    }

    final calls = <TextToolCall>[];
    for (final rawLine in cleaned.split(RegExp(r'[\n;]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      final linePayload = line
          .replaceAll(RegExp(r'^<tool_call>\s*', caseSensitive: false), '')
          .replaceAll(RegExp(r'</tool_call>\s*$', caseSensitive: false), '')
          .trim();
      if (linePayload.isEmpty) {
        continue;
      }

      final parsedLineCall =
          _parseXmlTaggedToolCall(linePayload) ??
          _parseHeuristicFunctionCall(linePayload);
      if (parsedLineCall != null) {
        calls.add(parsedLineCall);
        continue;
      }

      if (_isKnownToolName(linePayload)) {
        calls.add(
          TextToolCall(name: linePayload, arguments: const <String, dynamic>{}),
        );
      }
    }
    return calls;
  }

  TextToolCall? _parseXmlTaggedToolCall(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      return null;
    }

    String? name;

    final nameTagMatch = RegExp(
      r'<(?:name|tool_name|tool)>\s*([^<]+?)\s*</(?:name|tool_name|tool)>',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (nameTagMatch != null) {
      name = nameTagMatch.group(1)?.trim();
    }

    if (name == null || name.isEmpty) {
      final leadingNameMatch = RegExp(
        r'^([A-Za-z_][A-Za-z0-9_\-]*)\b',
      ).firstMatch(normalized);
      if (leadingNameMatch != null) {
        name = leadingNameMatch.group(1)?.trim();
      }
    }

    if (name == null || name.isEmpty || !_isKnownToolName(name)) {
      return null;
    }

    final arguments = <String, dynamic>{};

    final explicitArgsMatch = RegExp(
      r'<arguments>\s*([\s\S]*?)\s*</arguments>',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (explicitArgsMatch != null) {
      final argumentsPayload = explicitArgsMatch.group(1)?.trim() ?? '';
      if (argumentsPayload.isNotEmpty) {
        final decoded = _decodeArguments(argumentsPayload);
        if (decoded.isNotEmpty) {
          arguments.addAll(decoded);
        }
      }
    }

    final argPairPattern = RegExp(
      r'<arg_key>\s*([\s\S]*?)\s*</arg_key>\s*'
      r'<arg_value>\s*([\s\S]*?)\s*</arg_value>',
      caseSensitive: false,
    );
    for (final match in argPairPattern.allMatches(normalized)) {
      final keyRaw = match.group(1) ?? '';
      final valueRaw = match.group(2) ?? '';
      final key = _stripXmlTags(keyRaw).trim();
      if (key.isEmpty) {
        continue;
      }
      arguments[key] = _parseLooseValue(_stripXmlTags(valueRaw));
    }

    final namedArgPattern = RegExp(
      r'<arg\s+name="([^"]+)">\s*([\s\S]*?)\s*</arg>',
      caseSensitive: false,
    );
    for (final match in namedArgPattern.allMatches(normalized)) {
      final key = (match.group(1) ?? '').trim();
      if (key.isEmpty) {
        continue;
      }
      arguments[key] = _parseLooseValue(_stripXmlTags(match.group(2) ?? ''));
    }

    if (arguments.isEmpty) {
      final inlineJsonArgumentsPattern = RegExp(
        r'^[A-Za-z_][A-Za-z0-9_\-]*\s*(\{[\s\S]*\})\s*$',
        dotAll: true,
      );
      final inlineJsonMatch = inlineJsonArgumentsPattern.firstMatch(normalized);
      if (inlineJsonMatch != null) {
        final decoded = _decodeArguments(inlineJsonMatch.group(1) ?? '');
        if (decoded.isNotEmpty) {
          arguments.addAll(decoded);
        }
      }
    }

    return TextToolCall(name: name, arguments: arguments);
  }

  TextToolCall? _parseHeuristicFunctionCall(String input) {
    final inlineJsonArgumentsPattern = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_\-]*)\s*(\{[\s\S]*\})\s*$',
      dotAll: true,
    );
    final inlineJsonMatch = inlineJsonArgumentsPattern.firstMatch(input);
    if (inlineJsonMatch != null) {
      final name = inlineJsonMatch.group(1)?.trim();
      if (name != null && _isKnownToolName(name)) {
        final arguments = _decodeArguments(inlineJsonMatch.group(2) ?? '');
        return TextToolCall(name: name, arguments: arguments);
      }
    }

    final functionCallPattern = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_\-]*)\s*(?:\((.*)\))?$',
      dotAll: true,
    );
    final match = functionCallPattern.firstMatch(input);
    if (match == null) {
      return null;
    }

    final name = match.group(1)?.trim();
    if (name == null || !_isKnownToolName(name)) {
      return null;
    }

    final argumentsText = match.group(2)?.trim();
    if (argumentsText == null || argumentsText.isEmpty) {
      return TextToolCall(name: name, arguments: const <String, dynamic>{});
    }

    final jsonLike =
        argumentsText.startsWith('{') && argumentsText.endsWith('}');
    if (jsonLike) {
      final parsed = _decodeArguments(argumentsText);
      return TextToolCall(name: name, arguments: parsed);
    }

    return TextToolCall(
      name: name,
      arguments: <String, dynamic>{'input': argumentsText},
    );
  }

  List<TextToolCall> _normalizeCalls(Object? decoded) {
    if (decoded is List) {
      final calls = <TextToolCall>[];
      for (final item in decoded) {
        if (item is Map) {
          final call = _toolCallFromMap(item);
          if (call != null) {
            calls.add(call);
          }
        }
      }
      return calls;
    }

    if (decoded is Map) {
      final asMap = decoded.map(
        (Object? key, Object? value) =>
            MapEntry(key?.toString() ?? 'unknown', value),
      );

      final nested = asMap['tool_calls'];
      if (nested is List) {
        return _normalizeCalls(nested);
      }

      final single = _toolCallFromMap(asMap);
      if (single != null) {
        return <TextToolCall>[single];
      }
    }

    return const <TextToolCall>[];
  }

  TextToolCall? _toolCallFromMap(Map<dynamic, dynamic> source) {
    final map = source.map(
      (dynamic key, dynamic value) =>
          MapEntry(key?.toString() ?? 'unknown', value),
    );

    String? name;
    Object? argumentsRaw;

    final directName = map['name'];
    final directTool = map['tool'];
    final directToolName = map['tool_name'];
    final function = map['function'];

    if (directName is String && directName.trim().isNotEmpty) {
      name = directName.trim();
      argumentsRaw = map['arguments'] ?? map['params'] ?? map['input'];
    } else if (directTool is String && directTool.trim().isNotEmpty) {
      name = directTool.trim();
      argumentsRaw = map['arguments'] ?? map['params'] ?? map['input'];
    } else if (directToolName is String && directToolName.trim().isNotEmpty) {
      name = directToolName.trim();
      argumentsRaw = map['arguments'] ?? map['params'] ?? map['input'];
    } else if (function is Map) {
      final functionMap = function.map(
        (dynamic key, dynamic value) =>
            MapEntry(key?.toString() ?? 'unknown', value),
      );
      final functionName = functionMap['name'];
      if (functionName is String && functionName.trim().isNotEmpty) {
        name = functionName.trim();
        argumentsRaw = functionMap['arguments'] ?? functionMap['params'];
      }
    }

    if (name == null || name.isEmpty || !_isKnownToolName(name)) {
      return null;
    }

    final arguments = _normalizeArguments(argumentsRaw);
    return TextToolCall(name: name, arguments: arguments);
  }

  Map<String, dynamic> _normalizeArguments(Object? raw) {
    if (raw is Map) {
      return raw.map(
        (Object? key, Object? value) =>
            MapEntry(key?.toString() ?? 'unknown', value),
      );
    }

    if (raw is String) {
      return _decodeArguments(raw);
    }

    return const <String, dynamic>{};
  }

  Object? _parseLooseValue(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final hasJsonShape =
        (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
    if (hasJsonShape) {
      try {
        return jsonDecode(trimmed);
      } catch (_) {
        // Fall through to scalar parsing.
      }
    }

    final asInt = int.tryParse(trimmed);
    if (asInt != null) {
      return asInt;
    }

    final asDouble = double.tryParse(trimmed);
    if (asDouble != null) {
      return asDouble;
    }

    final lowered = trimmed.toLowerCase();
    if (lowered == 'true') {
      return true;
    }
    if (lowered == 'false') {
      return false;
    }
    if (lowered == 'null') {
      return null;
    }

    return trimmed;
  }

  String _stripXmlTags(String value) {
    return value.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }

  Map<String, dynamic> _decodeArguments(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map(
          (Object? key, Object? value) =>
              MapEntry(key?.toString() ?? 'unknown', value),
        );
      }
    } catch (_) {
      return const <String, dynamic>{};
    }

    return const <String, dynamic>{};
  }

  bool _isKnownToolName(String name) {
    return _knownToolNames.contains(name);
  }
}
