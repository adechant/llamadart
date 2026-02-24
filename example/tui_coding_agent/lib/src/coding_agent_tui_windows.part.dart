part of 'coding_agent_tui.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _CodingAgentTuiWindows on _CodingAgentTuiState {
  bool _handleDesktopWindowKeyboardEvent(KeyboardEvent event) {
    if (event.matches(LogicalKey.f5)) {
      _toggleActiveDesktopWindowZoom();
      return true;
    }

    if (event.matches(LogicalKey.f4)) {
      _switchToNextWorkspaceSession(reverse: true);
      return true;
    }

    if (event.matches(LogicalKey.f6)) {
      _focusNextDesktopWindow(reverse: event.isShiftPressed);
      return true;
    }

    if (event.matches(LogicalKey.f7)) {
      _createWorkspaceSession();
      return true;
    }

    if (event.matches(LogicalKey.f8)) {
      _switchToNextWorkspaceSession(reverse: event.isShiftPressed);
      return true;
    }

    if (event.matches(LogicalKey.f9)) {
      _focusNextDesktopWindow(reverse: true);
      return true;
    }

    if (event.matches(LogicalKey.f12) ||
        event.matches(LogicalKey.keyW, alt: true)) {
      _closeActiveWorkspaceSession();
      return true;
    }

    if (event.matches(LogicalKey.arrowLeft, alt: true, shift: true)) {
      _resizeActiveWindow(-1, 0);
      return true;
    }
    if (event.matches(LogicalKey.arrowRight, alt: true, shift: true)) {
      _resizeActiveWindow(1, 0);
      return true;
    }
    if (event.matches(LogicalKey.arrowUp, alt: true, shift: true)) {
      _resizeActiveWindow(0, -1);
      return true;
    }
    if (event.matches(LogicalKey.arrowDown, alt: true, shift: true)) {
      _resizeActiveWindow(0, 1);
      return true;
    }

    if (event.matches(LogicalKey.arrowLeft, alt: true)) {
      _nudgeActiveWindow(-1, 0);
      return true;
    }
    if (event.matches(LogicalKey.arrowRight, alt: true)) {
      _nudgeActiveWindow(1, 0);
      return true;
    }
    if (event.matches(LogicalKey.arrowUp, alt: true)) {
      _nudgeActiveWindow(0, -1);
      return true;
    }
    if (event.matches(LogicalKey.arrowDown, alt: true)) {
      _nudgeActiveWindow(0, 1);
      return true;
    }

    return false;
  }

  void _syncActiveWorkspaceHistorySnapshot() {
    _activeWorkspaceSession.history = _session.snapshotConversationHistory();
  }

  void _initializeWorkspaceSessions() {
    final first = _createWorkspaceSessionState();
    _workspaceSessions.add(first);
  }

  void _initializeDesktopWindows() {
    final firstWindow = _buildSessionDesktopWindow(
      _workspaceSessions.first,
      sequence: 0,
    );

    _desktopWindows
      ..clear()
      ..add(firstWindow);
    _activeDesktopWindowId = firstWindow.id;
    _applySessionWindowTitles();
  }

  _WorkspaceSessionState _createWorkspaceSessionState() {
    final ordinal = _sessionCounter;
    _sessionCounter += 1;
    final scrollController = AutoScrollController();
    scrollController.addListener(_handleWorkspaceSessionScroll);

    return _WorkspaceSessionState(
      id: 'session_$ordinal',
      title: 'Session $ordinal',
      history: <LlamaChatMessage>[],
      messages: <_AgentMessage>[],
      scrollController: scrollController,
    );
  }

  void _handleWorkspaceSessionScroll() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _disposeWorkspaceSessionState(_WorkspaceSessionState sessionState) {
    sessionState.scrollController.removeListener(_handleWorkspaceSessionScroll);
    sessionState.scrollController.dispose();
  }

  void _saveActiveWorkspaceHistory() {
    _activeWorkspaceSession.history = _session.snapshotConversationHistory();
  }

  void _restoreWorkspaceHistory(_WorkspaceSessionState state) {
    _session.restoreConversationHistory(state.history);
  }

  String _sessionWindowId(String sessionId) {
    return '$_sessionChatWindowPrefix$sessionId';
  }

  int _workspaceSessionIndexById(String sessionId) {
    for (var i = 0; i < _workspaceSessions.length; i++) {
      if (_workspaceSessions[i].id == sessionId) {
        return i;
      }
    }
    return -1;
  }

  _WorkspaceSessionState? _workspaceSessionById(String sessionId) {
    final index = _workspaceSessionIndexById(sessionId);
    if (index < 0) {
      return null;
    }
    return _workspaceSessions[index];
  }

  String _activeDesktopWindowLabel() {
    final activeWindow = _desktopWindowById(_activeDesktopWindowId);
    if (activeWindow == null) {
      return 'None';
    }

    final sessionId = activeWindow.sessionId;
    if (sessionId == null) {
      return activeWindow.title;
    }

    final session = _workspaceSessionById(sessionId);
    return session?.title ?? activeWindow.title;
  }

  _DesktopWindowState _buildSessionDesktopWindow(
    _WorkspaceSessionState session, {
    required int sequence,
  }) {
    final baseWidth = _desktopWidth > 0 ? _desktopWidth - 32 : 72;
    final baseHeight = _desktopHeight > 0 ? _desktopHeight - 4 : 18;
    final width = _clampInt(
      baseWidth,
      44,
      _desktopWidth > 0 ? _desktopWidth : 72,
    );
    final height = _clampInt(
      baseHeight,
      12,
      _desktopHeight > 0 ? _desktopHeight : 18,
    );
    final left = 1 + (sequence % 4) * 2;
    final top = 1 + (sequence % 4);

    return _DesktopWindowState(
      id: _sessionWindowId(session.id),
      sessionId: session.id,
      title: session.title,
      left: left,
      top: top,
      width: width,
      height: height,
      minWidth: 44,
      minHeight: 12,
    );
  }

  void _applySessionWindowTitles() {
    for (var i = 0; i < _desktopWindows.length; i++) {
      final window = _desktopWindows[i];
      final sessionId = window.sessionId;
      if (sessionId == null) {
        continue;
      }

      final sessionIndex = _workspaceSessionIndexById(sessionId);
      if (sessionIndex < 0) {
        continue;
      }

      final title = _workspaceSessions[sessionIndex].title;
      _desktopWindows[i] = window.copyWith(title: title);
    }
  }

  void _createWorkspaceSession() {
    if (_busy) {
      _pushMessage(
        role: _AgentRole.error,
        text: 'Cannot create a new session while generation is in progress.',
      );
      return;
    }

    _saveActiveWorkspaceHistory();
    final next = _createWorkspaceSessionState();
    next.messages.add(
      _AgentMessage(
        role: _AgentRole.system,
        text:
            '${next.title} ready. This session starts with a clean model context.',
      ),
    );

    setState(() {
      _workspaceSessions.add(next);
      _activeWorkspaceSessionIndex = _workspaceSessions.length - 1;
      final window = _buildSessionDesktopWindow(
        next,
        sequence: _workspaceSessions.length - 1,
      );
      _desktopWindows.add(window);
      _activeDesktopWindowId = window.id;
      _activeAssistantMessageIndex = null;
      _toolSummaryMessageIndex = null;
      _resetTurnToolStats();
      _inputController.clear();
      _updateSlashAutocompleteState('', resetCycle: true);
      _status = 'Created ${next.title}.';
      _applySessionWindowTitles();
    });

    _session.resetConversation();
  }

  void _switchWorkspaceSession(int index, {bool focusWindow = true}) {
    if (index < 0 || index >= _workspaceSessions.length) {
      return;
    }

    if (_busy) {
      _pushMessage(
        role: _AgentRole.error,
        text: 'Cannot switch sessions while generation is in progress.',
      );
      return;
    }

    if (index == _activeWorkspaceSessionIndex) {
      if (focusWindow) {
        _focusDesktopWindow(
          _sessionWindowId(_workspaceSessions[index].id),
          syncSession: false,
        );
      }
      return;
    }

    _saveActiveWorkspaceHistory();

    setState(() {
      _activeWorkspaceSessionIndex = index;
      _activeAssistantMessageIndex = null;
      _toolSummaryMessageIndex = null;
      _resetTurnToolStats();
      _inputController.clear();
      _updateSlashAutocompleteState('', resetCycle: true);
      _status = 'Switched to ${_activeWorkspaceSession.title}.';
      _applySessionWindowTitles();
    });

    _restoreWorkspaceHistory(_activeWorkspaceSession);
    if (focusWindow) {
      _focusDesktopWindow(
        _sessionWindowId(_activeWorkspaceSession.id),
        syncSession: false,
      );
    }
  }

  void _switchToNextWorkspaceSession({required bool reverse}) {
    if (_workspaceSessions.length <= 1) {
      _focusDesktopWindow(_sessionWindowId(_activeWorkspaceSession.id));
      return;
    }

    var next = _activeWorkspaceSessionIndex + (reverse ? -1 : 1);
    if (next < 0) {
      next = _workspaceSessions.length - 1;
    }
    if (next >= _workspaceSessions.length) {
      next = 0;
    }
    _switchWorkspaceSession(next);
  }

  void _closeActiveWorkspaceSession() {
    _closeWorkspaceSessionAt(_activeWorkspaceSessionIndex);
  }

  void _closeWorkspaceSessionAt(int index) {
    if (index < 0 || index >= _workspaceSessions.length) {
      return;
    }

    if (_workspaceSessions.length <= 1) {
      _pushMessage(
        role: _AgentRole.system,
        text: 'At least one session must remain open.',
      );
      return;
    }
    if (_busy) {
      _pushMessage(
        role: _AgentRole.error,
        text: 'Cannot close a session while generation is in progress.',
      );
      return;
    }

    _saveActiveWorkspaceHistory();

    final removedSessionId = _workspaceSessions[index].id;
    final removedTitle = _workspaceSessions[index].title;
    final removedSessionState = _workspaceSessions[index];
    final removedWasActive = index == _activeWorkspaceSessionIndex;
    final removedWindowId = _sessionWindowId(removedSessionId);

    setState(() {
      _workspaceSessions.removeAt(index);
      final removedWindowIndex = _desktopWindowIndex(removedWindowId);
      if (removedWindowIndex >= 0) {
        _desktopWindows.removeAt(removedWindowIndex);
      }

      if (removedWasActive) {
        if (_activeWorkspaceSessionIndex >= _workspaceSessions.length) {
          _activeWorkspaceSessionIndex = _workspaceSessions.length - 1;
        }

        _activeDesktopWindowId = _sessionWindowId(_activeWorkspaceSession.id);
      } else if (index < _activeWorkspaceSessionIndex) {
        _activeWorkspaceSessionIndex -= 1;
      }

      if (removedWasActive) {
        _activeAssistantMessageIndex = null;
        _toolSummaryMessageIndex = null;
        _resetTurnToolStats();
        _inputController.clear();
        _updateSlashAutocompleteState('', resetCycle: true);
      }

      _status = 'Closed $removedTitle.';
      _applySessionWindowTitles();
    });

    if (removedWasActive) {
      _restoreWorkspaceHistory(_activeWorkspaceSession);
      _focusDesktopWindow(
        _sessionWindowId(_activeWorkspaceSession.id),
        syncSession: false,
      );
    }

    _disposeWorkspaceSessionState(removedSessionState);
  }

  void _resetAllWorkspaceHistories() {
    for (final sessionState in _workspaceSessions) {
      sessionState.history = <LlamaChatMessage>[];
    }
  }

  void _resetAllWorkspaceMessages({required String systemNotice}) {
    if (!mounted) {
      return;
    }

    setState(() {
      for (final sessionState in _workspaceSessions) {
        sessionState.messages.clear();
      }
      _activeWorkspaceSession.messages.add(
        _AgentMessage(role: _AgentRole.system, text: systemNotice),
      );
      _activeAssistantMessageIndex = null;
      _toolSummaryMessageIndex = null;
      _resetTurnToolStats();
      _showExitConfirm = false;
      _exitConfirmChoice = _ExitChoice.no;
      _openTopMenuIndex = null;
      _openTopMenuItemIndex = 0;
      _updateSlashAutocompleteState('', resetCycle: true);
    });
  }

  void _focusNextDesktopWindow({required bool reverse}) {
    if (_desktopWindows.isEmpty) {
      return;
    }

    final currentIndex = _desktopWindowIndex(_activeDesktopWindowId);
    if (currentIndex < 0) {
      _focusDesktopWindow(_desktopWindows.last.id);
      return;
    }

    var next = currentIndex + (reverse ? -1 : 1);
    if (next < 0) {
      next = _desktopWindows.length - 1;
    }
    if (next >= _desktopWindows.length) {
      next = 0;
    }
    _focusDesktopWindow(_desktopWindows[next].id);
  }

  void _arrangeDesktopWindowsTiled() {
    if (_desktopWindows.isEmpty) {
      return;
    }

    if (_desktopWidth <= 0 || _desktopHeight <= 0) {
      setState(() {
        _status = 'Desktop layout is not ready yet.';
      });
      return;
    }

    var minWidth = 1;
    var minHeight = 1;
    for (final window in _desktopWindows) {
      if (window.minWidth > minWidth) {
        minWidth = window.minWidth;
      }
      if (window.minHeight > minHeight) {
        minHeight = window.minHeight;
      }
    }

    var maxColumnsByWidth = _desktopWidth ~/ minWidth;
    if (maxColumnsByWidth < 1) {
      maxColumnsByWidth = 1;
    }
    if (maxColumnsByWidth > _desktopWindows.length) {
      maxColumnsByWidth = _desktopWindows.length;
    }

    var selectedColumns = 1;
    var selectedRows = _desktopWindows.length;
    var foundExactFit = false;

    for (var columns = 1; columns <= maxColumnsByWidth; columns++) {
      final rows = (_desktopWindows.length + columns - 1) ~/ columns;
      final fitsHeight = rows * minHeight <= _desktopHeight;
      if (!fitsHeight) {
        continue;
      }

      if (!foundExactFit ||
          _isBetterTileGrid(columns, rows, selectedColumns, selectedRows)) {
        selectedColumns = columns;
        selectedRows = rows;
        foundExactFit = true;
      }
    }

    if (!foundExactFit) {
      selectedColumns = maxColumnsByWidth;
      selectedRows =
          (_desktopWindows.length + selectedColumns - 1) ~/ selectedColumns;
    }

    final columnWidths = List<int>.filled(
      selectedColumns,
      _desktopWidth ~/ selectedColumns,
    );
    final extraWidth = _desktopWidth % selectedColumns;
    for (var i = 0; i < extraWidth; i++) {
      columnWidths[i] += 1;
    }

    final rowHeights = List<int>.filled(
      selectedRows,
      _desktopHeight ~/ selectedRows,
    );
    final extraHeight = _desktopHeight % selectedRows;
    for (var i = 0; i < extraHeight; i++) {
      rowHeights[i] += 1;
    }

    final columnLefts = List<int>.filled(selectedColumns, 0);
    var currentLeft = 0;
    for (var i = 0; i < selectedColumns; i++) {
      columnLefts[i] = currentLeft;
      currentLeft += columnWidths[i];
    }

    final rowTops = List<int>.filled(selectedRows, 0);
    var currentTop = 0;
    for (var i = 0; i < selectedRows; i++) {
      rowTops[i] = currentTop;
      currentTop += rowHeights[i];
    }

    setState(() {
      for (var i = 0; i < _desktopWindows.length; i++) {
        final row = i ~/ selectedColumns;
        final column = i % selectedColumns;
        final window = _desktopWindows[i];
        final restored = window.maximized
            ? _restoreWindowFromZoom(window)
            : window;
        final tiled = restored.copyWith(
          left: columnLefts[column],
          top: rowTops[row],
          width: columnWidths[column],
          height: rowHeights[row],
          maximized: false,
          clearRestore: true,
        );
        _desktopWindows[i] = _clampDesktopWindow(tiled);
      }

      _status = foundExactFit
          ? 'Tiled ${_desktopWindows.length} windows.'
          : 'Tiled ${_desktopWindows.length} windows (tight fit).';
    });
  }

  void _arrangeDesktopWindowsStacked() {
    if (_desktopWindows.isEmpty) {
      return;
    }

    if (_desktopWidth <= 0 || _desktopHeight <= 0) {
      setState(() {
        _status = 'Desktop layout is not ready yet.';
      });
      return;
    }

    final targetWidth = _clampInt(_desktopWidth - 2, 44, _desktopWidth);
    final targetHeight = _clampInt(_desktopHeight - 2, 12, _desktopHeight);
    final maxLeftOffset = _desktopWidth - targetWidth;
    final maxTopOffset = _desktopHeight - targetHeight;
    const horizontalStep = 2;
    const verticalStep = 1;

    var cycleByX = 1;
    if (maxLeftOffset > 0) {
      cycleByX = (maxLeftOffset ~/ horizontalStep) + 1;
    }

    var cycleByY = 1;
    if (maxTopOffset > 0) {
      cycleByY = (maxTopOffset ~/ verticalStep) + 1;
    }

    final shorterCycle = cycleByX < cycleByY ? cycleByX : cycleByY;
    final offsetCycle = _clampInt(shorterCycle, 1, _desktopWindows.length);

    setState(() {
      for (var i = 0; i < _desktopWindows.length; i++) {
        final offsetIndex = offsetCycle <= 1 ? 0 : i % offsetCycle;
        final left = _clampInt(offsetIndex * horizontalStep, 0, maxLeftOffset);
        final top = _clampInt(offsetIndex * verticalStep, 0, maxTopOffset);

        final window = _desktopWindows[i];
        final restored = window.maximized
            ? _restoreWindowFromZoom(window)
            : window;
        final stacked = restored.copyWith(
          left: left,
          top: top,
          width: targetWidth,
          height: targetHeight,
          maximized: false,
          clearRestore: true,
        );
        _desktopWindows[i] = _clampDesktopWindow(stacked);
      }

      _status = 'Stacked ${_desktopWindows.length} windows.';
    });
  }

  bool _isBetterTileGrid(int columns, int rows, int bestColumns, int bestRows) {
    final imbalance = (columns - rows).abs();
    final bestImbalance = (bestColumns - bestRows).abs();
    if (imbalance != bestImbalance) {
      return imbalance < bestImbalance;
    }

    return columns > bestColumns;
  }

  void _focusDesktopWindow(String id, {bool syncSession = true}) {
    final index = _desktopWindowIndex(id);
    if (index < 0) {
      return;
    }

    final windowToFocus = _desktopWindows[index];

    setState(() {
      final window = _desktopWindows.removeAt(index);
      _desktopWindows.add(window);
      _activeDesktopWindowId = id;
      _status = 'Focused ${window.title}.';
    });

    if (!syncSession) {
      return;
    }

    final sessionId = windowToFocus.sessionId;
    if (sessionId == null) {
      return;
    }
    final targetSessionIndex = _workspaceSessionIndexById(sessionId);
    if (targetSessionIndex < 0 ||
        targetSessionIndex == _activeWorkspaceSessionIndex) {
      return;
    }

    _switchWorkspaceSession(targetSessionIndex, focusWindow: false);
  }

  void _toggleDesktopWindowZoom(String id) {
    _focusDesktopWindow(id);
    _toggleActiveDesktopWindowZoom();
  }

  void _nudgeActiveWindow(int dx, int dy) {
    _updateDesktopWindow(_activeDesktopWindowId, (window) {
      final editableWindow = window.maximized
          ? _restoreWindowFromZoom(window)
          : window;
      return _clampDesktopWindow(
        editableWindow.copyWith(
          left: editableWindow.left + dx,
          top: editableWindow.top + dy,
        ),
      );
    });
  }

  void _resizeActiveWindow(int dw, int dh) {
    _updateDesktopWindow(_activeDesktopWindowId, (window) {
      final editableWindow = window.maximized
          ? _restoreWindowFromZoom(window)
          : window;
      return _clampDesktopWindow(
        editableWindow.copyWith(
          width: editableWindow.width + dw,
          height: editableWindow.height + dh,
        ),
      );
    });
  }

  void _toggleActiveDesktopWindowZoom() {
    final current = _desktopWindowById(_activeDesktopWindowId);
    if (current == null) {
      return;
    }
    final willMaximize = !current.maximized;

    _updateDesktopWindow(_activeDesktopWindowId, (window) {
      if (_desktopWidth <= 0 || _desktopHeight <= 0) {
        return window;
      }

      if (window.maximized) {
        return _clampDesktopWindow(_restoreWindowFromZoom(window));
      }

      return _clampDesktopWindow(
        window.copyWith(
          left: 0,
          top: 0,
          width: _desktopWidth,
          height: _desktopHeight,
          maximized: true,
          restoreLeft: window.left,
          restoreTop: window.top,
          restoreWidth: window.width,
          restoreHeight: window.height,
        ),
      );
    });

    if (mounted) {
      setState(() {
        _status = willMaximize
            ? 'Zoomed ${current.title}.'
            : 'Restored ${current.title}.';
      });
    }
  }

  _DesktopWindowState _restoreWindowFromZoom(_DesktopWindowState window) {
    return window.copyWith(
      left: window.restoreLeft ?? window.left,
      top: window.restoreTop ?? window.top,
      width: window.restoreWidth ?? window.width,
      height: window.restoreHeight ?? window.height,
      maximized: false,
      clearRestore: true,
    );
  }

  void _startWindowDrag(String id, TapDownDetails details) {
    if ((_draggingWindowId != null && _draggingWindowId != id) ||
        (_resizingWindowId != null && _resizingWindowId != id)) {
      return;
    }

    _focusDesktopWindow(id);
    var window = _desktopWindowById(id);
    if (window == null) {
      return;
    }

    if (window.maximized) {
      final restored = _restoreWindowFromZoom(window);
      _updateDesktopWindow(id, (_) => _clampDesktopWindow(restored));
      window = restored;
    }

    final dragWindow = window;

    final pointerX = details.globalPosition.dx.round();
    final pointerY = details.globalPosition.dy.round() - _desktopTopOffset;
    setState(() {
      _resizingWindowId = null;
      _draggingWindowId = id;
      _dragOffsetX = pointerX - dragWindow.left;
      _dragOffsetY = pointerY - dragWindow.top;
    });
  }

  void _startWindowResize(String id, TapDownDetails details) {
    if ((_draggingWindowId != null && _draggingWindowId != id) ||
        (_resizingWindowId != null && _resizingWindowId != id)) {
      return;
    }

    _focusDesktopWindow(id);
    var window = _desktopWindowById(id);
    if (window == null) {
      return;
    }

    if (window.maximized) {
      final restored = _restoreWindowFromZoom(window);
      _updateDesktopWindow(id, (_) => _clampDesktopWindow(restored));
      window = restored;
    }

    final resizeWindow = window;

    setState(() {
      _draggingWindowId = null;
      _resizingWindowId = id;
      _resizeOriginPointerX = details.globalPosition.dx.round();
      _resizeOriginPointerY =
          details.globalPosition.dy.round() - _desktopTopOffset;
      _resizeOriginWidth = resizeWindow.width;
      _resizeOriginHeight = resizeWindow.height;
    });
  }

  void _handleDesktopMouseHover(MouseEvent event) {
    final pointerDown = event.isPrimaryButtonDown;
    if (!pointerDown) {
      if (_draggingWindowId != null || _resizingWindowId != null) {
        setState(() {
          _draggingWindowId = null;
          _resizingWindowId = null;
        });
      }
      return;
    }

    final draggingId = _draggingWindowId;
    if (draggingId != null) {
      final window = _desktopWindowById(draggingId);
      if (window == null) {
        return;
      }

      final pointerY = event.y - _desktopTopOffset;
      final next = window.copyWith(
        left: event.x - _dragOffsetX,
        top: pointerY - _dragOffsetY,
      );
      _updateDesktopWindow(draggingId, (_) => _clampDesktopWindow(next));
      return;
    }

    final resizingId = _resizingWindowId;
    if (resizingId != null) {
      final window = _desktopWindowById(resizingId);
      if (window == null) {
        return;
      }

      final pointerY = event.y - _desktopTopOffset;
      final widthDelta = event.x - _resizeOriginPointerX;
      final heightDelta = pointerY - _resizeOriginPointerY;
      final next = window.copyWith(
        width: _resizeOriginWidth + widthDelta,
        height: _resizeOriginHeight + heightDelta,
      );
      _updateDesktopWindow(resizingId, (_) => _clampDesktopWindow(next));
    }
  }

  void _syncDesktopLayout(int width, int height) {
    if (width <= 0 || height <= 0) {
      return;
    }

    _desktopWidth = width;
    _desktopHeight = height;

    if (!_desktopInitialized) {
      final safeChatWidth = _clampInt(width - 2, 44, width);
      final safeChatHeight = _clampInt(height - 2, 12, height);

      var sessionWindowSequence = 0;
      for (var i = 0; i < _desktopWindows.length; i++) {
        final window = _desktopWindows[i];
        final cascade = sessionWindowSequence;
        sessionWindowSequence += 1;
        _desktopWindows[i] = window.copyWith(
          left: 1 + (cascade % 4) * 2,
          top: 1 + (cascade % 4),
          width: safeChatWidth,
          height: safeChatHeight,
        );
      }

      _desktopInitialized = true;
      return;
    }

    for (var i = 0; i < _desktopWindows.length; i++) {
      _desktopWindows[i] = _clampDesktopWindow(_desktopWindows[i]);
    }
  }

  _DesktopWindowState _clampDesktopWindow(_DesktopWindowState window) {
    if (window.maximized && _desktopWidth > 0 && _desktopHeight > 0) {
      return window.copyWith(
        left: 0,
        top: 0,
        width: _desktopWidth,
        height: _desktopHeight,
      );
    }

    final maxWidth = _desktopWidth <= 0 ? window.width : _desktopWidth;
    final maxHeight = _desktopHeight <= 0 ? window.height : _desktopHeight;

    var nextWidth = _clampInt(window.width, window.minWidth, maxWidth);
    var nextHeight = _clampInt(window.height, window.minHeight, maxHeight);

    var maxLeft = _desktopWidth - nextWidth;
    if (maxLeft < 0) {
      maxLeft = 0;
    }
    var maxTop = _desktopHeight - nextHeight;
    if (maxTop < 0) {
      maxTop = 0;
    }

    final nextLeft = _clampInt(window.left, 0, maxLeft);
    final nextTop = _clampInt(window.top, 0, maxTop);

    return window.copyWith(
      left: nextLeft,
      top: nextTop,
      width: nextWidth,
      height: nextHeight,
    );
  }

  int _clampInt(int value, int min, int max) {
    if (max < min) {
      return min;
    }
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  _DesktopWindowState? _desktopWindowById(String id) {
    for (final window in _desktopWindows) {
      if (window.id == id) {
        return window;
      }
    }
    return null;
  }

  int _desktopWindowIndex(String id) {
    for (var i = 0; i < _desktopWindows.length; i++) {
      if (_desktopWindows[i].id == id) {
        return i;
      }
    }
    return -1;
  }

  void _updateDesktopWindow(
    String id,
    _DesktopWindowState Function(_DesktopWindowState window) updater,
  ) {
    final index = _desktopWindowIndex(id);
    if (index < 0) {
      return;
    }

    setState(() {
      _desktopWindows[index] = updater(_desktopWindows[index]);
    });
  }

  Component _buildDesktopArea() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _syncDesktopLayout(
          constraints.maxWidth.floor(),
          constraints.maxHeight.floor(),
        );

        final windowLayers = _desktopWindows
            .map(_buildDesktopWindow)
            .toList(growable: false);

        return MouseRegion(
          onHover: _handleDesktopMouseHover,
          child: Stack(
            children: <Component>[
              Positioned.fill(child: _buildDesktopBackdrop()),
              ...windowLayers,
            ],
          ),
        );
      },
    );
  }

  Component _buildDesktopBackdrop() {
    final lineWidth = _desktopWidth <= 0 ? 1 : _desktopWidth;
    final pattern = List<String>.filled(lineWidth, ':').join();

    return Container(
      decoration: BoxDecoration(color: _turboDesktopBackground),
      child: Column(
        children: <Component>[
          Expanded(child: SizedBox.expand()),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(color: _turboScrollTrack),
            child: Text(pattern, style: TextStyle(color: _turboDesktopPattern)),
          ),
        ],
      ),
    );
  }

  Component _buildDesktopWindow(_DesktopWindowState window) {
    final active = _activeDesktopWindowId == window.id;
    final content = _buildSessionChatWindowContent(window, active);

    return Positioned(
      left: window.left.toDouble(),
      top: window.top.toDouble(),
      width: window.width.toDouble(),
      height: window.height.toDouble(),
      child: GestureDetector(
        onTapDown: (_) => _handleDesktopWindowTapDown(window.id),
        behavior: HitTestBehavior.deferToChild,
        child: _buildWindowFrame(
          window: window,
          active: active,
          content: content,
        ),
      ),
    );
  }

  void _handleDesktopWindowTapDown(String id) {
    if (_draggingWindowId != null || _resizingWindowId != null) {
      return;
    }

    _focusDesktopWindow(id);
  }

  Component _buildWindowFrame({
    required _DesktopWindowState window,
    required bool active,
    required Component content,
  }) {
    final borderColor = _turboDialogBorderLight;

    return Container(
      decoration: BoxDecoration(color: _turboBluePanel),
      child: Column(
        children: <Component>[
          _buildWindowTopBorder(
            window: window,
            active: active,
            borderColor: borderColor,
          ),
          Expanded(
            child: Row(
              children: <Component>[
                SizedBox(
                  width: 1,
                  child: _buildVerticalFrameLine(color: borderColor),
                ),
                Expanded(child: content),
                SizedBox(
                  width: 1,
                  child: _buildVerticalFrameLine(color: borderColor),
                ),
              ],
            ),
          ),
          _buildWindowBottomBorder(
            window: window,
            active: active,
            borderColor: borderColor,
          ),
        ],
      ),
    );
  }

  Component _buildWindowTopBorder({
    required _DesktopWindowState window,
    required bool active,
    required Color borderColor,
  }) {
    final title = window.title;
    final sessionId = window.sessionId;
    final actionLabel = sessionId != null ? '[■]' : '[ ]';
    final canClose = sessionId != null;
    final zoomLabel = window.maximized ? '[↓]' : '[↑]';
    final windowNumber = () {
      if (sessionId == null) {
        return '';
      }
      final index = _workspaceSessionIndexById(sessionId);
      if (index < 0) {
        return '';
      }
      return '${index + 1}';
    }();
    final windowTag = windowNumber.isEmpty
        ? zoomLabel
        : '$windowNumber-$zoomLabel';
    final controlColor = active ? Colors.brightWhite : Colors.gray;
    final titleColor = active ? Colors.brightWhite : Colors.gray;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: BoxDecoration(
        color: active ? _turboWindowTitleActive : _turboWindowTitleInactive,
      ),
      child: Row(
        children: <Component>[
          Text('╔', style: TextStyle(color: borderColor)),
          GestureDetector(
            onTap: canClose
                ? () {
                    final closeSessionId = sessionId;
                    final targetIndex = _workspaceSessionIndexById(
                      closeSessionId,
                    );
                    if (targetIndex >= 0) {
                      _closeWorkspaceSessionAt(targetIndex);
                    }
                  }
                : null,
            behavior: HitTestBehavior.opaque,
            child: Text(
              actionLabel,
              style: TextStyle(
                color: controlColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text('═', style: TextStyle(color: borderColor)),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (TapDownDetails details) {
                _startWindowDrag(window.id, details);
              },
              child: Row(
                children: <Component>[
                  Expanded(child: _buildFrameLine(color: borderColor)),
                  Text(
                    ' $title ',
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(child: _buildFrameLine(color: borderColor)),
                ],
              ),
            ),
          ),
          Text('═', style: TextStyle(color: borderColor)),
          GestureDetector(
            onTap: () => _toggleDesktopWindowZoom(window.id),
            behavior: HitTestBehavior.opaque,
            child: Text(
              windowTag,
              style: TextStyle(
                color: controlColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text('╗', style: TextStyle(color: borderColor)),
        ],
      ),
    );
  }

  Component _buildFrameLine({required Color color}) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth.floor()
            : 1;
        final line = List<String>.filled(width <= 0 ? 1 : width, '═').join();
        return Text(line, style: TextStyle(color: color));
      },
    );
  }

  Component _buildVerticalFrameLine({required Color color}) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight.floor()
            : 1;
        final lineCount = height <= 0 ? 1 : height;
        final line = List<String>.filled(lineCount, '║').join('\n');
        return Text(line, style: TextStyle(color: color));
      },
    );
  }

  Component _buildWindowBottomBorder({
    required _DesktopWindowState window,
    required bool active,
    required Color borderColor,
  }) {
    final canResize = !window.maximized;
    final cornerColor = canResize && active ? Colors.brightCyan : borderColor;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: BoxDecoration(color: _turboBluePanel),
      child: Row(
        children: <Component>[
          Text('╚', style: TextStyle(color: borderColor)),
          Expanded(child: _buildFrameLine(color: borderColor)),
          GestureDetector(
            onTapDown: canResize
                ? (TapDownDetails details) {
                    _startWindowResize(window.id, details);
                  }
                : null,
            behavior: HitTestBehavior.opaque,
            child: Text(
              '╝',
              style: TextStyle(color: cornerColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Component _buildSessionChatWindowContent(
    _DesktopWindowState window,
    bool active,
  ) {
    final sessionId = window.sessionId;
    final session = sessionId == null ? null : _workspaceSessionById(sessionId);
    if (session == null) {
      return Center(
        child: Text(
          'Session unavailable.',
          style: TextStyle(color: Colors.brightRed),
        ),
      );
    }

    final isActiveSession = session.id == _activeWorkspaceSession.id;

    return Container(
      decoration: BoxDecoration(color: _turboBluePanel),
      child: Column(
        children: <Component>[
          Expanded(
            child: MouseRegion(
              onHover: (MouseEvent event) {
                if (event.button == MouseButton.wheelUp) {
                  session.scrollController.scrollUp(3.0);
                  return;
                }
                if (event.button == MouseButton.wheelDown) {
                  session.scrollController.scrollDown(3.0);
                }
              },
              child: Row(
                children: <Component>[
                  Expanded(
                    child: _buildMessagesView(
                      messages: session.messages,
                      controller: session.scrollController,
                    ),
                  ),
                  _buildTurboScrollRail(session: session),
                ],
              ),
            ),
          ),
          _buildSessionFooterBlock(
            session: session,
            active: active,
            isActiveSession: isActiveSession,
          ),
        ],
      ),
    );
  }

  Component _buildSessionFooterBlock({
    required _WorkspaceSessionState session,
    required bool active,
    required bool isActiveSession,
  }) {
    final footerContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Component>[
        if (isActiveSession) _buildSlashSuggestionsBar(),
        if (isActiveSession)
          _buildInputBar(
            focused: active && _openTopMenuIndex == null && !_showExitConfirm,
          )
        else
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 1, vertical: 0),
            decoration: BoxDecoration(
              color: _turboBlueHeader,
              border: BoxBorder(top: BorderSide(color: Colors.brightCyan)),
            ),
            child: Text(
              'Focus this window to activate ${session.title}.',
              style: TextStyle(color: Colors.brightWhite),
            ),
          ),
      ],
    );

    return Container(
      width: double.infinity,
      child: ClipRect(child: footerContent),
    );
  }

  Component _buildTurboScrollRail({required _WorkspaceSessionState session}) {
    final controller = session.scrollController;
    final canScroll = controller.maxScrollExtent > 0.0;

    return MouseRegion(
      onHover: (MouseEvent event) {
        if (event.button == MouseButton.wheelUp) {
          controller.scrollUp(3.0);
          return;
        }
        if (event.button == MouseButton.wheelDown) {
          controller.scrollDown(3.0);
        }
      },
      child: Container(
        width: 1,
        decoration: BoxDecoration(color: _turboScrollTrack),
        child: Column(
          children: <Component>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canScroll ? () => controller.scrollUp(2.0) : null,
              child: Text(
                '▲',
                style: TextStyle(
                  color: _turboBlueBackground,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final height = constraints.maxHeight.isFinite
                      ? constraints.maxHeight.floor()
                      : 1;
                  final trackHeight = height <= 0 ? 1 : height;
                  final maxOffset = controller.maxScrollExtent;
                  final currentOffset = controller.offset.clamp(
                    controller.minScrollExtent,
                    maxOffset,
                  );

                  final ratio = maxOffset <= 0.0
                      ? 0.0
                      : currentOffset / maxOffset;
                  var thumbIndex = (ratio * (trackHeight - 1)).round();
                  thumbIndex = _clampInt(thumbIndex, 0, trackHeight - 1);

                  final spans = <InlineSpan>[];
                  for (var i = 0; i < trackHeight; i++) {
                    final isThumb = i == thumbIndex;
                    spans.add(
                      TextSpan(
                        text: isThumb ? '█' : '│',
                        style: TextStyle(
                          color: isThumb
                              ? _turboScrollThumb
                              : _turboBlueBackground,
                        ),
                      ),
                    );
                    if (i < trackHeight - 1) {
                      spans.add(
                        TextSpan(
                          text: '\n',
                          style: TextStyle(color: _turboBlueBackground),
                        ),
                      );
                    }
                  }

                  return RichText(text: TextSpan(children: spans));
                },
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: canScroll ? () => controller.scrollDown(2.0) : null,
              child: Text(
                '▼',
                style: TextStyle(
                  color: _turboBlueBackground,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const int _desktopTopOffset = 1;
}
