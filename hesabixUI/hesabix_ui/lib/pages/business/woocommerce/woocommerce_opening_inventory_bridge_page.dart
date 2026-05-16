import 'package:flutter/material.dart';

import '../../../core/auth_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/woocommerce_integration_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/business_subpage_back_leading.dart';

/// اجرای موجودی اولیه / تراز افتتاحیه روی فروشگاه از طریق API پل (بدون wp-admin).
class WoocommerceOpeningInventoryBridgePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const WoocommerceOpeningInventoryBridgePage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<WoocommerceOpeningInventoryBridgePage> createState() =>
      _WoocommerceOpeningInventoryBridgePageState();
}

class _WoocommerceOpeningInventoryBridgePageState
    extends State<WoocommerceOpeningInventoryBridgePage> {
  final WoocommerceIntegrationService _svc = WoocommerceIntegrationService();
  final _warehouseCtl = TextEditingController(text: '0');
  final _batchCtl = TextEditingController(text: '12');
  final _log = StringBuffer();

  bool _busy = false;
  bool _batchLoopRunning = false;
  int? _batchProgCur;
  int? _batchProgTot;
  bool _invCompleted = false;
  String? _postConfirmPhrase;
  Map<String, dynamic>? _pendingJob;

  List<Map<String, dynamic>> _accounts = const [];
  int? _inventoryAccountId;
  int? _equityAccountId;

  bool _includeTax = false;
  bool _autoBalance = true;
  bool _doPost = false;
  String _costBasis = 'regular';
  String? _activeJobId;

  bool _canManage() {
    if (widget.authStore.currentBusiness?.isOwner == true) return true;
    return widget.authStore.hasBusinessPermission('woocommerce', 'manage');
  }

  @override
  void dispose() {
    _warehouseCtl.dispose();
    _batchCtl.dispose();
    super.dispose();
  }

  void _append(String line) {
    _log.writeln(line);
    if (mounted) setState(() {});
  }

  int _parseIntCtl(TextEditingController c, int fallback) {
    final v = int.tryParse(c.text.trim());
    return v ?? fallback;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  bool get _uiLocked => _invCompleted || _busy || _batchLoopRunning;

  EdgeInsetsGeometry _inputContentPadding(BuildContext context) {
    final p = Theme.of(context).inputDecorationTheme.contentPadding;
    if (p != null) return p;
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 16);
  }

  InputDecoration _outlineFieldDec(
    BuildContext context,
    String label, {
    bool enabled = true,
  }) {
    return InputDecoration(
      labelText: label,
      enabled: enabled,
      border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: _inputContentPadding(context),
    );
  }

  String _costBasisItemLabel(AppLocalizations t, String v) {
    switch (v) {
      case 'sale':
        return t.woocommerceOpeningInvCostBasisSale;
      case 'zero':
        return t.woocommerceOpeningInvCostBasisZero;
      case 'regular':
      default:
        return t.woocommerceOpeningInvCostBasisRegular;
    }
  }

  Map<String, dynamic> _preparePayload() {
    return <String, dynamic>{
      'include_tax': _includeTax,
      'cost_basis': _costBasis,
      'auto_balance_to_equity': _autoBalance,
      'do_post': _doPost,
      'inventory_account_id': _inventoryAccountId ?? 0,
      'equity_account_id': _equityAccountId ?? 0,
      'batch_size': _parseIntCtl(_batchCtl, 12).clamp(3, 40),
      'warehouse_id': _parseIntCtl(_warehouseCtl, 0),
    };
  }

  Future<void> _loadStatus() async {
    if (!_canManage()) return;
    setState(() => _busy = true);
    try {
      final s = await _svc.controlOpeningInventoryStatus(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() {
        _invCompleted = s['opening_inventory_completed'] == true;
        _postConfirmPhrase = s['post_confirm_phrase']?.toString();
        final pj = s['pending_job'];
        _pendingJob = pj is Map ? Map<String, dynamic>.from(pj) : null;
        if (_pendingJob != null && _pendingJob!['job_id'] != null) {
          _activeJobId = '${_pendingJob!['job_id']}';
        }
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAccounts() async {
    if (!_canManage()) return;
    setState(() => _busy = true);
    try {
      final r = await _svc.controlOpeningInventoryAccounts(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      final list = r['accounts'];
      setState(() {
        _accounts = list is List
            ? list.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : const [];
      });
      _append(
        '${AppLocalizations.of(context).woocommerceOpeningInvLoadAccounts}: ${_accounts.length}',
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview() async {
    if (!_canManage()) return;
    setState(() => _busy = true);
    try {
      final r = await _svc.postControlOpeningInventoryPreview(
        businessId: widget.businessId,
        payload: <String, dynamic>{
          'include_tax': _includeTax,
          'cost_basis': _costBasis,
          'batch_size': _parseIntCtl(_batchCtl, 12).clamp(3, 40),
          'warehouse_id': _parseIntCtl(_warehouseCtl, 0),
        },
      );
      if (!mounted) return;
      _append('preview: total=${r['total']} batches_est=${r['batches_est']}');
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareOnly() async {
    if (!_canManage()) return;
    if (_inventoryAccountId == null || _inventoryAccountId! < 1) {
      SnackBarHelper.showError(
        context,
        message: AppLocalizations.of(context).woocommerceOpeningInvPickInventoryHint,
      );
      return;
    }
    if (_autoBalance && (_equityAccountId == null || _equityAccountId! < 1)) {
      SnackBarHelper.showError(
        context,
        message: AppLocalizations.of(context).woocommerceOpeningInvPickEquityHint,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await _svc.postControlOpeningInventoryPrepare(
        businessId: widget.businessId,
        payload: _preparePayload(),
      );
      if (!mounted) return;
      final jid = r['job_id']?.toString();
      setState(() => _activeJobId = jid);
      _append('prepare job_id=$jid total=${r['total']} resumed=${r['resumed']} needs_finalize=${r['needs_finalize']}');
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runAllBatchesToEnd() async {
    final t = AppLocalizations.of(context);
    if (!_canManage()) return;
    final jid = _activeJobId;
    if (jid == null || jid.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: t.woocommerceOpeningInvNeedActiveJob,
      );
      return;
    }
    if (_invCompleted) return;
    setState(() {
      _batchLoopRunning = true;
      _batchProgCur = null;
      _batchProgTot = null;
    });
    try {
      await _runBatchesLoop(jid);
    } finally {
      if (mounted) {
        setState(() {
          _batchLoopRunning = false;
          _batchProgCur = null;
          _batchProgTot = null;
        });
      }
    }
  }

  Future<void> _finalizeOnly() async {
    final t = AppLocalizations.of(context);
    if (!_canManage()) return;
    final jid = _activeJobId;
    if (jid == null || jid.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: t.woocommerceOpeningInvNeedActiveJob,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _finalize(jid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runBatchesLoop(String jobId) async {
    while (mounted) {
      final r = await _svc.postControlOpeningInventoryBatch(
        businessId: widget.businessId,
        payload: <String, dynamic>{'job_id': jobId},
      );
      if (!mounted) return;
      final cancelled = r['cancelled'] == true;
      final done = r['done'] == true;
      final cur = r['cursor'];
      final tot = r['total'];
      _append('batch cursor=$cur / $tot done=$done cancelled=$cancelled');
      final curN = _asInt(cur);
      final totN = _asInt(tot);
      if (mounted) {
        setState(() {
          _batchProgCur = curN;
          if (totN != null && totN > 0) {
            _batchProgTot = totN;
          }
        });
      }
      await Future<void>.delayed(Duration.zero);
      if (cancelled) {
        final msg = r['message']?.toString() ?? '';
        if (msg.isNotEmpty) {
          if (!mounted) return;
          SnackBarHelper.showInfo(context, message: msg);
        }
        return;
      }
      if (done) {
        await _finalize(jobId);
        return;
      }
    }
  }

  Future<String?> _promptPostPhrase() async {
    final t = AppLocalizations.of(context);
    final phrase = _postConfirmPhrase ?? '';
    final ctl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.woocommerceOpeningInvPhrasePromptTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${t.woocommerceOpeningInvPhraseHint}\n«$phrase»'),
              const SizedBox(height: 12),
              TextField(controller: ctl, decoration: const InputDecoration(border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.woocommerceOpeningInvFinalize)),
          ],
        ),
      );
      if (ok != true || !mounted) return null;
      final typed = ctl.text.trim();
      if (typed != phrase) {
        SnackBarHelper.showError(context, message: t.woocommerceOpeningInvPhraseMismatch);
        return null;
      }
      return typed;
    } finally {
      ctl.dispose();
    }
  }

  Future<void> _finalize(String jobId) async {
    final payload = <String, dynamic>{'job_id': jobId};
    if (_doPost) {
      final p = await _promptPostPhrase();
      if (p == null) return;
      payload['confirm_post_phrase'] = p;
    }
    final r = await _svc.postControlOpeningInventoryFinalize(
      businessId: widget.businessId,
      payload: payload,
    );
    if (!mounted) return;
    _append('finalize: ${r['message'] ?? r}');
    SnackBarHelper.showSuccess(
      context,
      message: r['message']?.toString() ?? AppLocalizations.of(context).woocommerceSyncDone,
    );
    await _loadStatus();
  }

  Future<void> _cancel() async {
    if (_activeJobId == null || _activeJobId!.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await _svc.postControlOpeningInventoryCancel(
        businessId: widget.businessId,
        payload: <String, dynamic>{'job_id': _activeJobId},
      );
      if (!mounted) return;
      _append('cancel: ${r['message'] ?? r}');
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runOneBatch() async {
    if (_activeJobId == null || _activeJobId!.isEmpty) {
      SnackBarHelper.showError(
        context,
        message: AppLocalizations.of(context).woocommerceOpeningInvNeedActiveJob,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await _svc.postControlOpeningInventoryBatch(
        businessId: widget.businessId,
        payload: <String, dynamic>{'job_id': _activeJobId},
      );
      if (!mounted) return;
      _append('batch: done=${r['done']} cancelled=${r['cancelled']} cursor=${r['cursor']}/${r['total']}');
      if (r['done'] == true) {
        await _finalize(_activeJobId!);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_canManage()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadStatus());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!_canManage()) {
      return Scaffold(
        appBar: AppBar(
          leading: businessSubpageBackLeading(context, widget.businessId),
          title: Text(t.woocommerceOpeningInvBridgeTitle),
        ),
        body: Center(child: Text(t.woocommerceControlManageRequiredHint)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: businessSubpageBackLeading(context, widget.businessId),
        title: Text(t.woocommerceOpeningInvBridgeTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.woocommerceOpeningInvBridgeSubtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          if (_invCompleted)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                title: Text(t.woocommerceOpeningInvCompletedBanner),
              ),
            ),
          if (_pendingJob != null && !_invCompleted)
            Card(
              child: ListTile(
                title: Text('${t.woocommerceOpeningInvJobIdLabel}: $_activeJobId'),
                subtitle: Text(
                  t.woocommerceOpeningInvPendingProgress(
                    _pendingJob!['cursor'] ?? '—',
                    _pendingJob!['total'] ?? '—',
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: (_busy || _batchLoopRunning) ? null : _loadStatus,
                child: Text(t.woocommerceOpeningInvRefreshStatus),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: (_busy || _batchLoopRunning) ? null : _loadAccounts,
                child: Text(t.woocommerceOpeningInvLoadAccounts),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: _outlineFieldDec(
              context,
              t.woocommerceOpeningInvInventoryAccountLabel,
              enabled: !_uiLocked,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                isDense: true,
                padding: EdgeInsets.zero,
                value: _inventoryAccountId,
                hint: const Text('—'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  ..._accounts.map((a) {
                    final id = int.tryParse('${a['id']}') ?? 0;
                    final lab = '${a['label'] ?? a['name'] ?? id}';
                    return DropdownMenuItem<int?>(
                      value: id,
                      child: Text(lab, overflow: TextOverflow.ellipsis),
                    );
                  }),
                ],
                onChanged: _uiLocked ? null : (v) => setState(() => _inventoryAccountId = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: _outlineFieldDec(
              context,
              t.woocommerceOpeningInvEquityAccountLabel,
              enabled: _autoBalance && !_uiLocked,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                isDense: true,
                padding: EdgeInsets.zero,
                value: _equityAccountId,
                hint: const Text('—'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  ..._accounts.map((a) {
                    final id = int.tryParse('${a['id']}') ?? 0;
                    final lab = '${a['label'] ?? a['name'] ?? id}';
                    return DropdownMenuItem<int?>(
                      value: id,
                      child: Text(lab, overflow: TextOverflow.ellipsis),
                    );
                  }),
                ],
                onChanged: (!_autoBalance || _uiLocked) ? null : (v) => setState(() => _equityAccountId = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _warehouseCtl,
            enabled: !_uiLocked,
            decoration: _outlineFieldDec(
              context,
              t.woocommerceOpeningInvWarehouseOverrideLabel,
              enabled: !_uiLocked,
            ),
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _batchCtl,
            enabled: !_uiLocked,
            decoration: _outlineFieldDec(
              context,
              t.woocommerceOpeningInvBatchSizeLabel,
              enabled: !_uiLocked,
            ),
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: _outlineFieldDec(
              context,
              t.woocommerceOpeningInvCostBasisLabel,
              enabled: !_uiLocked,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                isDense: true,
                padding: EdgeInsets.zero,
                value: _costBasis,
                items: [
                  DropdownMenuItem(
                    value: 'regular',
                    child: Text(_costBasisItemLabel(t, 'regular')),
                  ),
                  DropdownMenuItem(
                    value: 'sale',
                    child: Text(_costBasisItemLabel(t, 'sale')),
                  ),
                  DropdownMenuItem(
                    value: 'zero',
                    child: Text(_costBasisItemLabel(t, 'zero')),
                  ),
                ],
                onChanged: _uiLocked ? null : (v) => setState(() => _costBasis = v ?? 'regular'),
              ),
            ),
          ),
          SwitchListTile(
            title: Text(t.woocommerceOpeningInvIncludeTaxLabel),
            value: _includeTax,
            onChanged: _uiLocked ? null : (v) => setState(() => _includeTax = v),
          ),
          SwitchListTile(
            title: Text(t.woocommerceOpeningInvAutoBalanceLabel),
            value: _autoBalance,
            onChanged: _uiLocked ? null : (v) => setState(() => _autoBalance = v),
          ),
          SwitchListTile(
            title: Text(t.woocommerceOpeningInvDoPostLabel),
            value: _doPost,
            onChanged: _uiLocked ? null : (v) => setState(() => _doPost = v),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(onPressed: _uiLocked ? null : _preview, child: Text(t.woocommerceOpeningInvPreview)),
              FilledButton(onPressed: _uiLocked ? null : _prepareOnly, child: Text(t.woocommerceOpeningInvPrepare)),
              FilledButton.tonal(
                onPressed: (_uiLocked || _activeJobId == null) ? null : _runAllBatchesToEnd,
                child: Text(t.woocommerceOpeningInvRunAllToEnd),
              ),
              OutlinedButton(onPressed: _uiLocked || _activeJobId == null ? null : _runOneBatch, child: Text(t.woocommerceOpeningInvRunBatches)),
              OutlinedButton(onPressed: _uiLocked || _activeJobId == null ? null : _finalizeOnly, child: Text(t.woocommerceOpeningInvFinalizeOnly)),
              OutlinedButton(
                onPressed: (_activeJobId == null || (_busy && !_batchLoopRunning)) ? null : _cancel,
                child: Text(t.woocommerceOpeningInvCancelJob),
              ),
              TextButton(
                onPressed: (_busy && !_batchLoopRunning)
                    ? null
                    : () {
                        setState(_log.clear);
                      },
                child: Text(t.woocommerceOpeningInvClearLog),
              ),
            ],
          ),
          if (_batchLoopRunning) ...[
            const SizedBox(height: 12),
            if (_batchProgTot != null && _batchProgTot! > 0 && _batchProgCur != null)
              LinearProgressIndicator(
                value: (_batchProgCur!.clamp(0, _batchProgTot!) / _batchProgTot!).clamp(0.0, 1.0),
              )
            else
              const LinearProgressIndicator(),
            const SizedBox(height: 4),
            Text(
              '${_batchProgCur ?? '—'} / ${_batchProgTot ?? '—'}',
              style: Theme.of(context).textTheme.bodySmall,
              textDirection: TextDirection.ltr,
            ),
          ],
          const SizedBox(height: 16),
          Text(t.woocommerceOpeningInvLogTitle, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _log.isEmpty ? '—' : _log.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          if (_busy && !_batchLoopRunning)
            const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
