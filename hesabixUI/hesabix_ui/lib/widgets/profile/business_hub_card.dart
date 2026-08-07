import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../models/business_dashboard_models.dart';
import '../../services/business_dashboard_service.dart';
import '../../utils/responsive_helper.dart';
import 'business_hub_actions.dart';
import 'business_hub_stats_cache.dart';
import 'business_hub_stats_preview.dart';
import 'businesses_hub_utils.dart';

typedef BusinessHubRefreshCallback = VoidCallback;

class BusinessHubCard extends StatefulWidget {
  final BusinessWithPermission business;
  final VoidCallback onEnter;
  final AuthStore authStore;
  final bool isPinned;
  final bool compact;
  final bool listLayout;
  /// حالت مینیمال: کمتر متادیتا، تمرکز روی ورود.
  final bool simplified;
  /// کارت برجسته‌تر وقتی فقط یک کسب‌وکار وجود دارد.
  final bool prominent;
  final ValueChanged<bool>? onPinChanged;
  final BusinessHubRefreshCallback? onRefresh;
  final BusinessDashboardService? dashboardService;
  final bool enableStatsPreview;

  const BusinessHubCard({
    super.key,
    required this.business,
    required this.onEnter,
    required this.authStore,
    this.isPinned = false,
    this.compact = false,
    this.listLayout = true,
    this.simplified = false,
    this.prominent = false,
    this.onPinChanged,
    this.onRefresh,
    this.dashboardService,
    this.enableStatsPreview = true,
  });

  @override
  State<BusinessHubCard> createState() => _BusinessHubCardState();
}

