import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/ai_stream_event.dart';
import 'ai_chat_design.dart';
import 'ai_chat_l10n.dart';

/// چک‌لیست برنامهٔ کاری agent — نمایش زنده و پس از اتمام پیام.
class AIAgentTodoList extends StatefulWidget {
  final AISessionTodoSnapshot snapshot;
  final bool compact;
  final bool initiallyExpanded;
  final void Function(AISessionTodoItem item, String status)? onUserStatus;

  const AIAgentTodoList({
    super.key,
    required this.snapshot,
    this.compact = false,
    this.initiallyExpanded = false,
    this.onUserStatus,
  });

  @override
  State<AIAgentTodoList> createState() => _AIAgentTodoListState();
}

class _AIAgentTodoListState extends State<AIAgentTodoList>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded || widget.snapshot.hasActiveItem;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.snapshot.hasActiveItem) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant AIAgentTodoList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.snapshot.hasActiveItem) {
      _expanded = true;
      if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat(reverse: true);
      }
    } else if (widget.snapshot.isFullyComplete && !widget.initiallyExpanded) {
      _expanded = false;
      _pulseCtrl.stop();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.snapshot.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final summary = widget.snapshot.summary;
    final progress = summary.progress;
    final title = widget.snapshot.planTitle?.trim().isNotEmpty == true
        ? widget.snapshot.planTitle!.trim()
        : aiSessionPlanDefaultTitle(l10n);

    return AnimatedContainer(
      duration: AIChatDesign.fadeTransition,
      margin: widget.compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 10),
      decoration: widget.compact
          ? null
          : AIChatDesign.subtlePanel(theme, accent: scheme.primary),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.compact ? 0 : 14,
          widget.compact ? 0 : 12,
          widget.compact ? 0 : 14,
          widget.compact ? 0 : 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: widget.compact
                  ? null
                  : () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.checklist_rounded,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            aiSessionPlanProgressLabel(
                              l10n,
                              completed: summary.completed,
                              total: summary.total,
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!widget.compact)
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value <= 0 ? null : value,
                    minHeight: 5,
                    backgroundColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    color: widget.snapshot.isFullyComplete
                        ? scheme.tertiary
                        : scheme.primary,
                  );
                },
              ),
            ),
            if (_expanded || widget.compact) ...[
              const SizedBox(height: 12),
              ...widget.snapshot.items.map(
                (item) => _TodoItemRow(
                  item: item,
                  pulse: _pulseCtrl,
                  l10n: l10n,
                  theme: theme,
                  scheme: scheme,
                  onUserStatus: widget.onUserStatus,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodoItemRow extends StatelessWidget {
  final AISessionTodoItem item;
  final Animation<double> pulse;
  final AppLocalizations l10n;
  final ThemeData theme;
  final ColorScheme scheme;
  final void Function(AISessionTodoItem item, String status)? onUserStatus;

  const _TodoItemRow({
    required this.item,
    required this.pulse,
    required this.l10n,
    required this.theme,
    required this.scheme,
    this.onUserStatus,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = item.isInProgress;
    final bg = isActive
        ? scheme.primary.withValues(alpha: 0.08)
        : Colors.transparent;
    final border = isActive
        ? Border.all(color: scheme.primary.withValues(alpha: 0.28))
        : Border.all(color: Colors.transparent);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: border,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusIcon(item: item, pulse: pulse, scheme: scheme),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    decoration: item.isSkipped
                        ? TextDecoration.lineThrough
                        : null,
                    color: item.isPending
                        ? scheme.onSurface.withValues(alpha: 0.72)
                        : scheme.onSurface,
                    height: 1.35,
                  ),
                ),
                if (item.description != null &&
                    item.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.description!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
                if (item.linkedTool != null &&
                    item.linkedTool!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    aiSessionPlanLinkedToolLabel(l10n, item.linkedTool!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary.withValues(alpha: 0.85),
                    ),
                  ),
                ],
                if (item.isError &&
                    item.errorMessage != null &&
                    item.errorMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.errorMessage!.trim(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onUserStatus != null && item.canUserDecide) ...[
            IconButton(
              tooltip: aiSessionPlanConfirmLabel(l10n),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.check_rounded,
                size: 18,
                color: scheme.tertiary,
              ),
              onPressed: () => onUserStatus!(item, 'done'),
            ),
            IconButton(
              tooltip: aiSessionPlanSkipLabel(l10n),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onPressed: () => onUserStatus!(item, 'skipped'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final AISessionTodoItem item;
  final Animation<double> pulse;
  final ColorScheme scheme;

  const _StatusIcon({
    required this.item,
    required this.pulse,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    if (item.isInProgress) {
      return AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          return Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.12 + pulse.value * 0.1),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.55),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
          );
        },
      );
    }
    if (item.isDone) {
      return Icon(Icons.check_circle_rounded, size: 22, color: scheme.tertiary);
    }
    if (item.isSkipped) {
      return Icon(
        Icons.remove_circle_outline_rounded,
        size: 22,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.65),
      );
    }
    if (item.isError) {
      return Icon(Icons.error_outline_rounded, size: 22, color: scheme.error);
    }
    return Icon(
      Icons.radio_button_unchecked_rounded,
      size: 22,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
    );
  }
}
