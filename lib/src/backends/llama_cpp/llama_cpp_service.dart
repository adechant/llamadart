import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import '../../core/models/chat/content_part.dart';
import '../../core/models/config/gpu_backend.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/inference/generation_params.dart';
import '../../core/models/inference/model_params.dart';
import '../generated/llama_cpp.dart';

/// Service responsible for managing Llama.cpp models and contexts.
///
/// This service handles the direct interaction with the native Llama.cpp library,
/// including loading models, creating contexts, managing memory, and running inference.
class LlamaCppService {
  static llama_cpp? _lib;
  static llama_cpp get lib {
    if (_lib == null) {
      if (Platform.isAndroid) {
        _lib = llama_cpp(DynamicLibrary.open("libllama.so"));
      } else if (Platform.isLinux) {
        _lib = llama_cpp(DynamicLibrary.open("libllama.so"));
      } else if (Platform.isWindows) {
        _lib = llama_cpp(DynamicLibrary.open("./llama.dll"));
      } else if (Platform.isMacOS) {
        _lib = llama_cpp(DynamicLibrary.open("libllama.dylib"));
      } else {
        throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
      }
    }
    return _lib!;
  }

  int _nextHandle = 1;
  LlamaLogLevel _configuredLogLevel = LlamaLogLevel.warn;
  int _activeResolvedGpuLayers = 0;
  bool _mtmdPrimarySymbolsUnavailable = false;

  // --- Internal State ---
  final Map<int, _LlamaModelWrapper> _models = {};
  final Map<int, _LlamaContextWrapper> _contexts = {};
  final Map<int, int> _contextToModel = {};
  final Map<int, Pointer<llama_sampler>> _samplers = {};
  final Map<int, llama_batch> _batches = {};
  final Map<int, llama_context_params> _contextParams = {};
  final Map<int, Map<String, _LlamaLoraWrapper>> _loraAdapters = {};
  final Map<int, Map<String, double>> _activeLoras = {};
  final Map<int, int> _modelResolvedGpuLayers = <int, int>{};

  // Mapping: modelHandle -> mtmdContextHandle
  final Map<int, int> _modelToMtmd = {};
  final Map<int, Pointer<mtmd_context>> _mtmdContexts = {};
  final Map<int, bool> _modelToMtmdUseGpu = {};

  int _getHandle() => _nextHandle++;

  /// Resolves the effective GPU layer count for model loading.
  ///
  /// CPU backend preference always forces zero offloaded layers.
  static int resolveGpuLayersForLoad(ModelParams modelParams) {
    return modelParams.preferredBackend == GpuBackend.cpu
        ? 0
        : modelParams.gpuLayers;
  }

  /// Returns whether context-time GPU offload should be disabled.
  ///
  /// When CPU mode is selected (or model load resolved to zero GPU layers),
  /// context-level offload knobs must also be disabled to prevent runtime
  /// GPU initialization during `llama_init_from_model(...)`.
  static bool shouldDisableContextGpuOffload(
    ModelParams modelParams, {
    int? resolvedGpuLayers,
  }) {
    final effectiveGpuLayers =
        resolvedGpuLayers ?? resolveGpuLayersForLoad(modelParams);
    return modelParams.preferredBackend == GpuBackend.cpu ||
        effectiveGpuLayers <= 0;
  }

  /// Resolves effective context batch parameters.
  ///
  /// Legacy behavior is preserved when [ModelParams.batchSize] and
  /// [ModelParams.microBatchSize] are not set:
  ///
  /// - `n_batch = n_ctx`
  /// - `n_ubatch = n_batch`
  ///
  /// Values are clamped to safe bounds so `n_ubatch <= n_batch <= n_ctx`.
  static ({int batchSize, int microBatchSize}) resolveContextBatchSizes(
    ModelParams modelParams,
    int contextSize,
  ) {
    final effectiveContextSize = contextSize > 0 ? contextSize : 1;

    final configuredBatchSize = modelParams.batchSize > 0
        ? modelParams.batchSize
        : effectiveContextSize;
    final cappedBatchSize = configuredBatchSize > effectiveContextSize
        ? effectiveContextSize
        : configuredBatchSize;
    final batchSize = cappedBatchSize > 0 ? cappedBatchSize : 1;

    final configuredMicroBatchSize = modelParams.microBatchSize > 0
        ? modelParams.microBatchSize
        : batchSize;
    final cappedMicroBatchSize = configuredMicroBatchSize > batchSize
        ? batchSize
        : configuredMicroBatchSize;
    final microBatchSize = cappedMicroBatchSize > 0 ? cappedMicroBatchSize : 1;

    return (batchSize: batchSize, microBatchSize: microBatchSize);
  }

  /// Resolves whether multimodal projector init should use GPU.
  ///
  /// This follows effective model-load configuration from model loading.
  static bool resolveMtmdUseGpuForLoad(
    ModelParams modelParams,
    int effectiveGpuLayers,
  ) {
    return !shouldDisableContextGpuOffload(
      modelParams,
      resolvedGpuLayers: effectiveGpuLayers,
    );
  }

  // --- Core Methods ---

  /// Sets the log level for the Llama.cpp library.
  void setLogLevel(LlamaLogLevel level) {
    _configuredLogLevel = level;
    _applyConfiguredLogLevel();
  }

  void _applyConfiguredLogLevel() {
    try {
      lib.common_log_set_verbosity_thold(_configuredLogLevel.index);
    } on ArgumentError {
      // Continue with explicit fallback lookup below.
    }

    // mtmd/clip uses its own logger callback chain; mirror llama logger so
    // multimodal projector logs honor the same configured native log level.
    _syncMtmdLogCallbackToLlamaLogger();
  }

  void _syncMtmdLogCallbackToLlamaLogger() {
    final logCallbackPtr = malloc<ggml_log_callback>();
    final userDataPtr = malloc<Pointer<Void>>();

    try {
      try {
        lib.llama_log_get(logCallbackPtr, userDataPtr);
      } on ArgumentError {
        return;
      }

      final callback = logCallbackPtr.value;
      final userData = userDataPtr.value;
      if (callback == nullptr) {
        return;
      }

      if (!_mtmdPrimarySymbolsUnavailable) {
        try {
          lib.mtmd_log_set(callback, userData);
        } on ArgumentError {
          _mtmdPrimarySymbolsUnavailable = true;
        }
      }
    } finally {
      malloc.free(logCallbackPtr);
      malloc.free(userDataPtr);
    }
  }

  /// Initializes the Llama.cpp backend.
  ///
  /// This must be called before loading any models.
  void initializeBackend() {
    _applyConfiguredLogLevel();
    lib.llama_backend_init();
  }

