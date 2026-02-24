import 'dart:async';

import 'package:llamadart/llamadart.dart' show LlamaChatMessage;
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
part 'coding_agent_tui_windows.part.dart';

class CodingAgentTui extends StatefulComponent {
  final CodingAgentConfig config;

  const CodingAgentTui({required this.config, super.key});

  @override
  State<CodingAgentTui> createState() => _CodingAgentTuiState();
}

class _CodingAgentTuiState extends State<CodingAgentTui> {
  late final CodingAgentSession _session;
  final TextEditingController _inputController = TextEditingController();

  final Map<String, int> _turnToolUsage = <String, int>{};
  final List<_WorkspaceSessionState> _workspaceSessions =
      <_WorkspaceSessionState>[];
  final List<_DesktopWindowState> _desktopWindows = <_DesktopWindowState>[];

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
  int _activeWorkspaceSessionIndex = 0;
  int _sessionCounter = 1;
  String _activeDesktopWindowId = '';
  String? _draggingWindowId;
  int _dragOffsetX = 0;
  int _dragOffsetY = 0;
  String? _resizingWindowId;
  int _resizeOriginPointerX = 0;
  int _resizeOriginPointerY = 0;
  int _resizeOriginWidth = 0;
  int _resizeOriginHeight = 0;
  int _desktopWidth = 0;
  int _desktopHeight = 0;
  bool _desktopInitialized = false;
  String _status = 'Initializing...';

  _WorkspaceSessionState get _activeWorkspaceSession =>
      _workspaceSessions[_activeWorkspaceSessionIndex];

  List<_AgentMessage> get _messages => _activeWorkspaceSession.messages;

  @override
  void initState() {
    super.initState();
    _session = CodingAgentSession(component.config);
    _initializeWorkspaceSessions();
    _initializeDesktopWindows();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final sessionState in _workspaceSessions) {
      _disposeWorkspaceSessionState(sessionState);
    }
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
          Expanded(child: _buildDesktopArea()),
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
            Positioned.fill(
              top: 1,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeTopMenu,
                child: SizedBox.expand(),
              ),
            ),
          if (_openTopMenuIndex != null && !_showExitConfirm)
            _buildTopMenuDropdownOverlay(),
          if (_showExitConfirm) _buildExitConfirmationOverlay(),
        ],
      ),
    );
  }

  Component _buildMessagesView({
    List<_AgentMessage>? messages,
    AutoScrollController? controller,
  }) {
    final visibleMessages = messages ?? _messages;
    final scrollController =
        controller ?? _activeWorkspaceSession.scrollController;

    if (visibleMessages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet. Ask a coding question.',
          style: TextStyle(color: Colors.gray),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(1),
      decoration: BoxDecoration(color: _turboBluePanel),
      child: ListView.builder(
        controller: scrollController,
        padding: EdgeInsets.all(1),
        itemCount: visibleMessages.length,
        itemBuilder: (BuildContext context, int index) {
          return _MessageRow(message: visibleMessages[index]);
        },
      ),
    );
  }

  Component _buildInputBar({required bool focused}) {
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
            child: ClipRect(
              child: TextField(
                controller: _inputController,
                focused: focused,
                enabled: focused && !_busy && !_showExitConfirm,
                placeholder: _busy
                    ? 'Assistant is working...'
                    : (focused
                          ? 'Ask for code edits, tests, or analysis... (/ + TAB for commands)'
                          : 'Activate the Chat window (F6/mouse) to type'),
                placeholderStyle: TextStyle(color: Colors.brightBlack),
                style: TextStyle(color: Colors.brightWhite),
                onChanged: _handleInputChanged,
                onKeyEvent: _handleInputKeyEvent,
                onSubmitted: (_) => _submitInput(),
              ),
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
    final activeWindowLabel = _activeDesktopWindowLabel();
    final detail = _slashAutocompleteHint.isNotEmpty
        ? _slashAutocompleteHint
        : _status;
    final sessionWindowSummary =
        activeWindowLabel == _activeWorkspaceSession.title
        ? _activeWorkspaceSession.title
        : '${_activeWorkspaceSession.title} [$activeWindowLabel]';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
      decoration: BoxDecoration(
        color: _turboStatusBarBackground,
        border: BoxBorder(top: BorderSide(color: _turboDialogBorderLight)),
      ),
      child: Row(
        children: <Component>[
          _buildStatusShortcut(key: 'F1', label: 'Help'),
          SizedBox(width: 1),
          _buildStatusShortcut(key: 'F2', label: 'Model'),
          SizedBox(width: 1),
          _buildStatusShortcut(key: 'F3', label: 'Clear'),
          SizedBox(width: 1),
          _buildStatusShortcut(key: 'F5', label: 'Zoom'),
          SizedBox(width: 1),
          _buildStatusShortcut(key: 'F10', label: 'Menu'),
          SizedBox(width: 1),
          _buildStatusShortcut(key: 'Alt+X', label: 'Exit'),
          SizedBox(width: 1),
          Text('|', style: TextStyle(color: _turboMenuText)),
          SizedBox(width: 1),
          Expanded(
            child: Text(detail, style: TextStyle(color: _turboMenuText)),
          ),
          Text(
            sessionWindowSummary,
            style: TextStyle(color: _turboDialogTextDim),
          ),
          SizedBox(width: 1),
          Text(
            _busy ? 'BUSY' : 'READY',
            style: TextStyle(
              color: _busy ? Colors.brightRed : Colors.brightBlue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Component _buildStatusShortcut({required String key, required String label}) {
    return RichText(
      text: TextSpan(
        style: TextStyle(color: _turboMenuText),
        children: <InlineSpan>[
          TextSpan(
            text: key,
            style: TextStyle(
              color: _turboMenuMnemonic,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: ' $label'),
        ],
      ),
    );
  }
}

enum _ExitChoice { yes, no }
