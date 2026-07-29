import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_agent_trace_timeline.dart';
import 'ai_agent_todo_list.dart';
import 'ai_chat_design.dart';
import 'ai_chat_l10n.dart';
import 'ai_chat_tool_activity_list.dart';

/// پنل استدلال — traceهای لایه reasoning جدا از پاسخ نهایی.
class AIReasoningPanel extends StatefulWidget {
  final List<AIAgentTraceStep> steps;
  final List<AIToolActivity> toolActivities;
  final AIStreamAgentBudget? agentBudget;
  final AISessionTodoSnapshot? todoSnapshot;
  final bool compact;
  final bool initiallyExpanded;

  const AIReasoningPanel({
    super.key,
    required this.steps,
    this.toolActivities = const [],
    this.agentBudget,
    this.todoSnapshot,
    this.compact = false,
    this.initiallyExpanded = false,
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
  /// کاربر دستی باز/بسته کرده — دیگر auto-collapse اعمال نشود.
  bool _userControlledExpansion = false;

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
  }

  @override
  void didUpdateWidget(covariant AIReasoningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userControlledExpansion) {
      if (_hasActiveStep) {
        _expanded = true;
      } else if (!widget.initiallyExpanded) {
        _expanded = false;
      }
    }
    if (_hasActiveStep && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!_hasActiveStep && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveStep =>
      widget.steps.any((s) => s.isActive && s.layer != 'answer') ||
      (widget.todoSnapshot?.hasActiveItem ?? false);

  bool get _hasTodoPlan =>
      widget.todoSnapshot != null && !widget.todoSnapshot!.isEmpty;

  @override
  Widget build(BuildContext context) {
    final reasoning = AIReasoningPanel.reasoningOnly(widget.steps);
    final toolCount = widget.toolActivities.length;
    final todoCount = widget.todoSnapshot?.items.length ?? 0;
    if (reasoning.isEmpty &&
        toolCount == 0 &&
        widget.agentBudget == null &&
        !_hasTodoPlan) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detailCount = reasoning.length +
        toolCount +
        todoCount +
        (widget.agentBudget != null ? 1 : 0);
    final title = _hasTodoPlan
        ? aiSessionPlanReasoningTitle(l10n)
        : reasoning.isNotEmpty
            ? l10n.aiReasoningPanelTitle
            : widget.agentBudget != null
                ? 'بودجه تحلیل'
                : 'ابزارهای استفاده‌شده';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.primaryContainer.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              _userControlledExpansion = true;
              _expanded = !_expanded;
            }),
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
                      title,
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
                      '$detailCount',
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
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // اسکرول داخل پنل استدلال به ListView والد نرسد (پرش به پاسخ نهایی).
                if (notification is ScrollUpdateNotification ||
                    notification is OverscrollNotification) {
                  return true;
                }
                return false;
              },
              child: DecoratedBox(
                decoration:
                    AIChatDesign.subtlePanel(theme, accent: scheme.primary),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_hasTodoPlan)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AIAgentTodoList(
                            snapshot: widget.todoSnapshot!,
                            compact: widget.compact,
                            initiallyExpanded:
                                widget.todoSnapshot!.hasActiveItem,
                          ),
                        ),
                      if (widget.agentBudget != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            aiAgentBudgetSummary(l10n, budget: widget.agentBudget!),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (reasoning.isNotEmpty)
                        AIAgentTraceTimeline(
                          steps: reasoning,
                          compact: widget.compact,
                          initiallyExpanded: false,
                        ),
                      if (widget.toolActivities.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: reasoning.isNotEmpty ? 8 : 0),
                          child: AIChatToolActivityList(
                            activities: widget.toolActivities,
                          ),
                        ),
                    ],
                  ),
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
