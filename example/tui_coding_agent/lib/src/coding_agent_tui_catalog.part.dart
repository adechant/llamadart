part of 'coding_agent_tui.dart';

const List<String> _slashCommandNames = <String>[
  '/help',
  '/clear',
  '/reset',
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

  const _TopMenuItem({
    required this.label,
    required this.shortcut,
    required this.command,
  });
}

const List<_TopMenu> _topMenus = <_TopMenu>[
  _TopMenu(
    label: 'File',
    mnemonic: 'f',
    items: <_TopMenuItem>[
      _TopMenuItem(label: 'New chat', shortcut: 'F3', command: '/clear'),
      _TopMenuItem(label: 'Exit', shortcut: 'Esc', command: '/exit'),
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
    label: 'Run',
    mnemonic: 'r',
    items: <_TopMenuItem>[
      _TopMenuItem(
        label: 'Cancel generation',
        shortcut: '/cancel',
        command: '/cancel',
      ),
      _TopMenuItem(
        label: 'Workspace status',
        shortcut: '/workspace',
        command: '/workspace',
      ),
    ],
  ),
  _TopMenu(
    label: 'Compile',
    mnemonic: 'c',
    items: <_TopMenuItem>[
      _TopMenuItem(label: 'Show model', shortcut: '/model', command: '/model'),
      _TopMenuItem(
        label: 'Switch model...',
        shortcut: 'F2',
        command: '/model ',
      ),
    ],
  ),
  _TopMenu(
    label: 'Debug',
    mnemonic: 'd',
    items: <_TopMenuItem>[
      _TopMenuItem(label: 'Show help', shortcut: 'F1', command: '/help'),
      _TopMenuItem(
        label: 'Cancel run',
        shortcut: '/cancel',
        command: '/cancel',
      ),
    ],
  ),
  _TopMenu(
    label: 'Project',
    mnemonic: 'p',
    items: <_TopMenuItem>[
      _TopMenuItem(
        label: 'Workspace root',
        shortcut: '/workspace',
        command: '/workspace',
      ),
      _TopMenuItem(
        label: 'Model details',
        shortcut: '/model',
        command: '/model',
      ),
    ],
  ),
  _TopMenu(
    label: 'Options',
    mnemonic: 'o',
    items: <_TopMenuItem>[
      _TopMenuItem(
        label: 'Switch model...',
        shortcut: 'F2',
        command: '/model ',
      ),
      _TopMenuItem(label: 'Show model', shortcut: '/model', command: '/model'),
    ],
  ),
  _TopMenu(
    label: 'Window',
    mnemonic: 'w',
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
