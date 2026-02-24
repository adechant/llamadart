import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_tui_coding_agent/src/text_tool_call_parser.dart';
import 'package:llamadart_tui_coding_agent/src/workspace_tools.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('runner tool regression', () {
    late Directory workspace;
    late WorkspaceTools tools;
    late TextToolCallParser parser;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('runner_tool_reg_');
      await File(p.join(workspace.path, 'README.md')).writeAsString('hello\n');

      tools = WorkspaceTools(workspaceRoot: workspace.path);
      parser = TextToolCallParser(
        knownToolNames: <String>{
          'list_files',
          'read_file',
          'search_files',
          'write_file',
          'run_command',
        },
      );
    });

    tearDown(() async {
      if (workspace.existsSync()) {
        await workspace.delete(recursive: true);
      }
    });

    test('executes parsed run_command calls from inline tool tags', () async {
      final assistantOutputs = <String>[
        'I need to provide the command parameter. Let me run ls correctly:\n'
            '<tool_call>run_command{"command":"ls"}',
        '<tool_call>run_command{"command":"git --version"}',
        '<tool_call>run_command{"command":"git status"}',
      ];

      for (final output in assistantOutputs) {
        final calls = parser.extract(output);
        expect(calls, hasLength(1));
        expect(calls.single.name, 'run_command');

        final result = await tools.runCommand(
          ToolParams(calls.single.arguments),
        );
        final map = result as Map<String, dynamic>;
        expect(map['command'], equals(calls.single.arguments['command']));
      }
    });

    test('maps alias input arg to command for runner tool', () async {
      final calls = parser.extract('<tool_call>run_command{"input":"ls"}');

      expect(calls, hasLength(1));
      expect(calls.single.arguments, containsPair('input', 'ls'));

      final result = await tools.runCommand(ToolParams(calls.single.arguments));
      final map = result as Map<String, dynamic>;
      expect(map['command'], equals('ls'));
      expect(map['ok'], isTrue);
    });
  });
}
