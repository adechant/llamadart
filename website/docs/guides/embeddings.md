---
title: Embeddings
---

`llamadart` supports local embedding generation through `LlamaEngine`.

## Basic usage

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final engine = LlamaEngine(LlamaBackend());

  try {
    await engine.loadModel('path/to/embedding-model.gguf');

    final List<double> vector = await engine.embed('hello world');
    final List<List<double>> batch = await engine.embedBatch([
      'semantic search',
      'document retrieval',
    ]);

    print('single dims=${vector.length}');
    print('batch count=${batch.length}');
  } finally {
    await engine.dispose();
  }
}
```

## Backend support

- Embeddings are an optional backend capability.
- If the active backend does not support embeddings, `LlamaEngine.embed(...)`
  and `embedBatch(...)` throw `LlamaUnsupportedException`.
- Native backend supports embeddings, including batched embeddings.

## Throughput tuning for `embedBatch(...)`

`ModelParams` controls batching behavior at context creation time:

```dart
const params = ModelParams(
  contextSize: 4096,
  batchSize: 2048,
  microBatchSize: 2048,
  maxParallelSequences: 8,
);
```

- `batchSize` (`n_batch`): max logical tokens per forward pass.
- `microBatchSize` (`n_ubatch`): scheduler micro-batch size.
- `maxParallelSequences` (`n_seq_max`): parallel sequence slots for true
  multi-sequence embedding batches.

Start with `maxParallelSequences` matching expected concurrent batch width (for
example `4` or `8`), then tune based on memory and latency/throughput tradeoffs.

## Benchmarking

Use the built-in scripts to compare sequential vs batch embedding throughput and
to sweep `max-seq` values.

```bash
# Single benchmark report
dart run tool/testing/native_embedding_benchmark.dart \
  --model path/to/model.gguf \
  --cpu \
  --mode both \
  --input-count 8 \
  --max-seq 8

# max-seq sweep with CSV output
dart run tool/testing/native_embedding_sweep.dart \
  --model path/to/model.gguf \
  --cpu \
  --max-seq-values 1,2,4,8 \
  --csv-out embedding_speedup.csv
```
