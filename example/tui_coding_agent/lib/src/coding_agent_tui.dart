import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:path/path.dart' as p;

import 'coding_agent_config.dart';
import 'coding_agent_session.dart';
import 'model_source_resolver.dart';
import 'session_event.dart';
import 'workspace_tools.dart';

part 'coding_agent_tui_catalog.part.dart';
part 'coding_agent_tui_input_handlers.part.dart';
part 'coding_agent_tui_menu_dialog.part.dart';
part 'coding_agent_tui_messages.part.dart';
part 'coding_agent_tui_theme.part.dart';

class CodingAgentTui extends StatefulComponent {
  final CodingAgentConfig config;

  const CodingAgentTui({required this.config, super.key});

  @override
  State<CodingAgentTui> createState() => _CodingAgentTuiState();
}

class _CodingAgentTuiState extends State<CodingAgentTui> {
  late final CodingAgentSession _session;
  final AutoScrollController _scrollController = AutoScrollController();
  final TextEditingController _inputController = TextEditingController();

  final List<_AgentMessage> _messages = <_AgentMessage>[];
  final Map<String, int> _turnToolUsage = <String, int>{};

  bool _busy = false;
  bool _ready = false;
  int? _activeAssistantMessageIndex;
  int? _toolSummaryMessageIndex;
  int _turnToolCallCount = 0;
  int _turnToolResultCount = 0;
  int _turnToolFailureCount = 0;
  bool _showExitConfirm = false;
  _ExitChoice _exitConfirmChoice = _ExitChoice.no;
  int? _openTopMenuIndex;
  int _openTopMenuItemIndex = 0;
  String _slashAutocompleteHint = '';
  List<String> _slashAutocompleteMatches = const <String>[];
  String _slashAutocompletePrefix = '';
  int _slashAutocompleteIndex = -1;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _session = CodingAgentSession(component.config);
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _session.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _pushMessage(
      role: _AgentRole.system,
      text:
          'Loading model. Default source: ${component.config.modelSource}. This may take a while on first run.',
    );

