import 'dart:io';

import 'package:path/path.dart' as p;

class WorkspaceGuard {
  final String _workspaceRoot;
  final String _workspaceCanonicalRoot;

  WorkspaceGuard(String workspaceRoot)
    : _workspaceRoot = p.normalize(p.absolute(workspaceRoot)),
      _workspaceCanonicalRoot = _resolveExistingPath(
        p.normalize(p.absolute(workspaceRoot)),
      ) {
    if (!Directory(_workspaceRoot).existsSync()) {
      throw FileSystemException(
        'Workspace directory not found',
        _workspaceRoot,
      );
    }
  }

  String get workspaceRoot => _workspaceRoot;

  String resolvePath(String input, {String? from}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return from == null ? _workspaceRoot : resolvePath(from);
    }

    final base = from == null ? _workspaceRoot : resolvePath(from);
    final absolute = p.normalize(
      p.absolute(p.isAbsolute(trimmed) ? trimmed : p.join(base, trimmed)),
    );
    final canonical = _resolveExistingPath(absolute);

    if (!_isInsideWorkspace(canonical)) {
      throw ArgumentError('Path escapes workspace root: $input');
    }

    return absolute;
  }

  String toWorkspaceRelative(String absolutePath) {
    final normalized = p.normalize(p.absolute(absolutePath));
    final canonical = _resolveExistingPath(normalized);
    if (!_isInsideWorkspace(canonical)) {
      return normalized;
    }

    final relative = p.relative(normalized, from: _workspaceRoot);
    return relative.isEmpty ? '.' : relative;
  }

  bool _isInsideWorkspace(String candidate) {
    return candidate == _workspaceCanonicalRoot ||
        p.isWithin(_workspaceCanonicalRoot, candidate);
  }

  static String _resolveExistingPath(String path) {
    final normalized = p.normalize(path);
    final entityType = FileSystemEntity.typeSync(normalized, followLinks: true);

    if (entityType == FileSystemEntityType.notFound) {
      final parentPath = p.dirname(normalized);
      if (parentPath == normalized) {
        return normalized;
      }
      final resolvedParent = _resolveExistingPath(parentPath);
      return p.normalize(p.join(resolvedParent, p.basename(normalized)));
    }

    try {
      switch (entityType) {
        case FileSystemEntityType.directory:
          return p.normalize(Directory(normalized).resolveSymbolicLinksSync());
        case FileSystemEntityType.file:
          return p.normalize(File(normalized).resolveSymbolicLinksSync());
        case FileSystemEntityType.link:
          return p.normalize(Link(normalized).resolveSymbolicLinksSync());
        case FileSystemEntityType.pipe:
          return normalized;
        case FileSystemEntityType.unixDomainSock:
          return normalized;
        case FileSystemEntityType.notFound:
          return normalized;
      }
    } catch (_) {
      return normalized;
    }

    return normalized;
  }
}
