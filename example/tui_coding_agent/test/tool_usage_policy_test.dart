import 'package:llamadart_tui_coding_agent/src/tool_usage_policy.dart';
import 'package:test/test.dart';

void main() {
  group('ToolUsagePolicy', () {
    const policy = ToolUsagePolicy();

    test('returns direct-answer mode for conceptual prompt', () {
      final decision = policy.decideForPrompt(
        'What is dependency inversion in SOLID?',
      );

      expect(decision.allowTools, isFalse);
      expect(decision.requiresWorkspaceInspection, isFalse);
    });

    test('enables tools for repo-specific prompt', () {
      final decision = policy.decideForPrompt(
        'Read lib/src/main.dart and explain.',
      );

      expect(decision.allowTools, isTrue);
      expect(decision.requiresWorkspaceInspection, isFalse);
    });

    test('requires workspace inspection for this-project prompt', () {
      final decision = policy.decideForPrompt('What is this project for?');

      expect(decision.allowTools, isTrue);
      expect(decision.requiresWorkspaceInspection, isTrue);
    });

    test('respects explicit no-tool instruction', () {
      final decision = policy.decideForPrompt(
        'Without tools, explain what this project might do.',
      );

      expect(decision.allowTools, isFalse);
      expect(decision.requiresWorkspaceInspection, isFalse);
    });

    test('detects tool-access deflection text', () {
      final isDeflection = policy.looksLikeToolAccessDeflection(
        "I don't have access to your files unless you want me to inspect.",
      );

      expect(isDeflection, isTrue);
    });

    test('does not flag normal grounded answer as deflection', () {
      final isDeflection = policy.looksLikeToolAccessDeflection(
        'I checked README.md and pubspec.yaml and this project provides a TUI coding agent example.',
      );

      expect(isDeflection, isFalse);
    });
  });
}
