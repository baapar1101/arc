import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../models/business_dashboard_models.dart';
import '../../utils/responsive_helper.dart';
import 'business_hub_actions.dart';
import 'businesses_hub_utils.dart';

/// آواتار ساده برای سوییچر فضای کاری.
class BusinessSwitcherAvatar extends StatelessWidget {
  final String name;
  final double size;

  const BusinessSwitcherAvatar({
    super.key,
    required this.name,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = businessAvatarColor(name, cs);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        businessAvatarInitial(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

String businessSwitcherMetaLine(BusinessWithPermission b, AppLocalizations t) {
  final role = b.isOwner ? t.owner : t.member;
  final type = translateBusinessType(b.businessType, t);
  final field = translateBusinessField(b.businessField, t);
  return '$role · $type · $field';
}

/// ردیف مینیمال لیست کسب‌وکارها — کل ردیف قابل کلیک است.
class BusinessSwitcherRow extends StatefulWidget {
  final BusinessWithPermission business;
  final AuthStore authStore;
  final VoidCallback? onEnter;
  final VoidCallback? onLongPress;
  final VoidCallback? onRefresh;
  final bool showDivider;
  final bool isActive;

  const BusinessSwitcherRow({
    super.key,
    required this.business,
    required this.authStore,
    this.onEnter,
    this.onLongPress,
    this.onRefresh,
    this.showDivider = true,
    this.isActive = false,
  });

  @override
  State<BusinessSwitcherRow> createState() => _BusinessSwitcherRowState();
}

class _BusinessSwitcherRowState extends State<BusinessSwitcherRow> {
  bool _hovered = false;
  bool _menuOpen = false;
  bool _restoring = false;

  BusinessWithPermission get b => widget.business;
  bool get _blocked => businessBlocksAccess(b.isDeleted, b.isDeletionPending);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = AppLocalizations.of(context);
    final highlight = _hovered || _menuOpen || widget.isActive;

    if (b.isDeletionPending && b.isOwner) {
      return _PendingDeletionRow(
        business: b,
        restoring: _restoring,
        showDivider: widget.showDivider,
        onRestore: _handleRestore,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        children: [
          Material(
            color: widget.isActive
                ? cs.primaryContainer.withValues(alpha: 0.35)
                : highlight
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.55)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _blocked ? null : widget.onEnter,
              onLongPress: _blocked ? null : widget.onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                child: Row(
                  children: [
                    BusinessSwitcherAvatar(name: b.name, size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  b.name,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    decoration:
                                        b.isDeletionPending ? TextDecoration.lineThrough : null,
                                    color: b.isDeletionPending ? cs.onSurfaceVariant : null,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.isActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: cs.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    t.businessesHubActiveBadge,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            businessSwitcherMetaLine(b, t),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    BusinessSwitcherMenu(
                      business: b,
                      authStore: widget.authStore,
                      visible: highlight,
                      alwaysVisibleOnTouch: true,
                      onRefresh: widget.onRefresh,
                      onOpenChanged: (open) => setState(() => _menuOpen = open),
                    ),
                    if (!_blocked)
                      Icon(
                        Icons.chevron_left_rounded,
                        color: cs.onSurfaceVariant.withValues(alpha: highlight ? 0.9 : 0.45),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.showDivider)
            Divider(
              height: 1,
              thickness: 1,
              indent: 68,
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
        ],
      ),
    );
  }

  Future<void> _handleRestore() async {
    setState(() => _restoring = true);
    try {
      await BusinessHubActions.restore(
        context,
        business: b,
        onRefresh: widget.onRefresh,
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }
}

class _PendingDeletionRow extends StatelessWidget {
  final BusinessWithPermission business;
  final bool restoring;
  final bool showDivider;
  final VoidCallback onRestore;

  const _PendingDeletionRow({
    required this.business,
    required this.restoring,
    required this.showDivider,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = AppLocalizations.of(context);

    String? remaining;
    if (business.autoDeleteAt != null) {
      try {
        final autoDeleteDate = DateTime.parse(business.autoDeleteAt!);
        final diff = autoDeleteDate.difference(DateTime.now());
        if (diff.inDays > 0) {
          remaining = t.businessesHubDaysRemaining(diff.inDays);
        } else if (diff.inHours > 0) {
          remaining = t.businessesHubHoursRemaining(diff.inHours);
        } else {
          remaining = t.businessesHubDeadlineExpired;
        }
      } catch (_) {}
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Opacity(
                opacity: 0.55,
                child: BusinessSwitcherAvatar(name: business.name, size: 44),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.lineThrough,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      remaining ?? t.businessesHubDeletionPending,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: restoring ? null : onRestore,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: restoring
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t.businessesHubRestore),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 68,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
      ],
    );
  }
}

/// منوی اقدامات ثانویه (تنظیمات / ارز / خروج / حذف).
class BusinessSwitcherMenu extends StatelessWidget {
  final BusinessWithPermission business;
  final AuthStore authStore;
  final bool visible;
  final bool alwaysVisibleOnTouch;
  final VoidCallback? onRefresh;
  final ValueChanged<bool>? onOpenChanged;

  const BusinessSwitcherMenu({
    super.key,
    required this.business,
    required this.authStore,
    this.visible = true,
    this.alwaysVisibleOnTouch = false,
    this.onRefresh,
    this.onOpenChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final blocked = businessBlocksAccess(business.isDeleted, business.isDeletionPending);
    final touch = ResponsiveHelper.isMobile(context);
    final show = visible || (alwaysVisibleOnTouch && touch);

    final hasSettings = !blocked;
    final hasCurrency = business.currencies.length > 1 && !blocked;
    final hasRestore = business.isDeletionPending && business.isOwner;
    final hasLeave = !business.isOwner && !business.isDeletionPending;
    final hasDelete = business.isOwner && !business.isDeletionPending && !business.isDeleted;
    final hasAny = hasSettings || hasCurrency || hasRestore || hasLeave || hasDelete;
    if (!hasAny) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: show ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: IgnorePointer(
        ignoring: !show,
        child: PopupMenuButton<_SwitcherMenuAction>(
          tooltip: t.menu,
          padding: EdgeInsets.zero,
          icon: Icon(Icons.more_horiz_rounded, color: cs.onSurfaceVariant, size: 22),
          onOpened: () => onOpenChanged?.call(true),
          onCanceled: () => onOpenChanged?.call(false),
          onSelected: (action) async {
            onOpenChanged?.call(false);
            switch (action) {
              case _SwitcherMenuAction.settings:
                await authStore.setCurrentBusiness(business);
                if (!context.mounted) return;
                context.go('/business/${business.id}/settings');
              case _SwitcherMenuAction.delete:
                await authStore.setCurrentBusiness(business);
                if (!context.mounted) return;
                context.go('/business/${business.id}/settings/delete');
              case _SwitcherMenuAction.leave:
                await BusinessHubActions.leave(
                  context,
                  business: business,
                  authStore: authStore,
                  onRefresh: onRefresh,
                );
              case _SwitcherMenuAction.restore:
                await BusinessHubActions.restore(
                  context,
                  business: business,
                  onRefresh: onRefresh,
                );
              case _SwitcherMenuAction.currency:
                break;
            }
          },
          itemBuilder: (ctx) {
            final items = <PopupMenuEntry<_SwitcherMenuAction>>[];

            if (hasSettings) {
              items.add(PopupMenuItem(
                value: _SwitcherMenuAction.settings,
                child: ListTile(
                  leading: const Icon(Icons.settings_outlined, size: 20),
                  title: Text(t.businessesHubOpenSettings),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ));
            }

            if (hasCurrency) {
              if (items.isNotEmpty) items.add(const PopupMenuDivider());
              items.add(PopupMenuItem(
                enabled: false,
                child: Text(
                  t.businessesHubDefaultCurrency,
                  style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ));
              for (final c in business.currencies) {
                final selected = _resolveCurrencyCode() == c.code;
                items.add(PopupMenuItem(
                  value: _SwitcherMenuAction.currency,
                  child: ListTile(
                    leading: Icon(
                      selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                      size: 20,
                      color: selected ? Theme.of(ctx).colorScheme.primary : null,
                    ),
                    title: Text('${c.title} (${c.code})'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await authStore.setSelectedCurrency(code: c.code, id: c.id);
                    },
                  ),
                ));
              }
            }

            if (hasRestore) {
              if (items.isNotEmpty) items.add(const PopupMenuDivider());
              items.add(PopupMenuItem(
                value: _SwitcherMenuAction.restore,
                child: ListTile(
                  leading: const Icon(Icons.restore_rounded, color: Colors.green),
                  title: Text(t.businessesHubRestore),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ));
            } else if (hasLeave) {
              if (items.isNotEmpty) items.add(const PopupMenuDivider());
              items.add(PopupMenuItem(
                value: _SwitcherMenuAction.leave,
                child: ListTile(
                  leading: Icon(Icons.exit_to_app_rounded, color: Theme.of(ctx).colorScheme.error),
                  title: Text(
                    t.businessesHubLeave,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ));
            }

            if (hasDelete) {
              if (items.isNotEmpty) items.add(const PopupMenuDivider());
              items.add(PopupMenuItem(
                value: _SwitcherMenuAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
                  title: Text(
                    t.deleteBusiness,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ));
            }

            return items;
          },
        ),
      ),
    );
  }

  String? _resolveCurrencyCode() {
    final codes = business.currencies.map((c) => c.code).toSet();
    final authCode = authStore.selectedCurrencyCode;
    if (authCode != null && codes.contains(authCode)) return authCode;
    return business.defaultCurrency?.code ??
        (business.currencies.isNotEmpty ? business.currencies.first.code : null);
  }
}

enum _SwitcherMenuAction { settings, delete, leave, restore, currency }

/// اسکلتون سبک برای سوییچر.
class BusinessSwitcherSkeleton extends StatelessWidget {
  final bool single;

  const BusinessSwitcherSkeleton({super.key, this.single = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (single) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            _Pulse(width: 72, height: 72, radius: 20, color: cs.surfaceContainerHighest),
            const SizedBox(height: 20),
            _Pulse(width: 180, height: 22, radius: 8, color: cs.surfaceContainerHighest),
            const SizedBox(height: 10),
            _Pulse(width: 140, height: 14, radius: 6, color: cs.surfaceContainerHighest),
            const SizedBox(height: 28),
            _Pulse(width: double.infinity, height: 48, radius: 12, color: cs.surfaceContainerHighest),
          ],
        ),
      );
    }

    return Column(
      children: List.generate(3, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              _Pulse(width: 44, height: 44, radius: 12, color: cs.surfaceContainerHighest),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Pulse(width: 160, height: 16, radius: 6, color: cs.surfaceContainerHighest),
                    const SizedBox(height: 8),
                    _Pulse(width: 120, height: 12, radius: 5, color: cs.surfaceContainerHighest),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _Pulse extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  final Color color;

  const _Pulse({
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
  });

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: 0.4 + _controller.value * 0.35,
        child: child,
      ),
      child: Container(
        width: widget.width == double.infinity ? double.infinity : widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
