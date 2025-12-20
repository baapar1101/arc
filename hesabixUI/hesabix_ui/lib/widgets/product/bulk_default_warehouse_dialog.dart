import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../../models/warehouse_model.dart';
import '../../services/bulk_default_warehouse_service.dart';
import '../../services/warehouse_service.dart';
import '../../utils/snackbar_helper.dart';

class BulkDefaultWarehouseDialog extends StatefulWidget {
  final int businessId;
  final List<int> selectedProductIds;
  final VoidCallback? onSuccess;

  const BulkDefaultWarehouseDialog({
    super.key,
    required this.businessId,
    required this.selectedProductIds,
    this.onSuccess,
  });

  @override
  State<BulkDefaultWarehouseDialog> createState() => _BulkDefaultWarehouseDialogState();
}

class _BulkDefaultWarehouseDialogState extends State<BulkDefaultWarehouseDialog> {
  final _api = ApiClient();
  late final WarehouseService _warehouseService;
  late final BulkDefaultWarehouseService _bulkService;

  bool _loadingWarehouses = true;
  bool _previewLoading = false;
  bool _applyLoading = false;

  List<Warehouse> _warehouses = const <Warehouse>[];
  int? _selectedWarehouseId;
  String _applyScope = 'all'; // track_inventory_true | track_inventory_false | all

  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _lastApplyResult;
  Timer? _previewDebounce;

  @override
  void initState() {
    super.initState();
    _warehouseService = WarehouseService(apiClient: _api);
    _bulkService = BulkDefaultWarehouseService(apiClient: _api);
    _loadWarehouses();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadWarehouses() async {
    setState(() => _loadingWarehouses = true);
    try {
      final items = await _warehouseService.listWarehouses(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _warehouses = items;
      });
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: '${t.error}: $e');
    } finally {
      if (mounted) setState(() => _loadingWarehouses = false);
    }
  }

  Map<String, dynamic> _buildPayload() {
    return <String, dynamic>{
      'ids': widget.selectedProductIds,
      'default_warehouse_id': _selectedWarehouseId,
      'apply_scope': _applyScope,
    };
  }

  void _scheduleAutoPreview() {
    // Auto-preview only after user has previewed once, to avoid noisy API calls
    if (_preview == null) return;
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _previewRequest();
    });
  }

  Future<void> _previewRequest() async {
    setState(() => _previewLoading = true);
    try {
      final data = await _bulkService.preview(
        businessId: widget.businessId,
        productIds: widget.selectedProductIds,
        defaultWarehouseId: _selectedWarehouseId,
        applyScope: _applyScope,
      );
      if (!mounted) return;
      setState(() => _preview = data);
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: t.previewError(e.toString()));
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  Future<void> _applyRequest() async {
    final t = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.bulkDefaultWarehouseConfirmTitle),
        content: Text(t.bulkDefaultWarehouseConfirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(t.applyChanges)),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _applyLoading = true);
    try {
      final data = await _bulkService.apply(
        businessId: widget.businessId,
        productIds: widget.selectedProductIds,
        defaultWarehouseId: _selectedWarehouseId,
        applyScope: _applyScope,
      );
      if (!mounted) return;
      final updated = data['updated_count'];
      setState(() => _lastApplyResult = data);
      SnackBarHelper.show(context, message: t.bulkDefaultWarehouseApplySuccess(updated?.toString() ?? '-'));
      widget.onSuccess?.call();
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(t.operationSuccessful),
          content: _ResultBox(
            result: data,
            reasonLabel: (r) => _reasonLabel(t, r),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.close)),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: '${t.error}: $e');
    } finally {
      if (mounted) setState(() => _applyLoading = false);
    }
  }

  String _scopeLabel(AppLocalizations t, String v) {
    switch (v) {
      case 'track_inventory_true':
        return t.bulkDefaultWarehouseScopeTrackInventoryTrue;
      case 'track_inventory_false':
        return t.bulkDefaultWarehouseScopeTrackInventoryFalse;
      default:
        return t.bulkDefaultWarehouseScopeAll;
    }
  }

  String _reasonLabel(AppLocalizations t, String? reason) {
    switch ((reason ?? '').toUpperCase()) {
      case 'ALREADY_SET':
        return t.bulkDefaultWarehouseReasonAlreadySet;
      case 'SCOPE_MISMATCH':
        return t.bulkDefaultWarehouseReasonScopeMismatch;
      case 'NOT_FOUND':
        return t.bulkDefaultWarehouseReasonNotFound;
      case 'SERVICE_ALREADY_NULL':
        return t.bulkDefaultWarehouseReasonServiceAlreadyNull;
      default:
        return t.bulkDefaultWarehouseReasonUnknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.bulkDefaultWarehouseTitle),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.bulkDefaultWarehouseSelectedCount(widget.selectedProductIds.length)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _loadingWarehouses
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<int?>(
                          value: _selectedWarehouseId,
                          items: [
                            DropdownMenuItem<int?>(
                              value: null,
                              child: Text(t.bulkDefaultWarehouseClearOption),
                            ),
                            ..._warehouses.map((w) {
                              return DropdownMenuItem<int?>(
                                value: w.id,
                                child: Text('${w.code} - ${w.name}'),
                              );
                            }),
                          ],
                          onChanged: (v) {
                            setState(() => _selectedWarehouseId = v);
                            _scheduleAutoPreview();
                          },
                          decoration: InputDecoration(
                            labelText: t.bulkDefaultWarehouseNewWarehouseLabel,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(t.bulkDefaultWarehouseScopeLabel),
            const SizedBox(height: 6),
            for (final v in const ['all', 'track_inventory_true', 'track_inventory_false'])
              RadioListTile<String>(
                value: v,
                groupValue: _applyScope,
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _applyScope = val);
                  _scheduleAutoPreview();
                },
                title: Text(_scopeLabel(t, v)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            const SizedBox(height: 12),
            if (_previewLoading) const LinearProgressIndicator(),
            if (_preview != null) ...[
              const SizedBox(height: 8),
              _PreviewBox(
                preview: _preview!,
                reasonLabel: (r) => _reasonLabel(t, r),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_previewLoading || _applyLoading) ? null : () => Navigator.of(context).pop(false),
          child: Text(t.close),
        ),
        FilledButton.tonal(
          onPressed: (_previewLoading || _applyLoading) ? null : _previewRequest,
          child: Text(t.preview),
        ),
        FilledButton(
          onPressed: (_applyLoading || _previewLoading) ? null : _applyRequest,
          child: _applyLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t.applyChanges),
        ),
      ],
    );
  }
}

