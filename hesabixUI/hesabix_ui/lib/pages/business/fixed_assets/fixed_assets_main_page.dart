import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../services/fixed_assets_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import 'fixed_assets_dialogs.dart';
import 'fixed_assets_ui.dart';

class FixedAssetsMainPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const FixedAssetsMainPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<FixedAssetsMainPage> createState() => _FixedAssetsMainPageState();
}

class _FixedAssetsMainPageState extends State<FixedAssetsMainPage> with SingleTickerProviderStateMixin {
  final FixedAssetsService _svc = FixedAssetsService();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  late TabController _tabController;

  bool _loading = true;
  Map<String, dynamic> _dashboard = const {};
  List<Map<String, dynamic>> _assets = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _runs = [];
  String? _statusFilter;
  int? _classFilter;

  bool get _canManage =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('fixed_assets', 'manage');

  bool get _canOperate =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('fixed_assets', 'operate');

  bool get _canPost =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('fixed_assets', 'post');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.getDashboard(businessId: widget.businessId),
        _svc.listAssets(
          businessId: widget.businessId,
          status: _statusFilter,
          classId: _classFilter,
          search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        ),
        _svc.listClasses(businessId: widget.businessId),
        _svc.listRuns(businessId: widget.businessId),
        _svc.listLocations(businessId: widget.businessId),
      ]);
      if (!mounted) return;
      final assetsData = Map<String, dynamic>.from(results[1] as Map);
      final runsData = Map<String, dynamic>.from(results[3] as Map);
      setState(() {
        _dashboard = Map<String, dynamic>.from(results[0] as Map);
        _assets = (assetsData['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _classes = List<Map<String, dynamic>>.from(results[2] as List);
        _runs = (runsData['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _locations = List<Map<String, dynamic>>.from(results[4] as List);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _runAction(Future<void> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: success);
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _createAsset() async {
    final t = AppLocalizations.of(context);
    if (_classes.isEmpty) {
      SnackBarHelper.show(context, message: t.fixedAssetsNoClasses);
      return;
    }
    final payload = await FixedAssetsCreateAssetDialog.show(
      context,
      businessId: widget.businessId,
      calendarController: widget.calendarController,
      classes: _classes,
      locations: _locations,
    );
    if (payload == null) return;
    await _runAction(
      () => _svc.createAsset(businessId: widget.businessId, payload: payload),
      t.fixedAssetsSaved,
    );
  }

  Future<void> _capitalize(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    final payload = await FixedAssetsCapitalizeDialog.show(context, businessId: widget.businessId);
    if (payload == null) return;
    await _runAction(
      () => _svc.capitalizeAsset(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: payload,
      ),
      t.fixedAssetsCapitalized,
    );
  }

  Future<void> _createRun() async {
    final t = AppLocalizations.of(context);
    final payload = await FixedAssetsDepreciationRunDialog.show(context);
    if (payload == null) return;
    await _runAction(
      () => _svc.createRun(businessId: widget.businessId, payload: payload),
      t.fixedAssetsRunCreated,
    );
  }

  Future<void> _postRun(Map<String, dynamic> run) async {
    final t = AppLocalizations.of(context);
    await _runAction(
      () => _svc.postRun(businessId: widget.businessId, runId: int.parse('${run['id']}')),
      t.fixedAssetsRunPosted,
    );
  }

  Future<void> _disposeAsset(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    final payload = await FixedAssetsDisposeDialog.show(
      context,
      businessId: widget.businessId,
      calendarController: widget.calendarController,
    );
    if (payload == null) return;
    await _runAction(
      () => _svc.disposeAsset(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: payload,
      ),
      t.fixedAssetsDisposed,
    );
  }

  Future<void> _subsequent(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    final payload = await FixedAssetsSubsequentDialog.show(
      context,
      businessId: widget.businessId,
      calendarController: widget.calendarController,
    );
    if (payload == null) return;
    await _runAction(
      () => _svc.postSubsequentExpenditure(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: payload,
      ),
      t.fixedAssetsExpenditurePosted,
    );
  }

  Future<void> _estimateChange(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    final payload = await FixedAssetsEstimateDialog.show(
      context,
      calendarController: widget.calendarController,
      asset: asset,
    );
    if (payload == null) return;
    await _runAction(
      () => _svc.changeEstimate(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: payload,
      ),
      t.fixedAssetsEstimateSaved,
    );
  }

  Future<void> _markIdle(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    final payload = await FixedAssetsIdleDialog.show(
      context,
      calendarController: widget.calendarController,
    );
    if (payload == null) return;
    await _runAction(
      () => _svc.setAssetIdle(
        businessId: widget.businessId,
        assetId: int.parse('${asset['id']}'),
        payload: payload,
      ),
      t.fixedAssetsIdleSaved,
    );
  }

  Future<void> _resume(Map<String, dynamic> asset) async {
    final t = AppLocalizations.of(context);
    await _runAction(
      () => _svc.resumeAsset(businessId: widget.businessId, assetId: int.parse('${asset['id']}')),
      t.fixedAssetsResumed,
    );
  }

  void _openInvoice(Map<String, dynamic> asset) {
    final invoiceId = asset['invoice_id'];
    if (invoiceId == null) return;
    context.go(context.businessPanelUrl(widget.businessId, 'invoice/$invoiceId/edit'));
  }

  Widget _assetTrailing(AppLocalizations t, Map<String, dynamic> asset) {
    final status = '${asset['status']}';
    if (status == 'draft' && _canPost) {
      return FilledButton.tonal(
        onPressed: () => _capitalize(asset),
        child: Text(t.fixedAssetsCapitalize),
      );
    }
    final live = status == 'capitalized' || status == 'idle';
    final menu = <PopupMenuEntry<String>>[
      if (asset['invoice_id'] != null) PopupMenuItem(value: 'invoice', child: Text(t.fixedAssetsViewInvoice)),
      if (live && _canPost) PopupMenuItem(value: 'dispose', child: Text(t.fixedAssetsDispose)),
      if (live && _canPost) PopupMenuItem(value: 'subsequent', child: Text(t.fixedAssetsSubsequent)),
      if (live && _canManage) PopupMenuItem(value: 'estimate', child: Text(t.fixedAssetsEstimateChange)),
      if (live && _canOperate && status != 'idle') PopupMenuItem(value: 'idle', child: Text(t.fixedAssetsMarkIdle)),
      if (live && _canOperate && status == 'idle') PopupMenuItem(value: 'resume', child: Text(t.fixedAssetsResume)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          FixedAssetsUi.money(asset['net_book_value']),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (menu.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: t.fixedAssetsQuickActions,
            onSelected: (v) {
              if (v == 'invoice') _openInvoice(asset);
              if (v == 'dispose') _disposeAsset(asset);
              if (v == 'subsequent') _subsequent(asset);
              if (v == 'estimate') _estimateChange(asset);
              if (v == 'idle') _markIdle(asset);
              if (v == 'resume') _resume(asset);
            },
            itemBuilder: (ctx) => menu,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.fixedAssetsMenu),
        actions: [
          IconButton(
            tooltip: t.fixedAssetsReportSection,
            icon: const Icon(Icons.summarize_outlined),
            onPressed: () => context.go(
              context.businessPanelUrl(
                widget.businessId,
                'reports/fixed-assets?kind=register',
              ),
            ),
          ),
          if (_canManage)
            IconButton(
              tooltip: t.fixedAssetsSettingsTab,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go(
                context.businessPanelUrl(widget.businessId, 'settings/fixed-assets'),
              ),
            ),
          IconButton(tooltip: t.refresh, icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: t.fixedAssetsAssetsTab),
            Tab(text: t.fixedAssetsDepreciationTab),
            Tab(text: t.fixedAssetsClassesTab),
          ],
        ),
      ),
      floatingActionButton: _canOperate && _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _createAsset,
              icon: const Icon(Icons.add),
              label: Text(t.fixedAssetsNewAsset),
            )
          : _canOperate && _tabController.index == 1
              ? FloatingActionButton.extended(
                  onPressed: _createRun,
                  icon: const Icon(Icons.calculate_outlined),
                  label: Text(t.fixedAssetsNewDepreciationRun),
                )
              : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _assetsTab(t),
                _runsTab(t),
                _classesTab(t),
              ],
            ),
    );
  }

  Widget _assetsTab(AppLocalizations t) {
    final counts = Map<String, dynamic>.from(_dashboard['counts'] as Map? ?? const {});
    final cs = Theme.of(context).colorScheme;
    final positive = SemanticColorResolver.positive(context);
    return ListView(
      padding: FixedAssetsUi.pagePadding,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final cards = [
              FixedAssetsUi.statCard(
                context: context,
                label: t.fixedAssetsCost,
                value: FixedAssetsUi.money(_dashboard['cost_total']),
                icon: Icons.payments_outlined,
                color: cs.primary,
              ),
              FixedAssetsUi.statCard(
                context: context,
                label: t.fixedAssetsNetBookValue,
                value: FixedAssetsUi.money(_dashboard['net_book_value']),
                icon: Icons.account_balance_outlined,
                color: positive,
              ),
              FixedAssetsUi.statCard(
                context: context,
                label: t.fixedAssetsStatusCapitalized,
                value: '${counts['capitalized'] ?? 0}',
                icon: Icons.check_circle_outline,
                color: positive,
              ),
              FixedAssetsUi.statCard(
                context: context,
                label: t.fixedAssetsStatusIdle,
                value: '${counts['idle'] ?? 0}',
                icon: Icons.pause_circle_outline,
                color: cs.tertiary,
              ),
            ];
            if (wide) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final c in cards) SizedBox(width: (constraints.maxWidth - 12) / 2, child: c),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchCtrl,
          textInputAction: TextInputAction.search,
          decoration: FixedAssetsUi.fieldDecoration(
            context,
            t.fixedAssetsSearchHint,
            prefixIcon: Icons.search,
          ),
          onSubmitted: (_) {
            _searchDebounce?.cancel();
            _loadAll();
          },
          onChanged: (_) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 350), _loadAll);
          },
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _statusChip(null, t.fixedAssetsStatusAll),
              const SizedBox(width: 8),
              _statusChip('draft', t.fixedAssetsStatusDraft),
              const SizedBox(width: 8),
              _statusChip('capitalized', t.fixedAssetsStatusCapitalized),
              const SizedBox(width: 8),
              _statusChip('idle', t.fixedAssetsStatusIdle),
              const SizedBox(width: 8),
              _statusChip('disposed', t.fixedAssetsStatusDisposed),
            ],
          ),
        ),
        if (_classes.length > 1) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            value: _classFilter,
            decoration: FixedAssetsUi.fieldDecoration(context, t.fixedAssetsClass, prefixIcon: Icons.category_outlined),
            items: [
              DropdownMenuItem<int?>(value: null, child: Text(t.fixedAssetsStatusAll)),
              for (final c in _classes)
                DropdownMenuItem<int?>(value: int.parse('${c['id']}'), child: Text('${c['name']}')),
            ],
            onChanged: (v) {
              setState(() => _classFilter = v);
              _loadAll();
            },
          ),
        ],
        const SizedBox(height: 16),
        if (_assets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            child: Column(
              children: [
                Icon(Icons.inventory_2_outlined, size: 48, color: cs.outline),
                const SizedBox(height: 12),
                Text(t.fixedAssetsNoAssets, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  t.fixedAssetsEmptyHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        for (final a in _assets) ...[
          FixedAssetsUi.listTileCard(
            context: context,
            accentColor: FixedAssetsUi.statusColor(context, a['status']),
            leading: Icon(
              a['invoice_id'] != null ? Icons.receipt_long_outlined : Icons.precision_manufacturing_outlined,
              color: FixedAssetsUi.statusColor(context, a['status']),
            ),
            title: Text('${a['code']} — ${a['name']}'),
            subtitle: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FixedAssetsUi.statusChip(context, t, a['status']),
                Text('${a['class_name'] ?? ''}'),
                Text('${t.fixedAssetsCost} ${FixedAssetsUi.money(a['cost'])}'),
                if (a['invoice_id'] != null)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(t.fixedAssetsFromInvoice),
                    onPressed: () => _openInvoice(a),
                  ),
                if (a['status'] == 'idle') Text('tax ${a['tax_idle_factor']}'),
              ],
            ),
            trailing: _assetTrailing(t, a),
            onTap: a['invoice_id'] != null ? () => _openInvoice(a) : null,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _statusChip(String? status, String label) {
    final selected = _statusFilter == status;
    return FilterChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) {
        setState(() => _statusFilter = status);
        _loadAll();
      },
    );
  }

  Widget _runsTab(AppLocalizations t) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: FixedAssetsUi.pagePadding,
      children: [
        if (_canOperate)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: _createRun,
              icon: const Icon(Icons.calculate_outlined),
              label: Text(t.fixedAssetsNewDepreciationRun),
            ),
          ),
        const SizedBox(height: 16),
        if (_runs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text(t.fixedAssetsNoRuns)),
          ),
        for (final r in _runs) ...[
          FixedAssetsUi.listTileCard(
            context: context,
            accentColor: r['status'] == 'posted' ? SemanticColorResolver.positive(context) : cs.outline,
            leading: Icon(
              r['status'] == 'posted' ? Icons.check_circle_outline : Icons.hourglass_empty,
              color: r['status'] == 'posted' ? SemanticColorResolver.positive(context) : cs.outline,
            ),
            title: Text('${r['period_year']}/${r['period_month']}'),
            subtitle: Text(
              '${r['status'] == 'posted' ? t.fixedAssetsRunPostedStatus : t.fixedAssetsRunDraft}'
              ' · ${FixedAssetsUi.money(r['total_amount'])}',
            ),
            trailing: r['status'] == 'draft' && _canPost
                ? FilledButton.tonal(
                    onPressed: () => _postRun(r),
                    child: Text(t.fixedAssetsPostRun),
                  )
                : null,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _classesTab(AppLocalizations t) {
    return ListView(
      padding: FixedAssetsUi.pagePadding,
      children: [
        FixedAssetsUi.infoBanner(context, t.fixedAssetsLegalRulesHint),
        const SizedBox(height: 16),
        if (_canManage || widget.authStore.hasBusinessPermission('fixed_assets', 'view'))
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: () => context.go(
                context.businessPanelUrl(widget.businessId, 'settings/fixed-assets'),
              ),
              icon: const Icon(Icons.settings_outlined),
              label: Text(t.fixedAssetsOpenFullSettings),
            ),
          ),
        const SizedBox(height: 16),
        Text(t.fixedAssetsClassesHint, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        for (final c in _classes) ...[
          FixedAssetsUi.listTileCard(
            context: context,
            leading: Icon(
              c['depreciable'] == true ? Icons.category_outlined : Icons.landscape_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text('${c['name']} (${c['code']})'),
            subtitle: Text(
              '${c['cost_account_code'] ?? ''} / ${c['accum_dep_account_code'] ?? '-'} / ${c['dep_expense_account_code'] ?? '-'}',
            ),
            trailing: c['depreciable'] == true ? null : Text(t.fixedAssetsNotDepreciable),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
