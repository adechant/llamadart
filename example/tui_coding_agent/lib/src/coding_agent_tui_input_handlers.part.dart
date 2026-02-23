part of 'coding_agent_tui.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _CodingAgentTuiInputHandlers on _CodingAgentTuiState {
  void _handleInputChanged(String value) {
    if (!mounted) {
      return;
    }

    setState(() {
      _updateSlashAutocompleteState(value, resetCycle: true);
    });
  }

  bool _handleGlobalLogicalKey(LogicalKey key) {
    if (_showExitConfirm) {
      return _handleExitConfirmationLogicalKey(key);
    }

    if (_openTopMenuIndex != null) {
      if (key == LogicalKey.escape) {
        _closeTopMenu();
        return true;
      }
      if (key == LogicalKey.arrowLeft) {
        _moveTopMenu(reverse: true);
        return true;
      }
      if (key == LogicalKey.arrowRight) {
        _moveTopMenu(reverse: false);
        return true;
      }
      if (key == LogicalKey.arrowUp) {
        _moveTopMenuItem(reverse: true);
        return true;
      }
      if (key == LogicalKey.arrowDown) {
        _moveTopMenuItem(reverse: false);
        return true;
      }
      if (key == LogicalKey.enter) {
        _activateTopMenuItem();
        return true;
      }
    }

    if (key == LogicalKey.f1) {
      _handleSlashCommand('/help');
      return true;
    }
    if (key == LogicalKey.f2) {
      _seedInput('/model ');
      return true;
    }
    if (key == LogicalKey.f3) {
      _clearConversation();
      return true;
    }
    if (key == LogicalKey.escape) {
      if (_busy) {
        _cancelInferenceFromShortcut();
      } else {
        _requestExitConfirmation();
      }
      return true;
    }
    return false;
  }

  bool _handleInputKeyEvent(KeyboardEvent event) {
    if (_showExitConfirm) {
      return _handleExitConfirmationKeyboardEvent(event);
    }

    if (_handleTopMenuHotKey(event)) {
      return true;
    }

    if (_openTopMenuIndex != null) {
      if (_handleTopMenuKeyboardEvent(event)) {
        return true;
      }
      _closeTopMenu(updateStatus: false);
    }

    if (event.matches(LogicalKey.f1) ||
        event.matches(LogicalKey.keyH, ctrl: true)) {
      _handleSlashCommand('/help');
      return true;
    }
    if (event.matches(LogicalKey.f2) ||
        event.matches(LogicalKey.keyM, ctrl: true)) {
      _seedInput('/model ');
      return true;
    }
    if (event.matches(LogicalKey.f3) ||
        event.matches(LogicalKey.keyL, ctrl: true)) {
      _clearConversation();
      return true;
    }
    if (event.matches(LogicalKey.escape) ||
        event.matches(LogicalKey.keyQ, ctrl: true)) {
      if (_busy) {
        _cancelInferenceFromShortcut();
      } else {
        _requestExitConfirmation();
      }
      return true;
    }
    if (event.matches(LogicalKey.arrowDown)) {
      return _autocompleteSlash(reverse: false);
    }
    if (event.matches(LogicalKey.arrowUp)) {
      return _autocompleteSlash(reverse: true);
    }
    if (event.matches(LogicalKey.tab)) {
      return _autocompleteSlash(reverse: event.isShiftPressed);
    }
    return false;
  }

  void _seedInput(String value) {
    if (!mounted) {
      return;
    }

    setState(() {
      _inputController.text = value;
      _inputController.selection = TextSelection.collapsed(
        offset: value.length,
      );
      _updateSlashAutocompleteState(value, resetCycle: true);
      _status = 'Input prepared: $value';
    });
  }

  bool _handleTopMenuHotKey(KeyboardEvent event) {
    if (!event.isAltPressed) {
      return false;
    }

    final mnemonic = _menuMnemonicFromEvent(event);
    if (mnemonic == null) {
      return false;
    }

    final menuIndex = _topMenus.indexWhere(
      (menu) => menu.mnemonic.toLowerCase() == mnemonic,
    );
    if (menuIndex < 0) {
      return false;
    }

    _toggleTopMenu(menuIndex);
    return true;
  }

  String? _menuMnemonicFromEvent(KeyboardEvent event) {
    final fromCharacter = event.character?.toLowerCase();
    if (fromCharacter != null && fromCharacter.length == 1) {
      return fromCharacter;
    }

    final key = event.logicalKey;
    if (key == LogicalKey.keyF) {
      return 'f';
    }
    if (key == LogicalKey.keyE) {
      return 'e';
    }
    if (key == LogicalKey.keyS) {
      return 's';
    }
    if (key == LogicalKey.keyR) {
      return 'r';
    }
    if (key == LogicalKey.keyC) {
      return 'c';
    }
    if (key == LogicalKey.keyD) {
      return 'd';
    }
    if (key == LogicalKey.keyP) {
      return 'p';
    }
    if (key == LogicalKey.keyO) {
      return 'o';
    }
    if (key == LogicalKey.keyW) {
      return 'w';
    }
    if (key == LogicalKey.keyH) {
      return 'h';
    }
    return null;
  }

  bool _handleTopMenuKeyboardEvent(KeyboardEvent event) {
    if (_openTopMenuIndex == null) {
      return false;
    }

    if (event.matches(LogicalKey.escape)) {
      _closeTopMenu();
      return true;
    }

    if (event.matches(LogicalKey.enter)) {
      _activateTopMenuItem();
      return true;
    }

    if (event.matches(LogicalKey.arrowLeft) ||
        (event.matches(LogicalKey.tab) && event.isShiftPressed)) {
      _moveTopMenu(reverse: true);
      return true;
    }

    if (event.matches(LogicalKey.arrowRight) ||
        event.matches(LogicalKey.tab, shift: false)) {
      _moveTopMenu(reverse: false);
      return true;
    }

    if (event.matches(LogicalKey.arrowUp)) {
      _moveTopMenuItem(reverse: true);
      return true;
    }

    if (event.matches(LogicalKey.arrowDown)) {
      _moveTopMenuItem(reverse: false);
      return true;
    }

    return false;
  }

  bool _handleExitConfirmationKeyboardEvent(KeyboardEvent event) {
    if (event.matches(LogicalKey.tab) ||
        event.matches(LogicalKey.arrowUp) ||
        event.matches(LogicalKey.arrowDown) ||
        event.matches(LogicalKey.arrowLeft) ||
        event.matches(LogicalKey.arrowRight)) {
      _toggleExitConfirmChoice();
      return true;
    }
    return _handleExitConfirmationLogicalKey(event.logicalKey);
  }

  bool _handleExitConfirmationLogicalKey(LogicalKey key) {
    if (key == LogicalKey.enter) {
      _acceptExitConfirmChoice();
      return true;
    }
    if (key == LogicalKey.keyY) {
      _setExitConfirmChoice(_ExitChoice.yes);
      _acceptExitConfirmChoice();
      return true;
    }
    if (key == LogicalKey.escape || key == LogicalKey.keyN) {
      _setExitConfirmChoice(_ExitChoice.no);
      _acceptExitConfirmChoice();
      return true;
    }
    if (key == LogicalKey.arrowLeft ||
        key == LogicalKey.arrowUp ||
        key == LogicalKey.keyH ||
        key == LogicalKey.arrowRight ||
        key == LogicalKey.arrowDown ||
        key == LogicalKey.keyL ||
        key == LogicalKey.tab) {
      _toggleExitConfirmChoice();
      return true;
    }
    return true;
  }

  void _toggleTopMenu(int menuIndex) {
    if (!mounted) {
      return;
    }

    setState(() {
      if (_openTopMenuIndex == menuIndex) {
        _openTopMenuIndex = null;
        _status = _busy
            ? 'Generation in progress...'
            : (_ready ? 'Ready.' : _status);
        return;
      }

      _openTopMenuIndex = menuIndex;
      _openTopMenuItemIndex = 0;
      _status =
          'Menu: ${_topMenus[menuIndex].label} (arrows/tab navigate, Enter select, Esc close)';
    });
  }

  void _closeTopMenu({bool updateStatus = true}) {
    if (!mounted) {
      return;
    }
    if (_openTopMenuIndex == null) {
      return;
    }

    setState(() {
      _openTopMenuIndex = null;
      _openTopMenuItemIndex = 0;
      if (updateStatus) {
        _status = _busy
            ? 'Generation in progress...'
            : (_ready ? 'Ready.' : _status);
      }
    });
  }

  void _moveTopMenu({required bool reverse}) {
    if (!mounted) {
      return;
    }

    final current = _openTopMenuIndex;
    if (current == null) {
      return;
    }

    var next = current + (reverse ? -1 : 1);
    if (next < 0) {
      next = _topMenus.length - 1;
    }
    if (next >= _topMenus.length) {
      next = 0;
    }

    setState(() {
      _openTopMenuIndex = next;
      _openTopMenuItemIndex = 0;
      _status =
          'Menu: ${_topMenus[next].label} (arrows/tab navigate, Enter select, Esc close)';
    });
  }

  void _moveTopMenuItem({required bool reverse}) {
    if (!mounted) {
      return;
    }

    final menuIndex = _openTopMenuIndex;
    if (menuIndex == null) {
      return;
    }

    final items = _topMenus[menuIndex].items;
    if (items.isEmpty) {
      return;
    }

    var next = _openTopMenuItemIndex + (reverse ? -1 : 1);
    if (next < 0) {
      next = items.length - 1;
    }
    if (next >= items.length) {
      next = 0;
    }

    setState(() {
      _openTopMenuItemIndex = next;
    });
  }

  void _activateTopMenuItem() {
    final menuIndex = _openTopMenuIndex;
    if (menuIndex == null) {
      return;
    }

    final items = _topMenus[menuIndex].items;
    if (items.isEmpty) {
      return;
    }

    final safeIndex = _openTopMenuItemIndex.clamp(0, items.length - 1);
    final item = items[safeIndex];
    _runTopMenuCommand(item.command);
  }

  void _runTopMenuCommand(String command) {
    _closeTopMenu(updateStatus: false);

    if (command.endsWith(' ')) {
      _seedInput(command);
      return;
    }

    unawaited(_handleSlashCommand(command));
  }

  void _setExitConfirmChoice(_ExitChoice choice) {
    if (!mounted) {
      return;
    }

    setState(() {
      _exitConfirmChoice = choice;
      final selected = _exitConfirmChoice == _ExitChoice.yes ? 'YES' : 'NO';
      _status =
          'Confirm exit: Left/Right/Tab choose option, Enter confirms ($selected).';
    });
  }

  void _toggleExitConfirmChoice() {
    if (!mounted) {
      return;
    }

    setState(() {
      _exitConfirmChoice = _exitConfirmChoice == _ExitChoice.yes
          ? _ExitChoice.no
          : _ExitChoice.yes;
      final selected = _exitConfirmChoice == _ExitChoice.yes ? 'YES' : 'NO';
      _status =
          'Confirm exit: Left/Right/Tab choose option, Enter confirms ($selected).';
    });
  }

  void _acceptExitConfirmChoice() {
    if (_exitConfirmChoice == _ExitChoice.yes) {
      _confirmExit();
      return;
    }
    _dismissExitConfirmation();
  }

  bool _autocompleteSlash({required bool reverse}) {
    final parsed = _parseSlashInput(_inputController.text);
    if (parsed == null) {
      return false;
    }

    final computedMatches = _slashCommandNames
        .where((command) => command.startsWith(parsed.commandPrefix))
        .toList(growable: false);
    final selectedFromPreviousCycle =
        _slashAutocompleteIndex >= 0 &&
            _slashAutocompleteIndex < _slashAutocompleteMatches.length
        ? _slashAutocompleteMatches[_slashAutocompleteIndex]
        : null;

    final continuePreviousCycle =
        computedMatches.length <= 1 &&
        _slashAutocompleteMatches.length > 1 &&
        selectedFromPreviousCycle != null &&
        parsed.commandPrefix == selectedFromPreviousCycle;

    final matches = continuePreviousCycle
        ? _slashAutocompleteMatches
        : computedMatches;
    if (matches.isEmpty) {
      return false;
    }

    setState(() {
      final isSamePrefix = _slashAutocompletePrefix == parsed.commandPrefix;
      final isSameMatches = _sameStringList(_slashAutocompleteMatches, matches);

      if (!isSamePrefix || !isSameMatches || _slashAutocompleteIndex < 0) {
        _slashAutocompleteIndex = reverse ? matches.length - 1 : 0;
      } else {
        _slashAutocompleteIndex += reverse ? -1 : 1;
        if (_slashAutocompleteIndex < 0) {
          _slashAutocompleteIndex = matches.length - 1;
        }
        if (_slashAutocompleteIndex >= matches.length) {
          _slashAutocompleteIndex = 0;
        }
      }

      final selected = matches[_slashAutocompleteIndex];
      final commandSeed = _slashCommandSeed(selected, hasArgs: parsed.hasArgs);
      final nextValue =
          parsed.leadingWhitespace + commandSeed + parsed.argsSuffix;

      _inputController.text = nextValue;
      _inputController.selection = TextSelection.collapsed(
        offset: nextValue.length,
      );
      _slashAutocompleteMatches = matches;
      _slashAutocompletePrefix = continuePreviousCycle
          ? _slashAutocompletePrefix
          : parsed.commandPrefix;
      _slashAutocompleteHint =
          'autocomplete ${_slashAutocompleteIndex + 1}/${matches.length}: $selected';
    });

    return true;
  }

  ({
    String leadingWhitespace,
    String commandPrefix,
    String argsSuffix,
    bool hasArgs,
  })?
  _parseSlashInput(String input) {
    final leadingWhitespace = RegExp(r'^\s*').stringMatch(input) ?? '';
    final trimmed = input.substring(leadingWhitespace.length);
    if (!trimmed.startsWith('/')) {
      return null;
    }

    final firstSpace = trimmed.indexOf(' ');
    if (firstSpace < 0) {
      return (
        leadingWhitespace: leadingWhitespace,
        commandPrefix: trimmed,
        argsSuffix: '',
        hasArgs: false,
      );
    }

    final commandPrefix = trimmed.substring(0, firstSpace);
    final argsSuffix = trimmed.substring(firstSpace);
    return (
      leadingWhitespace: leadingWhitespace,
      commandPrefix: commandPrefix,
      argsSuffix: argsSuffix,
      hasArgs: argsSuffix.trim().isNotEmpty,
    );
  }

  String _slashCommandSeed(String command, {required bool hasArgs}) {
    if (hasArgs) {
      return command;
    }
    if (command == '/model') {
      return '/model ';
    }
    return command;
  }

  void _updateSlashAutocompleteState(String input, {required bool resetCycle}) {
    final parsed = _parseSlashInput(input);
    if (parsed == null) {
      _slashAutocompleteHint = '';
      _slashAutocompleteMatches = const <String>[];
      _slashAutocompletePrefix = '';
      if (resetCycle) {
        _slashAutocompleteIndex = -1;
      }
      return;
    }

    final matches = _slashCommandNames
        .where((command) => command.startsWith(parsed.commandPrefix))
        .toList(growable: false);
    _slashAutocompleteMatches = matches;
    _slashAutocompletePrefix = parsed.commandPrefix;
    if (resetCycle) {
      _slashAutocompleteIndex = -1;
    }

    if (matches.isEmpty) {
      _slashAutocompleteHint =
          'no slash command matches ${parsed.commandPrefix}';
      return;
    }

    if (matches.length == 1) {
      final only = matches.first;
      _slashAutocompleteHint =
          'TAB complete: ${_slashCommandUsage[only] ?? only}';
      return;
    }

    final preview = matches.take(4).join('  ');
    final hidden = matches.length - matches.take(4).length;
    final suffix = hidden > 0 ? '  +$hidden' : '';
    _slashAutocompleteHint = 'TAB cycle: $preview$suffix';
  }

  bool _sameStringList(List<String> a, List<String> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  void _cancelInferenceFromShortcut() {
    _session.cancelGeneration();
    if (!mounted) {
      return;
    }

    setState(() {
      _busy = false;
      _status = 'Generation cancelled.';
    });
  }

  void _requestExitConfirmation() {
    if (!mounted) {
      return;
    }

    setState(() {
      _openTopMenuIndex = null;
      _openTopMenuItemIndex = 0;
      _showExitConfirm = true;
      _exitConfirmChoice = _ExitChoice.no;
      _status =
          'Confirm exit: Left/Right/Tab choose option, Enter confirms (NO).';
    });
  }

  void _dismissExitConfirmation() {
    if (!mounted) {
      return;
    }

    setState(() {
      _showExitConfirm = false;
      _exitConfirmChoice = _ExitChoice.no;
      _status = _busy
          ? 'Generation in progress...'
          : (_ready ? 'Ready.' : _status);
    });
  }

  void _confirmExit() {
    if (_busy) {
      _session.cancelGeneration();
    }
    shutdownApp(0);
  }

  void _clearConversation() {
    if (!mounted) {
      return;
    }

    if (_busy) {
      _session.cancelGeneration();
    }

    setState(() {
      _messages.clear();
      _activeAssistantMessageIndex = null;
      _toolSummaryMessageIndex = null;
      _resetTurnToolStats();
      _busy = false;
      _showExitConfirm = false;
      _exitConfirmChoice = _ExitChoice.no;
      _openTopMenuIndex = null;
      _openTopMenuItemIndex = 0;
      _updateSlashAutocompleteState('', resetCycle: true);
      _status = 'Conversation cleared.';
    });
    _session.resetConversation();
  }

  Future<void> _submitInput() async {
    final input = _inputController.text.trim();
    if (input.isEmpty) {
      return;
    }

    if (_showExitConfirm) {
      return;
    }

    if (_openTopMenuIndex != null) {
      _closeTopMenu(updateStatus: false);
    }

    _inputController.clear();

    if (input.startsWith('/')) {
      await _handleSlashCommand(input);
      return;
    }

    if (!_ready) {
      _pushMessage(
        role: _AgentRole.error,
        text: 'Model is not ready yet. Please wait.',
      );
      return;
    }

    if (_busy) {
      _pushMessage(
        role: _AgentRole.error,
        text: 'A request is already in progress. Use /cancel if needed.',
      );
      return;
    }

    _pushMessage(role: _AgentRole.user, text: input);
    setState(() {
      _busy = true;
      _activeAssistantMessageIndex = null;
      _resetTurnToolStats();
      _updateSlashAutocompleteState('', resetCycle: true);
      _status = 'Generating response...';
    });

    try {
      await _session.runPrompt(input, onEvent: _handleSessionEvent);
    } catch (error) {
      _pushMessage(role: _AgentRole.error, text: 'Generation failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _finalizeTurnToolSummary();
          _busy = false;
          _status = 'Ready.';
          _activeAssistantMessageIndex = null;
        });
      }
    }
  }

  Future<void> _handleSlashCommand(String input) async {
    final command = input.trim();

    if (command == '/help') {
      _pushMessage(
        role: _AgentRole.system,
        text:
            'Commands:\n'
            '/help - show this help\n'
            '/clear - clear chat log\n'
            '/model - show current model\n'
            '/model <path|url|owner/repo[:hint]> - switch model\n'
            '/workspace - print workspace root\n'
            '/cancel - cancel current generation\n'
            '/exit - open exit confirmation\n'
            'TAB/Shift+TAB or Up/Down - slash command autocomplete\n'
            'Menus: Alt+menu letter (File/Edit/Search/Run/Compile/Debug/Project/Options/Window/Help)\n'
            'Shortcuts: F1/Ctrl+H help, F2/Ctrl+M model, F3/Ctrl+L clear, ESC cancel-or-exit-confirm, Ctrl+Q exit confirm\n'
            'Tool mode: ${_session.enableNativeToolCalling ? 'native (experimental)' : 'stable text protocol'}',
      );
      return;
    }

    if (command == '/clear' || command == '/reset') {
      _clearConversation();
      return;
    }

    if (command == '/workspace') {
      _pushMessage(
        role: _AgentRole.system,
        text: 'Workspace: ${workspaceDisplayPath(_session.workspaceRoot)}',
      );
      return;
    }

    if (command == '/cancel') {
      _cancelInferenceFromShortcut();
      _pushMessage(role: _AgentRole.system, text: 'Generation cancelled.');
      return;
    }

    if (command == '/exit' || command == '/quit') {
      _requestExitConfirmation();
      return;
    }

    if (command == '/model') {
      _pushMessage(
        role: _AgentRole.system,
        text:
            'Requested source: ${_session.modelSource}\n'
            'Loaded path: ${_session.loadedModelPath ?? '(not loaded)'}\n'
            'Tool mode: ${_session.enableNativeToolCalling ? 'native (experimental)' : 'stable text protocol'}',
      );
      return;
    }

    if (command.startsWith('/model ')) {
      final source = command.substring('/model '.length).trim();
      if (source.isEmpty) {
        _pushMessage(
          role: _AgentRole.error,
          text: 'Usage: /model <path|url|owner/repo[:hint]>',
        );
        return;
      }

      if (_busy) {
        _pushMessage(
          role: _AgentRole.error,
          text: 'Cannot switch model while a generation is in progress.',
        );
        return;
      }

      setState(() {
        _busy = true;
        _status = 'Switching model...';
      });
      _pushMessage(role: _AgentRole.system, text: 'Switching model to $source');

      try {
        await _session.switchModel(
          source,
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

        _pushMessage(
          role: _AgentRole.system,
          text: 'Model switched to ${_displayModelName()}. Conversation reset.',
        );
        _session.resetConversation();
      } catch (error) {
        _pushMessage(
          role: _AgentRole.error,
          text: 'Failed to switch model: $error',
        );
      } finally {
        if (mounted) {
          setState(() {
            _busy = false;
            _status = 'Ready.';
          });
        }
      }

      return;
    }

    _pushMessage(
      role: _AgentRole.error,
      text: 'Unknown command: $command. Type /help.',
    );
  }
}
