import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_chat_l10n.dart';

/// تایم‌لاین عمودی مراحل agent (شبیه Cursor).
class AIAgentTraceTimeline extends StatelessWidget {
  final List<AIAgentTraceStep> steps;
  final bool compact;

  const AIAgentTraceTimeline({
    super.key,
    required this.steps,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _TraceStepTile(
            step: steps[i],
            title: aiTraceStepTitle(l10n, steps[i]),
            isLast: i == steps.length - 1,
            theme: theme,
            scheme: scheme,
            compact: compact,
          ),
      ],
    );
  }
}

class _TraceStepTile extends StatelessWidget {
  final AIAgentTraceStep step;
  final String title;
  final bool isLast;
  final ThemeData theme;
  final ColorScheme scheme;
  final bool compact;

  const _TraceStepTile({
    required this.step,
    required this.title,
    required this.isLast,
    required this.theme,
    required this.scheme,
    required this.compact,
  });

  IconData _iconForKind() {
    switch (step.kind) {
      case 'plan':
      case 'plan_next':
        return Icons.route_outlined;
      case 'narrative':
        return Icons.psychology_outlined;
      case 'tool':
        return Icons.build_circle_outlined;
      case 'observation':
        return Icons.insights_outlined;
      case 'answer':
        return Icons.edit_note_outlined;
      case 'context':
        return Icons.tune_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = step.bodyMarkdown?.trim() ?? '';
    final showBody = body.isNotEmpty && step.kind != 'answer';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _StepNode(
                  icon: _iconForKind(),
                  active: step.isActive,
                  error: step.isError,
                  scheme: scheme,
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: scheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 4 : (compact ? 10 : 14),
                left: 4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (step.isActive)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: step.isError
                                ? scheme.error
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showBody) ...[
                    const SizedBox(height: 6),
                    MarkdownBody(
                      data: body,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: theme.textTheme.bodySmall?.copyWith(
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
                        h3: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        listBullet: theme.textTheme.bodySmall,
                        code: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool error;
  final ColorScheme scheme;

  const _StepNode({
    required this.icon,
    required this.active,
    required this.error,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final color = error
        ? scheme.error
        : active
            ? scheme.primary
            : scheme.onSurfaceVariant;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? scheme.primary : scheme.outlineVariant,
          width: active ? 1.5 : 1,
        ),
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }
}
