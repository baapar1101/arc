import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

/// Hero header for the user support tickets page.
class UserSupportPageHeader extends StatelessWidget {
  final AppLocalizations t;
  final int openCount;
  final int totalCount;
  final VoidCallback? onCreateTicket;
  final bool showCreateButton;

  const UserSupportPageHeader({
    super.key,
    required this.t,
    this.openCount = 0,
    this.totalCount = 0,
    this.onCreateTicket,
    this.showCreateButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final onHeader = isDark ? scheme.onSurface : Colors.white;
    final subtitleOnHeader =
        isDark ? scheme.onSurfaceVariant : Colors.white.withValues(alpha: 0.9);
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.supportTickets,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: onHeader,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'مدیریت، پیگیری و ارتباط با تیم پشتیبانی',
          style: theme.textTheme.bodyMedium?.copyWith(color: subtitleOnHeader),
        ),
        if (totalCount > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StatChip(
                label: '$totalCount تیکت',
                icon: Icons.inbox_outlined,
                foreground: onHeader,
                background: isDark
                    ? scheme.onSurface.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.18),
              ),
              if (openCount > 0)
                _StatChip(
                  label: '$openCount باز',
                  icon: Icons.pending_actions_outlined,
                  foreground: onHeader,
                  background: isDark
                      ? scheme.error.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.22),
                ),
            ],
          ),
        ],
      ],
    );

    final createButton = showCreateButton && onCreateTicket != null
        ? FilledButton.tonal(
            onPressed: onCreateTicket,
            style: FilledButton.styleFrom(
              backgroundColor: isDark
                  ? scheme.primaryContainer
                  : Colors.white.withValues(alpha: 0.95),
              foregroundColor: isDark ? scheme.onPrimaryContainer : scheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, size: 20),
                const SizedBox(width: 6),
                Text(t.newTicket),
              ],
            ),
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerHighest : null,
        gradient: isDark
            ? null
            : LinearGradient(
                colors: [scheme.primary, scheme.primary.withValues(alpha: 0.82)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? scheme.shadow.withValues(alpha: 0.1)
                : scheme.primary.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? scheme.onSurface.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.support_agent_rounded, color: onHeader, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: content),
                  ],
                ),
                if (createButton != null) ...[
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: createButton),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? scheme.onSurface.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.support_agent_rounded, color: onHeader, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(child: content),
                if (createButton != null) ...[
                  const SizedBox(width: 12),
                  createButton,
                ],
              ],
            ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  const _StatChip({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
