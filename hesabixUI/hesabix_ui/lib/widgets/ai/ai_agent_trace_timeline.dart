import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _TraceStepTile extends StatefulWidget {
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

  @override
  State<_TraceStepTile> createState() => _TraceStepTileState();
}

class _TraceStepTileState extends State<_TraceStepTile> {
  bool _bodyExpanded = false;

  IconData _iconForKind() {
    switch (widget.step.kind) {
      case 'explore':
        return Icons.travel_explore_outlined;
      case 'explored':
        return Icons.fact_check_outlined;
      case 'thought':
        return Icons.psychology_outlined;
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
    final step = widget.step;
    final body = step.bodyMarkdown?.trim() ?? '';
    final hasBody = body.isNotEmpty &&
        (step.kind == 'narrative' ||
            step.kind == 'plan' ||
            step.kind == 'observation' ||
            step.kind == 'explored' ||
            step.kind == 'thought' ||
            step.kind == 'explore' ||
            (step.kind != 'answer' && !step.isActive));

    final showBodyAlways = hasBody &&
        (step.kind == 'narrative' ||
            step.kind == 'plan' ||
            step.kind == 'explored' ||
            step.kind == 'thought' ||
            widget.compact);
    final showBodyToggle = hasBody && !showBodyAlways;

    final theme = widget.theme;
    final scheme = widget.scheme;

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
                if (!widget.isLast)
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
                bottom: widget.isLast ? 4 : (widget.compact ? 10 : 14),
                left: 4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ردیف عنوان + badge‌های غنی
                  GestureDetector(
                    onTap: showBodyToggle
                        ? () => setState(() => _bodyExpanded = !_bodyExpanded)
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
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
                        // badge تعداد نتایج
                        if (step.resultCount != null && step.resultCount! > 0) ...[
                          const SizedBox(width: 6),
                          _Badge(
                            label: '${step.resultCount}',
                            icon: Icons.format_list_bulleted_rounded,
                            color: scheme.secondary,
                            scheme: scheme,
                          ),
                        ],
                        // badge زمان اجرا
                        if (step.elapsedLabel != null) ...[
                          const SizedBox(width: 4),
                          _Badge(
                            label: step.elapsedLabel!,
                            icon: Icons.timer_outlined,
                            color: scheme.outline,
                            scheme: scheme,
                          ),
                        ],
                        // iteration number
                        if (step.confidence != null &&
                            (step.kind == 'thought')) ...[
                          const SizedBox(width: 4),
                          _Badge(
                            label: step.confidence!,
                            icon: Icons.verified_outlined,
                            color: _confidenceColor(scheme, step.confidence!),
                            scheme: scheme,
                          ),
                        ],
                        if (step.findingsCount != null &&
                            step.kind == 'thought') ...[
                          const SizedBox(width: 4),
                          _Badge(
                            label: '${step.findingsCount}',
                            icon: Icons.lightbulb_outline,
                            color: scheme.tertiary,
                            scheme: scheme,
                          ),
                        ],
                        if (step.iteration != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            '#${step.iteration}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                        ],
                        // toggle expand
                        if (showBodyToggle) ...[
                          const SizedBox(width: 2),
                          Icon(
                            _bodyExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16,
                            color: scheme.outline,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // بدنه همیشه نمایش
                  if (showBodyAlways) ...[
                    const SizedBox(height: 6),
                    _BodyContent(body: body, theme: theme, scheme: scheme),
                  ],
                  // بدنه با toggle
                  if (showBodyToggle && _bodyExpanded) ...[
                    const SizedBox(height: 6),
                    _BodyContent(body: body, theme: theme, scheme: scheme),
                  ],
                  // citations
                  if (step.citations != null && step.citations!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _CitationRow(citations: step.citations!, scheme: scheme, theme: theme),
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

class _BodyContent extends StatelessWidget {
  final String body;
  final ThemeData theme;
  final ColorScheme scheme;

  const _BodyContent({
    required this.body,
    required this.theme,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
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
    );
  }
}

class _CitationRow extends StatelessWidget {
  final List<String> citations;
  final ThemeData theme;
  final ColorScheme scheme;

  const _CitationRow({
    required this.citations,
    required this.theme,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: citations.take(5).map((c) {
        return GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: c));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              c,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

Color _confidenceColor(ColorScheme scheme, String confidence) {
  switch (confidence) {
    case 'high':
      return scheme.primary;
    case 'low':
      return scheme.error;
    default:
      return scheme.tertiary;
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final ColorScheme scheme;

  const _Badge({
    required this.label,
    required this.icon,
    required this.color,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
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
