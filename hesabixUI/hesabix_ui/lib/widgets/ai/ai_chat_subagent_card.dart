import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_chat_l10n.dart';
import 'ai_subagent_trace.dart';

/// کارت زیر-ایجنت شبیه Task در Cursor — هدف، وضعیت زنده، مراحل تو در تو، قطع.
class AIChatSubagentCard extends StatefulWidget {
  final AIAgentTraceStep step;
  final List<AIAgentTraceStep> allSteps;
  final bool compact;
  final void Function(String subagentId)? onCancelSubagent;

  const AIChatSubagentCard({
    super.key,
    required this.step,
    required this.allSteps,
    this.compact = false,
    this.onCancelSubagent,
  });

  @override
  State<AIChatSubagentCard> createState() => _AIChatSubagentCardState();
}

class _AIChatSubagentCardState extends State<AIChatSubagentCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.step.isActive || widget.compact;
  }

  @override
  void didUpdateWidget(covariant AIChatSubagentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.step.isActive && !_expanded) {
      _expanded = true;
    }
  }

  String _goal(AppLocalizations l10n) {
    final params = widget.step.titleParams;
    final fromParams = (params?['goal'] as String?)?.trim() ?? '';
    if (fromParams.isNotEmpty) return fromParams;
    final body = widget.step.bodyMarkdown?.trim() ?? '';
    if (body.isNotEmpty) return body;
    final titled = aiTraceStepTitle(l10n, widget.step).trim();
    if (titled.isNotEmpty && titled != l10n.aiToolSpawnSubagent) {
      return titled.replaceFirst('${l10n.aiToolSpawnSubagent}: ', '');
    }
    return l10n.aiSubagentLabel;
  }

  String _statusLabel(AppLocalizations l10n) {
    if (widget.step.isError) {
      final err = widget.step.bodyMarkdown ?? '';
      if (err.contains('CANCEL')) return l10n.aiSubagentStatusCancelled;
      return l10n.aiSubagentStatusFailed;
    }
    if (widget.step.isActive) return l10n.aiSubagentStatusRunning;
    return l10n.aiSubagentStatusCompleted;
  }

  Color _statusColor(ColorScheme scheme) {
    if (widget.step.isError) return scheme.error;
    if (widget.step.isActive) return scheme.primary;
    return scheme.tertiary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final children = subagentChildSteps(widget.allSteps, widget.step);
    final statusColor = _statusColor(scheme);
    final cancelId = widget.step.cancelableSubagentId;
    final canCancel = widget.step.isActive &&
        cancelId != null &&
        widget.onCancelSubagent != null;

    return Padding(
      padding: EdgeInsets.only(bottom: widget.compact ? 10 : 12),
      child: Material(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.step.isActive
                    ? scheme.primary.withValues(alpha: 0.45)
                    : scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: statusColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _StatusGlyph(
                                active: widget.step.isActive,
                                error: widget.step.isError,
                                color: statusColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.aiSubagentLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusChip(
                                label: _statusLabel(l10n),
                                color: statusColor,
                              ),
                              if (widget.step.elapsedLabel != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  widget.step.elapsedLabel!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.outline,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (canCancel)
                                Tooltip(
                                  message: l10n.aiToolCancelSubagent,
                                  child: InkWell(
                                    onTap: () =>
                                        widget.onCancelSubagent!(cancelId),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.stop_circle_outlined,
                                        size: 18,
                                        color: scheme.error,
                                      ),
                                    ),
                                  ),
                                ),
                              Icon(
                                _expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: scheme.outline,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _goal(l10n),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                          if (_expanded) ...[
                            const SizedBox(height: 10),
                            if (children.isEmpty)
                              Text(
                                widget.step.isActive
                                    ? l10n.aiSubagentWorking
                                    : (widget.step.bodyMarkdown
                                                ?.trim()
                                                .isNotEmpty ==
                                            true
                                        ? widget.step.bodyMarkdown!.trim()
                                        : l10n.aiSubagentStatusCompleted),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                              )
                            else
                              ...children.map(
                                (child) => _ChildToolRow(
                                  step: child,
                                  title: aiTraceStepTitle(l10n, child),
                                  theme: theme,
                                  scheme: scheme,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChildToolRow extends StatelessWidget {
  final AIAgentTraceStep step;
  final String title;
  final ThemeData theme;
  final ColorScheme scheme;

  const _ChildToolRow({
    required this.step,
    required this.title,
    required this.theme,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final color = step.isError
        ? scheme.error
        : step.isActive
            ? scheme.primary
            : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: step.isActive && !step.isError
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: scheme.primary,
                    ),
                  )
                : Icon(
                    step.kind == 'observation'
                        ? Icons.insights_outlined
                        : Icons.build_circle_outlined,
                    size: 14,
                    color: color,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                height: 1.35,
                fontWeight: step.isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          if (step.elapsedLabel != null)
            Text(
              step.elapsedLabel!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusGlyph extends StatelessWidget {
  final bool active;
  final bool error;
  final Color color;

  const _StatusGlyph({
    required this.active,
    required this.error,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (active && !error) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Icon(
      error ? Icons.error_outline : Icons.check_circle_outline,
      size: 16,
      color: color,
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
