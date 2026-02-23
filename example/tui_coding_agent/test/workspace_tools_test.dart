import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_tui_coding_agent/src/workspace_tools.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('WorkspaceTools', () {
    late Directory workspace;
    late WorkspaceTools tools;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('workspace_tools_');
      await Directory(p.join(workspace.path, 'lib')).create(recursive: true);
      await File(p.join(workspace.path, 'lib', 'main.dart')).writeAsString(
        'void main() {\n'
        '  print("hello");\n'
        '}\n',
      );
      tools = WorkspaceTools(workspaceRoot: workspace.path);
    });

    tearDown(() async {
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    });

    test('listFiles returns workspace-relative entries', () async {
      final result = await tools.listFiles(
        const ToolParams(<String, dynamic>{'path': '.', 'recursive': true}),
      );

      final map = result as Map<String, dynamic>;
      final entries = (map['entries'] as List<dynamic>).cast<String>();
      expect(entries, contains('lib/main.dart'));
    });

    test('readFile returns selected line window', () async {
      final result = await tools.readFile(
        const ToolParams(<String, dynamic>{
          'path': 'lib/main.dart',
          'start_line': 2,
          'max_lines': 1,
        }),
      );

      final map = result as Map<String, dynamic>;
      expect(map['start_line'], equals(2));
      expect(map['end_line'], equals(2));
      expect(map['content'], equals('  print("hello");'));
    });

    test('searchFiles returns matching lines', () async {
      final result = await tools.searchFiles(
        const ToolParams(<String, dynamic>{
          'query': 'print',
          'path': '.',
          'case_sensitive': false,
        }),
      );

      final map = result as Map<String, dynamic>;
      final matches = (map['results'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(matches, isNotEmpty);
      expect(matches.first['path'], equals('lib/main.dart'));
    });

    test('writeFile writes and appends content', () async {
      final filePath = p.join(workspace.path, 'notes.txt');

      await tools.writeFile(
        const ToolParams(<String, dynamic>{
          'path': 'notes.txt',
          'content': 'first line',
          'mode': 'overwrite',
        }),
      );

      await tools.writeFile(
        const ToolParams(<String, dynamic>{
          'path': 'notes.txt',
          'content': '\nsecond line',
          'mode': 'append',
        }),
      );

      final content = await File(filePath).readAsString();
      expect(content, equals('first line\nsecond line'));
    });

    test('runCommand blocks restricted commands', () async {
      final result = await tools.runCommand(
        const ToolParams(<String, dynamic>{'command': 'sudo ls'}),
      );

      final map = result as Map<String, dynamic>;
      expect(map['ok'], isFalse);
      expect(map['error'], contains('blocked'));
    });

    test('runCommand accepts input alias for command', () async {
      final result = await tools.runCommand(
        const ToolParams(<String, dynamic>{'input': 'echo alias_ok'}),
      );

      final map = result as Map<String, dynamic>;
      expect(map['ok'], isTrue);
      expect(map['stdout'], contains('alias_ok'));
    });

    test('formatToolArguments handles non-json values safely', () {
      final formatted = formatToolArguments(<String, dynamic>{
        'name': 'demo',
        'value': _NonJsonValue(),
      });

      expect(formatted, contains('name=demo'));
      expect(formatted, contains('value=Instance of'));
    });
  });
}

class _NonJsonValue {}
