import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/woocommerce_integration_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/data_table/data_table_config.dart';
import '../../../widgets/data_table/data_table_widget.dart';
import 'woocommerce_l10n_format.dart';

String _prettyJson(Object? value) {
  try {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(value);
  } catch (_) {
    return '$value';
  }
}

TextStyle _monoStyle(BuildContext context) {
  return TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: 1.35,
    color: Theme.of(context).colorScheme.onSurface,
  );
}

/// پنل تنظیمات و عملیات ArcWOC (قبلاً در تب «کنترل» مرکز ووکامرس).
class WooArcwocPluginSettingsPanel extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const WooArcwocPluginSettingsPanel({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<WooArcwocPluginSettingsPanel> createState() =>
      _WooArcwocPluginSettingsPanelState();
}

class _WooArcwocPluginSettingsPanelState
    extends State<WooArcwocPluginSettingsPanel> {
  final WoocommerceIntegrationService _svc = WoocommerceIntegrationService();
  final _bulkIdsCtl = TextEditingController();

  bool _loading = false;
  Map<String, dynamic> _syncStats = const {};
  Map<String, dynamic> _settingsSummary = const {};
  Map<String, dynamic> _connection = const {};
  Map<String, dynamic> _pluginInfo = const {};
  Map<String, dynamic> _queueSnapshot = const {};
  bool _showRawSettingsJson = false;

  List<Map<String, dynamic>> _logRows = const [];
  int _logTotal = 0;
  int _logPage = 1;
  int _logPerPage = 15;
  int _logEpoch = 0;

  bool _canWooCommerceManage() {
    if (widget.authStore.currentBusiness?.isOwner == true) return true;
    return widget.authStore.hasBusinessPermission('woocommerce', 'manage');
  }

  bool _canWooCommerceView() {
    if (widget.authStore.currentBusiness?.isOwner == true) return true;
    return widget.authStore.hasBusinessPermission('woocommerce', 'view');
  }

  @override
  void initState() {
    super.initState();
    if (_canWooCommerceView()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadAll());
    }
  }

  @override
  void dispose() {
    _bulkIdsCtl.dispose();
    super.dispose();
  }

  Future<void> _loadAll({bool logsOnly = false}) async {
    if (!_canWooCommerceView()) return;
    setState(() => _loading = true);
    try {
      if (!logsOnly) {
        final results = await Future.wait([
          _svc.controlSyncStats(businessId: widget.businessId),
          _svc.controlSettingsSummary(businessId: widget.businessId),
          _svc.controlConnection(businessId: widget.businessId),
          _svc.controlPlugin(businessId: widget.businessId),
          _svc.controlQueueSnapshot(businessId: widget.businessId),
        ]);
        if (!mounted) return;
        setState(() {
          final stats = results[0];
          final sm = stats['stats'];
          _syncStats = sm is Map ? Map<String, dynamic>.from(sm) : const {};
          _settingsSummary = Map<String, dynamic>.from(results[1] as Map);
          _connection = Map<String, dynamic>.from(results[2] as Map);
          _pluginInfo = Map<String, dynamic>.from(results[3] as Map);
          _queueSnapshot = Map<String, dynamic>.from(results[4] as Map);
        });
      }
      final lr = await _svc.controlLogs(
        businessId: widget.businessId,
        page: _logPage,
        perPage: _logPerPage,
      );
      if (!mounted) return;
      final items = lr['items'];
      setState(() {
        _logRows = items is List
            ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : const [];
        _logTotal = int.tryParse('${lr['total'] ?? 0}') ?? 0;
        _logEpoch++;
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirmSyncAction(
    BuildContext context,
    AppLocalizations t, {
    required String title,
    required String body,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.woocommerceHubSyncColumnLabel),
          ),
        ],
      ),
    );
    return r == true;
  }

  List<int> _parseCommaSeparatedIds(String raw) {
    final parts = raw.split(RegExp(r'[\s,،]+'));
    final out = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p.trim());
      if (v != null && v > 0) {
        out.add(v);
      }
    }
    return out;
  }

  Future<void> _runBulkSync(
    BuildContext context,
    AppLocalizations t,
    String kind,
  ) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(
        context,
        message: t.woocommerceControlManageRequiredHint,
      );
      return;
    }
    final ids = _parseCommaSeparatedIds(_bulkIdsCtl.text);
    if (ids.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: t.woocommerceControlBulkIdsHint,
      );
      return;
    }
    final ok = await _confirmSyncAction(
      context,
      t,
      title: t.woocommerceControlBulkTitle,
      body: t.woocommerceControlBulkConfirmBody('${ids.length}'),
    );
    if (!ok || !context.mounted) return;
    try {
      if (kind == 'orders') {
        await _svc.postControlSyncOrders(
          businessId: widget.businessId,
          orderIds: ids,
        );
      } else if (kind == 'products') {
        await _svc.postControlSyncProducts(
          businessId: widget.businessId,
          productIds: ids,
        );
      } else {
        await _svc.postControlSyncCustomers(
          businessId: widget.businessId,
          customerIds: ids,
        );
      }
      if (!context.mounted) return;
      SnackBarHelper.showSuccess(context, message: t.woocommerceSyncDone);
      await _loadAll();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _onProcessQueueOnce(
    BuildContext context,
    AppLocalizations t,
  ) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(
        context,
        message: t.woocommerceControlManageRequiredHint,
      );
      return;
    }
    try {
      final r = await _svc.postControlQueueProcessOnce(
        businessId: widget.businessId,
      );
      if (!context.mounted) return;
      final d = int.tryParse('${r['pending_delta'] ?? 0}') ?? 0;
      SnackBarHelper.showSuccess(
        context,
        message: t.woocommerceControlQueueProcessDone('$d'),
      );
      await _loadAll();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _onPluginForceUpdateCheck(
    BuildContext context,
    AppLocalizations t,
  ) async {
    if (!_canWooCommerceManage()) {
      SnackBarHelper.showError(
        context,
        message: t.woocommerceControlManageRequiredHint,
      );
      return;
    }
    try {
      await _svc.postControlPluginUpdateCheck(
        businessId: widget.businessId,
        force: true,
      );
      if (!context.mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: t.woocommerceControlPluginCheckDone,
      );
      await _loadAll();
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Future<void> _onDebugModeChanged(
    BuildContext context,
    AppLocalizations t,
    bool value,
  ) async {
    if (!_canWooCommerceManage()) return;
    try {
      await _svc.postControlSettingsPatch(
        businessId: widget.businessId,
        payload: <String, dynamic>{'hesabix_v2_debug_mode': value},
      );
      if (!context.mounted) return;
      setState(() {
        _settingsSummary = Map<String, dynamic>.from(_settingsSummary)
          ..['hesabix_v2_debug_mode'] = value;
      });
      SnackBarHelper.showSuccess(
        context,
        message: t.woocommerceControlSettingsApplied,
      );
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    }
  }

  Widget _statsSection(BuildContext context, AppLocalizations t) {
    if (_syncStats.isEmpty) {
      return Text(
        t.woocommerceNoData,
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _syncStats.entries.map((e) {
        final type = e.key;
        final m = e.value is Map
            ? Map<String, dynamic>.from(e.value as Map)
            : const <String, dynamic>{};
        final total = int.tryParse('${m['total'] ?? 0}') ?? 0;
        final extras = m.entries.where((x) => x.key != 'total').toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          type,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        '${t.woocommerceStatsTotalLabel}: ${formatWooInteger(context, total)}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  if (extras.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: extras.map((x) {
                        final label = wooSyncStatusLabel(t, x.key as String?);
                        final cnt = int.tryParse('${x.value ?? 0}') ?? 0;
                        return Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            '$label: ${formatWooInteger(context, cnt)}',
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _connectionBlock(BuildContext context, AppLocalizations t) {
    final ok = _connection['ok'] == true;
    final msg = '${_connection['message'] ?? ''}'.trim();
    final payload = _connection['payload'];
    String? userLine;
    if (payload is Map && payload['user'] is Map) {
      final u = Map<String, dynamic>.from(payload['user'] as Map);
      final em = '${u['email'] ?? ''}'.trim();
      if (em.isNotEmpty) {
        userLine = em;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              ok ? Icons.check_circle_outline : Icons.error_outline,
              color: ok ? Colors.green : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ok
                    ? t.woocommerceControlConnectionOk
                    : t.woocommerceControlConnectionFail,
              ),
            ),
          ],
        ),
        if (msg.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg)),
        if (userLine != null && userLine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(userLine, textDirection: TextDirection.ltr),
          ),
      ],
    );
  }

  Widget _queueBlock(BuildContext context, AppLocalizations t) {
    final by = _queueSnapshot['by_status'];
    final batch = '${_queueSnapshot['batch_size'] ?? '—'}';
    final buf = StringBuffer();
    if (by is Map && by.isNotEmpty) {
      by.forEach((k, v) {
        buf.writeln('$k: $v');
      });
    } else {
      buf.write('—');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.woocommerceControlQueueBatchHint(batch)),
        const SizedBox(height: 8),
        SelectionArea(
          child: Text(buf.toString().trim(), style: _monoStyle(context)),
        ),
        if (_canWooCommerceManage()) ...[
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _loading ? null : () => _onProcessQueueOnce(context, t),
            icon: const Icon(Icons.play_circle_outline, size: 22),
            label: Text(t.woocommerceControlQueueProcessOnceButton),
          ),
        ],
      ],
    );
  }

  Widget _pluginBlock(BuildContext context, AppLocalizations t) {
    final cur = '${_pluginInfo['current_version'] ?? ''}'.trim();
    final up = _pluginInfo['updater'];
    String remote = '';
    bool updateAvail = false;
    if (up is Map) {
      remote = '${up['remote_version'] ?? ''}'.trim();
      updateAvail = up['update_available'] == true;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${t.woocommerceControlCurrentVersion}: ${cur.isEmpty ? '—' : cur}',
        ),
        const SizedBox(height: 6),
        Text(
          '${t.woocommerceControlRemoteVersion}: ${remote.isEmpty ? '—' : remote}',
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 6),
        Text(
          '${t.woocommerceControlUpdateAvailable}: ${updateAvail ? t.woocommerceControlConnectionOk : '—'}',
        ),
        if (_canWooCommerceManage()) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loading
                ? null
                : () => _onPluginForceUpdateCheck(context, t),
            icon: const Icon(Icons.system_update_alt_outlined, size: 20),
            label: Text(t.woocommerceControlPluginForceCheckButton),
          ),
        ],
      ],
    );
  }

  DataTableConfig<Map<String, dynamic>> _controlLogsTableConfig(
    AppLocalizations t,
  ) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/_local/woocommerce/control/logs',
      tableId: 'woo_control_logs_settings',
      title: t.woocommerceControlLogsTitle,
      columns: [
        TextColumn('id', t.woocommerceControlColumnLogId),
        TextColumn('entity_type', t.woocommerceControlColumnEntityType),
        TextColumn('entity_id', t.woocommerceControlColumnEntityId),
        TextColumn('action', t.woocommerceControlColumnAction),
        TextColumn('status', t.woocommerceControlColumnStatus),
        TextColumn('created_at', t.woocommerceControlColumnCreatedAt),
        TextColumn('error_message', t.woocommerceControlColumnError),
      ],
      searchFields: const [
        'id',
        'entity_type',
        'entity_id',
        'action',
        'status',
        'error_message',
      ],
      showFilters: false,
      showPagination: true,
      persistPageSize: false,
      pageSizeOptions: const [10, 15, 25, 50],
      showRefreshButton: false,
      showClearFiltersButton: false,
      enableDateRangeFilter: false,
      defaultPageSize: _logPerPage,
      enableColumnSettings: true,
      showColumnSearch: false,
      enableGlobalSearch: false,
      enableSorting: false,
      showSearch: false,
      showTableIcon: false,
      showActiveFilters: false,
      emptyStateMessage: t.woocommerceNoData,
      minTableWidth: 960,
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_canWooCommerceView()) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.woocommerceSettingsArcwocPluginTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.woocommerceSettingsArcwocPluginIntro,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: t.woocommerceControlRefreshTooltip,
              onPressed: _loading ? null : () => _loadAll(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 8),
        _sectionCard(
          context,
          title: t.woocommerceControlStatsTitle,
          child: _statsSection(context, t),
        ),
        _sectionCard(
          context,
          title: t.woocommerceControlConnectionTitle,
          child: _connectionBlock(context, t),
        ),
        _sectionCard(
          context,
          title: t.woocommerceControlQueueTitle,
          child: _queueBlock(context, t),
        ),
        _sectionCard(
          context,
          title: t.woocommerceControlPluginTitle,
          child: _pluginBlock(context, t),
        ),
        _sectionCard(
          context,
          title: t.woocommerceControlSettingsTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_settingsSummary.isEmpty)
                Text(t.woocommerceNoData)
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._settingsSummary.entries.map((e) {
                      if (e.value is Map || e.value is List) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(e.key, style: _monoStyle(context)),
                            subtitle: Text(
                              _prettyJson(e.value),
                              style: _monoStyle(context),
                            ),
                          ),
                        );
                      }
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          e.key,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        subtitle: Text(
                          '${e.value}',
                          textDirection: TextDirection.ltr,
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setState(
                        () => _showRawSettingsJson = !_showRawSettingsJson,
                      ),
                      icon: Icon(
                        _showRawSettingsJson
                            ? Icons.visibility_off_outlined
                            : Icons.code,
                      ),
                      label: Text(
                        _showRawSettingsJson
                            ? t.woocommerceHideRawSettingsJson
                            : t.woocommerceShowRawSettingsJson,
                      ),
                    ),
                    if (_showRawSettingsJson)
                      SelectionArea(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            _prettyJson(_settingsSummary),
                            style: _monoStyle(context),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (_canWooCommerceManage())
          Card(
            child: SwitchListTile(
              title: Text(t.woocommerceControlDebugModeTitle),
              subtitle: Text(t.woocommerceControlDebugModeSubtitle),
              value: _settingsSummary['hesabix_v2_debug_mode'] == true,
              onChanged: _loading
                  ? null
                  : (v) => _onDebugModeChanged(context, t, v),
            ),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t.woocommerceControlManageRequiredHint),
            ),
          ),
        if (_canWooCommerceManage()) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.woocommerceControlBulkTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _bulkIdsCtl,
                    decoration: InputDecoration(
                      labelText: t.woocommerceControlBulkIdsHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    minLines: 1,
                    maxLines: 3,
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.start,
                    children: [
                      FilledButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _runBulkSync(context, t, 'orders'),
                        icon: const Icon(Icons.receipt_long_outlined, size: 20),
                        label: Text(t.woocommerceControlSyncOrdersButton),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _loading
                            ? null
                            : () => _runBulkSync(context, t, 'products'),
                        icon: const Icon(Icons.inventory_2_outlined, size: 20),
                        label: Text(t.woocommerceControlSyncProductsButton),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _runBulkSync(context, t, 'customers'),
                        icon: const Icon(Icons.people_outline, size: 20),
                        label: Text(t.woocommerceControlSyncCustomersButton),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          t.woocommerceControlLogsTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 420,
          child: DataTableWidget<Map<String, dynamic>>(
            key: ValueKey(
              'woo_logs_settings_${_logPage}_${_logPerPage}_$_logEpoch',
            ),
            config: _controlLogsTableConfig(t),
            fromJson: (json) => Map<String, dynamic>.from(json as Map),
            localRawItems: _logRows,
            localTotalCount: _logTotal,
            localCurrentPage: _logPage,
            localPageSize: _logPerPage,
            onLocalPageChange: (p) {
              setState(() => _logPage = p);
              _loadAll(logsOnly: true);
            },
            onLocalPageSizeChange: (s) {
              setState(() {
                _logPerPage = s.clamp(1, 100);
                _logPage = 1;
              });
              _loadAll(logsOnly: true);
            },
          ),
        ),
      ],
    );
  }
}