  /// Loads a model from the specified [modelPath].
  ///
  /// Returns a handle to the loaded model.
  /// Throws an [Exception] if the file does not exist or fails to load.
  int loadModel(String modelPath, ModelParams modelParams) {
    final modelFile = File(modelPath);
    if (!modelFile.existsSync()) {
      throw Exception("File not found: $modelPath");
    }
    final modelFileSize = modelFile.lengthSync();
    if (modelFileSize <= 0) {
      throw Exception("Model file is empty: $modelPath");
    }
    if (!_looksLikeGguf(modelFile)) {
      throw Exception(
        "Model file does not appear to be GGUF: $modelPath. "
        "Please verify the download completed correctly.",
      );
    }

    _applyConfiguredLogLevel();

    final modelPathPtr = modelPath.toNativeUtf8();
    final mparams = lib.llama_model_default_params();
    var gpuLayers = resolveGpuLayersForLoad(modelParams);
    var forcedCpuFallback = false;

    final explicitGpuBackend =
        modelParams.preferredBackend != GpuBackend.auto &&
        modelParams.preferredBackend != GpuBackend.cpu;
    if (explicitGpuBackend) {
      // Honor explicit backend intent: if requested GPU backend is unavailable,
      // fall back to CPU instead of letting another GPU backend auto-select.
      // TODO: implement check for gpu availability
      gpuLayers = 0;
      forcedCpuFallback = true;
    }
    final mtmdUseGpu = resolveMtmdUseGpuForLoad(modelParams, gpuLayers);

    mparams.n_gpu_layers = gpuLayers;
    mparams.use_mmap = true;

    Pointer<llama_model> modelPtr = nullptr;
    try {
      modelPtr = lib.llama_model_load_from_file(modelPathPtr.cast(), mparams);
    } finally {
      malloc.free(modelPathPtr);
    }

    if (modelPtr == nullptr) {
      throw Exception("Failed to load model (size=$modelFileSize bytes");
    }

    final handle = _getHandle();
    _models[handle] = _LlamaModelWrapper(modelPtr, lib);
    _loraAdapters[handle] = {};
    _modelToMtmdUseGpu[handle] = mtmdUseGpu;
    _modelResolvedGpuLayers[handle] = gpuLayers;
    _activeResolvedGpuLayers = gpuLayers;

    return handle;
  }

  static bool _looksLikeGguf(File modelFile) {
    try {
      final header = modelFile.openSync(mode: FileMode.read);
      try {
        final magic = header.readSync(4);
        if (magic.length < 4) {
          return false;
        }
        return magic[0] == 0x47 &&
            magic[1] == 0x47 &&
            magic[2] == 0x55 &&
            magic[3] == 0x46;
      } finally {
        header.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  /// Frees the model associated with [modelHandle].
  ///
  /// This also frees all contexts and LoRA adapters associated with the model.
  void freeModel(int modelHandle) {
    final model = _models.remove(modelHandle);
    _modelToMtmdUseGpu.remove(modelHandle);
    if (model != null) {
      final contextsToRemove = _contextToModel.entries
          .where((e) => e.value == modelHandle)
          .map((e) => e.key)
          .toList();
      for (final ctxHandle in contextsToRemove) {
        _freeContext(ctxHandle);
      }
      final adapters = _loraAdapters.remove(modelHandle);
      adapters?.values.forEach((a) => a.dispose());

      // Free associated multimodal context
      final mmHandle = _modelToMtmd.remove(modelHandle);
      if (mmHandle != null) {
        final mmCtx = _mtmdContexts.remove(mmHandle);
        if (mmCtx != null) lib.mtmd_free(mmCtx);
      }

      model.dispose();
    }

    _modelResolvedGpuLayers.remove(modelHandle);
    _activeResolvedGpuLayers = 0;
  }

  /// Creates an inference context for the specified [modelHandle].
  ///
  /// Returns a handle to the created context.
  /// Throws an [Exception] if the model handle is invalid or context creation fails.
  int createContext(int modelHandle, ModelParams params) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }

    final ctxParams = lib.llama_context_default_params();
    int nCtx = params.contextSize;
    if (nCtx <= 0) {
      nCtx = lib.llama_model_n_ctx_train(model.pointer);
    }
    final resolvedBatchSizes = resolveContextBatchSizes(params, nCtx);
    final maxSeqLimit = lib.llama_max_parallel_sequences();
    final resolvedMaxParallelSequences = math.max(
      1,
      math.min(params.maxParallelSequences, maxSeqLimit),
    );

    ctxParams.n_ctx = nCtx;
    ctxParams.n_batch = resolvedBatchSizes.batchSize;
    ctxParams.n_ubatch = resolvedBatchSizes.microBatchSize;
    ctxParams.n_seq_max = resolvedMaxParallelSequences;
    ctxParams.n_threads = params.numberOfThreads;
    ctxParams.n_threads_batch = params.numberOfThreadsBatch;
    if (resolvedMaxParallelSequences > 1) {
      // Keep per-sequence context at full n_ctx when multiple sequence slots
      // are enabled so regular generation behavior is unchanged.
      ctxParams.kv_unified = true;
    }

    final resolvedModelGpuLayers = _modelResolvedGpuLayers[modelHandle];
    if (shouldDisableContextGpuOffload(
      params,
      resolvedGpuLayers: resolvedModelGpuLayers,
    )) {
      ctxParams.offload_kqv = false;
      ctxParams.op_offload = false;
      ctxParams.flash_attn_typeAsInt =
          llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value;
    }

    final ctxPtr = lib.llama_init_from_model(model.pointer, ctxParams);
    if (ctxPtr == nullptr) {
      throw Exception("Failed to create context");
    }

    final handle = _getHandle();
    _contexts[handle] = _LlamaContextWrapper(ctxPtr, model, lib);
    _contextToModel[handle] = modelHandle;
    _activeLoras[handle] = {};
    _contextParams[handle] = ctxParams;
    _samplers[handle] = lib.llama_sampler_chain_init(
      lib.llama_sampler_chain_default_params(),
    );
    _batches[handle] = lib.llama_batch_init(resolvedBatchSizes.batchSize, 0, 1);

    return handle;
  }

  /// Frees the context associated with [contextHandle].
  void freeContext(int contextHandle) {
    _freeContext(contextHandle);
  }

  void _freeContext(int handle) {
    _contextToModel.remove(handle);
    _activeLoras.remove(handle);
    _contextParams.remove(handle);
    final sampler = _samplers.remove(handle);
    if (sampler != null && sampler != nullptr) lib.llama_sampler_free(sampler);
    final batch = _batches.remove(handle);
    if (batch != null) lib.llama_batch_free(batch);
    _contexts.remove(handle)?.dispose();
  }

  /// Generates text based on the given [prompt] and [params].
  ///
  /// Returns a [Stream] of token bytes.
  /// Supports multimodal input via [parts].
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params,
    int cancelTokenAddress, {
    List<LlamaContentPart>? parts,
  }) async* {
    var ctx = _contexts[contextHandle];
    if (ctx == null) throw Exception("Invalid context handle");

    final modelHandle = _contextToModel[contextHandle]!;
    final model = _models[modelHandle]!;
    final modelParams = _contextParams[contextHandle]!;
    final vocab = lib.llama_model_get_vocab(model.pointer);
    final hasMediaParts =
        parts?.any((p) => p is LlamaImageContent || p is LlamaAudioContent) ??
        false;

    // 1. Reset Context
    ctx = _resetContext(
      contextHandle,
      ctx,
      clearMemory: hasMediaParts || !params.reusePromptPrefix,
    );

    // 2. Prepare Resources
    final nCtx = lib.llama_n_ctx(ctx.pointer);
    final batch = _batches[contextHandle]!;
    final tokensPtr = malloc<Int32>(nCtx);
    final pieceBuf = malloc<Uint8>(256);
    Pointer<Utf8> grammarPtr = nullptr;
    Pointer<Utf8> rootPtr = nullptr;
    _LazyGrammarConfig? lazyGrammarConfig;

    if (params.grammar != null) {
      grammarPtr = params.grammar!.toNativeUtf8();
      rootPtr = params.grammarRoot.toNativeUtf8();
      if (params.grammarLazy && params.grammarTriggers.isNotEmpty) {
        lazyGrammarConfig = _buildLazyGrammarConfig(params);
      }
    }

    try {
      // 3. Ingest Prompt (Text or Multimodal)
      final initialTokens = _ingestPrompt(
        contextHandle,
        modelHandle,
        ctx,
        batch,
        vocab,
        prompt,
        parts,
        tokensPtr,
        nCtx,
        modelParams,
        allowTextPromptReuse: !hasMediaParts && params.reusePromptPrefix,
      );

      // 4. Initialize and Run Sampler Loop
      final sampler = _initializeSampler(
        params,
        vocab,
        grammarPtr,
        rootPtr,
        lazyGrammarConfig,
        initialTokens,
        tokensPtr,
      );

      final preservedTokenIds = _resolvePreservedTokenIds(
        vocab,
        params.preservedTokens,
      );
      final effectiveStopSequences = _effectiveStopSequences(
        params.stopSequences,
        params.preservedTokens,
      );

      yield* _runInferenceLoop(
        ctx,
        batch,
        vocab,
        sampler,
        params,
        initialTokens,
        nCtx,
        cancelTokenAddress,
        pieceBuf,
        grammarPtr,
        preservedTokenIds,
        effectiveStopSequences,
      );

      lib.llama_sampler_free(sampler);
    } finally {
      malloc.free(tokensPtr);
      malloc.free(pieceBuf);
      if (grammarPtr != nullptr) malloc.free(grammarPtr);
      if (rootPtr != nullptr) malloc.free(rootPtr);
      lazyGrammarConfig?.dispose();
    }
  }

