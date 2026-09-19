import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/widgets/ai/ai_chat_session_controller.dart';

AIChatSession _session({
  required int id,
  DateTime? updatedAt,
  DateTime? createdAt,
}) {
  return AIChatSession(
    id: id,
    userId: 1,
    title: 's$id',
    updatedAt: updatedAt,
    createdAt: createdAt,
  );
}

void main() {
  test('sortChatSessionsByRecency puts newest first', () {
    final older = _session(id: 1, updatedAt: DateTime(2026, 1, 1));
    final newer = _session(id: 2, updatedAt: DateTime(2026, 8, 1));
    final sorted = sortChatSessionsByRecency([older, newer]);
    expect(sorted.map((s) => s.id), [2, 1]);
  });

  test('goHome clears current thread', () {
    final thread = AIChatSessionController()
      ..current = _session(id: 4)
      ..messages = [
        AIChatMessage(sessionId: 4, role: MessageRole.user, content: 'سلام'),
      ]
      ..messagesLoading = true;
    thread.goHome();
    expect(thread.current, isNull);
    expect(thread.messages, isEmpty);
    expect(thread.messagesLoading, isFalse);
    expect(
      thread.isHomeMode(streamActive: false, sending: false),
      isTrue,
    );
  });

  test('begin then finish select replaces messages', () {
    final thread = AIChatSessionController();
    final session = _session(id: 9);
    thread.beginSelectSession(session);
    expect(thread.current?.id, 9);
    expect(thread.messagesLoading, isTrue);
    expect(thread.messages, isEmpty);

    thread.finishSelectSession([
      AIChatMessage(sessionId: 9, role: MessageRole.user, content: 'گزارش'),
    ]);
    expect(thread.messagesLoading, isFalse);
    expect(thread.messages, hasLength(1));
    expect(
      thread.isHomeMode(streamActive: false, sending: false),
      isFalse,
    );
  });

  test('appendOptimisticUser requires current session', () {
    final thread = AIChatSessionController();
    expect(
      () => thread.appendOptimisticUser('سلام'),
      throwsStateError,
    );
    thread.adoptCreatedSession(_session(id: 3));
    final msg = thread.appendOptimisticUser(
      'فروش ماه',
      now: DateTime(2026, 8, 18),
    );
    expect(msg.sessionId, 3);
    expect(msg.role, MessageRole.user);
    expect(thread.messages.single.content, 'فروش ماه');
  });

  test('sessionById finds loaded session after replaceSessions', () {
    final thread = AIChatSessionController();
    thread.replaceSessions([
      _session(id: 1, updatedAt: DateTime(2026, 1, 1)),
      _session(id: 5, updatedAt: DateTime(2026, 8, 1)),
    ]);
    expect(thread.sessions.first.id, 5);
    expect(thread.sessionById(1)?.title, 's1');
    expect(thread.sessionsLoading, isFalse);
  });

  test('patchSession updates current and list entry', () {
    final original = AIChatSession(
      id: 1,
      userId: 1,
      title: 'old',
      updatedAt: DateTime(2026, 1, 1),
    );
    final thread = AIChatSessionController()
      ..replaceSessions([original])
      ..adoptCreatedSession(original);
    thread.patchSession(
      AIChatSession(
        id: 1,
        userId: 1,
        title: 'new',
        executionMode: 'supervised',
        updatedAt: DateTime(2026, 8, 1),
      ),
    );
    expect(thread.current?.title, 'new');
    expect(thread.current?.executionMode, 'supervised');
    expect(thread.sessionById(1)?.title, 'new');
  });
}