    try {
      await _session.initialize(
        onStatus: _setStatus,
        onProgress: (ModelDownloadProgress progress) {
          final fraction = progress.fraction;
          if (fraction == null) {
            final mb = progress.receivedBytes / (1024 * 1024);
            _setStatus('Downloading model... ${mb.toStringAsFixed(1)} MB');
            return;
          }
          final percent = (fraction * 100).toStringAsFixed(1);
          _setStatus('Downloading model... $percent%');
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _ready = true;
        _status = 'Ready.';
      });

      _pushMessage(
        role: _AgentRole.system,
        text:
            'Model ready: ${_displayModelName()} (${_session.enableNativeToolCalling ? 'native tools' : 'stable text tools'}). '
            'Type /help for commands. Workspace: ${workspaceDisplayPath(_session.workspaceRoot)}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _status = 'Initialization failed.';
      });
      _pushMessage(
        role: _AgentRole.error,
        text: 'Failed to initialize session: $error',
      );
    }
  }

  void _setStatus(String status) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
    });
  }

  void _handleSessionEvent(SessionEvent event) {
    if (!mounted) {
      return;
    }

    setState(() {
      switch (event.type) {
        case SessionEventType.status:
          _status = event.message;
          break;
        case SessionEventType.assistantToken:
          final index = _activeAssistantMessageIndex;
          if (index == null || index >= _messages.length) {
            _activeAssistantMessageIndex = _appendMessage(
              role: _AgentRole.assistant,
              text: event.message,
            );
          } else {
            final updatedText = _messages[index].text + event.message;
            _messages[index] = _messages[index].copyWith(text: updatedText);
          }
          break;
        case SessionEventType.toolCall:
          _recordToolCall(event.message);
          break;
        case SessionEventType.toolResult:
          _recordToolResult(event.message);
          break;
        case SessionEventType.error:
          _finalizeTurnToolSummary();
          _appendMessage(role: _AgentRole.error, text: event.message);
          break;
      }
    });
  }

  void _resetTurnToolStats() {
    _turnToolUsage.clear();
    _turnToolCallCount = 0;
    _turnToolResultCount = 0;
    _turnToolFailureCount = 0;
    _toolSummaryMessageIndex = null;
  }

  void _recordToolCall(String callMessage) {
    _turnToolCallCount += 1;
    final toolName = _extractToolName(callMessage);
    _turnToolUsage[toolName] = (_turnToolUsage[toolName] ?? 0) + 1;
    _status = 'Running tools...';
    _upsertToolSummaryMessage(inProgress: true);
  }

  void _recordToolResult(String resultMessage) {
    _turnToolResultCount += 1;
    if (resultMessage.toLowerCase().contains('failed')) {
      _turnToolFailureCount += 1;
    }
    _upsertToolSummaryMessage(inProgress: true);
  }

  void _finalizeTurnToolSummary() {
    if (_turnToolCallCount == 0) {
      return;
    }
    _upsertToolSummaryMessage(inProgress: false);
  }

  void _upsertToolSummaryMessage({required bool inProgress}) {
    final summary = _buildToolSummaryText(inProgress: inProgress);
    final index = _toolSummaryMessageIndex;
    if (index == null || index < 0 || index >= _messages.length) {
      _toolSummaryMessageIndex = _appendMessage(
        role: _AgentRole.tool,
        text: summary,
      );
      return;
    }

    _messages[index] = _messages[index].copyWith(text: summary);
  }

  String _buildToolSummaryText({required bool inProgress}) {
    final topTools = _turnToolUsage.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    final topPreview = topTools
        .take(3)
        .map((entry) => '${entry.key} x${entry.value}')
        .join(', ');
    final extraCount = topTools.length - topTools.take(3).length;
    final extra = extraCount > 0 ? ', +$extraCount more' : '';

    final failure = _turnToolFailureCount > 0
        ? ', $_turnToolFailureCount failed'
        : '';

    if (inProgress) {
      return '$_turnToolCallCount call(s), $_turnToolResultCount result(s) '
          'so far: $topPreview$extra$failure';
    }

    return 'Used $_turnToolCallCount tool call(s) '
        'across ${_turnToolUsage.length} tool(s): $topPreview$extra$failure';
  }

  String _extractToolName(String callMessage) {
    final trimmed = callMessage.trim();
    final openParen = trimmed.indexOf('(');
    if (openParen <= 0) {
      return trimmed.isEmpty ? 'tool' : trimmed;
    }
    return trimmed.substring(0, openParen).trim();
  }

  int _appendMessage({required _AgentRole role, required String text}) {
    _messages.add(_AgentMessage(role: role, text: text));
    return _messages.length - 1;
  }

  void _pushMessage({required _AgentRole role, required String text}) {
    if (!mounted) {
      return;
    }

    setState(() {
      _appendMessage(role: role, text: text);
    });
  }

  String _displayModelName() {
    final loadedPath = _session.loadedModelPath;
    if (loadedPath == null || loadedPath.trim().isEmpty) {
      return _session.modelSource;
    }
    return p.basename(loadedPath);
  }

  @override
  Component build(BuildContext context) {
    final shell = Container(
      decoration: BoxDecoration(color: _turboBlueBackground),
      child: Column(
        children: <Component>[
          _buildTopMenuBar(),
          _buildHeader(),
          Expanded(child: _buildMessagesView()),
          _buildInputBar(),
          _buildSlashSuggestionsBar(),
          _buildStatusBar(),
        ],
      ),
    );

    return KeyboardListener(
      autofocus: true,
      onKeyEvent: _handleGlobalLogicalKey,
      child: Stack(
        children: <Component>[
          shell,
          if (_openTopMenuIndex != null && !_showExitConfirm)
            _buildTopMenuDropdownOverlay(),
          if (_showExitConfirm) _buildExitConfirmationOverlay(),
        ],
      ),
    );
  }

  Component _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
      decoration: BoxDecoration(
        color: _turboBlueHeader,
        border: BoxBorder(bottom: BorderSide(color: Colors.brightWhite)),
      ),
      child: Row(
        children: <Component>[
          Text(
            'llamadart agent',
            style: TextStyle(
              color: Colors.brightWhite,
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          Text(
            'model: ${_displayModelName()}',
            style: TextStyle(color: Colors.brightCyan),
          ),
        ],
      ),
    );
  }

  Component _buildMessagesView() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Ask a coding question.',
          style: TextStyle(color: Colors.gray),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: _turboBluePanel,
        border: BoxBorder.all(color: Colors.brightWhite),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _turboBluePanel,
          border: BoxBorder.all(color: Colors.brightCyan),
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.all(1),
            itemCount: _messages.length,
            itemBuilder: (BuildContext context, int index) {
              return _MessageRow(message: _messages[index]);
            },
          ),
        ),
      ),
    );
  }

  Component _buildInputBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      decoration: BoxDecoration(
        border: BoxBorder(top: BorderSide(color: Colors.brightCyan)),
        color: _turboBlueHeader,
      ),
      child: Row(
        children: <Component>[
          Text('> ', style: TextStyle(color: Colors.brightYellow)),
          Expanded(
            child: TextField(
              controller: _inputController,
              focused: true,
              enabled: !_busy || _showExitConfirm,
              placeholder: _busy
                  ? 'Assistant is working...'
                  : 'Ask for code edits, tests, or analysis... (/ + TAB for commands)',
              placeholderStyle: TextStyle(color: Colors.brightBlack),
              style: TextStyle(color: Colors.brightWhite),
              onChanged: _handleInputChanged,
              onKeyEvent: _handleInputKeyEvent,
              onSubmitted: (_) => _submitInput(),
            ),
          ),
        ],
      ),
    );
  }

  Component _buildSlashSuggestionsBar() {
    if (_showExitConfirm) {
      return SizedBox(height: 0);
    }

    final parsed = _parseSlashInput(_inputController.text);
    if (parsed == null || _slashAutocompleteMatches.isEmpty) {
      return SizedBox(height: 0);
    }

    final selectedIndex =
        _slashAutocompleteIndex >= 0 &&
            _slashAutocompleteIndex < _slashAutocompleteMatches.length
        ? _slashAutocompleteIndex
        : 0;
    final selected = _slashAutocompleteMatches[selectedIndex];
    final preview = _slashAutocompleteMatches
        .take(5)
        .map((command) => command == selected ? '[$command]' : command)
        .join('  ');
    final hidden =
        _slashAutocompleteMatches.length -
        _slashAutocompleteMatches.take(5).length;
    final suffix = hidden > 0 ? '  +$hidden' : '';
    final usage = _slashCommandUsage[selected] ?? selected;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
      decoration: BoxDecoration(
        color: _turboBluePanel,
        border: BoxBorder(top: BorderSide(color: Colors.brightCyan)),
      ),
      child: Text(
        'slash: $preview$suffix   -> $usage',
        style: TextStyle(color: Colors.brightCyan),
      ),
    );
  }

  Component _buildStatusBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 1, vertical: 1),
      decoration: BoxDecoration(
        color: _turboBlueHeader,
        border: BoxBorder(top: BorderSide(color: Colors.brightCyan)),
      ),
      child: Row(
        children: <Component>[
          Text(
            _busy ? '[busy]' : '[ready]',
            style: TextStyle(
              color: _busy ? Colors.yellow : Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 1),
          Expanded(
            child: Text(_status, style: TextStyle(color: Colors.brightWhite)),
          ),
          Text(
            _slashAutocompleteHint.isNotEmpty
                ? _slashAutocompleteHint
                : 'F1 HELP  F2 MODEL  F3 CLEAR  ESC STOP/EXIT  TAB COMPLETE  ALT+menu letter',
            style: TextStyle(color: Colors.brightYellow),
          ),
        ],
      ),
    );
  }
}

enum _ExitChoice { yes, no }
