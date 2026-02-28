import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

void main() {
  test('ModelParams defaults preserve legacy context batching behavior', () {
    const params = ModelParams();

    expect(params.batchSize, 0);
    expect(params.microBatchSize, 0);
    expect(params.maxParallelSequences, 1);
  });

  test('ModelParams copyWith updates selected fields', () {
    const params = ModelParams(contextSize: 1024);
    final updated = params.copyWith(
      gpuLayers: 2,
      preferredBackend: GpuBackend.metal,
      batchSize: 256,
      microBatchSize: 64,
      maxParallelSequences: 8,
    );

    expect(updated.contextSize, 1024);
    expect(updated.gpuLayers, 2);
    expect(updated.preferredBackend, GpuBackend.metal);
    expect(updated.batchSize, 256);
    expect(updated.microBatchSize, 64);
    expect(updated.maxParallelSequences, 8);
  });
}
