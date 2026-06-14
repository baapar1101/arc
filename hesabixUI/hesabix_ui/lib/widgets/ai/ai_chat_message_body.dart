import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_reasoning_panel.dart';
import 'ai_chat_chart_widget.dart';
import 'ai_chat_l10n.dart';
import 'ai_chat_table_widget.dart';
import 'ai_markdown_table_parser.dart';
import 'ai_visualization_spec.dart';
import 'ai_workflow_chat_actions.dart';

class AIChatMessageBody extends StatelessWidget {
  final String content;
  final bool isUser;
  final int? businessId;
  final Object? functionCalls;
  final Object? functionResults;
  final bool suppressApprovalToolChips;

  const AIChatMessageBody({
    super.key,
    required this.content,
    required this.isUser,
    this.businessId,
    this.functionCalls,
    this.functionResults,
    this.suppressApprovalToolChips = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    var agentTrace = extractAgentTraceFromResults(functionResults);
    if (suppressApprovalToolChips) {
      agentTrace =
          agentTrace.where((s) => s.kind != 'approval').toList();
    }
    var toolActivities = _buildToolActivities(l10n);
    if (suppressApprovalToolChips) {
      toolActivities =
          toolActivities.where((a) => !a.approvalRequired).toList();
    }

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (agentTrace.isNotEmpty) ...[
          AIReasoningPanel(
            steps: agentTrace,
            compact: true,
            initiallyExpanded: false,
          ),
          const SizedBox(height: 12),
        ],
        if (toolActivities.isNotEmpty) ...[
          for (final activity in toolActivities)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ToolActivityChip(activity: activity),
            ),
        ],
        if (content.trim().isNotEmpty) ...[
          isUser
              ? SelectableText(
                  content,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AssistantRichContent(
                      content: content,
                      theme: theme,
                      scheme: scheme,
                      businessId: businessId,
                    ),
                    if (!isUser)
                      AIWorkflowChatActions(
                        businessId: businessId,
                        functionResults: functionResults,
                        assistantContent: content,
                      ),
                  ],
                ),
        ],
      ],
    );
  }

  List<AIToolActivity> _buildToolActivities(AppLocalizations l10n) {
    final calls = _normalizeCalls(functionCalls);
    if (calls.isEmpty) return [];

    final results = functionResults is Map
        ? (Map<String, dynamic>.from(functionResults as Map)
          ..remove(kAgentTraceStorageKey))
        : <String, dynamic>{};

    return calls.map((call) {
      final name = call['name'] as String? ?? 'unknown';
      final callId = call['id'] as String?;
      Object? result;
      if (callId != null && results.containsKey(callId)) {
        final raw = results[callId];
        if (raw is Map && raw.containsKey('result')) {
          result = raw['result'];
        } else {
          result = raw;
        }
      } else {
        result = results[name];
      }
      final needsApproval = result is Map &&
          result['error'] == 'APPROVAL_REQUIRED';
      final hasError = result is Map && result.containsKey('error') && !needsApproval;

      return AIToolActivity(
        tool: name,
        label: aiToolLabel(l10n, name),
        running: false,
        success: result != null && !hasError && !needsApproval,
        approvalRequired: needsApproval,
      );
    }).toList();
  }

  List<Map<String, dynamic>> _normalizeCalls(Object? raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is Map) {
      final m = Map<String, dynamic>.from(raw);
      if (m['calls'] is List) {
        return (m['calls'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (m['name'] != null) return [m];
    }
    return [];
  }
}

class _AssistantRichContent extends StatelessWidget {
  final String content;
  final ThemeData theme;
  final ColorScheme scheme;
  final int? businessId;

  const _AssistantRichContent({
    required this.content,
    required this.theme,
    required this.scheme,
    this.businessId,
  });

  @override
  Widget build(BuildContext context) {
    final segments = _expandMarkdownTables(_splitVisualizationBlocks(content));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final seg in segments)
          if (seg.chartSpec != null)
            AIChatChartWidget(spec: seg.chartSpec!)
          else if (seg.tableSpec != null)
            AIChatTableWidget(spec: seg.tableSpec!)
          else if (seg.text.trim().isNotEmpty)
            MarkdownBody(
              data: seg.text.trim(),
              selectable: true,
              styleSheet: _markdownStyle(theme, scheme),
              onTapLink: businessId != null
                  ? (text, href, title) => _onMarkdownLink(context, businessId!, text, href)
                  : null,
            ),
      ],
    );
  }

  static void _onMarkdownLink(
    BuildContext context,
    int businessId,
    String text,
    String? href,
  ) {
    final target = (href ?? text).trim();
    if (target.isEmpty) return;
    final workflowMatch = _editorPathInMarkdown.firstMatch(target);
    if (workflowMatch != null) {
      final wid = int.tryParse(workflowMatch.group(1)!);
      if (wid != null) {
        openWorkflowInEditor(context, businessId, wid);
        return;
      }
    }
    if (target.startsWith('/business/')) {
      context.go(target);
    }
  }

  static final _editorPathInMarkdown = RegExp(
    r'(?:/business/\d+/tab\d+/)?workflows/(\d+)/edit',
  );

  static MarkdownStyleSheet _markdownStyle(ThemeData theme, ColorScheme scheme) {
    return MarkdownStyleSheet(
      p: theme.textTheme.bodyLarge?.copyWith(height: 1.65, letterSpacing: 0.1),
      h1: theme.textTheme.titleLarge,
      h2: theme.textTheme.titleMedium,
      h3: theme.textTheme.titleSmall,
      code: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: scheme.surfaceContainerHighest,
      ),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(right: BorderSide(color: scheme.primary, width: 3)),
      ),
      listBullet: theme.textTheme.bodyLarge,
    );
  }

  /// جدا کردن بلوک‌های ```chart / ```table / ```json از متن.
  static List<_ContentSegment> _splitVisualizationBlocks(String raw) {
    final pattern = RegExp(
      r'```(chart|table|json)\s*([\s\S]*?)```',
      caseSensitive: false,
      multiLine: true,
    );
    final segments = <_ContentSegment>[];
    var start = 0;

    for (final match in pattern.allMatches(raw)) {
      if (match.start > start) {
        segments.add(_ContentSegment(text: raw.substring(start, match.start)));
      }
      final kind = (match.group(1) ?? '').toLowerCase();
      final body = match.group(2) ?? '';
      final fenced = match.group(0) ?? '';

      if (kind == 'chart') {
        final spec = AIChartSpec.tryParse(body);
        if (spec != null && spec.hasData) {
          segments.add(_ContentSegment.chart(spec));
        } else {
          segments.add(_ContentSegment(text: fenced));
        }
      } else if (kind == 'table') {
        final spec = AIMarkdownTableParser.tryParseLoose(body);
        if (spec != null) {
          segments.add(_ContentSegment.table(spec));
        } else {
          segments.add(_ContentSegment(text: fenced));
        }
      } else if (kind == 'json') {
        final segment = _segmentFromJsonFence(body, fenced);
        segments.add(segment);
      }
      start = match.end;
    }

    if (start < raw.length) {
      segments.add(_ContentSegment(text: raw.substring(start)));
    }
    if (segments.isEmpty) {
      segments.add(_ContentSegment(text: raw));
    }
    return segments;
  }

  static _ContentSegment _segmentFromJsonFence(String body, String fenced) {
    final table = AIMarkdownTableParser.tryParseLoose(body);
    if (table != null) return _ContentSegment.table(table);

    final chart = AIChartSpec.tryParse(body);
    if (chart != null && chart.hasData) return _ContentSegment.chart(chart);

    return _ContentSegment(text: fenced);
  }

  /// استخراج جدول‌های pipe از قطعات متنی باقی‌مانده.
  static List<_ContentSegment> _expandMarkdownTables(List<_ContentSegment> input) {
    final out = <_ContentSegment>[];
    for (final seg in input) {
      if (seg.chartSpec != null || seg.tableSpec != null) {
        out.add(seg);
        continue;
      }
      final parts = AIMarkdownTableParser.splitText(seg.text);
      if (parts.isEmpty) {
        if (seg.text.trim().isNotEmpty) out.add(seg);
        continue;
      }
      for (final part in parts) {
        if (part.tableSpec != null) {
          out.add(_ContentSegment.table(part.tableSpec!));
        } else if (part.text != null && part.text!.trim().isNotEmpty) {
          out.add(_ContentSegment(text: part.text!));
        }
      }
    }
    return out.isEmpty ? input : out;
  }
}

