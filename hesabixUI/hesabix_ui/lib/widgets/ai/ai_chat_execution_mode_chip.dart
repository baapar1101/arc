import 'package:flutter/material.dart';

import 'ai_chat_design.dart';
import 'ai_execution_mode.dart';

/// انتخاب حالت اجرای دستیار — کنار composer.
class AIChatExecutionModeChip extends StatelessWidget {
  final String selectedMode;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final bool compact;

  const AIChatExecutionModeChip({
    super.key,
    required this.selectedMode,
    this.enabled = true,
    this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mode = AIExecutionMode.normalize(selectedMode);
    final accent = AIExecutionMode.accentColor(context, mode);

    return PopupMenuButton<String>(
      tooltip: 'حالت اجرای دستیار',
      enabled: enabled && onChanged != null,
      initialValue: mode,
      onSelected: onChanged,
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (context) => AIExecutionMode.all
          .map(
            (value) => PopupMenuItem<String>(
              value: value,
              child: _ModeMenuRow(
                mode: value,
                selected: value == mode,
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        decoration: compact
            ? null
            : AIChatDesign.chipDecoration(theme).copyWith(
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AIExecutionMode.icon(mode), size: 15, color: accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                AIExecutionMode.label(mode),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ModeMenuRow extends StatelessWidget {
  final String mode;
  final bool selected;

  const _ModeMenuRow({required this.mode, required this.selected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AIExecutionMode.accentColor(context, mode);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          selected ? Icons.check_circle_rounded : AIExecutionMode.icon(mode),
          size: 20,
          color: selected ? accent : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AIExecutionMode.label(mode),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AIExecutionMode.description(mode),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
