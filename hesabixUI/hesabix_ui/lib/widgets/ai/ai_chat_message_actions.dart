import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// اقدامات سریع زیر پیام assistant (کپی، بازخورد، تولید مجدد).
class AIChatMessageActions extends StatelessWidget {
  final VoidCallback onCopy;
  final VoidCallback? onRegenerate;
  final ValueChanged<int>? onFeedback;
  final int? currentRating;

  const AIChatMessageActions({
    super.key,
    required this.onCopy,
    this.onRegenerate,
    this.onFeedback,
    this.currentRating,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          _ActionIcon(
            icon: Icons.copy_outlined,
            tooltip: l10n.aiActionCopy,
            onPressed: onCopy,
            scheme: scheme,
            selected: false,
          ),
          if (onRegenerate != null) ...[
            const SizedBox(width: 4),
            _ActionIcon(
              icon: Icons.refresh_rounded,
              tooltip: l10n.aiActionRegenerate,
              onPressed: onRegenerate,
              scheme: scheme,
              selected: false,
            ),
          ],
          if (onFeedback != null) ...[
            const SizedBox(width: 4),
            _ActionIcon(
              icon: Icons.thumb_up_outlined,
              selectedIcon: Icons.thumb_up,
              tooltip: l10n.aiActionThumbsUp,
              onPressed: () => onFeedback!(1),
              scheme: scheme,
              selected: currentRating == 1,
            ),
            const SizedBox(width: 2),
            _ActionIcon(
              icon: Icons.thumb_down_outlined,
              selectedIcon: Icons.thumb_down,
              tooltip: l10n.aiActionThumbsDown,
              onPressed: () => onFeedback!(-1),
              scheme: scheme,
              selected: currentRating == -1,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String tooltip;
  final VoidCallback? onPressed;
  final ColorScheme scheme;
  final bool selected;

  const _ActionIcon({
    required this.icon,
    this.selectedIcon,
    required this.tooltip,
    required this.onPressed,
    required this.scheme,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        selected && selectedIcon != null ? selectedIcon : icon,
        size: 18,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}
