import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/downloadable_model.dart';
import 'model_service_base.dart';

class ModelServiceWeb implements ModelService {
  static const String _downloadedModelsKey = 'web_cached_models';
  static const String _hfToken = String.fromEnvironment('HF_TOKEN');

  final Dio _dio = Dio();

  Map<String, Object>? _requestHeaders() {
    final token = _hfToken.trim();
    if (token.isEmpty) {
      return null;
    }
    return <String, Object>{'authorization': 'Bearer $token'};
  }

  @override
  Future<String> getModelsDirectory() async => 'browser-cache';

  @override
  Future<Set<String>> getDownloadedModels(
    List<DownloadableModel> models,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList(_downloadedModelsKey) ?? const [];
    final valid = models.map((m) => m.filename).toSet();
    return downloaded.where(valid.contains).toSet();
  }

  @override
  Future<void> downloadModel({
    required DownloadableModel model,
    required String modelsDir,
    required CancelToken cancelToken,
    required Function(double progress) onProgress,
    Function(ModelDownloadProgress progress)? onProgressDetail,
    required Function(String filename) onSuccess,
    required Function(dynamic error) onError,
  }) async {
    final hasMmproj = model.mmprojUrl != null && model.mmprojUrl!.isNotEmpty;
    final stageCount = hasMmproj ? 2 : 1;
    final aggregate = ModelDownloadProgressTracker(
      includeMmproj: hasMmproj,
      providedTotalBytes: model.sizeBytes > 0 ? model.sizeBytes : null,
    );

    try {
      // Web avoids buffering full GGUF bytes in app memory during pre-download.
      // The runtime bridge handles actual byte caching on first model load.
      await _verifyRemoteStage(
        model.url,
        stage: ModelDownloadStage.model,
        stageIndex: 1,
        stageCount: stageCount,
        cancelToken: cancelToken,
        aggregate: aggregate,
        updateStage: aggregate.updateModel,
        onProgress: onProgress,
        onProgressDetail: onProgressDetail,
      );

      if (hasMmproj) {
        await _verifyRemoteStage(
          model.mmprojUrl!,
          stage: ModelDownloadStage.multimodalProjector,
          stageIndex: 2,
          stageCount: stageCount,
          cancelToken: cancelToken,
          aggregate: aggregate,
          updateStage: aggregate.updateMmproj,
          onProgress: onProgress,
          onProgressDetail: onProgressDetail,
        );
      }

      final finalDetail = aggregate.finalProgress(stageCount: stageCount);
      onProgress(finalDetail.overallProgress);
      onProgressDetail?.call(finalDetail);

      final prefs = await SharedPreferences.getInstance();
      final downloaded =
          prefs.getStringList(_downloadedModelsKey) ?? <String>[];
      if (!downloaded.contains(model.filename)) {
        downloaded.add(model.filename);
        await prefs.setStringList(_downloadedModelsKey, downloaded);
      }

      onSuccess(model.filename);
    } catch (error) {
      onError(error);
    }
  }

  Future<void> _verifyRemoteStage(
    String url, {
    required ModelDownloadStage stage,
    required int stageIndex,
    required int stageCount,
    required CancelToken cancelToken,
    required ModelDownloadProgressTracker aggregate,
    required void Function(int downloadedBytes, int? totalBytes) updateStage,
    required Function(double progress) onProgress,
    Function(ModelDownloadProgress progress)? onProgressDetail,
  }) async {
    final stageTotalBytes = await _resolveRemoteLength(
      url: url,
      cancelToken: cancelToken,
    );

    updateStage(0, stageTotalBytes);
    final initial = aggregate.buildProgress(
      stage: stage,
      stageIndex: stageIndex,
      stageCount: stageCount,
      stageDownloadedBytes: 0,
      stageTotalBytes: stageTotalBytes,
      resumed: false,
    );
    onProgress(initial.overallProgress);
    onProgressDetail?.call(initial);

    final completedBytes = stageTotalBytes != null && stageTotalBytes > 0
        ? stageTotalBytes
        : 1;
    final normalizedStageTotal = stageTotalBytes ?? completedBytes;
    updateStage(completedBytes, normalizedStageTotal);

    final completed = aggregate.buildProgress(
      stage: stage,
      stageIndex: stageIndex,
      stageCount: stageCount,
      stageDownloadedBytes: completedBytes,
      stageTotalBytes: normalizedStageTotal,
      resumed: false,
    );
    onProgress(completed.overallProgress);
    onProgressDetail?.call(completed);
  }

  Future<int?> _resolveRemoteLength({
    required String url,
    required CancelToken cancelToken,
  }) async {
    final response = await _dio.head<void>(
      url,
      cancelToken: cancelToken,
      options: Options(
        headers: _requestHeaders(),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 500,
      ),
    );

    final statusCode = response.statusCode ?? 500;
    if (statusCode >= 400) {
      throw DioException.badResponse(
        statusCode: statusCode,
        requestOptions: response.requestOptions,
        response: response,
      );
    }

    return int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    );
  }

  @override
  Future<void> deleteModel(String modelsDir, DownloadableModel model) async {
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList(_downloadedModelsKey) ?? <String>[];
    downloaded.remove(model.filename);
    await prefs.setStringList(_downloadedModelsKey, downloaded);
  }
}

ModelService createModelService() => ModelServiceWeb();
