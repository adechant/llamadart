enum SessionEventType { status, assistantToken, toolCall, toolResult, error }

class SessionEvent {
  final SessionEventType type;
  final String message;

  const SessionEvent(this.type, this.message);

  factory SessionEvent.status(String message) {
    return SessionEvent(SessionEventType.status, message);
  }

  factory SessionEvent.assistantToken(String message) {
    return SessionEvent(SessionEventType.assistantToken, message);
  }

  factory SessionEvent.toolCall(String message) {
    return SessionEvent(SessionEventType.toolCall, message);
  }

  factory SessionEvent.toolResult(String message) {
    return SessionEvent(SessionEventType.toolResult, message);
  }

  factory SessionEvent.error(String message) {
    return SessionEvent(SessionEventType.error, message);
  }
}