class _BusinessHubCardState extends State<BusinessHubCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _isRestoring = false;
  bool _statsLoading = false;
  BusinessStatistics? _stats;
  Timer? _hoverTimer;
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _statsPortal = OverlayPortalController();

  BusinessWithPermission get b => widget.business;
  bool get _blocked => businessBlocksAccess(b.isDeleted, b.isDeletionPending);
  bool get _canPreviewStats =>
      widget.enableStatsPreview && widget.dashboardService != null && !_blocked;

  @override
  void dispose() {
    _hoverTimer?.cancel();
    if (_statsPortal.isShowing) _statsPortal.hide();
    super.dispose();
  }

  void _onHoverEnter() {
    setState(() => _hovered = true);
    if (!_canPreviewStats || !ResponsiveHelper.isDesktop(context)) return;
    _hoverTimer?.cancel();
    _hoverTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || !_hovered) return;
      _loadStats();
      if (!_statsPortal.isShowing) _statsPortal.show();
    });
  }

  void _onHoverExit() {
    _hoverTimer?.cancel();
    if (_statsPortal.isShowing) _statsPortal.hide();
    setState(() {
      _hovered = false;
      // Keep cached stats in state for instant re-show; clear loading flag only.
      _statsLoading = false;
    });
  }

  Future<void> _loadStats() async {
    if (!_canPreviewStats || _statsLoading) return;
    if (_stats != null) return;
    setState(() => _statsLoading = true);
    final stats = await BusinessHubStatsCache.load(b.id, widget.dashboardService!);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _statsLoading = false;
    });
  }

  Future<void> _showStatsSheet() async {
    if (!_canPreviewStats || !mounted) return;
    await BusinessHubStatsSheet.show(
      context,
      businessName: b.name,
      businessId: b.id,
      service: widget.dashboardService!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final isDesktop = ResponsiveHelper.isDesktop(context);

    final elevation = _pressed ? 0.0 : (_hovered ? 5.0 : (widget.prominent ? 2.0 : 1.0));
    final borderColor = widget.isPinned
        ? cs.primary.withValues(alpha: _hovered ? 0.55 : 0.35)
        : cs.outlineVariant.withValues(alpha: _hovered ? 0.7 : 0.32);

    return OverlayPortal(
      controller: _statsPortal,
      overlayChildBuilder: (context) {
        return UnconstrainedBox(
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 8),
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: Transform.scale(scale: value, child: child),
                  );
                },
                child: BusinessHubStatsPreview(
                  stats: _stats,
                  loading: _statsLoading && _stats == null,
                  floating: true,
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _layerLink,
        child: MouseRegion(
          onEnter: (_) => _onHoverEnter(),
          onExit: (_) => _onHoverExit(),
          child: AnimatedScale(
            scale: _pressed ? 0.985 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.prominent ? 18 : 16),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withValues(alpha: 0.05 + (elevation * 0.018)),
                    blurRadius: 4 + elevation * 2.5,
                    offset: Offset(0, elevation * 0.7),
                  ),
                ],
              ),
              child: Material(
                color: cs.surfaceContainerLowest,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(widget.prominent ? 18 : 16),
                  side: BorderSide(color: borderColor, width: widget.isPinned ? 1.5 : 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Builder(
                  builder: (context) {
                    final ink = InkWell(
                      onTap: _blocked ? null : widget.onEnter,
                      onLongPress: ResponsiveHelper.isMobile(context) && _canPreviewStats
                          ? _showStatsSheet
                          : null,
                      onHighlightChanged: (v) => setState(() => _pressed = v),
                      child: Padding(
                        padding: EdgeInsets.all(
                          widget.listLayout
                              ? (widget.prominent ? 18 : 14)
                              : (widget.prominent ? 18 : 16),
                        ),
                        child: widget.listLayout
                            ? _buildListBody(context, t)
                            : _buildGridBody(context, t),
                      ),
                    );
                    if (!isDesktop || !_canPreviewStats) return ink;
                    return Tooltip(
                      message: t.businessesHubStatsHint,
                      waitDuration: const Duration(milliseconds: 900),
                      child: ink,
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListBody(BuildContext context, AppLocalizations t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildAvatar(context, size: widget.prominent ? 56 : 48),
        SizedBox(width: widget.prominent ? 16 : 14),
        Expanded(child: _buildMainInfo(context, t)),
        const SizedBox(width: 10),
        _buildTrailing(context, t),
      ],
    );
  }

  Widget _buildGridBody(BuildContext context, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildAvatar(context, size: 44),
            const Spacer(),
            _buildMenuButton(context, t),
          ],
        ),
        const SizedBox(height: 12),
        _buildNameRow(context, t),
        const SizedBox(height: 4),
        _buildMetaLine(context, t),
        if (!widget.simplified) ...[
          const SizedBox(height: 8),
          _buildChipsRow(context, t),
        ] else if (b.isDeletionPending || b.isMultiCurrency) ...[
          const SizedBox(height: 8),
          _buildChipsRow(context, t),
        ],
        const Spacer(),
        if (b.isDeletionPending && b.isOwner)
          _buildRestoreSection(context, t)
        else
          FilledButton.tonalIcon(
            onPressed: _blocked ? null : widget.onEnter,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: Text(t.businessesHubEnter),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context, {double size = 52}) {
    final cs = Theme.of(context).colorScheme;
    final bg = businessAvatarColor(b.name, cs);
    final initial = businessAvatarInitial(b.name);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bg, Color.lerp(bg, Colors.black, 0.12)!],
            ),
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: _hovered ? 0.45 : 0.3),
                blurRadius: _hovered ? 12 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (widget.isPinned)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
              ),
              child: Icon(
                Icons.push_pin_rounded,
                size: size * 0.22,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMainInfo(BuildContext context, AppLocalizations t) {
    final showDate = !widget.simplified &&
        !ResponsiveHelper.isMobile(context) &&
        b.createdAt.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildNameRow(context, t),
        const SizedBox(height: 4),
        _buildMetaLine(context, t),
        if (!widget.simplified || b.isDeletionPending || b.isMultiCurrency) ...[
          const SizedBox(height: 6),
          _buildChipsRow(context, t),
        ],
        if (showDate) ...[
          const SizedBox(height: 4),
          Text(
            '${t.businessesHubEstablished}: ${formatBusinessCreatedAt(b.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        if (b.isDeletionPending && b.isOwner) ...[
          const SizedBox(height: 10),
          _buildRestoreSection(context, t),
        ],
      ],
    );
  }

  Widget _buildNameRow(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            b.name,
            style: (widget.prominent ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)
                ?.copyWith(
              fontWeight: FontWeight.w700,
              decoration: b.isDeletionPending ? TextDecoration.lineThrough : null,
              color: b.isDeletionPending ? theme.colorScheme.onSurfaceVariant : null,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _buildRoleBadge(context, t),
      ],
    );
  }

  Widget _buildRoleBadge(BuildContext context, AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    final isOwner = b.isOwner;
    final color = isOwner ? cs.primary : cs.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isOwner ? t.owner : t.member,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildMetaLine(BuildContext context, AppLocalizations t) {
    return Text(
      '${translateBusinessType(b.businessType, t)} • ${translateBusinessField(b.businessField, t)}',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildChipsRow(BuildContext context, AppLocalizations t) {
    final chips = <Widget>[];
    if (b.isMultiCurrency) {
      chips.add(_statusChip(context, t.businessesHubMultiCurrency, Icons.currency_exchange_rounded, Colors.blue));
    }
    if (b.isDeletionPending) {
      chips.add(_statusChip(
        context,
        t.businessesHubDeletionPending,
        Icons.hourglass_top_rounded,
        Colors.orange,
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _statusChip(BuildContext context, String label, IconData icon, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade800),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailing(BuildContext context, AppLocalizations t) {
    // CTA همیشه ثابت و قابل کلیک — هاور فقط elevation/آمار شناور را تغییر می‌دهد.
    final showEnter = !_blocked && !(b.isDeletionPending && b.isOwner);
    final isMobile = ResponsiveHelper.isMobile(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEnter)
          AnimatedScale(
            scale: _hovered && ResponsiveHelper.isDesktop(context) ? 1.03 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: isMobile
                ? FilledButton.tonalIcon(
                    onPressed: widget.onEnter,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text(t.businessesHubEnter),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                : FilledButton.icon(
                    onPressed: widget.onEnter,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text(t.businessesHubEnter),
                    style: FilledButton.styleFrom(
                      minimumSize: Size(widget.prominent ? 108 : 0, widget.prominent ? 44 : 40),
                      padding: EdgeInsets.symmetric(horizontal: widget.prominent ? 18 : 14),
                    ),
                  ),
          )
        else if (isMobile)
          Icon(
            Icons.chevron_left_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        _buildMenuButton(context, t),
      ],
    );
  }

  Widget _buildMenuButton(BuildContext context, AppLocalizations t) {
    return PopupMenuButton<_HubMenuAction>(
      icon: Icon(Icons.more_vert_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
      tooltip: t.menu,
      onSelected: (action) => _handleMenuAction(context, t, action),
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<_HubMenuAction>>[];

        if (!_blocked) {
          items.add(PopupMenuItem(
            value: _HubMenuAction.enter,
            child: ListTile(
              leading: const Icon(Icons.login_rounded),
              title: Text(t.businessesHubEnter),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ));
        }

        if (_canPreviewStats) {
          items.add(PopupMenuItem(
            value: _HubMenuAction.stats,
            child: ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: Text(t.businessesHubStatsTitle),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ));
        }

        items.add(PopupMenuItem(
          value: _HubMenuAction.pin,
          child: ListTile(
            leading: Icon(widget.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(widget.isPinned ? t.businessesHubUnpin : t.businessesHubPin),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ));

        if (b.currencies.length > 1 && !_blocked) {
          items.add(const PopupMenuDivider());
          items.add(PopupMenuItem(
            enabled: false,
            child: Text(
              t.businessesHubDefaultCurrency,
              style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
          ));
          for (final c in b.currencies) {
            final selected = _resolveCurrencyCode() == c.code;
            items.add(PopupMenuItem(
              value: _HubMenuAction.currency,
              child: ListTile(
                leading: Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 20,
                  color: selected ? Theme.of(ctx).colorScheme.primary : null,
                ),
                title: Text('${c.title} (${c.code})'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _setCurrency(c.code, c.id);
                },
              ),
            ));
          }
        }

        if (b.isDeletionPending && b.isOwner) {
          items.add(const PopupMenuDivider());
          items.add(PopupMenuItem(
            value: _HubMenuAction.restore,
            child: ListTile(
              leading: const Icon(Icons.restore_rounded, color: Colors.green),
              title: Text(t.businessesHubRestore),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ));
        } else if (!b.isOwner) {
          items.add(const PopupMenuDivider());
          items.add(PopupMenuItem(
            value: _HubMenuAction.leave,
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

        return items;
      },
    );
  }

  String? _resolveCurrencyCode() {
    final codes = b.currencies.map((c) => c.code).toSet();
    final authCode = widget.authStore.selectedCurrencyCode;
    if (authCode != null && codes.contains(authCode)) return authCode;
    return b.defaultCurrency?.code ??
        (b.currencies.isNotEmpty ? b.currencies.first.code : null);
  }

  Future<void> _setCurrency(String code, int id) async {
    await widget.authStore.setSelectedCurrency(code: code, id: id);
    if (mounted) setState(() {});
  }

  Future<void> _handleMenuAction(BuildContext context, AppLocalizations t, _HubMenuAction action) async {
    switch (action) {
      case _HubMenuAction.enter:
        widget.onEnter();
      case _HubMenuAction.stats:
        await _showStatsSheet();
      case _HubMenuAction.pin:
        widget.onPinChanged?.call(!widget.isPinned);
      case _HubMenuAction.restore:
        await _handleRestore(context, t);
      case _HubMenuAction.leave:
        await _handleLeave(context, t);
      case _HubMenuAction.currency:
        break;
    }
  }

  Widget _buildRestoreSection(BuildContext context, AppLocalizations t) {
    final theme = Theme.of(context);
    String? remaining;
    if (b.autoDeleteAt != null) {
      try {
        final autoDeleteDate = DateTime.parse(b.autoDeleteAt!);
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (remaining != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time_rounded, size: 16, color: Colors.orange.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    remaining,
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        FilledButton.icon(
          onPressed: _isRestoring ? null : () => _handleRestore(context, t),
          icon: _isRestoring
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : const Icon(Icons.restore_rounded, size: 18),
          label: Text(_isRestoring ? t.businessesHubRestoring : t.businessesHubRestore),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 40),
          ),
        ),
      ],
    );
  }

  Future<void> _handleRestore(BuildContext context, AppLocalizations t) async {
    setState(() => _isRestoring = true);
    try {
      await BusinessHubActions.restore(
        context,
        business: b,
        onRefresh: widget.onRefresh,
      );
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _handleLeave(BuildContext context, AppLocalizations t) async {
    await BusinessHubActions.leave(
      context,
      business: b,
      authStore: widget.authStore,
      onRefresh: widget.onRefresh,
    );
  }
}

enum _HubMenuAction { enter, stats, pin, restore, leave, currency }
