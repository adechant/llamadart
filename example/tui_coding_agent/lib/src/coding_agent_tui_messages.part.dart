part of 'coding_agent_tui.dart';

enum _AgentRole { system, user, assistant, tool, error }

class _AgentMessage {
  final _AgentRole role;
  final String text;

  const _AgentMessage({required this.role, required this.text});

  _AgentMessage copyWith({_AgentRole? role, String? text}) {
    return _AgentMessage(role: role ?? this.role, text: text ?? this.text);
  }
}

class _MessageRow extends StatelessComponent {
  final _AgentMessage message;

  const _MessageRow({required this.message});

  @override
  Component build(BuildContext context) {
    final content = _buildMessageContent(message);

    final label = switch (message.role) {
      _AgentRole.system => 'system',
      _AgentRole.user => 'you',
      _AgentRole.assistant => 'assistant',
      _AgentRole.tool => 'tool',
      _AgentRole.error => 'error',
    };

    final color = switch (message.role) {
      _AgentRole.system => Colors.brightYellow,
      _AgentRole.user => Colors.brightGreen,
      _AgentRole.assistant => Colors.brightCyan,
      _AgentRole.tool => Colors.brightMagenta,
      _AgentRole.error => Colors.brightRed,
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Component>[
          Text(
            '[$label] ',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

Component _buildMessageContent(_AgentMessage message) {
  switch (message.role) {
    case _AgentRole.assistant:
      return RichText(text: _buildAssistantSpan(message.text));
    case _AgentRole.tool:
      return Text(
        _formatToolMessage(message.text),
        style: TextStyle(color: Colors.brightMagenta),
      );
    case _AgentRole.system:
      return Text(message.text, style: TextStyle(color: Colors.brightWhite));
    case _AgentRole.user:
      return Text(message.text, style: TextStyle(color: Colors.brightWhite));
    case _AgentRole.error:
      return Text(message.text, style: TextStyle(color: Colors.brightRed));
  }
}

InlineSpan _buildAssistantSpan(String markdown) {
  final normalized = markdown.replaceAll('\r\n', '\n');
  final children = <InlineSpan>[];
  final codeBlockPattern = RegExp(
    r'^\s*```+\s*([a-zA-Z0-9_+\-]*)\s*\n([\s\S]*?)^\s*```+\s*$',
    multiLine: true,
  );

  var cursor = 0;
  for (final match in codeBlockPattern.allMatches(normalized)) {
    if (match.start > cursor) {
      _appendTextOrUnclosedCodeSegment(
        children,
        normalized.substring(cursor, match.start),
      );
    }

    final language = (match.group(1) ?? '').trim().toLowerCase();
    final code = (match.group(2) ?? '').replaceAll('\r\n', '\n').trimRight();
    if (code.isNotEmpty) {
      if (children.isNotEmpty && !children.last.toPlainText().endsWith('\n')) {
        children.add(TextSpan(text: '\n', style: _assistantTextStyle));
      }
      children.addAll(_buildCodeBlockSpans(code, language: language));
      children.add(TextSpan(text: '\n', style: _assistantTextStyle));
    }

    cursor = match.end;
  }

  if (cursor < normalized.length) {
    _appendTextOrUnclosedCodeSegment(children, normalized.substring(cursor));
  }

  if (children.isEmpty) {
    return TextSpan(
      text: _renderMarkdownLikeText(markdown),
      style: _assistantTextStyle,
    );
  }

  return TextSpan(style: _assistantTextStyle, children: children);
}

void _appendTextOrUnclosedCodeSegment(
  List<InlineSpan> children,
  String textSegment,
) {
  final unclosedFencePattern = RegExp(
    r'^([\s\S]*?)^\s*```+\s*([a-zA-Z0-9_+\-]*)\s*\n([\s\S]*)$',
    multiLine: true,
  );
  final unclosedFenceMatch = unclosedFencePattern.firstMatch(textSegment);
  if (unclosedFenceMatch == null) {
    _appendRenderedTextSegment(children, textSegment);
    return;
  }

  final textPrefix = unclosedFenceMatch.group(1) ?? '';
  _appendRenderedTextSegment(children, textPrefix);

  final language = (unclosedFenceMatch.group(2) ?? '').trim().toLowerCase();
  final trailingCode = (unclosedFenceMatch.group(3) ?? '')
      .replaceAll('\r\n', '\n')
      .trimRight();
  if (trailingCode.isEmpty) {
    return;
  }

  if (children.isNotEmpty && !children.last.toPlainText().endsWith('\n')) {
    children.add(TextSpan(text: '\n', style: _assistantTextStyle));
  }
  children.addAll(_buildCodeBlockSpans(trailingCode, language: language));
}

void _appendRenderedTextSegment(List<InlineSpan> children, String textSegment) {
  final renderedText = _renderMarkdownLikeText(textSegment);
  if (renderedText.isEmpty) {
    return;
  }
  children.add(TextSpan(text: renderedText, style: _assistantTextStyle));
}

List<InlineSpan> _buildCodeBlockSpans(String code, {required String language}) {
  final spans = <InlineSpan>[];
  final languageLabel = language.isEmpty ? 'code' : language;
  final lines = code.split('\n');
  var contentWidth = 18;
  for (final line in lines) {
    final length = line.replaceAll('\t', '  ').length;
    if (length > contentWidth) {
      contentWidth = length;
    }
  }
  if (contentWidth > 88) {
    contentWidth = 88;
  }

  final topBorder = '+${_repeatChar('-', contentWidth + 2)}+';
  spans.add(TextSpan(text: '$topBorder\n', style: _codeFrameStyle));

  final headerText = ' ${languageLabel.toUpperCase()} ';
  final headerFill = contentWidth + 2 - headerText.length;
  final headerSuffix = headerFill > 0 ? _repeatChar('-', headerFill) : '';
  spans.add(
    TextSpan(text: '|$headerText$headerSuffix|\n', style: _codeHeaderStyle),
  );

  for (var i = 0; i < lines.length; i++) {
    final fittedLine = _fitCodeLineForFrame(lines[i], contentWidth);
    spans.add(TextSpan(text: '| ', style: _codeFrameStyle));
    spans.addAll(_highlightCodeLine(fittedLine));
    spans.add(TextSpan(text: ' |', style: _codeFrameStyle));
    if (i < lines.length - 1) {
      spans.add(TextSpan(text: '\n', style: _codeFrameStyle));
    }
  }

  spans.add(TextSpan(text: '\n$topBorder', style: _codeFrameStyle));

  return spans;
}

String _fitCodeLineForFrame(String line, int width) {
  final expanded = line.replaceAll('\t', '  ');
  if (expanded.length <= width) {
    return expanded.padRight(width);
  }
  if (width <= 3) {
    return expanded.substring(0, width);
  }
  return '${expanded.substring(0, width - 3)}...';
}

String _repeatChar(String char, int count) {
  if (count <= 0) {
    return '';
  }
  return List<String>.filled(count, char).join();
}

List<InlineSpan> _highlightCodeLine(String line) {
  if (line.isEmpty) {
    return <InlineSpan>[TextSpan(text: '', style: _codeDefaultStyle)];
  }

  final commentIndex = _findCommentStart(line);
  if (commentIndex == 0) {
    return <InlineSpan>[TextSpan(text: line, style: _codeCommentStyle)];
  }

  final codePart = commentIndex > 0 ? line.substring(0, commentIndex) : line;
  final commentPart = commentIndex > 0 ? line.substring(commentIndex) : null;

  final spans = <InlineSpan>[];
  spans.addAll(_highlightCodePart(codePart));
  if (commentPart != null && commentPart.isNotEmpty) {
    spans.add(TextSpan(text: commentPart, style: _codeCommentStyle));
  }

  return spans;
}

List<InlineSpan> _highlightCodePart(String codePart) {
  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final match in _codeTokenPattern.allMatches(codePart)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(
          text: codePart.substring(cursor, match.start),
          style: _codeDefaultStyle,
        ),
      );
    }

    final token = match.group(0) ?? '';
    final nextChar = _nextNonWhitespaceChar(codePart, match.end);
    final isFunctionCall =
        _identifierTokenPattern.hasMatch(token) &&
        !_codeKeywords.contains(token) &&
        nextChar == '(';
    spans.add(
      TextSpan(
        text: token,
        style: _styleForCodeToken(token, isFunctionCall: isFunctionCall),
      ),
    );
    cursor = match.end;
  }

  if (cursor < codePart.length) {
    spans.add(
      TextSpan(text: codePart.substring(cursor), style: _codeDefaultStyle),
    );
  }

  if (spans.isEmpty) {
    spans.add(TextSpan(text: codePart, style: _codeDefaultStyle));
  }

  return spans;
}

TextStyle _styleForCodeToken(String token, {required bool isFunctionCall}) {
  if (token.startsWith('@')) {
    return _codeAnnotationStyle;
  }

  if (token.startsWith('"') || token.startsWith("'") || token.startsWith('`')) {
    return _codeStringStyle;
  }

  if (_numberTokenPattern.hasMatch(token)) {
    return _codeNumberStyle;
  }

  if (_operatorTokenPattern.hasMatch(token)) {
    return _codeOperatorStyle;
  }

  if (_codeKeywords.contains(token)) {
    return _codeKeywordStyle;
  }

  if (_codeConstants.contains(token)) {
    return _codeConstantStyle;
  }

  if (isFunctionCall) {
    return _codeFunctionStyle;
  }

  if (_typeNamePattern.hasMatch(token)) {
    return _codeTypeStyle;
  }

  return _codeDefaultStyle;
}

String? _nextNonWhitespaceChar(String value, int startIndex) {
  for (var i = startIndex; i < value.length; i++) {
    final char = value[i];
    if (char.trim().isNotEmpty) {
      return char;
    }
  }
  return null;
}

int _findCommentStart(String line) {
  var inSingle = false;
  var inDouble = false;
  var inBacktick = false;
  var escaped = false;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];

    if (escaped) {
      escaped = false;
      continue;
    }

    if (char == '\\') {
      escaped = true;
      continue;
    }

    if (!inDouble && !inBacktick && char == "'") {
      inSingle = !inSingle;
      continue;
    }
    if (!inSingle && !inBacktick && char == '"') {
      inDouble = !inDouble;
      continue;
    }
    if (!inSingle && !inDouble && char == '`') {
      inBacktick = !inBacktick;
      continue;
    }

    if (inSingle || inDouble || inBacktick) {
      continue;
    }

    if (char == '/' && i + 1 < line.length && line[i + 1] == '/') {
      return i;
    }
    if (char == '#') {
      final isLineStart = i == 0;
      final prev = isLineStart ? ' ' : line[i - 1];
      if (isLineStart || prev.trim().isEmpty) {
        return i;
      }
    }
  }

  return -1;
}

String _renderMarkdownLikeText(String input) {
  var text = input.replaceAll('\r\n', '\n');

  text = text.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (Match match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'\*\*([^*]+)\*\*'),
    (Match match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    RegExp(r'__([^_]+)__'),
    (Match match) => match.group(1) ?? '',
  );

  text = text.replaceAllMapped(
    RegExp(r'^(#{1,6})\s+(.+)$', multiLine: true),
    (Match match) => (match.group(2) ?? '').toUpperCase(),
  );

  text = text.replaceAllMapped(
    RegExp(r'^\s*[-*]\s+', multiLine: true),
    (_) => '• ',
  );

  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

String _formatToolMessage(String text) {
  final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return _truncateDisplayText(compact, 200);
}

String _truncateDisplayText(String text, int maxChars) {
  if (text.length <= maxChars) {
    return text;
  }
  return '${text.substring(0, maxChars)}...';
}
