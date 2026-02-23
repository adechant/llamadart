import 'package:llamadart_tui_coding_agent/src/text_tool_call_parser.dart';
import 'package:test/test.dart';

void main() {
  group('TextToolCallParser', () {
    late TextToolCallParser parser;

    setUp(() {
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

    test('parses dangling inline tool tag with inline JSON arguments', () {
      final calls = parser.extract(
        'I need command parameter first.\n'
        '<tool_call>run_command{"command":"ls"}',
      );

      expect(calls, hasLength(1));
      expect(calls.single.name, 'run_command');
      expect(calls.single.arguments, containsPair('command', 'ls'));
    });

    test('parses xml-style key/value tool arguments', () {
      final calls = parser.extract(
        '<tool_call>'
        '<name>run_command</name>'
        '<arg_key>command</arg_key><arg_value>git status</arg_value>'
        '</tool_call>',
      );

      expect(calls, hasLength(1));
      expect(calls.single.name, 'run_command');
      expect(calls.single.arguments, containsPair('command', 'git status'));
    });

    test('parses OpenAI-style nested function call payload', () {
      final calls = parser.extract(
        '{"tool_calls":[{"function":{"name":"run_command",'
        '"arguments":"{\\"command\\":\\"git --version\\"}"}}]}',
      );

      expect(calls, hasLength(1));
      expect(calls.single.name, 'run_command');
      expect(calls.single.arguments, containsPair('command', 'git --version'));
    });

    test('ignores unknown tool names', () {
      final calls = parser.extract(
        '<tool_call>unknown_tool{"x":1}</tool_call>',
      );

      expect(calls, isEmpty);
    });
  });
}
