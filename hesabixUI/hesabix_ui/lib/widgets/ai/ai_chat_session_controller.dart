import 'package:flutter/foundation.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_turn.dart';

DateTime chatSessionRecency(AIChatSession session) {
  return session.updatedAt ??
      session.createdAt ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

List<AIChatSession> sortChatSessionsByRecency(Iterable<AIChatSession> list) {
  final out = List<AIChatSession>.from(list);
  out.sort((a, b) => chatSessionRecency(b).compareTo(chatSessionRecency(a)));
  return out;
}

/// State جلسه و پیام‌ها جدا از God Widget (UX-01).
///
/// حلقهٔ SSE در [AIChatStreamController.consume] است؛ صوت در [AIChatVoiceSessionController].
class AIChatSessionController extends ChangeNotifier {
  List<AIChatSession> sessions = [];
  AIChatSession? current;
  List<AIChatMessage> messages = [];
  bool sessionsLoading = true;
  bool messagesLoading = false;

  bool isHomeMode({
    required bool streamActive,
    required bool sending,
  }) {
    return !messagesLoading && messages.isEmpty && !streamActive && !sending;
  }

  AIChatSession? sessionById(int id) {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  void markSessionsLoading() {
    sessionsLoading = true;
    notifyListeners();
  }

  void replaceSessions(List<AIChatSession> list) {
    sessions = sortChatSessionsByRecency(list);
    sessionsLoading = false;
    notifyListeners();
  }

  void failSessionsLoad() {
    sessionsLoading = false;
    notifyListeners();
  }

  void adoptCreatedSession(AIChatSession session) {
    current = session;
    notifyListeners();
  }

  void patchSession(AIChatSession updated) {
    current = updated;
    sessions = [
      for (final session in sessions)
        if (session.id == updated.id) updated else session,
    ];
    notifyListeners();
  }

  void beginSelectSession(AIChatSession session) {
    current = session;
    messages = [];
    messagesLoading = true;
    notifyListeners();
  }

  void finishSelectSession(List<AIChatMessage> loaded) {
    messages = List<AIChatMessage>.from(loaded);
    messagesLoading = false;
    notifyListeners();
  }

  void failSelectSession() {
    messagesLoading = false;
    notifyListeners();
  }

  void goHome() {
    current = null;
    messages = [];
    messagesLoading = false;
    notifyListeners();
  }

  void replaceMessages(List<AIChatMessage> next) {
    messages = List<AIChatMessage>.from(next);
    notifyListeners();
  }

  void appendMessage(AIChatMessage message) {
    messages = List<AIChatMessage>.from(messages)..add(message);
    notifyListeners();
  }

  void removeLastMessage() {
    if (messages.isEmpty) return;
    messages = List<AIChatMessage>.from(messages)..removeLast();
    notifyListeners();
  }

  AIChatMessage appendOptimisticUser(String content, {DateTime? now}) {
    final sessionId = current?.id;
    if (sessionId == null) {
      throw StateError('appendOptimisticUser requires an open session');
    }
    final message = AIChatMessage(
      sessionId: sessionId,
      role: MessageRole.user,
      content: content,
      createdAt: now ?? DateTime.now(),
    );
    appendMessage(message);
    return message;
  }

  void applyUsageToLastAssistant(Map<String, dynamic>? usage) {
    final patched = patchLastAssistantUsage(messages, usage);
    if (!identical(patched, messages)) {
      messages = patched;
      notifyListeners();
    }
  }
}