class _ContentSegment {
  final String text;
  final AIChartSpec? chartSpec;
  final AITableSpec? tableSpec;

  _ContentSegment({this.text = '', this.chartSpec, this.tableSpec});

  factory _ContentSegment.chart(AIChartSpec spec) =>
      _ContentSegment(chartSpec: spec);

  factory _ContentSegment.table(AITableSpec spec) =>
      _ContentSegment(tableSpec: spec);
}

class AIChatToolActivityList extends StatelessWidget {
  final List<AIToolActivity> activities;
  final bool hideApprovalPending;

  const AIChatToolActivityList({
    super.key,
    required this.activities,
    this.hideApprovalPending = false,
  });

  @override
  Widget build(BuildContext context) {
    final visible = hideApprovalPending
        ? activities.where((a) => !a.approvalRequired).toList()
        : activities;
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ToolActivityChip(activity: a),
          ),
      ],
    );
  }
}

class _ToolActivityChip extends StatelessWidget {
  final AIToolActivity activity;

  const _ToolActivityChip({required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    IconData icon;
    Color? iconColor;
    if (activity.running) {
      icon = Icons.hourglass_top_rounded;
      iconColor = scheme.primary;
    } else if (activity.approvalRequired) {
      icon = Icons.gpp_maybe_outlined;
      iconColor = scheme.tertiary;
    } else if (activity.success == true) {
      icon = Icons.check_circle_outline_rounded;
      iconColor = Colors.green.shade700;
    } else if (activity.success == false) {
      icon = Icons.error_outline_rounded;
      iconColor = scheme.error;
    } else {
      icon = Icons.build_circle_outlined;
      iconColor = scheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (activity.running)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            )
          else
            Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              activity.running
                  ? l10n.aiStatusRunningTool(activity.label)
                  : activity.approvalRequired
                      ? '${activity.label} — نیاز به تأیید'
                      : activity.label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
