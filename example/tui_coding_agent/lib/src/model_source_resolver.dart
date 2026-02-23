import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class HfModelSpec {
  final String repository;
  final String? fileHint;

  const HfModelSpec({required this.repository, this.fileHint});

  static HfModelSpec parse(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Model source cannot be empty.');
    }

    final separatorIndex = trimmed.indexOf(':');
    final repository = separatorIndex == -1
        ? trimmed
        : trimmed.substring(0, separatorIndex).trim();
    final fileHint = separatorIndex == -1
        ? null
        : trimmed.substring(separatorIndex + 1).trim();

    if (!repository.contains('/')) {
      throw FormatException(
        'Invalid Hugging Face model spec "$source". Expected owner/repo[:hint].',
      );
    }

    return HfModelSpec(
      repository: repository,
      fileHint: fileHint == null || fileHint.isEmpty ? null : fileHint,
    );
  }
}

class ModelDownloadProgress {
  final int receivedBytes;
  final int? totalBytes;

  const ModelDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }

    final ratio = receivedBytes / total;
    if (ratio < 0) {
      return 0;
    }
    if (ratio > 1) {
      return 1;
    }
    return ratio;
  }
}

class ResolvedModelSource {
  final String requestedSource;
  final String localPath;
  final bool downloaded;

  const ResolvedModelSource({
    required this.requestedSource,
    required this.localPath,
    required this.downloaded,
  });
}

class ModelSourceResolver {
  final String _workspaceRoot;
  final String _cacheDirectory;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  ModelSourceResolver({
    required String workspaceRoot,
    required String cacheDirectory,
    http.Client? httpClient,
  }) : _workspaceRoot = p.normalize(p.absolute(workspaceRoot)),
       _cacheDirectory = p.normalize(p.absolute(cacheDirectory)),
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  Future<ResolvedModelSource> resolve(
    String source, {
    void Function(String status)? onStatus,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Model source cannot be empty.');
    }

    final localPath = _resolveLocalPath(trimmed);
    if (localPath != null) {
      return ResolvedModelSource(
        requestedSource: source,
        localPath: localPath,
        downloaded: false,
      );
    }

    if (_isHttpUrl(trimmed)) {
      final downloadedPath = await _downloadIfNeeded(
        Uri.parse(trimmed),
        onStatus: onStatus,
        onProgress: onProgress,
      );
      return ResolvedModelSource(
        requestedSource: source,
        localPath: downloadedPath,
        downloaded: true,
      );
    }

    if (_looksLikeHfSpec(trimmed)) {
      final hfSpec = HfModelSpec.parse(trimmed);
      final fileName = await _resolveHfFileName(hfSpec);
      final downloadUri = _buildHfDownloadUri(hfSpec.repository, fileName);
      onStatus?.call('Resolved ${hfSpec.repository} to $fileName');

      final downloadedPath = await _downloadIfNeeded(
        downloadUri,
        forceFileName: p.basename(fileName),
        onStatus: onStatus,
        onProgress: onProgress,
      );
      return ResolvedModelSource(
        requestedSource: source,
        localPath: downloadedPath,
        downloaded: true,
      );
    }

    throw FileSystemException(
      'Model source not found. Use a local path, URL, or owner/repo[:hint] Hugging Face spec.',
      source,
    );
  }

  String? _resolveLocalPath(String source) {
    final asIs = File(source);
    if (asIs.existsSync()) {
      return asIs.absolute.path;
    }

    final fromWorkspace = File(p.join(_workspaceRoot, source));
    if (fromWorkspace.existsSync()) {
      return fromWorkspace.absolute.path;
    }

    return null;
  }

  bool _looksLikeHfSpec(String source) {
    if (source.startsWith('.') || source.startsWith('/')) {
      return false;
    }
    if (source.contains('\\') || source.toLowerCase().endsWith('.gguf')) {
      return false;
    }

    final repositoryPart = source.split(':').first;
    final segments = repositoryPart.split('/');
    if (segments.length != 2) {
      return false;
    }

    return segments.every(
      (segment) => segment.trim().isNotEmpty && !segment.contains(' '),
    );
  }

  bool _isHttpUrl(String source) {
    return source.startsWith('http://') || source.startsWith('https://');
  }

  Future<String> _resolveHfFileName(HfModelSpec spec) async {
    final hint = spec.fileHint;
    if (hint != null && hint.toLowerCase().endsWith('.gguf')) {
      return hint;
    }

    final endpoint = Uri.https(
      'huggingface.co',
      '/api/models/${spec.repository}',
    );
    final response = await _httpClient.get(endpoint);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Failed to inspect ${spec.repository} (HTTP ${response.statusCode}).',
        uri: endpoint,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Hugging Face API response body.');
    }