  /// Generates a single embedding vector for [text].
  List<double> embed(int contextHandle, String text, {bool normalize = true}) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw Exception('Invalid context handle');
    }

    final modelHandle = _contextToModel[contextHandle];
    if (modelHandle == null) {
      throw Exception('Invalid context handle');
    }

    final model = _models[modelHandle];
    if (model == null) {
      throw Exception('Invalid model handle');
    }

    final contextParams = _contextParams[contextHandle];
    if (contextParams == null) {
      throw Exception('Missing context parameters');
    }

    final hasEncoder = lib.llama_model_has_encoder(model.pointer);
    final hasDecoder = lib.llama_model_has_decoder(model.pointer);
    if (hasEncoder && hasDecoder) {
      throw Exception(
        'Embedding extraction for encoder-decoder models is not supported',
      );
    }
    final useEncoderPath = hasEncoder && !hasDecoder;

    final vocab = lib.llama_model_get_vocab(model.pointer);
    final nSeqCtx = lib.llama_n_ctx_seq(ctx.pointer);
    final tokens = _tokenizeEmbeddingText(vocab, text, nSeqCtx);
    final configuredBatchSize = contextParams.n_batch > 0
        ? contextParams.n_batch
        : tokens.length;
    final batchCapacity = math.max(
      1,
      math.min(configuredBatchSize, tokens.length),
    );
    final batch = lib.llama_batch_init(batchCapacity, 0, 1);
    final embeddingSize = _resolveEmbeddingDimension(model.pointer);

    try {
      lib.llama_synchronize(ctx.pointer);
      _clearContextMemory(ctx.pointer, strict: false);
      ctx.cachedPromptTokens = null;
      lib.llama_set_embeddings(ctx.pointer, true);

      var decodedTokens = 0;
      while (decodedTokens < tokens.length) {
        final remaining = tokens.length - decodedTokens;
        final chunkTokenCount = math.min(batchCapacity, remaining);
        batch.n_tokens = chunkTokenCount;

        for (int i = 0; i < chunkTokenCount; i++) {
          final tokenIndex = decodedTokens + i;
          batch.token[i] = tokens[tokenIndex];
          batch.pos[i] = tokenIndex;
          batch.n_seq_id[i] = 1;
          batch.seq_id[i][0] = 0;
          batch.logits[i] = 1;
        }

        final status = useEncoderPath
            ? lib.llama_encode(ctx.pointer, batch)
            : lib.llama_decode(ctx.pointer, batch);
        if (status != 0) {
          throw Exception('Embedding forward pass failed');
        }

        decodedTokens += chunkTokenCount;
      }

      final poolingType = lib.llama_pooling_type$1(ctx.pointer);
      Pointer<Float> embeddingPtr;
      if (poolingType == llama_pooling_type.LLAMA_POOLING_TYPE_NONE) {
        embeddingPtr = lib.llama_get_embeddings_ith(
          ctx.pointer,
          batch.n_tokens - 1,
        );
        if (embeddingPtr == nullptr) {
          embeddingPtr = lib.llama_get_embeddings(ctx.pointer);
        }
      } else {
        embeddingPtr = lib.llama_get_embeddings_seq(ctx.pointer, 0);
        if (embeddingPtr == nullptr) {
          embeddingPtr = lib.llama_get_embeddings(ctx.pointer);
        }
      }

      if (embeddingPtr == nullptr) {
        throw Exception('Embedding output is unavailable');
      }

      final vector = List<double>.from(
        embeddingPtr.asTypedList(embeddingSize),
        growable: false,
      );

      if (!normalize) {
        return vector;
      }

      return _normalizeEmbeddingVector(vector);
    } finally {
      lib.llama_set_embeddings(ctx.pointer, false);
      lib.llama_batch_free(batch);
    }
  }

  /// Generates embedding vectors for [texts] in input order.
  List<List<double>> embedBatch(
    int contextHandle,
    List<String> texts, {
    bool normalize = true,
  }) {
    if (texts.isEmpty) {
      return const <List<double>>[];
    }

    final ctx = _contexts[contextHandle];
    if (ctx == null) {
      throw Exception('Invalid context handle');
    }

    final modelHandle = _contextToModel[contextHandle];
    if (modelHandle == null) {
      throw Exception('Invalid context handle');
    }

    final model = _models[modelHandle];
    if (model == null) {
      throw Exception('Invalid model handle');
    }

    final contextParams = _contextParams[contextHandle];
    if (contextParams == null) {
      throw Exception('Missing context parameters');
    }

    final hasEncoder = lib.llama_model_has_encoder(model.pointer);
    final hasDecoder = lib.llama_model_has_decoder(model.pointer);
    if (hasEncoder && hasDecoder) {
      throw Exception(
        'Embedding extraction for encoder-decoder models is not supported',
      );
    }
    final useEncoderPath = hasEncoder && !hasDecoder;

    final poolingType = lib.llama_pooling_type$1(ctx.pointer);
    final maxParallelSequences = lib.llama_n_seq_max(ctx.pointer);
    if (poolingType == llama_pooling_type.LLAMA_POOLING_TYPE_NONE ||
        maxParallelSequences <= 1) {
      final fallbackVectors = <List<double>>[];
      for (final text in texts) {
        fallbackVectors.add(embed(contextHandle, text, normalize: normalize));
      }
      return fallbackVectors;
    }

    final vocab = lib.llama_model_get_vocab(model.pointer);
    final nSeqCtx = lib.llama_n_ctx_seq(ctx.pointer);
    final configuredBatchSize = contextParams.n_batch > 0
        ? contextParams.n_batch
        : lib.llama_n_ctx(ctx.pointer);
    final batchCapacity = math.max(1, configuredBatchSize);
    final embeddingSize = _resolveEmbeddingDimension(model.pointer);

    final tokenizedInputs = <List<int>>[];
    for (final text in texts) {
      final tokens = _tokenizeEmbeddingText(vocab, text, nSeqCtx);
      tokenizedInputs.add(tokens);
    }

    final vectors = List<List<double>?>.filled(texts.length, null);

    int index = 0;
    while (index < texts.length) {
      final currentTokenCount = tokenizedInputs[index].length;

      if (currentTokenCount > batchCapacity) {
        vectors[index] = embed(
          contextHandle,
          texts[index],
          normalize: normalize,
        );
        index += 1;
        continue;
      }

      var groupTokenCount = 0;
      final groupStart = index;
      while (index < texts.length &&
          (index - groupStart) < maxParallelSequences) {
        final nextCount = tokenizedInputs[index].length;
        if (nextCount > batchCapacity) {
          break;
        }

        final nextTotal = groupTokenCount + nextCount;
        if (groupTokenCount > 0 && nextTotal > batchCapacity) {
          break;
        }

        groupTokenCount = nextTotal;
        index += 1;
      }

      if (groupStart == index) {
        vectors[index] = embed(
          contextHandle,
          texts[index],
          normalize: normalize,
        );
        index += 1;
        continue;
      }

      final groupSize = index - groupStart;
      final batch = lib.llama_batch_init(groupTokenCount, 0, groupSize);
      try {
        lib.llama_synchronize(ctx.pointer);
        _clearContextMemory(ctx.pointer, strict: false);
        ctx.cachedPromptTokens = null;
        lib.llama_set_embeddings(ctx.pointer, true);

        batch.n_tokens = groupTokenCount;

        var tokenOffset = 0;
        for (int sequence = 0; sequence < groupSize; sequence++) {
          final tokens = tokenizedInputs[groupStart + sequence];
          for (int pos = 0; pos < tokens.length; pos++) {
            batch.token[tokenOffset] = tokens[pos];
            batch.pos[tokenOffset] = pos;
            batch.n_seq_id[tokenOffset] = 1;
            batch.seq_id[tokenOffset][0] = sequence;
            batch.logits[tokenOffset] = 1;
            tokenOffset += 1;
          }
        }

        final status = useEncoderPath
            ? lib.llama_encode(ctx.pointer, batch)
            : lib.llama_decode(ctx.pointer, batch);
        if (status != 0) {
          throw Exception('Batch embedding forward pass failed');
        }

        for (int sequence = 0; sequence < groupSize; sequence++) {
          var embeddingPtr = lib.llama_get_embeddings_seq(
            ctx.pointer,
            sequence,
          );
          if (embeddingPtr == nullptr && groupSize == 1) {
            embeddingPtr = lib.llama_get_embeddings(ctx.pointer);
          }
          if (embeddingPtr == nullptr) {
            throw Exception('Batch embedding output is unavailable');
          }

          final vector = List<double>.from(
            embeddingPtr.asTypedList(embeddingSize),
            growable: false,
          );
          vectors[groupStart + sequence] = normalize
              ? _normalizeEmbeddingVector(vector)
              : vector;
        }
      } finally {
        lib.llama_set_embeddings(ctx.pointer, false);
        lib.llama_batch_free(batch);
      }
    }

    return vectors.map((vector) => vector!).toList(growable: false);
  }

  List<int> _tokenizeEmbeddingText(
    Pointer<llama_vocab> vocab,
    String text,
    int maxTokens,
  ) {
    final shouldAddSpecial = !_promptStartsWithBosToken(vocab, text);
    final textPtr = text.toNativeUtf8();

    final requiredTokenCount = -lib.llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      nullptr,
      0,
      shouldAddSpecial,
      true,
    );

    if (requiredTokenCount <= 0 || requiredTokenCount > maxTokens) {
      malloc.free(textPtr);
      throw Exception('Failed to tokenize embedding input');
    }

    final tokensPtr = malloc<Int32>(requiredTokenCount);
    try {
      final actualTokenCount = lib.llama_tokenize(
        vocab,
        textPtr.cast(),
        textPtr.length,
        tokensPtr,
        requiredTokenCount,
        shouldAddSpecial,
        true,
      );
      if (actualTokenCount <= 0 || actualTokenCount > maxTokens) {
        throw Exception('Failed to encode embedding input');
      }

      return List<int>.from(tokensPtr.asTypedList(actualTokenCount));
    } finally {
      malloc.free(tokensPtr);
      malloc.free(textPtr);
    }
  }

  int _resolveEmbeddingDimension(Pointer<llama_model> modelPointer) {
    var embeddingSize = lib.llama_model_n_embd_out(modelPointer);
    if (embeddingSize <= 0) {
      embeddingSize = lib.llama_model_n_embd(modelPointer);
    }
    if (embeddingSize <= 0) {
      throw Exception('Failed to resolve embedding dimension');
    }
    return embeddingSize;
  }

  List<double> _normalizeEmbeddingVector(List<double> vector) {
    var normSquared = 0.0;
    for (final value in vector) {
      normSquared += value * value;
    }

    if (normSquared <= 0.0) {
      return vector;
    }

    final scale = 1.0 / math.sqrt(normSquared);
    final normalized = List<double>.filled(vector.length, 0.0, growable: false);
    for (int i = 0; i < vector.length; i++) {
      normalized[i] = vector[i] * scale;
    }
    return normalized;
  }

  /// Helper: Resets the context state to be ready for new generation.
  _LlamaContextWrapper _resetContext(
    int contextHandle,
    _LlamaContextWrapper ctx, {
    required bool clearMemory,
  }) {
    lib.llama_synchronize(ctx.pointer);

    if (clearMemory) {
      _clearContextMemory(ctx.pointer);
      ctx.cachedPromptTokens = null;
    }

    _contexts[contextHandle] = ctx;
    return ctx;
  }

  void _clearContextMemory(
    Pointer<llama_context> contextPointer, {
    bool strict = true,
  }) {
    final memory = lib.llama_get_memory(contextPointer);
    if (memory == nullptr) {
      if (strict) {
        throw Exception("Failed to reset context memory");
      }
      return;
    }

    lib.llama_memory_clear(memory, true);
  }

  /// Helper: Ingests the prompt (text or multimodal) and returns initial token count.
  int _ingestPrompt(
    int contextHandle,
    int modelHandle,
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart>? parts,
    Pointer<Int32> tokensPtr,
    int nCtx,
    llama_context_params modelParams, {
    required bool allowTextPromptReuse,
  }) {
    final mediaParts =
        parts
            ?.where((p) => p is LlamaImageContent || p is LlamaAudioContent)
            .toList() ??
        [];
    final mmHandle = _modelToMtmd[modelHandle];
    final mmCtx = mmHandle != null ? _mtmdContexts[mmHandle] : null;

    if (mediaParts.isNotEmpty && mmCtx != null) {
      return _ingestMultimodalPrompt(
        mmCtx,
        ctx,
        vocab,
        prompt,
        mediaParts,
        modelParams,
      );
    } else {
      return _ingestTextPrompt(
        batch,
        vocab,
        prompt,
        tokensPtr,
        nCtx,
        ctx,
        maxBatchTokens: modelParams.n_batch,
        allowPromptReuse: allowTextPromptReuse,
      );
    }
  }

  int _ingestMultimodalPrompt(
    Pointer<mtmd_context> mmCtx,
    _LlamaContextWrapper ctx,
    Pointer<llama_vocab> vocab,
    String prompt,
    List<LlamaContentPart> mediaParts,
    llama_context_params modelParams,
  ) {
    int initialTokens = 0;
    final bitmaps = malloc<Pointer<mtmd_bitmap>>(mediaParts.length);
    final chunks = lib.mtmd_input_chunks_init();

    try {
      for (int i = 0; i < mediaParts.length; i++) {
        final p = mediaParts[i];
        bitmaps[i] = nullptr;
        if (p is LlamaImageContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8();
            bitmaps[i] = lib.mtmd_helper_bitmap_init_from_file(
              mmCtx,
              pathPtr.cast(),
            );
            malloc.free(pathPtr);
          } else if (p.bytes != null) {
            final dataPtr = malloc<Uint8>(p.bytes!.length);
            dataPtr.asTypedList(p.bytes!.length).setAll(0, p.bytes!);
            bitmaps[i] = lib.mtmd_helper_bitmap_init_from_buf(
              mmCtx,
              dataPtr.cast(),
              p.bytes!.length,
            );
            malloc.free(dataPtr);
          }
        } else if (p is LlamaAudioContent) {
          if (p.path != null) {
            final pathPtr = p.path!.toNativeUtf8();
            bitmaps[i] = lib.mtmd_helper_bitmap_init_from_file(
              mmCtx,
              pathPtr.cast(),
            );
            malloc.free(pathPtr);
          } else if (p.bytes != null) {
            final dataPtr = malloc<Uint8>(p.bytes!.length);
            dataPtr.asTypedList(p.bytes!.length).setAll(0, p.bytes!);
            bitmaps[i] = lib.mtmd_helper_bitmap_init_from_buf(
              mmCtx,
              dataPtr.cast(),
              p.bytes!.length,
            );
            malloc.free(dataPtr);
          } else if (p.samples != null) {
            final dataPtr = malloc<Float>(p.samples!.length);
            dataPtr.asTypedList(p.samples!.length).setAll(0, p.samples!);
            bitmaps[i] = lib.mtmd_bitmap_init_from_audio(
              p.samples!.length,
              dataPtr.cast(),
            );
            malloc.free(dataPtr);
          }
        }

        if (bitmaps[i] == nullptr) {
          throw Exception("Failed to load media part $i");
        }
      }

      final inputText = malloc<mtmd_input_text>();
      final normalizedPrompt = _normalizeMtmdPromptMarkers(
        prompt,
        mediaParts.length,
      );
      final promptPtr = normalizedPrompt.toNativeUtf8();
      inputText.ref.text = promptPtr.cast();

      final bos = lib.llama_vocab_bos(vocab);
      final eos = lib.llama_vocab_eos(vocab);
      final shouldAddSpecial =
          (bos != eos && bos != -1) &&
          !_promptStartsWithBosToken(vocab, normalizedPrompt);
      inputText.ref.add_special = shouldAddSpecial;
      inputText.ref.parse_special = true;

      final res = lib.mtmd_tokenize(
        mmCtx,
        chunks,
        inputText,
        bitmaps.cast(),
        mediaParts.length,
      );

      if (res == 0) {
        final newPast = malloc<llama_pos>();
        if (lib.mtmd_helper_eval_chunks(
              mmCtx,
              ctx.pointer,
              chunks,
              0,
              0,
              modelParams.n_batch,
              true,
              newPast,
            ) ==
            0) {
          initialTokens = newPast.value;
        }
        malloc.free(newPast);
      } else {
        throw Exception("mtmd_tokenize failed: $res");
      }

      malloc.free(promptPtr);
      malloc.free(inputText);
    } finally {
      for (int i = 0; i < mediaParts.length; i++) {
        if (bitmaps[i] != nullptr) lib.mtmd_bitmap_free(bitmaps[i]);
      }
      malloc.free(bitmaps);
      lib.mtmd_input_chunks_free(chunks);
    }
    ctx.cachedPromptTokens = null;
    return initialTokens;
  }

  String _normalizeMtmdPromptMarkers(String prompt, int mediaPartCount) {
    final markerPtr = lib.mtmd_default_marker();
    final marker = markerPtr == nullptr
        ? '<__media__>'
        : markerPtr.cast<Utf8>().toDartString();

    var normalized = prompt;
    const directPlaceholders = [
      '<image>',
      '[IMG]',
      '<|image|>',
      '<img>',
      '<|img|>',
    ];

    for (final placeholder in directPlaceholders) {
      normalized = normalized.replaceAll(placeholder, marker);
    }

    // Some VLM templates index image placeholders (e.g. <|image_1|>).
    normalized = normalized.replaceAll(RegExp(r'<\|image_\d+\|>'), marker);

    if (mediaPartCount <= 0) {
      return normalized;
    }

    final markerCount = _countOccurrences(normalized, marker);
    if (markerCount < mediaPartCount) {
      final missing = mediaPartCount - markerCount;
      final markerBlock = List.filled(missing, marker).join(' ');

      if (normalized.contains('User:')) {
        normalized = normalized.replaceFirst('User:', 'User: $markerBlock ');
      } else if (normalized.contains('user:')) {
        normalized = normalized.replaceFirst('user:', 'user: $markerBlock ');
      } else {
        normalized = '$markerBlock\n$normalized';
      }
    }

    return normalized;
  }

  int _countOccurrences(String text, String pattern) {
    if (pattern.isEmpty) {
      return 0;
    }

    int count = 0;
    int start = 0;
    while (true) {
      final index = text.indexOf(pattern, start);
      if (index == -1) {
        break;
      }
      count++;
      start = index + pattern.length;
    }
    return count;
  }

  bool _promptStartsWithBosToken(Pointer<llama_vocab> vocab, String prompt) {
    final bos = lib.llama_vocab_bos(vocab);
    if (bos < 0) {
      return false;
    }

    final bosPtr = lib.llama_token_get_text(vocab, bos);
    if (bosPtr == nullptr) {
      return false;
    }

    final bosToken = bosPtr.cast<Utf8>().toDartString();
    if (bosToken.isEmpty) {
      return false;
    }

    return prompt.trimLeft().startsWith(bosToken);
  }

  int _ingestTextPrompt(
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    String prompt,
    Pointer<Int32> tokensPtr,
    int nCtx,
    _LlamaContextWrapper ctx, {
    required int maxBatchTokens,
    required bool allowPromptReuse,
  }) {
    final promptPtr = prompt.toNativeUtf8();
    final shouldAddSpecial = !_promptStartsWithBosToken(vocab, prompt);
    final nTokens = lib.llama_tokenize(
      vocab,
      promptPtr.cast(),
      promptPtr.length,
      tokensPtr,
      nCtx,
      shouldAddSpecial,
      true,
    );
    malloc.free(promptPtr);

    if (nTokens < 0 || nTokens > nCtx) {
      throw Exception("Tokenization failed or prompt too long");
    }

    if (!allowPromptReuse || nTokens == 0) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
      );
    }

    final cachedTokens = ctx.cachedPromptTokens;
    if (cachedTokens == null || cachedTokens.isEmpty) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
      );
    }

    final reusedPrefix = _sharedPrefixLength(cachedTokens, tokensPtr, nTokens);

    if (reusedPrefix <= 0 || reusedPrefix >= nTokens) {
      final canReuseCachedCopy =
          reusedPrefix == nTokens && cachedTokens.length == nTokens;
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
        existingCachedTokens: canReuseCachedCopy ? cachedTokens : null,
      );
    }

    final memory = lib.llama_get_memory(ctx.pointer);
    if (memory == nullptr) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
      );
    }

    final decodeStart = reusedPrefix;

    final maxSeqPos = lib.llama_memory_seq_pos_max(memory, 0);
    final removeTo = maxSeqPos >= decodeStart ? maxSeqPos + 1 : decodeStart;
    final removedTail = lib.llama_memory_seq_rm(
      memory,
      0,
      decodeStart,
      removeTo,
    );
    if (!removedTail) {
      return _decodeAndCacheFullPrompt(
        batch,
        tokensPtr,
        ctx,
        nTokens,
        maxBatchTokens: maxBatchTokens,
      );
    }

    final suffixTokenCount = nTokens - decodeStart;
    _decodePromptSegment(
      batch,
      tokensPtr,
      ctx,
      startTokenIndex: decodeStart,
      tokenCount: suffixTokenCount,
      maxBatchTokens: maxBatchTokens,
    );

    ctx.cachedPromptTokens = _copyPromptTokens(tokensPtr, nTokens);

    return nTokens;
  }

  int _decodeAndCacheFullPrompt(
    llama_batch batch,
    Pointer<Int32> tokensPtr,
    _LlamaContextWrapper ctx,
    int nTokens, {
    required int maxBatchTokens,
    List<int>? existingCachedTokens,
  }) {
    _clearContextMemory(ctx.pointer);
    _decodePromptSegment(
      batch,
      tokensPtr,
      ctx,
      startTokenIndex: 0,
      tokenCount: nTokens,
      maxBatchTokens: maxBatchTokens,
    );
    ctx.cachedPromptTokens =
        existingCachedTokens ?? _copyPromptTokens(tokensPtr, nTokens);
    return nTokens;
  }

  List<int> _copyPromptTokens(Pointer<Int32> tokensPtr, int tokenCount) {
    if (tokenCount <= 0) {
      return const <int>[];
    }
    return List<int>.from(tokensPtr.asTypedList(tokenCount), growable: false);
  }

  void _decodePromptSegment(
    llama_batch batch,
    Pointer<Int32> tokensPtr,
    _LlamaContextWrapper ctx, {
    required int startTokenIndex,
    required int tokenCount,
    required int maxBatchTokens,
  }) {
    if (tokenCount <= 0) {
      return;
    }

    final effectiveBatchTokens = maxBatchTokens > 0
        ? maxBatchTokens
        : tokenCount;
    var decoded = 0;

    while (decoded < tokenCount) {
      final remaining = tokenCount - decoded;
      final chunkTokenCount = remaining > effectiveBatchTokens
          ? effectiveBatchTokens
          : remaining;
      batch.n_tokens = chunkTokenCount;

      for (int i = 0; i < chunkTokenCount; i++) {
        final tokenIndex = startTokenIndex + decoded + i;
        batch.token[i] = tokensPtr[tokenIndex];
        batch.pos[i] = tokenIndex;
        batch.n_seq_id[i] = 1;
        batch.seq_id[i][0] = 0;
        final isLastTokenInPrompt = decoded + i == tokenCount - 1;
        batch.logits[i] = isLastTokenInPrompt ? 1 : 0;
      }

      if (lib.llama_decode(ctx.pointer, batch) != 0) {
        throw Exception("Initial decode failed");
      }

      decoded += chunkTokenCount;
    }
  }

  int _sharedPrefixLength(
    List<int> cachedTokens,
    Pointer<Int32> newTokens,
    int newTokenCount,
  ) {
    final maxLength = cachedTokens.length < newTokenCount
        ? cachedTokens.length
        : newTokenCount;
    int i = 0;
    while (i < maxLength && cachedTokens[i] == newTokens[i]) {
      i++;
    }
    return i;
  }

  /// Helper: Initializes the sampler chain.
  Pointer<llama_sampler> _initializeSampler(
    GenerationParams params,
    Pointer<llama_vocab> vocab,
    Pointer<Utf8> grammarPtr,
    Pointer<Utf8> rootPtr,
    _LazyGrammarConfig? lazyGrammarConfig,
    int initialTokens,
    Pointer<Int32> tokensPtr,
  ) {
    final sampler = lib.llama_sampler_chain_init(
      lib.llama_sampler_chain_default_params(),
    );

    lib.llama_sampler_chain_add(
      sampler,
      lib.llama_sampler_init_penalties(64, params.penalty, 0.0, 0.0),
    );

    if (grammarPtr != nullptr) {
      if (params.grammarLazy && lazyGrammarConfig != null) {
        lib.llama_sampler_chain_add(
          sampler,
          lib.llama_sampler_init_grammar_lazy_patterns(
            vocab,
            grammarPtr.cast(),
            rootPtr.cast(),
            lazyGrammarConfig.triggerPatterns,
            lazyGrammarConfig.numTriggerPatterns,
            lazyGrammarConfig.triggerTokens,
            lazyGrammarConfig.numTriggerTokens,
          ),
        );
      } else {
        lib.llama_sampler_chain_add(
          sampler,
          lib.llama_sampler_init_grammar(
            vocab,
            grammarPtr.cast(),
            rootPtr.cast(),
          ),
        );
      }
    }

    lib.llama_sampler_chain_add(
      sampler,
      lib.llama_sampler_init_top_k(params.topK),
    );
    lib.llama_sampler_chain_add(
      sampler,
      lib.llama_sampler_init_top_p(params.topP, 1),
    );
    if (params.minP > 0) {
      lib.llama_sampler_chain_add(
        sampler,
        lib.llama_sampler_init_min_p(params.minP, 1),
      );
    }
    lib.llama_sampler_chain_add(
      sampler,
      lib.llama_sampler_init_temp(params.temp),
    );

    if (params.temp <= 0) {
      lib.llama_sampler_chain_add(sampler, lib.llama_sampler_init_greedy());
    } else {
      final seed = params.seed ?? DateTime.now().millisecondsSinceEpoch;
      lib.llama_sampler_chain_add(sampler, lib.llama_sampler_init_dist(seed));
    }

    if (grammarPtr == nullptr && tokensPtr != nullptr && initialTokens > 0) {
      for (int i = 0; i < initialTokens; i++) {
        lib.llama_sampler_accept(sampler, tokensPtr[i]);
      }
    }

    return sampler;
  }

  /// Helper: Runs the main inference loop and yields tokens.
  Stream<List<int>> _runInferenceLoop(
    _LlamaContextWrapper ctx,
    llama_batch batch,
    Pointer<llama_vocab> vocab,
    Pointer<llama_sampler> sampler,
    GenerationParams params,
    int startPos,
    int nCtx,
    int cancelTokenAddress,
    Pointer<Uint8> pieceBuf,
    Pointer<Utf8> grammarPtr,
    Set<int> preservedTokenIds,
    List<String> stopSequences,
  ) async* {
    final cancelToken = Pointer<Int8>.fromAddress(cancelTokenAddress);
    int currentPos = startPos;
    final accumulatedBytes = <int>[];

    for (int i = 0; i < params.maxTokens; i++) {
      if (cancelToken.value == 1) break;
      if (currentPos >= nCtx) break;

      final selectedToken = lib.llama_sampler_sample(sampler, ctx.pointer, -1);
      if (lib.llama_vocab_is_eog(vocab, selectedToken)) break;

      final n = lib.llama_token_to_piece(
        vocab,
        selectedToken,
        pieceBuf.cast(),
        256,
        0,
        preservedTokenIds.contains(selectedToken),
      );

      if (n > 0) {
        final bytes = pieceBuf.asTypedList(n).toList();
        yield bytes;

        if (stopSequences.isNotEmpty) {
          accumulatedBytes.addAll(bytes);
          if (accumulatedBytes.length > 64) {
            accumulatedBytes.removeRange(0, accumulatedBytes.length - 64);
          }
          final text = utf8.decode(accumulatedBytes, allowMalformed: true);
          if (stopSequences.any((s) => text.endsWith(s))) break;
        }
      }

      batch.n_tokens = 1;
      batch.token[0] = selectedToken;
      batch.pos[0] = currentPos++;
      batch.n_seq_id[0] = 1;
      batch.seq_id[0][0] = 0;
      batch.logits[0] = 1;

      if (lib.llama_decode(ctx.pointer, batch) != 0) break;
    }
  }

  _LazyGrammarConfig? _buildLazyGrammarConfig(GenerationParams params) {
    final triggerPatterns = <String>[];
    final triggerTokens = <int>[];

    for (final trigger in params.grammarTriggers) {
      switch (trigger.type) {
        case 0:
          triggerPatterns.add(_regexEscape(trigger.value));
          break;
        case 1:
          final token = trigger.token ?? int.tryParse(trigger.value);
          if (token != null) {
            triggerTokens.add(token);
          }
          break;
        case 2:
          triggerPatterns.add(trigger.value);
          break;
        case 3:
          final pattern = trigger.value;
          final anchored = pattern.isEmpty
              ? r'^$'
              : "${pattern.startsWith('^') ? '' : '^'}$pattern${pattern.endsWith(r'$') ? '' : r'$'}";
          triggerPatterns.add(anchored);
          break;
      }
    }

    if (triggerPatterns.isEmpty && triggerTokens.isEmpty) {
      return null;
    }

    final allocatedPatternPtrs = triggerPatterns
        .map((pattern) => pattern.toNativeUtf8())
        .toList(growable: false);

    final triggerPatternsPtr = allocatedPatternPtrs.isEmpty
        ? nullptr
        : malloc<Pointer<Char>>(allocatedPatternPtrs.length);

    if (triggerPatternsPtr != nullptr) {
      for (var i = 0; i < allocatedPatternPtrs.length; i++) {
        triggerPatternsPtr[i] = allocatedPatternPtrs[i].cast();
      }
    }

    final triggerTokensPtr = triggerTokens.isEmpty
        ? nullptr
        : malloc<llama_token>(triggerTokens.length);

    if (triggerTokensPtr != nullptr) {
      for (var i = 0; i < triggerTokens.length; i++) {
        triggerTokensPtr[i] = triggerTokens[i];
      }
    }

    return _LazyGrammarConfig(
      triggerPatterns: triggerPatternsPtr,
      numTriggerPatterns: allocatedPatternPtrs.length,
      triggerTokens: triggerTokensPtr,
      numTriggerTokens: triggerTokens.length,
      allocatedPatternPointers: allocatedPatternPtrs,
    );
  }

  Set<int> _resolvePreservedTokenIds(
    Pointer<llama_vocab> vocab,
    List<String> preservedTokens,
  ) {
    if (preservedTokens.isEmpty) {
      return const <int>{};
    }

    final ids = <int>{};
    for (final tokenText in preservedTokens) {
      if (tokenText.isEmpty) {
        continue;
      }

      final textPtr = tokenText.toNativeUtf8();
      try {
        final required = -lib.llama_tokenize(
          vocab,
          textPtr.cast(),
          textPtr.length,
          nullptr,
          0,
          false,
          true,
        );

        if (required <= 0) {
          continue;
        }

        final tokenIds = malloc<Int32>(required);
        try {
          final actual = lib.llama_tokenize(
            vocab,
            textPtr.cast(),
            textPtr.length,
            tokenIds,
            required,
            false,
            true,
          );

          if (actual > 0) {
            for (int i = 0; i < actual; i++) {
              ids.add(tokenIds[i]);
            }
          }
        } finally {
          malloc.free(tokenIds);
        }
      } finally {
        malloc.free(textPtr);
      }
    }

    return ids;
  }

  List<String> _effectiveStopSequences(
    List<String> stopSequences,
    List<String> preservedTokens,
  ) {
    if (stopSequences.isEmpty || preservedTokens.isEmpty) {
      return stopSequences;
    }

    final preservedSet = preservedTokens.toSet();
    return stopSequences
        .where((sequence) => !preservedSet.contains(sequence))
        .toList(growable: false);
  }

  String _regexEscape(String input) {
    final escaped = StringBuffer();
    const regexMeta = r'\^$.*+?()[]{}|';
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (regexMeta.contains(char)) {
        escaped.write('\\');
      }
      escaped.write(char);
    }
    return escaped.toString();
  }

  /// Tokenizes the given [text].
  List<int> tokenize(int modelHandle, String text, bool addSpecial) {
    final model = _models[modelHandle];
    if (model == null) return [];
    final vocab = lib.llama_model_get_vocab(model.pointer);
    final textPtr = text.toNativeUtf8();
    final shouldAddSpecial =
        addSpecial && !_promptStartsWithBosToken(vocab, text);
    final n = -lib.llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      nullptr,
      0,
      shouldAddSpecial,
      true,
    );
    final tokensPtr = malloc<Int32>(n);
    final actual = lib.llama_tokenize(
      vocab,
      textPtr.cast(),
      textPtr.length,
      tokensPtr,
      n,
      shouldAddSpecial,
      true,
    );
    final result = List.generate(actual, (i) => tokensPtr[i]);
    malloc.free(textPtr);
    malloc.free(tokensPtr);
    return result;
  }

  /// Detokenizes the given [tokens].
  String detokenize(int modelHandle, List<int> tokens, bool special) {
    final model = _models[modelHandle];
    if (model == null) return "";
    final vocab = lib.llama_model_get_vocab(model.pointer);
    final buffer = malloc<Int8>(256);
    final bytes = <int>[];
    for (final t in tokens) {
      final n = lib.llama_token_to_piece(
        vocab,
        t,
        buffer.cast(),
        256,
        0,
        special,
      );
      if (n > 0) bytes.addAll(buffer.asTypedList(n));
    }
    malloc.free(buffer);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Returns metadata for the specified [modelHandle].
  Map<String, String> getMetadata(int modelHandle) {
    final model = _models[modelHandle];
    if (model == null) return {};
    final metadata = <String, String>{};
    final keyBuf = malloc<Int8>(1024);
    final valBuf = malloc<Int8>(1024 * 64);
    final n = lib.llama_model_meta_count(model.pointer);
    for (int i = 0; i < n; i++) {
      lib.llama_model_meta_key_by_index(model.pointer, i, keyBuf.cast(), 1024);
      lib.llama_model_meta_val_str_by_index(
        model.pointer,
        i,
        valBuf.cast(),
        1024 * 64,
      );
      metadata[keyBuf.cast<Utf8>().toDartString()] = valBuf
          .cast<Utf8>()
          .toDartString();
    }
    malloc.free(keyBuf);
    malloc.free(valBuf);
    return metadata;
  }

  /// Handles LoRA adapter operations.
  void handleLora(int contextHandle, String? path, double? scale, String op) {
    final ctx = _contexts[contextHandle];
    final modelHandle = _contextToModel[contextHandle];
    if (ctx == null || modelHandle == null) return;

    final modelAdapters = _loraAdapters[modelHandle];
    final activeLoras = _activeLoras[contextHandle];
    if (modelAdapters == null || activeLoras == null) return;

    try {
      if (op == 'set') {
        if (path == null) {
          throw Exception('LoRA path is required for set operation');
        }
        if (scale == null) {
          throw Exception('LoRA scale is required for set operation');
        }

        var adapter = modelAdapters[path];
        if (adapter == null) {
          final pathPtr = path.toNativeUtf8();
          final adapterPtr = lib.llama_adapter_lora_init(
            _models[modelHandle]!.pointer,
            pathPtr.cast(),
          );
          malloc.free(pathPtr);
          if (adapterPtr == nullptr) {
            throw Exception("Failed to load LoRA at $path");
          }
          adapter = _LlamaLoraWrapper(adapterPtr, lib);
          modelAdapters[path] = adapter;
        }
        activeLoras[path] = scale;
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
        ctx.cachedPromptTokens = null;
      } else if (op == 'remove') {
        if (path == null) {
          throw Exception('LoRA path is required for remove operation');
        }
        activeLoras.remove(path);
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
        ctx.cachedPromptTokens = null;
      } else if (op == 'clear') {
        activeLoras.clear();
        _applyActiveLoras(ctx.pointer, modelAdapters, activeLoras);
        ctx.cachedPromptTokens = null;
      } else {
        throw Exception('Unknown LoRA operation: $op');
      }
    } catch (e) {
      rethrow;
    }
  }

  void _applyActiveLoras(
    Pointer<llama_context> context,
    Map<String, _LlamaLoraWrapper> loadedAdapters,
    Map<String, double> activeLoras,
  ) {
    if (activeLoras.isEmpty) {
      final result = lib.llama_set_adapters_lora(context, nullptr, 0, nullptr);
      if (result != 0) {
        throw Exception('Failed to clear LoRA adapters (code: $result)');
      }
      return;
    }

    final activeEntries = activeLoras.entries.toList(growable: false);
    final adapterPointers = malloc<Pointer<llama_adapter_lora>>(
      activeEntries.length,
    );
    final scalesPointer = malloc<Float>(activeEntries.length);

    try {
      for (var i = 0; i < activeEntries.length; i++) {
        final entry = activeEntries[i];
        final adapter = loadedAdapters[entry.key];
        if (adapter == null) {
          throw Exception(
            'LoRA adapter not loaded for active path: ${entry.key}',
          );
        }
        adapterPointers[i] = adapter.pointer;
        scalesPointer[i] = entry.value;
      }

      final result = lib.llama_set_adapters_lora(
        context,
        adapterPointers,
        activeEntries.length,
        scalesPointer,
      );
      if (result != 0) {
        throw Exception('Failed to apply LoRA adapters (code: $result)');
      }
    } finally {
      malloc.free(adapterPointers);
      malloc.free(scalesPointer);
    }
  }

  /// Returns resolved GPU layers for the active model load.
  int? getResolvedGpuLayers() {
    if (_models.isEmpty) {
      return null;
    }
    return _activeResolvedGpuLayers;
  }

  /// Returns whether GPU offloading is supported.
  bool getGpuSupport() {
    return lib.llama_supports_gpu_offload();
  }

  /// Disposes of all resources managed by the service.
  void dispose() {
    for (final c in _contexts.values) {
      c.dispose();
    }
    _contexts.clear();
    for (final m in _models.values) {
      m.dispose();
    }
    _models.clear();
    _modelResolvedGpuLayers.clear();
    _activeResolvedGpuLayers = 0;
    for (final m in _mtmdContexts.values) {
      lib.mtmd_free(m);
    }
    _mtmdContexts.clear();
    _modelToMtmd.clear();
    _modelToMtmdUseGpu.clear();
    // llama_backend_free(); // DISABLED: Prevents race conditions with other isolates
  }

  /// Creates a multimodal context (projector) for the model.
  int createMultimodalContext(int modelHandle, String mmProjPath) {
    final model = _models[modelHandle];
    if (model == null) {
      throw Exception("Invalid model handle");
    }
    _applyConfiguredLogLevel();

    final mmProjPathPtr = mmProjPath.toNativeUtf8();
    Pointer<mtmd_context> mmCtx = nullptr;
    try {
      final ctxParams = lib.mtmd_context_params_default();
      ctxParams.use_gpu = _modelToMtmdUseGpu[modelHandle] ?? true;
      mmCtx = lib.mtmd_init_from_file(
        mmProjPathPtr.cast(),
        model.pointer,
        ctxParams,
      );
    } finally {
      malloc.free(mmProjPathPtr);
    }

    if (mmCtx == nullptr) {
      throw Exception("Failed to load multimodal projector");
    }

    final handle = _getHandle();
    _mtmdContexts[handle] = mmCtx;
    _modelToMtmd[modelHandle] = handle;
    return handle;
  }

  /// Frees the multimodal context (projector).
  void freeMultimodalContext(int mmContextHandle) {
    final mmCtx = _mtmdContexts.remove(mmContextHandle);
    if (mmCtx != null) {
      lib.mtmd_free(mmCtx);
      _modelToMtmd.removeWhere((k, v) => v == mmContextHandle);
    }
  }

  // --- Helper Getters ---

  /// Returns the context size for the given [contextHandle].
  int getContextSize(int contextHandle) {
    final ctx = _contexts[contextHandle];
    if (ctx == null) return 0;
    return lib.llama_n_ctx(ctx.pointer);
  }

  /// Checks if a multimodal context exists.
  bool hasMultimodalContext(int mmContextHandle) {
    return _mtmdContexts.containsKey(mmContextHandle);
  }
}

