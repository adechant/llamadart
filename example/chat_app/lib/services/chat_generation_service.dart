import 'dart:async';

import 'package:llamadart/llamadart.dart';

import '../models/chat_settings.dart';

class GenerationStreamUpdate {
  final String cleanText;
  final String fullThinking;
  final bool shouldNotify;
  final int generatedTokenDelta;

  const GenerationStreamUpdate({
    required this.cleanText,
    required this.fullThinking,
    required this.shouldNotify,
    this.generatedTokenDelta = 0,
  });
}

class GenerationStreamResult {
  final String fullResponse;
  final String fullThinking;
  final int generatedTokens;
  final int? firstTokenLatencyMs;
  final int elapsedMs;

  const GenerationStreamResult({
    required this.fullResponse,
    required this.fullThinking,
    required this.generatedTokens,
    required this.firstTokenLatencyMs,
    required this.elapsedMs,
  });
}

class ChatGenerationService {
  const ChatGenerationService();

  static const int _streamRevealIntervalMs = 14;
  static const int _streamFlushBudgetMs = 220;

  GenerationParams buildParams(ChatSettings settings) {
    return GenerationParams(
      maxTokens: settings.maxTokens,
      temp: settings.temperature,
      topK: settings.topK,
      topP: settings.topP,
      minP: settings.minP,
      penalty: settings.penalty,
      stopSequences: const <String>[],
    );
  }

  List<LlamaContentPart> buildChatParts({
    required String text,
    List<LlamaContentPart>? stagedParts,
  }) {
    return <LlamaContentPart>[
      ...?stagedParts,
      if (text.isNotEmpty) LlamaTextContent(text),
    ];
  }

  Future<GenerationStreamResult> consumeStream({
    required Stream<LlamaCompletionChunk> stream,
    required bool thinkingEnabled,
    required int uiNotifyIntervalMs,
    required String Function(String) cleanResponse,
    required bool Function() shouldContinue,
    required void Function(GenerationStreamUpdate update) onUpdate,
  }) async {
    final stopwatch = Stopwatch()..start();

    var fullResponse = '';
    var fullThinking = '';
    var visibleCleanText = '';
    var cleanTarget = '';
    var generatedTokens = 0;
    var sawFirstToken = false;
    int? firstTokenLatencyMs;

    final effectiveNotifyIntervalMs = uiNotifyIntervalMs <= 0
        ? 0
        : uiNotifyIntervalMs;
    var lastUpdateAt = DateTime.fromMillisecondsSinceEpoch(0);
    var lastNotifiedCleanText = '';
    var lastNotifiedThinking = '';
    var streamCompleted = false;
    var streamCancelled = false;

    void emitUpdate({
      required int generatedTokenDelta,
      bool forceNotify = false,
    }) {
      final now = DateTime.now();
      final hasVisibleDelta =
          visibleCleanText != lastNotifiedCleanText ||
          fullThinking != lastNotifiedThinking;

      final shouldNotify =
          forceNotify ||
          (hasVisibleDelta &&
              (effectiveNotifyIntervalMs == 0 ||
                  now.difference(lastUpdateAt).inMilliseconds >=
                      effectiveNotifyIntervalMs));

      if (!shouldNotify && generatedTokenDelta == 0) {
        return;
      }

      if (shouldNotify) {
        lastUpdateAt = now;
        lastNotifiedCleanText = visibleCleanText;
        lastNotifiedThinking = fullThinking;
      }

      onUpdate(
        GenerationStreamUpdate(
          cleanText: visibleCleanText,
          fullThinking: fullThinking,
          shouldNotify: shouldNotify,
          generatedTokenDelta: generatedTokenDelta,
        ),
      );
    }

    void advanceVisibleTextAndEmit() {
      if (!shouldContinue()) {
        streamCancelled = true;
        return;
      }

      final nextVisible = _advanceVisibleText(
        currentText: visibleCleanText,
        targetText: cleanTarget,
      );
      if (nextVisible == visibleCleanText) {
        return;
      }

      visibleCleanText = nextVisible;
      emitUpdate(generatedTokenDelta: 0);
    }

    final revealTicker =
        Stream<void>.periodic(
          const Duration(milliseconds: _streamRevealIntervalMs),
          (_) {},
        ).listen((_) {
          if (streamCompleted || streamCancelled) {
            return;
          }
          advanceVisibleTextAndEmit();
        });

    try {
      await for (final chunk in stream) {
        if (!shouldContinue()) {
          streamCancelled = true;
          break;
        }

        final delta = chunk.choices.first.delta;
        final content = delta.content ?? '';
        final thinking = thinkingEnabled ? (delta.thinking ?? '') : '';

        if (!sawFirstToken &&
            (content.isNotEmpty ||
                thinking.isNotEmpty ||
                (delta.toolCalls?.isNotEmpty ?? false))) {
          firstTokenLatencyMs = stopwatch.elapsedMilliseconds;
          sawFirstToken = true;
        }

        fullResponse += content;
        fullThinking += thinking
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\r', '\r');
        generatedTokens++;

        cleanTarget = cleanResponse(fullResponse);
        visibleCleanText = _advanceVisibleText(
          currentText: visibleCleanText,
          targetText: cleanTarget,
        );

        emitUpdate(generatedTokenDelta: 1);
      }

      streamCompleted = true;

      if (!streamCancelled && visibleCleanText != cleanTarget) {
        final flushDeadline = DateTime.now().add(
          const Duration(milliseconds: _streamFlushBudgetMs),
        );
        while (visibleCleanText != cleanTarget &&
            DateTime.now().isBefore(flushDeadline)) {
          advanceVisibleTextAndEmit();
          if (visibleCleanText == cleanTarget) {
            break;
          }
          await Future<void>.delayed(
            const Duration(milliseconds: _streamRevealIntervalMs),
          );
        }
      }

      if (!streamCancelled) {
        if (visibleCleanText != cleanTarget) {
          visibleCleanText = cleanTarget;
          emitUpdate(generatedTokenDelta: 0, forceNotify: true);
        } else if (visibleCleanText != lastNotifiedCleanText ||
            fullThinking != lastNotifiedThinking) {
          emitUpdate(generatedTokenDelta: 0, forceNotify: true);
        }
      }
    } finally {
      await revealTicker.cancel();
    }

    stopwatch.stop();
    return GenerationStreamResult(
      fullResponse: fullResponse,
      fullThinking: fullThinking,
      generatedTokens: generatedTokens,
      firstTokenLatencyMs: firstTokenLatencyMs,
      elapsedMs: stopwatch.elapsedMilliseconds,
    );
  }

  String _advanceVisibleText({
    required String currentText,
    required String targetText,
  }) {
    if (currentText == targetText) {
      return targetText;
    }

    final canPrefixAdvance =
        targetText.length > currentText.length &&
        targetText.startsWith(currentText);
    if (!canPrefixAdvance) {
      return targetText;
    }

    final backlog = targetText.length - currentText.length;
    final revealStep = _revealStepForBacklog(backlog);
    final nextLength = currentText.length + revealStep;
    if (nextLength >= targetText.length) {
      return targetText;
    }
    return targetText.substring(0, nextLength);
  }

  int _revealStepForBacklog(int backlog) {
    if (backlog <= 12) {
      return backlog;
    }
    if (backlog <= 48) {
      return 2;
    }
    if (backlog <= 160) {
      return 4;
    }
    if (backlog <= 360) {
      return 8;
    }
    return 12;
  }
}
