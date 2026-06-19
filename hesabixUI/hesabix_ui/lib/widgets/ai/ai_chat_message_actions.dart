import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import 'ai_chat_design.dart';

/// اقدامات سریع زیر پیام assistant — همیشه کم‌رنگ؛ پررنگ روی hover.
class AIChatMessageActions extends StatefulWidget {
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
  State<AIChatMessageActions> createState() => _AIChatMessageActionsState();
}

class _AIChatMessageActionsState extends State<AIChatMessageActions> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final alwaysVisible = AIChatDesign.isCompactWidth(context);
    final visible = alwaysVisible || _hovered;
    final baseOpacity = alwaysVisible ? 1.0 : (_hovered ? 1.0 : 0.5);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedOpacity(
        opacity: visible ? baseOpacity : 0.5,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
          ignoring: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                _ActionIcon(
                  icon: Icons.copy_outlined,
                  tooltip: l10n.aiActionCopy,
                  onPressed: widget.onCopy,
                  scheme: scheme,
                  selected: false,
                ),
                if (widget.onRegenerate != null) ...[
                  const SizedBox(width: 4),
                  _ActionIcon(
                    icon: Icons.refresh_rounded,
                    tooltip: l10n.aiActionRegenerate,
                    onPressed: widget.onRegenerate,
                    scheme: scheme,
                    selected: false,
                  ),
                ],
                if (widget.onFeedback != null) ...[
                  const SizedBox(width: 4),
                  _ActionIcon(
                    icon: Icons.thumb_up_outlined,
                    selectedIcon: Icons.thumb_up,
                    tooltip: l10n.aiActionThumbsUp,
                    onPressed: () => widget.onFeedback!(1),
                    scheme: scheme,
                    selected: widget.currentRating == 1,
                  ),
                  const SizedBox(width: 2),
                  _ActionIcon(
                    icon: Icons.thumb_down_outlined,
                    selectedIcon: Icons.thumb_down,
                    tooltip: l10n.aiActionThumbsDown,
                    onPressed: () => widget.onFeedback!(-1),
                    scheme: scheme,
                    selected: widget.currentRating == -1,
                  ),
                ],
              ],
            ),
          ),
        ),
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
