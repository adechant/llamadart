import 'dart:io';

import 'package:llamadart_tui_coding_agent/src/workspace_guard.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('WorkspaceGuard', () {
    late Directory tempWorkspace;
    late WorkspaceGuard guard;

    setUp(() async {
      tempWorkspace = await Directory.systemTemp.createTemp('workspace_guard_');
      guard = WorkspaceGuard(tempWorkspace.path);
    });

    tearDown(() async {
      if (tempWorkspace.existsSync()) {
        await tempWorkspace.delete(recursive: true);
      }
    });

    test('resolves relative paths inside workspace', () {
      final resolved = guard.resolvePath('lib/main.dart');

      expect(
        resolved,
        equals(p.normalize(p.join(tempWorkspace.path, 'lib/main.dart'))),
      );
    });

    test('rejects traversal outside workspace root', () {
      expect(
        () => guard.resolvePath('../outside.txt'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('converts absolute path to workspace relative path', () {
      final absolutePath = p.join(tempWorkspace.path, 'foo', 'bar.txt');

      final relative = guard.toWorkspaceRelative(absolutePath);

      expect(relative, equals(p.join('foo', 'bar.txt')));
    });
  });
}
