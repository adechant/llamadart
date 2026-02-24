import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;

import 'workspace_guard.dart';

class WorkspaceTools {
  static const int _defaultMaxEntries = 200;
  static const int _maxEntriesLimit = 500;
  static const int _defaultReadLines = 200;
  static const int _maxReadLinesLimit = 800;
  static const int _defaultSearchResults = 80;
  static const int _maxSearchResultsLimit = 200;
  static const int _maxReadableFileBytes = 1024 * 1024;
  static const int _maxSearchFileBytes = 512 * 1024;
  static const int _maxCommandOutputChars = 12000;

  static final List<RegExp> _blockedCommandPatterns = <RegExp>[
    RegExp(r'(^|\s)sudo(\s|$)', caseSensitive: false),
    RegExp(r'(^|\s)doas(\s|$)', caseSensitive: false),
    RegExp(r'(^|\s)shutdown(\s|$)', caseSensitive: false),
    RegExp(r'(^|\s)reboot(\s|$)', caseSensitive: false),
    RegExp(r'rm\s+-rf\s+/', caseSensitive: false),
    RegExp(r'dd\s+if=', caseSensitive: false),
  ];

  final WorkspaceGuard _guard;

  WorkspaceTools({required String workspaceRoot})
    : _guard = WorkspaceGuard(workspaceRoot);

  String get workspaceRoot => _guard.workspaceRoot;

  List<ToolDefinition> buildToolDefinitions() {
    return <ToolDefinition>[
      ToolDefinition(
        name: 'list_files',
        description:
            'List files in a workspace directory. Use recursive=true when needed.',
        parameters: <ToolParam>[
          ToolParam.string(
            'path',
            description: 'Directory path relative to the workspace root.',
          ),
          ToolParam.boolean(
            'recursive',
            description: 'Recursively list subdirectories.',
          ),
          ToolParam.integer(
            'max_entries',
            description: 'Maximum number of entries to return (1-500).',
          ),
        ],
        handler: listFiles,
      ),
      ToolDefinition(
        name: 'read_file',
        description:
            'Read a UTF-8 text file from the workspace by path and line range.',
        parameters: <ToolParam>[
          ToolParam.string(
            'path',
            description: 'File path relative to the workspace root.',
            required: true,
          ),
          ToolParam.integer(
            'start_line',
            description: '1-based line number to start reading from.',
          ),
          ToolParam.integer(
            'max_lines',
            description: 'Maximum number of lines to return (1-800).',
          ),
        ],
        handler: readFile,
      ),
      ToolDefinition(
        name: 'search_files',
        description:
            'Search text in workspace files and return matching lines with file paths.',
        parameters: <ToolParam>[
          ToolParam.string(
            'query',
            description: 'Text query to search for.',
            required: true,
          ),
          ToolParam.string(
            'path',
            description: 'Directory path relative to workspace root.',
          ),
          ToolParam.boolean(
            'case_sensitive',
            description: 'Whether matching should be case sensitive.',
          ),
          ToolParam.integer(
            'max_results',
            description: 'Maximum number of matches to return (1-200).',
          ),
        ],
        handler: searchFiles,
      ),
      ToolDefinition(
        name: 'write_file',
        description:
            'Write text content to a workspace file. Supports overwrite or append.',
        parameters: <ToolParam>[
          ToolParam.string(
            'path',
            description: 'Target file path relative to workspace root.',
            required: true,
          ),
          ToolParam.string(
            'content',
            description: 'Text content to write.',
            required: true,
          ),
          ToolParam.enumType(
            'mode',
            values: <String>['overwrite', 'append'],
            description: 'File write mode.',
          ),
          ToolParam.boolean(
            'create_dirs',
            description: 'Create missing parent directories automatically.',
          ),
        ],
        handler: writeFile,
      ),
      ToolDefinition(
        name: 'run_command',
        description:
            'Run a shell command inside the workspace and return stdout/stderr.',
        parameters: <ToolParam>[
          ToolParam.string(
            'command',
            description: 'Shell command to execute.',
            required: true,
          ),
          ToolParam.string(
            'working_directory',
            description: 'Directory relative to workspace root.',
          ),
          ToolParam.integer(
            'timeout_seconds',
            description: 'Command timeout in seconds (1-120).',
          ),
        ],
        handler: runCommand,
      ),
    ];
  }

  Future<Object?> listFiles(ToolParams params) async {
    final path = params.getString('path') ?? '.';
    final recursive = params.getBool('recursive') ?? false;
    final maxEntries = (params.getInt('max_entries') ?? _defaultMaxEntries)
        .clamp(1, _maxEntriesLimit);

    final resolvedPath = _guard.resolvePath(path);
    final directory = Directory(resolvedPath);
    if (!directory.existsSync()) {
      throw FileSystemException('Directory not found', resolvedPath);
    }

    final entries = <String>[];
    var truncated = false;

    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entries.length >= maxEntries) {
        truncated = true;
        break;
      }