class _LazyGrammarConfig {
  final Pointer<Pointer<Char>> triggerPatterns;
  final int numTriggerPatterns;
  final Pointer<llama_token> triggerTokens;
  final int numTriggerTokens;
  final List<Pointer<Utf8>> allocatedPatternPointers;

  const _LazyGrammarConfig({
    required this.triggerPatterns,
    required this.numTriggerPatterns,
    required this.triggerTokens,
    required this.numTriggerTokens,
    required this.allocatedPatternPointers,
  });

  void dispose() {
    for (final pointer in allocatedPatternPointers) {
      malloc.free(pointer);
    }

    if (triggerPatterns != nullptr) {
      malloc.free(triggerPatterns);
    }
    if (triggerTokens != nullptr) {
      malloc.free(triggerTokens);
    }
  }
}

// --- Native Wrappers ---

class _LlamaLoraWrapper {
  final llama_cpp lib;
  final Pointer<llama_adapter_lora> pointer;
  _LlamaLoraWrapper(this.pointer, this.lib);
  void dispose() {
    lib.llama_adapter_lora_free(pointer);
  }
}

class _LlamaModelWrapper {
  final llama_cpp lib;
  final Pointer<llama_model> pointer;
  _LlamaModelWrapper(this.pointer, this.lib);
  void dispose() {
    lib.llama_model_free(pointer);
  }
}

class _LlamaContextWrapper {
  final llama_cpp lib;
  final Pointer<llama_context> pointer;
  final _LlamaModelWrapper? _modelKeepAlive;
  List<int>? cachedPromptTokens;
  _LlamaContextWrapper(this.pointer, this._modelKeepAlive, this.lib);
  void dispose() {
    // ignore: unused_local_variable
    final _ = _modelKeepAlive;
    cachedPromptTokens = null;
    lib.llama_free(pointer);
  }
}
