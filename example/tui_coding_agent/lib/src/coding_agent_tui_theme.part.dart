part of 'coding_agent_tui.dart';

final Color _turboBlueBackground = Color.fromRGB(0, 0, 170);
final Color _turboBluePanel = Color.fromRGB(0, 0, 128);
final Color _turboBlueHeader = Color.fromRGB(0, 0, 170);
final Color _turboDesktopBackground = Color.fromRGB(0, 0, 170);
final Color _turboDesktopPattern = Color.fromRGB(90, 120, 220);
final Color _turboMenuBar = Color.fromRGB(192, 192, 192);
final Color _turboMenuText = Color.fromRGB(0, 0, 0);
final Color _turboMenuMnemonic = Color.fromRGB(170, 0, 0);
final Color _turboMenuSelectionBackground = Color.fromRGB(0, 170, 0);
final Color _turboMenuBorder = Color.fromRGB(0, 0, 0);
final Color _turboStatusBarBackground = Color.fromRGB(192, 192, 192);
final Color _turboDialogShadow = Color.fromRGB(96, 96, 96);
final Color _turboDialogBody = Color.fromRGB(192, 192, 192);
final Color _turboDialogTitleBar = Color.fromRGB(0, 0, 170);
final Color _turboDialogText = Color.fromRGB(0, 0, 0);
final Color _turboDialogTextDim = Color.fromRGB(55, 55, 55);
final Color _turboDialogBorderLight = Color.fromRGB(255, 255, 255);
final Color _turboDialogBorderDark = Color.fromRGB(90, 90, 90);
final Color _turboWindowTitleActive = Color.fromRGB(0, 0, 170);
final Color _turboWindowTitleInactive = Color.fromRGB(0, 0, 128);
final Color _turboWindowSelectionBackground = Color.fromRGB(0, 170, 170);
final Color _turboScrollTrack = Color.fromRGB(0, 170, 170);
final Color _turboScrollThumb = Color.fromRGB(255, 255, 255);
final Color _turboCodeBackground = Color.fromRGB(0, 0, 102);

final TextStyle _assistantTextStyle = TextStyle(color: Colors.brightWhite);
final TextStyle _codeFrameStyle = TextStyle(
  color: Colors.brightBlue,
  backgroundColor: _turboCodeBackground,
  fontWeight: FontWeight.bold,
);
final TextStyle _codeHeaderStyle = TextStyle(
  color: Colors.brightYellow,
  backgroundColor: _turboCodeBackground,
  fontWeight: FontWeight.bold,
);
final TextStyle _codeDefaultStyle = TextStyle(
  color: Colors.brightWhite,
  backgroundColor: _turboCodeBackground,
);
final TextStyle _codeKeywordStyle = TextStyle(
  color: Colors.brightCyan,
  backgroundColor: _turboCodeBackground,
  fontWeight: FontWeight.bold,
);
final TextStyle _codeStringStyle = TextStyle(
  color: Colors.brightYellow,
  backgroundColor: _turboCodeBackground,
);
final TextStyle _codeNumberStyle = TextStyle(
  color: Colors.brightMagenta,
  backgroundColor: _turboCodeBackground,
);
final TextStyle _codeCommentStyle = TextStyle(
  color: Colors.brightGreen,
  backgroundColor: _turboCodeBackground,
);
final TextStyle _codeFunctionStyle = TextStyle(
  color: Colors.brightWhite,
  backgroundColor: _turboCodeBackground,
  fontWeight: FontWeight.bold,
);
final TextStyle _codeTypeStyle = TextStyle(
  color: Colors.brightCyan,
  backgroundColor: _turboCodeBackground,
);
final TextStyle _codeOperatorStyle = TextStyle(
  color: Colors.brightYellow,
  backgroundColor: _turboCodeBackground,
);
final TextStyle _codeAnnotationStyle = TextStyle(
  color: Colors.brightGreen,
  backgroundColor: _turboCodeBackground,
  fontWeight: FontWeight.bold,
);
final TextStyle _codeConstantStyle = TextStyle(
  color: Colors.brightMagenta,
  backgroundColor: _turboCodeBackground,
  fontWeight: FontWeight.bold,
);

final RegExp _codeTokenPattern = RegExp(
  "(\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|`(?:\\\\.|[^`\\\\])*`|@[a-zA-Z_][a-zA-Z0-9_]*|\\b\\d+(?:\\.\\d+)?\\b|\\b[a-zA-Z_][a-zA-Z0-9_]*\\b|[{}\\[\\]().,:;=+\\-*/<>!&|%^~?]+)",
);
final RegExp _numberTokenPattern = RegExp(r'^\d+(?:\.\d+)?$');
final RegExp _identifierTokenPattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
final RegExp _operatorTokenPattern = RegExp(
  r'^[{}\[\]().,:;=+\-*/<>!&|%^~?]+$',
);
final RegExp _typeNamePattern = RegExp(r'^[A-Z][a-zA-Z0-9_]*$');
const Set<String> _codeKeywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'defer',
  'def',
  'do',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'if',
  'implements',
  'import',
  'in',
  'interface',
  'is',
  'late',
  'let',
  'library',
  'mixin',
  'new',
  'null',
  'on',
  'package',
  'part',
  'private',
  'protected',
  'public',
  'required',
  'return',
  'set',
  'show',
  'static',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'using',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

const Set<String> _codeConstants = <String>{
  'true',
  'false',
  'null',
  'undefined',
  'NaN',
  'Infinity',
};