      final relative = _guard.toWorkspaceRelative(entity.path);
      if (entity is Directory) {
        entries.add('$relative/');
      } else {
        entries.add(relative);
      }
    }

    entries.sort();

    return <String, dynamic>{
      'path': _guard.toWorkspaceRelative(resolvedPath),
      'recursive': recursive,
      'count': entries.length,
      'truncated': truncated,
      'entries': entries,
    };
  }

  Future<Object?> readFile(ToolParams params) async {
    final path = params.getRequiredString('path');
    final startLine = (params.getInt('start_line') ?? 1).clamp(1, 1000000);
    final maxLines = (params.getInt('max_lines') ?? _defaultReadLines).clamp(
      1,
      _maxReadLinesLimit,
    );

    final resolvedPath = _guard.resolvePath(path);
    final file = File(resolvedPath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', resolvedPath);
    }

    final fileSize = file.lengthSync();
    if (fileSize > _maxReadableFileBytes) {
      throw ArgumentError(
        'File is too large to read ($fileSize bytes, max $_maxReadableFileBytes bytes).',
      );
    }

    final lines = const LineSplitter().convert(
      await file.readAsString(encoding: utf8),
    );

    final startIndex = startLine - 1;
    if (startIndex >= lines.length) {
      return <String, dynamic>{
        'path': _guard.toWorkspaceRelative(resolvedPath),
        'start_line': startLine,
        'end_line': startLine - 1,
        'line_count': 0,
        'content': '',
        'truncated': false,
      };
    }

    final endExclusive = (startIndex + maxLines).clamp(0, lines.length);
    final selected = lines.sublist(startIndex, endExclusive);
    final endLine = startIndex + selected.length;

    return <String, dynamic>{
      'path': _guard.toWorkspaceRelative(resolvedPath),
      'start_line': startLine,
      'end_line': endLine,
      'line_count': selected.length,
      'truncated': endExclusive < lines.length,
      'content': selected.join('\n'),
    };
  }

  Future<Object?> searchFiles(ToolParams params) async {
    final query = params.getRequiredString('query');
    final path = params.getString('path') ?? '.';
    final caseSensitive = params.getBool('case_sensitive') ?? false;
    final maxResults = (params.getInt('max_results') ?? _defaultSearchResults)
        .clamp(1, _maxSearchResultsLimit);

    final resolvedPath = _guard.resolvePath(path);
    final directory = Directory(resolvedPath);
    if (!directory.existsSync()) {
      throw FileSystemException('Directory not found', resolvedPath);
    }

    final results = <Map<String, dynamic>>[];
    final queryNeedle = caseSensitive ? query : query.toLowerCase();
    var truncated = false;

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (results.length >= maxResults) {
        truncated = true;
        break;
      }

      if (entity is! File) {
        continue;
      }

      final fileLength = entity.lengthSync();
      if (fileLength > _maxSearchFileBytes) {
        continue;
      }

      late final List<String> lines;
      try {
        lines = const LineSplitter().convert(
          await entity.readAsString(encoding: utf8),
        );
      } catch (_) {
        continue;
      }

      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        if (results.length >= maxResults) {
          truncated = true;
          break;
        }

        final line = lines[lineIndex];
        final haystack = caseSensitive ? line : line.toLowerCase();
        if (!haystack.contains(queryNeedle)) {
          continue;
        }

        results.add(<String, dynamic>{
          'path': _guard.toWorkspaceRelative(entity.path),
          'line': lineIndex + 1,
          'text': line,
        });
      }
    }

    return <String, dynamic>{
      'query': query,
      'path': _guard.toWorkspaceRelative(resolvedPath),
      'case_sensitive': caseSensitive,
      'count': results.length,
      'truncated': truncated,
      'results': results,
    };
  }

  Future<Object?> writeFile(ToolParams params) async {
    final path = params.getRequiredString('path');
    final mode = (params.getString('mode') ?? 'overwrite').trim().toLowerCase();
    final createDirs = params.getBool('create_dirs') ?? true;

    Object? rawContent = params['content'];
    if (rawContent == null) {
      throw ArgumentError('Required parameter "content" is missing');
    }

    final content = rawContent is String ? rawContent : jsonEncode(rawContent);
    final resolvedPath = _guard.resolvePath(path);
    final file = File(resolvedPath);

    final parent = file.parent;
    if (!parent.existsSync()) {
      if (!createDirs) {
        throw FileSystemException(
          'Parent directory does not exist',
          parent.path,
        );
      }
      await parent.create(recursive: true);
    }

    if (mode == 'append') {
      await file.writeAsString(content, mode: FileMode.append, flush: true);
    } else if (mode == 'overwrite') {
      await file.writeAsString(content, mode: FileMode.write, flush: true);
    } else {
      throw ArgumentError('Invalid write mode: $mode');
    }

    return <String, dynamic>{
      'path': _guard.toWorkspaceRelative(resolvedPath),
      'mode': mode,
      'bytes_written': utf8.encode(content).length,
    };
  }

  Future<Object?> runCommand(ToolParams params) async {
    final command =
        (params.getString('command') ??
                params.getString('cmd') ??
                params.getString('input') ??
                params.getString('shell_command'))
            ?.trim() ??
        '';
    if (command.isEmpty) {
      throw ArgumentError('Required parameter "command" is missing or empty');
    }

    if (_isBlockedCommand(command)) {
      return <String, dynamic>{
        'ok': false,
        'error': 'Command blocked by safety policy.',
      };
    }

    final timeoutSeconds = (params.getInt('timeout_seconds') ?? 20).clamp(
      1,
      120,
    );
    final workdirInput = params.getString('working_directory');
    final workingDirectory = workdirInput == null
        ? workspaceRoot
        : _guard.resolvePath(workdirInput);

    final shell = _shellForPlatform(command);
    final stdoutCollector = _BoundedOutputCollector(_maxCommandOutputChars);
    final stderrCollector = _BoundedOutputCollector(_maxCommandOutputChars);

    late final Process process;
    try {
      process = await Process.start(
        shell.executable,
        shell.arguments,
        workingDirectory: workingDirectory,
        runInShell: false,
      );
    } catch (error) {
      return <String, dynamic>{
        'ok': false,
        'error': 'Failed to start command: $error',
      };
    }

    final stdoutDone = _collectProcessOutput(
      process.stdout,
      collector: stdoutCollector,
      streamLabel: 'stdout',
    );
    final stderrDone = _collectProcessOutput(
      process.stderr,
      collector: stderrCollector,
      streamLabel: 'stderr',
    );

    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      Duration(seconds: timeoutSeconds),
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );

    await stdoutDone;
    await stderrDone;

    final stdoutText = stdoutCollector.build();
    final stderrText = stderrCollector.build();

    return <String, dynamic>{
      'ok': !timedOut && exitCode == 0,
      'command': command,
      'working_directory': _guard.toWorkspaceRelative(workingDirectory),
      'timed_out': timedOut,
      'exit_code': exitCode,
      'stdout': stdoutText,
      'stderr': stderrText,
    };
  }

  bool _isBlockedCommand(String command) {
    return _blockedCommandPatterns.any((pattern) => pattern.hasMatch(command));
  }

  ({String executable, List<String> arguments}) _shellForPlatform(
    String command,
  ) {
    if (Platform.isWindows) {
      return (executable: 'cmd', arguments: <String>['/C', command]);
    }
    return (executable: 'bash', arguments: <String>['-lc', command]);
  }

  Future<void> _collectProcessOutput(
    Stream<List<int>> stream, {
    required _BoundedOutputCollector collector,
    required String streamLabel,
  }) async {
    try {
      await for (final chunk in stream.transform(
        const Utf8Decoder(allowMalformed: true),
      )) {
        collector.add(chunk);
      }
    } catch (error) {
      collector.add('\n[$streamLabel stream error: $error]');
    }
  }
}

