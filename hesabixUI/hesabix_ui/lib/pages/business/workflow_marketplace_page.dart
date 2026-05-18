import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth_store.dart';
import '../../core/business_named_route_locations.dart';
import '../../core/business_nav.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../l10n/app_localizations.dart';
import '../../services/workflow_marketplace_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_helper.dart';

/// مخزن ورک‌فلو: مرور، نصب و مدیریت انتشار
class WorkflowMarketplacePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const WorkflowMarketplacePage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<WorkflowMarketplacePage> createState() => _WorkflowMarketplacePageState();
}

class _WorkflowMarketplacePageState extends State<WorkflowMarketplacePage> with SingleTickerProviderStateMixin {
  final WorkflowMarketplaceService _service = WorkflowMarketplaceService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  late TabController _tabController;

  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _load();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  bool get _isBrowseTab => _tabController.index == 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _busy = true;
    });
    try {
      final Map<String, dynamic> raw;
      if (!_isBrowseTab) {
        raw = await _service.listMyPackages(
          businessId: widget.businessId,
          skip: 0,
          take: 100,
        );
      } else {
        raw = await _service.listPackages(
          skip: 0,
          take: 100,
          search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
          tag: _tagController.text.trim().isEmpty ? null : _tagController.text.trim(),
        );
      }
      final list = (raw['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      if (!mounted) return;
      setState(() {
        _items = list;
      });
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            '${AppLocalizations.of(context).workflowMarketplaceError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _openDetail(Map<String, dynamic> summary) async {
    final t = AppLocalizations.of(context);
    final rawId = summary['id'];
    if (rawId == null) return;
    final packageId = rawId is int ? rawId : int.tryParse(rawId.toString());
    if (packageId == null) return;

    final isMy = !_isBrowseTab;
    setState(() => _busy = true);
    try {
      final detail = isMy
          ? await _service.getMyPackage(businessId: widget.businessId, packageId: packageId)
          : await _service.getPackage(packageId);
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) {
          final canInstall = widget.authStore.hasBusinessPermission('workflows', 'add') ||
              widget.authStore.hasBusinessPermission('workflows', 'edit');
          final nameCtrl = TextEditingController();
          final statusStr = (detail['status'] ?? 'published').toString().toLowerCase();
          final isPublished = statusStr == 'published';
          final isHidden = statusStr == 'hidden';
          final canEditPublish = widget.authStore.hasBusinessPermission('workflows', 'edit');

          final mq = MediaQuery.of(ctx);
          final maxH = mq.size.height * 0.92;

          return AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail['title']?.toString() ?? '',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          if (detail['short_description'] != null &&
                              detail['short_description'].toString().trim().isNotEmpty)
                            Text(detail['short_description'].toString()),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Chip(
                                label: Text('${t.workflowMarketplaceVersion}: ${detail['version_label'] ?? '-'}'),
                                visualDensity: VisualDensity.compact,
                              ),
                              Chip(
                                label: Text('${t.workflowMarketplaceInstallCount}: ${detail['install_count'] ?? 0}'),
                                visualDensity: VisualDensity.compact,
                              ),
                              if (isMy && isPublished)
                                Chip(
                                  avatar: Icon(Icons.public, size: 16, color: Theme.of(context).colorScheme.primary),
                                  label: Text(t.workflowMarketplaceStatusLive),
                                  visualDensity: VisualDensity.compact,
                                ),
                              if (isMy && isHidden)
                                Chip(
                                  avatar: Icon(Icons.visibility_off_outlined, size: 16),
                                  label: Text(t.workflowMarketplaceStatusPrivate),
                                  visualDensity: VisualDensity.compact,
                                ),
                              if (isMy && detail['publisher_display_name'] != null)
                                Chip(
                                  label: Text(
                                    '${t.workflowMarketplacePublisher}: ${detail['publisher_display_name']}',
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(t.workflowMarketplaceLongDescriptionLabel, style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Text(
                            (detail['long_description'] ?? detail['short_description'] ?? '-').toString(),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (detail['changelog'] != null && detail['changelog'].toString().trim().isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(t.workflowMarketplaceChangelog, style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Text(detail['changelog'].toString()),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 2,
                    shadowColor: Colors.black26,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isBrowseTab && canInstall) ...[
                            TextField(
                              controller: nameCtrl,
                              decoration: InputDecoration(
                                labelText: t.workflowMarketplaceNameAfterInstall,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: () async {
                                Navigator.of(ctx).pop();
                                await _installPackage(
                                  packageId: packageId,
                                  name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                                );
                              },
                              icon: const Icon(Icons.download_done_outlined),
                              label: Text(t.workflowMarketplaceInstall),
                            ),
                          ],
                          if (isMy && canEditPublish) ...[
                            if (isPublished) ...[
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dCtx) {
                                      return AlertDialog(
                                        title: Text(t.workflowMarketplaceUnpublishConfirmTitle),
                                        content: Text(t.workflowMarketplaceUnpublishConfirmBody),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(t.cancel)),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(dCtx, true),
                                            child: Text(t.workflowMarketplaceUnpublish),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                  if (ok != true || !ctx.mounted) return;
                                  Navigator.of(ctx).pop();
                                  await _unpublishPackage(packageId);
                                },
                                icon: const Icon(Icons.public_off_outlined),
                                label: Text(t.workflowMarketplaceUnpublish),
                              ),
                            ],
                            if (isHidden) ...[
                              FilledButton.icon(
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  await _republishPackage(packageId);
                                },
                                icon: const Icon(Icons.publish_outlined),
                                label: Text(t.workflowMarketplaceRepublish),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.workflowMarketplaceError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unpublishPackage(int packageId) async {
    final t = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await _service.unpublish(businessId: widget.businessId, packageId: packageId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.workflowMarketplaceRemovedFromRepo);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.workflowMarketplaceError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _republishPackage(int packageId) async {
    final t = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await _service.republish(businessId: widget.businessId, packageId: packageId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.workflowMarketplaceRepublishedToast);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.workflowMarketplaceError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installPackage({required int packageId, String? name}) async {
    final t = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final data = await _service.install(
        businessId: widget.businessId,
        packageId: packageId,
        name: name,
      );
      final wf = data['workflow'];
      if (wf is! Map) {
        throw StateError('invalid response');
      }
      final wfMap = Map<String, dynamic>.from(wf);
      if (!mounted) return;
      SnackBarHelper.show(context, message: t.workflowMarketplaceInstalled);
      final wfId = wfMap['id'];
      if (wfId is int) {
        BusinessNamedRoutes.goNamed(
          context,
          businessId: widget.businessId,
          routeName: 'business_edit_workflow',
          pathParameters: {
            'business_id': widget.businessId.toString(),
            'workflow_id': wfId.toString(),
          },
          extra: wfMap,
        );
      } else {
        context.go(context.businessPanelUrl(widget.businessId, 'workflows'));
      }
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.workflowMarketplaceError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.workflowMarketplaceTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t.workflowMarketplaceBrowseTab),
            Tab(text: t.workflowMarketplaceMyPublished),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t.workflowRefresh,
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                    SliverToBoxAdapter(child: _MarketplaceHero(theme: theme, t: t)),
                    if (_isBrowseTab) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                                  labelText: t.workflowMarketplaceSearchHint,
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: _busy ? null : _load,
                                  ),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onSubmitted: (_) => _load(),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _tagController,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                                  labelText: t.workflowMarketplaceTagFilterHint,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onSubmitted: (_) => _load(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_loading)
                      const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                    else if (_items.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 56, color: cs.outline),
                                const SizedBox(height: 16),
                                Text(
                                  _isBrowseTab ? t.workflowMarketplaceEmpty : t.workflowMarketplaceMyEmpty,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.crossAxisExtent;
                            final crossAxisCount = w >= ResponsiveHelper.shellNavigationRailExtendedMinWidth
                                ? 3
                                : w >= 720
                                    ? 2
                                    : 1;
                            if (crossAxisCount == 1) {
                              return SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (c, i) => Padding(
                                    padding: EdgeInsets.only(bottom: i < _items.length - 1 ? 12 : 0),
                                    child: _WorkflowMarketCard(
                                      item: _items[i],
                                      calendarController: widget.calendarController,
                                      onOpen: () => _openDetail(_items[i]),
                                      showPrivateBadge: !_isBrowseTab,
                                    ),
                                  ),
                                  childCount: _items.length,
                                ),
                              );
                            }
                            // ردیف‌به‌ردیف به‌جای Grid با aspect ثابت تا کارت‌ها فقط به اندازهٔ محتوا بلند شوند
                            const double rowGap = 14;
                            final cellW = (w - rowGap * (crossAxisCount - 1)) / crossAxisCount;
                            final rowCount = (_items.length + crossAxisCount - 1) ~/ crossAxisCount;
                            return SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (c, row) {
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: row < rowCount - 1 ? rowGap : 0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        for (int col = 0; col < crossAxisCount; col++) ...[
                                          if (col > 0) const SizedBox(width: rowGap),
                                          SizedBox(
                                            width: cellW,
                                            child: row * crossAxisCount + col >= _items.length
                                                ? const SizedBox.shrink()
                                                : _WorkflowMarketCard(
                                                    item: _items[row * crossAxisCount + col],
                                                    calendarController: widget.calendarController,
                                                    onOpen: () => _openDetail(_items[row * crossAxisCount + col]),
                                                    showPrivateBadge: !_isBrowseTab,
                                                  ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                                childCount: rowCount,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                  ),
              ),
            ],
          ),
          if (_busy && !_loading)
            const Positioned.fill(
              child: IgnorePointer(
                child: ModalBarrier(dismissible: false, color: Color(0x22000000)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MarketplaceHero extends StatelessWidget {
  const _MarketplaceHero({required this.theme, required this.t});

  final ThemeData theme;
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primaryContainer.withValues(alpha: 0.95),
              cs.tertiaryContainer.withValues(alpha: 0.7),
              cs.secondaryContainer.withValues(alpha: 0.45),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.hub_outlined, size: 36, color: cs.primary),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.workflowMarketplaceTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.workflowMarketplaceSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.9),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowMarketCard extends StatelessWidget {
  const _WorkflowMarketCard({
    required this.item,
    required this.calendarController,
    required this.onOpen,
    required this.showPrivateBadge,
  });

  final Map<String, dynamic> item;
  final CalendarController calendarController;
  final VoidCallback onOpen;
  final bool showPrivateBadge;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final pub = item['published_at']?.toString();
    final parsed = pub == null ? null : DateTime.tryParse(pub)?.toLocal();
    final dateStr = parsed == null
        ? '-'
        : HesabixDateUtils.formatDateTime(parsed, calendarController.isJalali);
    final tags = (item['tags'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final statusStr = (item['status'] ?? 'published').toString().toLowerCase();
    final isHidden = statusStr == 'hidden';

    return Material(
      color: cs.surfaceContainerLow,
      elevation: 0,
      surfaceTintColor: cs.surfaceTint.withValues(alpha: 0.08),
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: cs.primaryContainer.withValues(alpha: 0.85),
                    child: Icon(Icons.account_tree_outlined, color: cs.onPrimaryContainer, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item['title']?.toString() ?? '',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (showPrivateBadge && isHidden) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.errorContainer.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                t.workflowMarketplaceStatusPrivate,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left, color: cs.outline, size: 22),
                ],
              ),
              if (item['short_description'] != null &&
                  item['short_description'].toString().trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  item['short_description'].toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _SmallMetaChip(icon: Icons.tag, label: '${t.workflowMarketplaceVersion}: ${item['version_label'] ?? '-'}'),
                  _SmallMetaChip(
                    icon: Icons.downloading_outlined,
                    label: '${t.workflowMarketplaceInstallCount}: ${item['install_count'] ?? 0}',
                  ),
                  _SmallMetaChip(icon: Icons.schedule, label: dateStr),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '${t.workflowMarketplacePublisher}: ${item['publisher_display_name'] ?? '-'}',
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: tags
                      .take(6)
                      .map(
                        (x) => Chip(
                          label: Text(x, style: theme.textTheme.labelSmall),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                        ),
                      )
                      .toList(),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  '${t.workflowMarketplacePublisher}: ${item['publisher_display_name'] ?? '-'}',
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallMetaChip extends StatelessWidget {
  const _SmallMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
