/// Decision tuple describing whether tools should be used for a prompt.
class ToolUsageDecision {
  /// Whether the model is allowed to emit tool calls for this prompt.
  final bool allowTools;

  /// Whether the model should inspect workspace files before answering.
  final bool requiresWorkspaceInspection;

  const ToolUsageDecision({
    required this.allowTools,
    required this.requiresWorkspaceInspection,
  });
}

/// Heuristic policy for deciding when repository tools are necessary.
class ToolUsagePolicy {
  static final RegExp _explicitNoToolPromptPattern = RegExp(
    r"\b(no tools?|without tools?|don't use tools?)\b",
  );
  static final RegExp _repoSpecificPromptPattern = RegExp(
    r'`[^`]+`|\.[a-z0-9]{1,6}\b|[/\\]|\b(file|files|path|directory|folder|repo|repository|project|codebase|workspace)\b|\b(read|search|list|open|inspect|edit|change|modify|update|implement|refactor|rename|fix|run|test|build|commit|diff)\b',
  );
  static final RegExp _conceptualPromptPattern = RegExp(
    r'^\s*(what|why|how|when|where|who)\b|\bexplain\b|\bconcept\b|\bbest practice\b|\bdifference\b|\bcompare\b',
  );
  static final RegExp _requiresWorkspaceInspectionPattern = RegExp(
    r'\b(this project|this repo|this repository|this codebase|this workspace|project purpose|what is this project|what does this project do|entry point|where is|which file|which files|project structure|folder structure|code structure)\b',
  );
  static final RegExp _containsThisPattern = RegExp(r'\bthis\b');
  static final RegExp _workspaceObjectPattern = RegExp(
    r'\b(project|repo|repository|codebase|workspace|file|files|folder|directory)\b',
  );
  static final RegExp _toolAccessDeflectionPattern = RegExp(
    r"(don't have access|do not have access|can't access|cannot access|unable to access|would need to|if you'd like me to|if you want me to|i can use tools if)",
  );

  const ToolUsagePolicy();

  /// Returns a tool-usage decision for the provided user prompt.
  ToolUsageDecision decideForPrompt(String prompt) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const ToolUsageDecision(
        allowTools: false,
        requiresWorkspaceInspection: false,
      );
    }

    if (_explicitNoToolPromptPattern.hasMatch(normalized)) {
      return const ToolUsageDecision(
        allowTools: false,
        requiresWorkspaceInspection: false,
      );
    }

    final requiresInspection = _requiresWorkspaceInspection(normalized);
    if (_repoSpecificPromptPattern.hasMatch(normalized)) {
      return ToolUsageDecision(
        allowTools: true,
        requiresWorkspaceInspection: requiresInspection,
      );
    }

    if (_conceptualPromptPattern.hasMatch(normalized)) {
      return ToolUsageDecision(
        allowTools: false,
        requiresWorkspaceInspection: requiresInspection,
      );
    }

    return ToolUsageDecision(
      allowTools: false,
      requiresWorkspaceInspection: requiresInspection,
    );
  }

  /// Returns true when assistant text looks like a false access deflection.
  bool looksLikeToolAccessDeflection(String assistantText) {
    final normalized = assistantText.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    return _toolAccessDeflectionPattern.hasMatch(normalized);
  }

  /// Builds a follow-up prompt instructing the model to inspect workspace files.
  String buildWorkspaceInspectionFollowupPrompt(String prompt) {
    return 'This request requires repository inspection. '
        'You DO have access through tools in this session. '
        'Do not ask for permission and do not claim lack of access. '
        'First call one or more tools (for example list_files and read_file) '
        'to gather evidence, then answer with concrete findings.\n'
        'User request:\n$prompt';
  }

  /// Builds a follow-up prompt requesting a direct answer without tools.
  String buildDirectAnswerRequestPrompt(String prompt) {
    return 'Answer directly without any tool calls. '
        'Do not emit <tool_call> blocks.\n'
        'User request:\n$prompt';
  }

  /// Builds a correction prompt when tools are overused for a direct question.
  String buildToolSuppressionFollowupPrompt() {
    return 'Do not call tools for this request. '
        'Answer directly using your current knowledge and prior context.';
  }

  /// Returns true when prompt wording indicates repository inspection is needed.
  bool _requiresWorkspaceInspection(String normalizedPrompt) {
    if (_requiresWorkspaceInspectionPattern.hasMatch(normalizedPrompt)) {
      return true;
    }

    final hasThis = _containsThisPattern.hasMatch(normalizedPrompt);
    final hasWorkspaceObject = _workspaceObjectPattern.hasMatch(
      normalizedPrompt,
    );
    return hasThis && hasWorkspaceObject;
  }
}