class _BoundedOutputCollector {
  final int _limit;
  final StringBuffer _buffer = StringBuffer();
  bool _truncated = false;

  _BoundedOutputCollector(this._limit);

  void add(String chunk) {
    if (chunk.isEmpty) {
      return;
    }

    if (_buffer.length >= _limit) {
      _truncated = true;
      return;
    }

    final remaining = _limit - _buffer.length;
    if (chunk.length <= remaining) {
      _buffer.write(chunk);
      return;
    }

    _buffer.write(chunk.substring(0, remaining));
    _truncated = true;
  }

  String build() {
    if (!_truncated) {
      return _buffer.toString();
    }
    return '${_buffer.toString()}\n...[truncated]';
  }
}

String formatToolArguments(Map<String, dynamic> arguments) {
  if (arguments.isEmpty) {
    return '';
  }

  final orderedKeys = arguments.keys.toList(growable: false)..sort();
  return orderedKeys
      .map((key) => '$key=${_inlineValue(arguments[key])}')
      .join(', ');
}

String _inlineValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return value;
  }
  if (value is num || value is bool) {
    return '$value';
  }
  try {
    return jsonEncode(value);
  } catch (_) {
    return '$value';
  }
}

String workspaceDisplayPath(String workspaceRoot) {
  final normalized = p.normalize(workspaceRoot);
  return normalized.isEmpty ? '.' : normalized;
}
