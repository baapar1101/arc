import 'package:flutter/material.dart';
import 'package:hesabix_ui/widgets/support/user_support_types.dart';

/// Material 3 pill-style tab selector for user support inbox views.
class UserSupportTabBar extends StatelessWidget {
  final UserSupportTab activeTab;
  final ValueChanged<UserSupportTab> onChanged;

  const UserSupportTabBar({
    super.key,
    required this.activeTab,
    required this.onChanged,
  });

  static const _tabs = <(UserSupportTab, String, IconData)>[
    (UserSupportTab.all, 'همه', Icons.inbox_rounded),
    (UserSupportTab.open, 'باز', Icons.lock_open_rounded),
    (UserSupportTab.unread, 'جدید', Icons.mark_email_unread_rounded),
    (UserSupportTab.waiting, 'منتظر پاسخ', Icons.schedule_rounded),
    (UserSupportTab.resolved, 'بسته‌شده', Icons.check_circle_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (tab, label, icon) in _tabs) ...[
              _PillTab(
                label: label,
                icon: icon,
                selected: activeTab == tab,
                onTap: () => onChanged(tab),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PillTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PillTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Material(
        color: selected ? scheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        elevation: selected ? 1 : 0,
        shadowColor: scheme.shadow.withValues(alpha: 0.12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
