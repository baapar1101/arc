import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/ai_models.dart';
import 'package:hesabix_ui/widgets/ai/ai_write_approval_helpers.dart';

void main() {
  group('extractPendingApprovalOpsFromResults', () {
    test('returns empty for non-map', () {
      expect(extractPendingApprovalOpsFromResults(null), isEmpty);
      expect(extractPendingApprovalOpsFromResults('x'), isEmpty);
    });

    test('dedupes nested tool_call_id and name-keyed same approval', () {
      const required = {
        'error': 'APPROVAL_REQUIRED',
        'approval_id': 'abc123',
        'function': 'create_invoice',
        'arguments': {'person_id': 1},
      };
      final ops = extractPendingApprovalOpsFromResults({
        'call_1': {
          'name': 'create_invoice',
          'result': required,
        },
        'create_invoice': required,
      });
      expect(ops, hasLength(1));
      expect(ops.single['function'], 'create_invoice');
      expect(ops.single['approval_id'], 'abc123');
    });

    test('finds APPROVAL_REQUIRED at top level and nested result', () {
      final ops = extractPendingApprovalOpsFromResults({
        '_agent_trace': [
          {'step_id': 't1'},
        ],
        'create_invoice': {
          'error': 'APPROVAL_REQUIRED',
          'function': 'create_invoice',
        },
        'update_person': {
          'result': {
            'error': 'APPROVAL_REQUIRED',
            'function': 'update_person',
          },
        },
        'search_invoices': {'ok': true},
      });
      expect(ops, hasLength(2));
      expect(
        ops.map((e) => e['function']).toSet(),
        {'create_invoice', 'update_person'},
      );
    });
  });

  group('extractPendingApprovalOpsFromMessages', () {
    test('uses last assistant message only', () {
      final messages = [
        AIChatMessage(
          sessionId: 1,
          role: MessageRole.assistant,
          content: 'old',
          functionResults: {
            'create_invoice': {'error': 'APPROVAL_REQUIRED'},
          },
        ),
        AIChatMessage(
          sessionId: 1,
          role: MessageRole.user,
          content: 'ادامه',
        ),
        AIChatMessage(
          sessionId: 1,
          role: MessageRole.assistant,
          content: 'new',
          functionResults: {
            'create_person': {'error': 'APPROVAL_REQUIRED'},
          },
        ),
      ];
      final ops = extractPendingApprovalOpsFromMessages(messages);
      expect(ops, hasLength(1));
      expect(ops.single['error'], 'APPROVAL_REQUIRED');
      expect(messagesHavePendingWriteApproval(messages), isTrue);
    });
  });

  group('collectPendingApprovalOps', () {
    test('prefers last assistant message over stream ops', () {
      final messages = [
        AIChatMessage(
          sessionId: 7,
          role: MessageRole.assistant,
          content: 'ok',
          functionResults: {
            'create_invoice': {'error': 'APPROVAL_REQUIRED'},
          },
        ),
      ];
      final ops = collectPendingApprovalOps(
        messages: messages,
        sessionId: 7,
        streamPending: true,
        pendingApprovalSessionId: 7,
        streamOps: [
          {'error': 'APPROVAL_REQUIRED', 'function': 'from_stream'},
        ],
      );
      expect(ops, hasLength(1));
      expect(ops.single['function'], isNot('from_stream'));
    });
  });
}
