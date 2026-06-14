import 'package:flutter/material.dart';

import 'ai_chat_design.dart';

/// نوار ابزار ثانویهٔ دستیار — دسترسی سریع به قابلیت‌های کلیدی.
class AIChatToolbar extends StatelessWidget {
  final bool isHomeMode;
  final bool hasSession;
  final bool hasBusiness;
  final bool focusMode;
  final bool showFocusToggle;
  final VoidCallback? onSearch;
  final VoidCallback? onMemory;
  final VoidCallback? onExport;
  final VoidCallback? onConnectors;
  final VoidCallback? onKnowledge;
  final VoidCallback? onSkills;
  final VoidCallback? onVoiceSettings;
  final VoidCallback? onToggleFocus;

  const AIChatToolbar({
    super.key,
    required this.isHomeMode,
    required this.hasSession,
    required this.hasBusiness,
    this.focusMode = false,
    this.showFocusToggle = false,
    this.onSearch,
    this.onMemory,
    this.onExport,
    this.onConnectors,
    this.onKnowledge,
    this.onSkills,
    this.onVoiceSettings,
    this.onToggleFocus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = <_ToolbarItem>[];

    if (!isHomeMode && hasSession && onSearch != null) {
      items.add(_ToolbarItem(
        icon: Icons.search_rounded,
        label: 'جستجو',
        onTap: onSearch!,
      ));
    }
    if (!isHomeMode && hasSession && onMemory != null) {
      items.add(_ToolbarItem(
        icon: Icons.psychology_outlined,
        label: 'حافظه',
        onTap: onMemory!,
      ));
    }
    if (hasBusiness && onSkills != null) {
      items.add(_ToolbarItem(
        icon: Icons.extension_outlined,
        label: 'مهارت‌ها',
        onTap: onSkills!,
      ));
    }
    if (hasBusiness && onConnectors != null) {
      items.add(_ToolbarItem(
        icon: Icons.link_rounded,
        label: 'کانکتورها',
        onTap: onConnectors!,
      ));
    }
    if (hasBusiness && onKnowledge != null) {
      items.add(_ToolbarItem(
        icon: Icons.menu_book_outlined,
        label: 'دانشنامه',
        onTap: onKnowledge!,
      ));
    }
    if (!isHomeMode && hasSession && onExport != null) {
      items.add(_ToolbarItem(
        icon: Icons.ios_share_outlined,
        label: 'خروجی',
        onTap: onExport!,
      ));
    }
    if (onVoiceSettings != null) {
      items.add(_ToolbarItem(
        icon: Icons.tune_rounded,
        label: 'صدا',
        onTap: onVoiceSettings!,
      ));
    }
    if (showFocusToggle && onToggleFocus != null) {
      items.add(_ToolbarItem(
        icon: focusMode ? Icons.view_sidebar_rounded : Icons.crop_landscape_rounded,
        label: focusMode ? 'نمای کامل' : 'تمرکز',
        onTap: onToggleFocus!,
        selected: focusMode,
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Material(
      color: scheme.surface.withValues(alpha: 0.72),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(
          children: [
            for (final item in items) ...[
              _ToolbarChip(item: item, theme: theme, scheme: scheme),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolbarItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _ToolbarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
}

class _ToolbarChip extends StatelessWidget {
  final _ToolbarItem item;
  final ThemeData theme;
  final ColorScheme scheme;

  const _ToolbarChip({
    required this.item,
    required this.theme,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final selected = item.selected;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.55)
          : scheme.surfaceContainerHigh.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(AIChatDesign.chipRadius),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(AIChatDesign.chipRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 16,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
