import 'package:llamadart_tui_coding_agent/src/tool_call_gate.dart';
import 'package:test/test.dart';

void main() {
  group('ToolCallGate', () {
    test('requires positive per-round limit', () {
      expect(
        () => ToolCallGate(maxToolCallsPerRound: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('allows first unique call', () {
      final gate = ToolCallGate(maxToolCallsPerRound: 2);

      final decision = gate.evaluate('list_files:{}');

      expect(decision.shouldExecute, isTrue);
      expect(decision.skipReason, isNull);
    });

    test('skips duplicate signature', () {
      final gate = ToolCallGate(maxToolCallsPerRound: 3);
      gate.evaluate('list_files:{}');

      final decision = gate.evaluate('list_files:{}');

      expect(decision.shouldExecute, isFalse);
      expect(decision.skipReason, ToolCallSkipReason.duplicateCall);
    });

    test('skips calls beyond per-round limit', () {
      final gate = ToolCallGate(maxToolCallsPerRound: 1);
      gate.evaluate('list_files:{}');

      final decision = gate.evaluate('read_file:{"path":"README.md"}');

      expect(decision.shouldExecute, isFalse);
      expect(decision.skipReason, ToolCallSkipReason.perRoundLimit);
    });
  });

  group('buildSkippedToolCallResult', () {
    test('builds duplicate-call payload', () {
      final payload = buildSkippedToolCallResult(
        ToolCallSkipReason.duplicateCall,
        limit: 4,
      );

      expect(payload['ok'], isTrue);
      expect(payload['skipped'], isTrue);
      expect(payload['reason'], 'duplicate_call');
      expect(payload.containsKey('limit'), isFalse);
    });

    test('builds per-round-limit payload', () {
      final payload = buildSkippedToolCallResult(
        ToolCallSkipReason.perRoundLimit,
        limit: 4,
      );

      expect(payload['ok'], isTrue);
      expect(payload['skipped'], isTrue);
      expect(payload['reason'], 'per_round_limit');
      expect(payload['limit'], 4);
    });
  });
}