    final siblings = decoded['siblings'];
    if (siblings is! List) {
      throw const FormatException('Missing siblings list in Hugging Face API.');
    }

    final files = <String>[];
    for (final item in siblings) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final filename = item['rfilename'];
      if (filename is String && filename.isNotEmpty) {
        files.add(filename);
      }
    }

    return selectBestGgufFile(files, hint: hint);
  }

  Uri _buildHfDownloadUri(String repository, String fileName) {
    final segments = <String>[
      ...repository.split('/').where((segment) => segment.isNotEmpty),
      'resolve',
      'main',
      ...fileName.split('/').where((segment) => segment.isNotEmpty),
    ];
    return Uri.https(
      'huggingface.co',
      '/${segments.join('/')}',
      <String, String>{'download': 'true'},
    );
  }

  Future<String> _downloadIfNeeded(
    Uri uri, {
    String? forceFileName,
    void Function(String status)? onStatus,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    final modelsDir = Directory(_cacheDirectory);
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final fileName = forceFileName ?? _fileNameFromUri(uri);
    final targetFile = File(p.join(modelsDir.path, fileName));
    final tempFile = File('${targetFile.path}.download');

    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      final bytes = targetFile.lengthSync();
      onProgress?.call(
        ModelDownloadProgress(receivedBytes: bytes, totalBytes: bytes),
      );
      return targetFile.absolute.path;
    }

    var resumeOffset = tempFile.existsSync() ? tempFile.lengthSync() : 0;

    final request = http.Request('GET', uri);
    if (resumeOffset > 0) {
      request.headers[HttpHeaders.rangeHeader] = 'bytes=$resumeOffset-';
    }

    onStatus?.call('Downloading $fileName');
    final response = await _httpClient.send(request);
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw HttpException(
        'Failed to download model (HTTP ${response.statusCode}).',
        uri: uri,
      );
    }

    final appendMode =
        response.statusCode == HttpStatus.partialContent && resumeOffset > 0;
    if (!appendMode) {
      resumeOffset = 0;
    }

    final contentLength = response.contentLength;
    final totalBytes = contentLength == null || contentLength <= 0
        ? null
        : contentLength + (appendMode ? resumeOffset : 0);

    final sink = tempFile.openWrite(
      mode: appendMode ? FileMode.append : FileMode.write,
    );

    try {
      var receivedBytes = resumeOffset;
      if (receivedBytes > 0) {
        onProgress?.call(
          ModelDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(
          ModelDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
          ),
        );
      }

      await sink.flush();
    } finally {
      await sink.close();
    }

    if (targetFile.existsSync()) {
      await targetFile.delete();
    }

    await tempFile.rename(targetFile.path);
    final finalBytes = targetFile.lengthSync();
    onProgress?.call(
      ModelDownloadProgress(
        receivedBytes: finalBytes,
        totalBytes: totalBytes ?? finalBytes,
      ),
    );

    return targetFile.absolute.path;
  }

  String _fileNameFromUri(Uri uri) {
    if (uri.pathSegments.isEmpty) {
      return 'model.gguf';
    }
    final name = uri.pathSegments.last;
    if (name.isEmpty) {
      return 'model.gguf';
    }
    return name;
  }
}

String selectBestGgufFile(List<String> files, {String? hint}) {
  final ggufFiles = files
      .where((file) => file.toLowerCase().endsWith('.gguf'))
      .toList(growable: false);
  if (ggufFiles.isEmpty) {
    throw const FormatException('No GGUF files found in Hugging Face repo.');
  }

  if (hint == null || hint.trim().isEmpty) {
    final sorted = ggufFiles.toList()..sort();
    return sorted.first;
  }

  final loweredHint = hint.toLowerCase();
  final exactNeedle = loweredHint.endsWith('.gguf')
      ? loweredHint
      : '$loweredHint.gguf';

  final exactMatches = ggufFiles
      .where((file) => file.toLowerCase() == exactNeedle)
      .toList(growable: false);
  if (exactMatches.isNotEmpty) {
    final sorted = exactMatches.toList()..sort();
    return sorted.first;
  }

  final normalizedHint = _normalizeHint(loweredHint);
  final partialMatches = ggufFiles
      .where((file) => _normalizeHint(file).contains(normalizedHint))
      .toList(growable: false);
  if (partialMatches.isNotEmpty) {
    partialMatches.sort((a, b) {
      final lengthComparison = a.length.compareTo(b.length);
      if (lengthComparison != 0) {
        return lengthComparison;
      }
      return a.compareTo(b);
    });
    return partialMatches.first;
  }

  throw FormatException(
    'No GGUF file matched "$hint". Available files: ${ggufFiles.join(', ')}',
  );
}

String _normalizeHint(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
