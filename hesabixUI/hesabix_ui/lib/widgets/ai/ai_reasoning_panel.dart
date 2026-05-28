import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_agent_trace_timeline.dart';
import 'ai_chat_design.dart';

/// پنل استدلال — traceهای لایه reasoning جدا از پاسخ نهایی.
class AIReasoningPanel extends StatefulWidget {
  final List<AIAgentTraceStep> steps;
  final bool compact;
  final bool initiallyExpanded;
  final bool collapseWhenDone;

  const AIReasoningPanel({
    super.key,
    required this.steps,
    this.compact = false,
    this.initiallyExpanded = true,
    this.collapseWhenDone = false,
  });

  static List<AIAgentTraceStep> reasoningOnly(List<AIAgentTraceStep> all) {
    return all
        .where((s) {
          final layer = s.layer;
          if (layer == 'answer') return false;
          if (layer == null && s.kind == 'answer') return false;
          return true;
        })
        .toList();
  }

  @override
  State<AIReasoningPanel> createState() => _AIReasoningPanelState();
}

class _AIReasoningPanelState extends State<AIReasoningPanel>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (_hasActiveStep) {
      _pulseCtrl.repeat(reverse: true);
    }
    _maybeCollapseWhenDone();
  }

  @override
  void didUpdateWidget(covariant AIReasoningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.compact) _expanded = true;
    if (_hasActiveStep && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!_hasActiveStep && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    }
    _maybeCollapseWhenDone();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveStep =>
      widget.steps.any((s) => s.isActive && s.layer != 'answer');

  void _maybeCollapseWhenDone() {
    if (!widget.collapseWhenDone || widget.initiallyExpanded) return;
    final allDone = widget.steps.isNotEmpty &&
        widget.steps.every((s) => !s.isActive);
    if (allDone && _expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _expanded = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasoning = AIReasoningPanel.reasoningOnly(widget.steps);
    if (reasoning.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.primaryContainer.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 4),
                  _hasActiveStep
                      ? ScaleTransition(
                          scale: Tween(begin: 1.0, end: 1.1).animate(
                            CurvedAnimation(
                              parent: _pulseCtrl,
                              curve: Curves.easeInOut,
                            ),
                          ),
                          child: Icon(
                            Icons.psychology_outlined,
                            size: 18,
                            color: scheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.psychology_outlined,
                          size: 18,
                          color: scheme.primary,
                        ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.aiReasoningPanelTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${reasoning.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstCurve: Curves.easeOutCubic,
          secondCurve: Curves.easeInCubic,
          sizeCurve: Curves.easeOutCubic,
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: AIChatDesign.layoutTransition,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DecoratedBox(
              decoration: AIChatDesign.subtlePanel(theme, accent: scheme.primary),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: AIAgentTraceTimeline(
                  steps: reasoning,
                  compact: widget.compact,
                  initiallyExpanded: true,
                ),
              ),
            ),
          ),
          secondChild: const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}
