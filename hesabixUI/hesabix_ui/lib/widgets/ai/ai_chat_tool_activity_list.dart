import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_subagent_trace.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

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
    final filtered = visible
        .where((a) => !kSubagentLifecycleTools.contains(a.tool))
        .toList();
    if (filtered.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in filtered)
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
      iconColor = SemanticColorResolver.positive(context);
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
