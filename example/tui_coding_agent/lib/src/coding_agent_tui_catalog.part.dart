part of 'coding_agent_tui.dart';

const List<String> _slashCommandNames = <String>[
  '/help',
  '/clear',
  '/reset',
  '/new',
  '/next',
  '/prev',
  '/close',
  '/zoom-window',
  '/next-window',
  '/prev-window',
  '/tile-windows',
  '/stack-windows',
  '/model',
  '/workspace',
  '/cancel',
  '/exit',
  '/quit',
];

const Map<String, String> _slashCommandUsage = <String, String>{
  '/help': '/help',
  '/clear': '/clear',
  '/reset': '/reset',
  '/new': '/new',
  '/next': '/next',
  '/prev': '/prev',
  '/close': '/close',
  '/zoom-window': '/zoom-window',
  '/next-window': '/next-window',
  '/prev-window': '/prev-window',
  '/tile-windows': '/tile-windows',
  '/stack-windows': '/stack-windows',
  '/model': '/model <path|url|owner/repo[:hint]>',
  '/workspace': '/workspace',
  '/cancel': '/cancel',
  '/exit': '/exit',
  '/quit': '/quit',
};

class _TopMenu {
  final String label;
  final String mnemonic;
  final List<_TopMenuItem> items;

  const _TopMenu({
    required this.label,
    required this.mnemonic,
    required this.items,
  });
}

class _TopMenuItem {
  final String label;
  final String shortcut;
  final String command;
  final bool isSeparator;

  const _TopMenuItem({
    required this.label,
    required this.shortcut,
    required this.command,
  }) : isSeparator = false;

  const _TopMenuItem.separator()
    : label = '',
      shortcut = '',
      command = '',
      isSeparator = true;
}

const List<_TopMenu> _topMenus = <_TopMenu>[
  _TopMenu(
    label: 'File',
    mnemonic: 'f',
    items: <_TopMenuItem>[
      _TopMenuItem(label: 'New session', shortcut: 'F7', command: '/new'),
      _TopMenuItem(label: 'Clear session', shortcut: 'F3', command: '/clear'),
      _TopMenuItem(
        label: 'Switch model...',
        shortcut: 'F2',
        command: '/model ',
      ),
      _TopMenuItem.separator(),
      _TopMenuItem(label: 'Exit', shortcut: 'Alt+X', command: '/exit'),
    ],
  ),
  _TopMenu(
    label: 'Edit',
    mnemonic: 'e',
    items: <_TopMenuItem>[
      _TopMenuItem(
        label: 'Clear conversation',
        shortcut: '/clear',
        command: '/clear',
      ),
      _TopMenuItem(
        label: 'Reset context',
        shortcut: '/reset',
        command: '/reset',
      ),
    ],
  ),
  _TopMenu(
    label: 'Search',
    mnemonic: 's',
    items: <_TopMenuItem>[
      _TopMenuItem(
        label: 'Workspace root',
        shortcut: '/workspace',
        command: '/workspace',
      ),
      _TopMenuItem(label: 'Command help', shortcut: 'F1', command: '/help'),
    ],
  ),
  _TopMenu(
    label: 'Windows',
    mnemonic: 'w',
    items: <_TopMenuItem>[
      _TopMenuItem(
        label: 'Zoom window',
        shortcut: 'F5',
        command: '/zoom-window',
      ),
      _TopMenuItem(
        label: 'Next window',
        shortcut: 'F6',
        command: '/next-window',
      ),
      _TopMenuItem(
        label: 'Previous window',
        shortcut: 'F9',
        command: '/prev-window',
      ),
      _TopMenuItem(
        label: 'Tile windows',
        shortcut: '',
        command: '/tile-windows',
      ),
      _TopMenuItem(
        label: 'Stack windows',
        shortcut: '',
        command: '/stack-windows',
      ),
      _TopMenuItem.separator(),
      _TopMenuItem(label: 'Next session', shortcut: 'F8', command: '/next'),
      _TopMenuItem(label: 'Prev session', shortcut: 'F4', command: '/prev'),
      _TopMenuItem(label: 'Close session', shortcut: 'F12', command: '/close'),
    ],
  ),
  _TopMenu(
    label: 'Help',
    mnemonic: 'h',
    items: <_TopMenuItem>[
      _TopMenuItem(label: 'Commands', shortcut: 'F1', command: '/help'),
      _TopMenuItem(
        label: 'Workspace',
        shortcut: '/workspace',
        command: '/workspace',
      ),
    ],
  ),
];

const String _sessionChatWindowPrefix = 'chat_session_';

class _DesktopWindowState {
  final String id;
  final String? sessionId;
  final String title;
  final int left;
  final int top;
  final int width;
  final int height;
  final int minWidth;
  final int minHeight;
  final bool maximized;
  final int? restoreLeft;
  final int? restoreTop;
  final int? restoreWidth;
  final int? restoreHeight;

  const _DesktopWindowState({
    required this.id,
    this.sessionId,
    required this.title,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.minWidth,
    required this.minHeight,
    this.maximized = false,
    this.restoreLeft,
    this.restoreTop,
    this.restoreWidth,
    this.restoreHeight,
  });

  _DesktopWindowState copyWith({
    String? title,
    int? left,
    int? top,
    int? width,
    int? height,
    bool? maximized,
    int? restoreLeft,
    int? restoreTop,
    int? restoreWidth,
    int? restoreHeight,
    bool clearRestore = false,
  }) {
    return _DesktopWindowState(
      id: id,
      sessionId: sessionId,
      title: title ?? this.title,
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
      minWidth: minWidth,
      minHeight: minHeight,
      maximized: maximized ?? this.maximized,
      restoreLeft: clearRestore ? null : (restoreLeft ?? this.restoreLeft),
      restoreTop: clearRestore ? null : (restoreTop ?? this.restoreTop),
      restoreWidth: clearRestore ? null : (restoreWidth ?? this.restoreWidth),
      restoreHeight: clearRestore
          ? null
          : (restoreHeight ?? this.restoreHeight),
    );
  }
}

class _WorkspaceSessionState {
  final String id;
  String title;
  List<LlamaChatMessage> history;
  final List<_AgentMessage> messages;
  final AutoScrollController scrollController;

  _WorkspaceSessionState({
    required this.id,
    required this.title,
    required this.history,
    required this.messages,
    required this.scrollController,
  });
}
