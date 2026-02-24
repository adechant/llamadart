import 'package:llamadart/llamadart.dart';

class CodingAgentConfig {
  final String workspaceRoot;
  final String modelSource;
  final String modelCacheDirectory;
  final ModelParams modelParams;
  final GenerationParams generationParams;
  final int? maxToolRounds;
  final bool enableNativeToolCalling;

  const CodingAgentConfig({
    required this.workspaceRoot,
    required this.modelSource,
    required this.modelCacheDirectory,
    required this.modelParams,
    required this.generationParams,
    this.maxToolRounds,
    this.enableNativeToolCalling = false,
  });
}
