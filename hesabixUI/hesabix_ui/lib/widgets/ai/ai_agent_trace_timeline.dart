import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_chat_l10n.dart';

/// تایم‌لاین عمودی مراحل agent (شبیه Cursor) — پیش‌فرض جمع‌شده.
class AIAgentTraceTimeline extends StatefulWidget {
  final List<AIAgentTraceStep> steps;
  final bool compact;
  final bool initiallyExpanded;

  const AIAgentTraceTimeline({
    super.key,
    required this.steps,
    this.compact = false,
    this.initiallyExpanded = false,
  });

  @override
  State<AIAgentTraceTimeline> createState() => _AIAgentTraceTimelineState();
}

class _AIAgentTraceTimelineState extends State<AIAgentTraceTimeline> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded || widget.compact;
  }

  @override
  void didUpdateWidget(covariant AIAgentTraceTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.compact) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activeCount =
        widget.steps.where((s) => s.isActive).length;

    final visibleSteps = _expanded
        ? widget.steps
        : widget.steps
            .where((s) => s.isActive || s.isError)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.aiTraceStepsHeader(widget.steps.length),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!_expanded && activeCount > 0)
                    Text(
                      l10n.aiTraceStepsActive(activeCount),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_expanded || widget.compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < visibleSteps.length; i++)
                _TraceStepTile(
                  step: visibleSteps[i],
                  title: aiTraceStepTitle(l10n, visibleSteps[i]),
                  isLast: i == visibleSteps.length - 1,
                  theme: theme,
                  scheme: scheme,
                  compact: widget.compact,
                ),
            ],
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
        return Icons.record_voice_over_outlined;
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
    final showBody = body.isNotEmpty &&
        (step.kind == 'narrative' ||
            step.kind == 'plan' ||
            step.kind == 'observation' ||
            (step.kind != 'answer' && !step.isActive));

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
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: step.isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: step.isError
                                ? scheme.error
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      if (step.iteration != null)
                        Text(
                          '#${step.iteration}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.outline,
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
                          color: scheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                        listBullet: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
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
            : scheme.outline;

    return SizedBox(
      width: 24,
      height: 24,
      child: active && !error
          ? Padding(
              padding: const EdgeInsets.all(3),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            )
          : Icon(icon, size: 18, color: color),
    );
  }
}