class _PreviewBox extends StatelessWidget {
  final Map<String, dynamic> preview;
  final String Function(String? reason) reasonLabel;
  const _PreviewBox({required this.preview, required this.reasonLabel});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final total = preview['total_requested'];
    final found = preview['found_count'];
    final willUpdate = preview['will_update_count'];
    final forcedServiceNull = preview['forced_service_null_count'];
    final skipped = (preview['skipped'] as List?) ?? const [];
    final notes = (preview['notes'] as List?) ?? const [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.bulkDefaultWarehousePreviewSummary(
            total?.toString() ?? '-',
            found?.toString() ?? '-',
            willUpdate?.toString() ?? '-',
          )),
          const SizedBox(height: 6),
          if (notes.isNotEmpty) ...[
            Text(t.bulkDefaultWarehouseNotesLabel),
            for (final n in notes) Text('- ${n.toString()}'),
            const SizedBox(height: 6),
          ],
          if (forcedServiceNull is int && forcedServiceNull > 0) ...[
            Text(t.bulkDefaultWarehouseForcedServiceNull(forcedServiceNull)),
            const SizedBox(height: 6),
          ],
          Text(t.bulkDefaultWarehouseSkippedCount(skipped.length)),
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 140,
              child: ListView.builder(
                itemCount: skipped.length,
                itemBuilder: (_, i) {
                  final row = skipped[i];
                  if (row is! Map) return const SizedBox.shrink();
                  final m = Map<String, dynamic>.from(row as Map);
                  final id = m['id'];
                  final reason = m['reason']?.toString();
                  final code = m['code'];
                  final name = m['name'];
                  final label = [
                    if (code != null) code.toString(),
                    if (name != null) name.toString(),
                  ].where((x) => x.isNotEmpty).join(' - ');
                  return Text('• $id: ${reasonLabel(reason)}${label.isNotEmpty ? ' ($label)' : ''}');
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultBox extends StatelessWidget {
  final Map<String, dynamic> result;
  final String Function(String? reason) reasonLabel;
  const _ResultBox({required this.result, required this.reasonLabel});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final total = result['total_requested'];
    final found = result['found_count'];
    final updated = result['updated_count'];
    final forcedServiceNull = result['forced_service_null_count'];
    final skipped = (result['skipped'] as List?) ?? const [];
    final notes = (result['notes'] as List?) ?? const [];

    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.bulkDefaultWarehouseApplySummary(
            total?.toString() ?? '-',
            found?.toString() ?? '-',
            updated?.toString() ?? '-',
            skipped.length.toString(),
          )),
          if (forcedServiceNull is int && forcedServiceNull > 0) ...[
            const SizedBox(height: 8),
            Text(t.bulkDefaultWarehouseForcedServiceNull(forcedServiceNull)),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(t.bulkDefaultWarehouseNotesLabel),
            for (final n in notes) Text('- ${n.toString()}'),
          ],
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(t.bulkDefaultWarehouseSkippedCount(skipped.length)),
            const SizedBox(height: 6),
            SizedBox(
              height: 140,
              child: ListView.builder(
                itemCount: skipped.length,
                itemBuilder: (_, i) {
                  final row = skipped[i];
                  if (row is! Map) return const SizedBox.shrink();
                  final m = Map<String, dynamic>.from(row as Map);
                  final id = m['id'];
                  final reason = m['reason']?.toString();
                  final code = m['code'];
                  final name = m['name'];
                  final label = [
                    if (code != null) code.toString(),
                    if (name != null) name.toString(),
                  ].where((x) => x.isNotEmpty).join(' - ');
                  return Text('• $id: ${reasonLabel(reason)}${label.isNotEmpty ? ' ($label)' : ''}');
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}


