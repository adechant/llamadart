/// Reason why a tool call was skipped by [ToolCallGate].
enum ToolCallSkipReason { duplicateCall, perRoundLimit }

/// Outcome of evaluating whether a tool call should execute.
class ToolCallGateDecision {
  /// Whether the tool call should run.
  final bool shouldExecute;

  /// Reason for skipping when [shouldExecute] is false.
  final ToolCallSkipReason? skipReason;

  const ToolCallGateDecision._({
    required this.shouldExecute,
    required this.skipReason,
  });

  /// Creates a decision that permits tool execution.
  const ToolCallGateDecision.execute()
    : this._(shouldExecute: true, skipReason: null);

  /// Creates a decision that skips execution for [reason].
  const ToolCallGateDecision.skip(ToolCallSkipReason reason)
    : this._(shouldExecute: false, skipReason: reason);
}

/// Stateful guard that limits duplicate and excessive tool calls per round.
class ToolCallGate {
  /// Maximum number of tool calls allowed in one assistant round.
  final int maxToolCallsPerRound;
  final Set<String> _seenSignatures = <String>{};
  int _executedToolCalls = 0;

  /// Creates a gate configured with [maxToolCallsPerRound].
  ToolCallGate({required this.maxToolCallsPerRound})
    : assert(maxToolCallsPerRound > 0);

  /// Returns execution decision for a tool call [signature].
  ToolCallGateDecision evaluate(String signature) {
    if (!_seenSignatures.add(signature)) {
      return const ToolCallGateDecision.skip(ToolCallSkipReason.duplicateCall);
    }

    if (_executedToolCalls >= maxToolCallsPerRound) {
      return const ToolCallGateDecision.skip(ToolCallSkipReason.perRoundLimit);
    }

    _executedToolCalls += 1;
    return const ToolCallGateDecision.execute();
  }
}

/// Builds a serialized skipped-tool result payload for model continuity.
Map<String, dynamic> buildSkippedToolCallResult(
  ToolCallSkipReason reason, {
  required int limit,
}) {
  if (reason == ToolCallSkipReason.perRoundLimit) {
    return <String, dynamic>{
      'ok': true,
      'skipped': true,
      'reason': 'per_round_limit',
      'limit': limit,
    };
  }

  return <String, dynamic>{
    'ok': true,
    'skipped': true,
    'reason': 'duplicate_call',
  };
}
