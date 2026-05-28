import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/business_nav.dart';
import '../../models/ai_stream_event.dart';

/// نام workflow sandbox در API (هم‌نام با بک‌اند).
const kAiSandboxWorkflowName = '[AI] پیش‌نمایش آزمایشی';

final _editorPathInText = RegExp(
  r'(?:/business/\d+/tab\d+/)?workflows/(\d+)/edit',
);

/// لینک باز کردن ادیتور از نتیجهٔ tool یا متن پاسخ.
class WorkflowEditorLink {
  final int workflowId;
  final String? workflowName;
  final bool sandboxPreview;

  const WorkflowEditorLink({
    required this.workflowId,
    this.workflowName,
    this.sandboxPreview = false,
  });
}

bool isAiSandboxWorkflow(Map<String, dynamic> workflow) {
  final settings = workflow['settings'];
  if (settings is Map && settings['ai_sandbox'] == true) return true;
  final name = workflow['name']?.toString() ?? '';
  return name == kAiSandboxWorkflowName;
}

/// استخراج لینک‌های ادیتور از function_results و متن assistant.
List<WorkflowEditorLink> collectWorkflowEditorLinks({
  Object? functionResults,
  String? assistantContent,
}) {
  final byId = <int, WorkflowEditorLink>{};

  void addFromMap(Map<String, dynamic> map) {
    final wid = _parseWorkflowId(map['workflow_id'] ?? map['id']);
    if (wid == null) return;
    final sandbox = map['sandbox_used'] == true ||
        map['name']?.toString() == kAiSandboxWorkflowName;
    byId[wid] = WorkflowEditorLink(
      workflowId: wid,
      workflowName: map['name']?.toString(),
      sandboxPreview: sandbox || (byId[wid]?.sandboxPreview ?? false),
    );
  }

  void walk(dynamic value) {
    if (value is Map) {
      final m = Map<String, dynamic>.from(value);
      if (m.containsKey('editor_path') ||
          (m.containsKey('workflow_id') &&
              (m.containsKey('name') || m.containsKey('status')))) {
        addFromMap(m);
      }
      for (final v in m.values) {
        walk(v);
      }
    } else if (value is List) {
      for (final item in value) {
        walk(item);
      }
    }
  }

  if (functionResults is Map) {
    final fr = Map<String, dynamic>.from(functionResults);
    fr.remove(kAgentTraceStorageKey);
    walk(fr);
  }

  final text = assistantContent ?? '';
  for (final m in _editorPathInText.allMatches(text)) {
    final wid = int.tryParse(m.group(1)!);
    if (wid != null && !byId.containsKey(wid)) {
      byId[wid] = WorkflowEditorLink(workflowId: wid);
    }
  }

  return byId.values.toList()
    ..sort((a, b) => b.workflowId.compareTo(a.workflowId));
}

int? _parseWorkflowId(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

void openWorkflowInEditor(BuildContext context, int businessId, int workflowId) {
  final path = context.businessPanelUrl(businessId, 'workflows/$workflowId/edit');
  context.go(path);
}

/// دکمه‌های «باز کردن در ادیتور» زیر پیام دستیار.
class AIWorkflowChatActions extends StatelessWidget {
  final int? businessId;
  final Object? functionResults;
  final String? assistantContent;

  const AIWorkflowChatActions({
    super.key,
    required this.businessId,
    this.functionResults,
    this.assistantContent,
  });

  @override
  Widget build(BuildContext context) {
    if (businessId == null) return const SizedBox.shrink();
    final links = collectWorkflowEditorLinks(
      functionResults: functionResults,
      assistantContent: assistantContent,
    );
    if (links.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final link in links)
            FilledButton.tonalIcon(
              onPressed: () => openWorkflowInEditor(
                context,
                businessId!,
                link.workflowId,
              ),
              icon: Icon(
                link.sandboxPreview
                    ? Icons.science_outlined
                    : Icons.account_tree_outlined,
                size: 18,
              ),
              label: Text(_labelFor(link)),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  String _labelFor(WorkflowEditorLink link) {
    if (link.sandboxPreview) {
      return 'مشاهده پیش‌نمایش در ادیتور';
    }
    final name = link.workflowName?.trim();
    if (name != null && name.isNotEmpty && name != kAiSandboxWorkflowName) {
      return 'ادیتور: $name';
    }
    return 'باز کردن در ادیتور اتوماسیون';
  }
}
