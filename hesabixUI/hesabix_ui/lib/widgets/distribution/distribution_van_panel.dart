import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/business_user_model.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_form_helpers.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/warehouse_combobox_widget.dart';

/// تب ون: موجودی، ساخت، بارگیری و تخلیه.
class DistributionVanPanel extends StatefulWidget {
  final int businessId;
  final DistributionService service;
  final bool enableVanSales;
  final bool canManage;

  const DistributionVanPanel({
    super.key,
    required this.businessId,
    required this.service,
    required this.enableVanSales,
    required this.canManage,
  });

  @override
  State<DistributionVanPanel> createState() => _DistributionVanPanelState();
}

class _DistributionVanPanelState extends State<DistributionVanPanel> {
  List<dynamic> _vans = [];
  Map<String, dynamic>? _myStock;
  bool _loading = false;
  int? _selectedVanId;

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final futures = <Future>[
        widget.service.getMyVanStock(businessId: widget.businessId),
      ];
      if (widget.canManage) {
        futures.add(widget.service.listVans(businessId: widget.businessId));
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _myStock = Map<String, dynamic>.from(results[0] as Map);
        if (widget.canManage && results.length > 1) {
          _vans = results[1] as List<dynamic>;
        }
        _selectedVanId ??= (_myStock?['van_id'] as int?) ??
            (_vans.isNotEmpty ? (_vans.first as Map)['id'] as int? : null);
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _showVanDialog({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final nameCtl = TextEditingController(text: existing?['name']?.toString() ?? '');
    int? userId = int.tryParse('${existing?['user_id'] ?? ''}');
    List<BusinessUser> users = const [];
    try {
      final res = await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId);
      users = res.users;
    } catch (_) {}

    if (!mounted) return;
    final editing = existing != null;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(editing ? t.distributionVanEdit : t.distributionVanCreate),
          content: distributionFormColumn(
            children: [
              TextField(
                controller: nameCtl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.distributionVanName,
                  border: const OutlineInputBorder(),
                ),
              ),
              DropdownButtonFormField<int?>(
                value: userId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t.distributionSelectVisitor,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('—')),
                  ...users.map(
                    (u) => DropdownMenuItem<int?>(
                      value: u.userId,
                      child: Text(u.userName.isNotEmpty ? u.userName : 'user ${u.userId}'),
                    ),
                  ),
                ],
                onChanged: (v) => setD(() => userId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                final name = nameCtl.text.trim();
                if (name.isEmpty) return;
                try {
                  if (editing) {
                    await widget.service.updateVan(
                      businessId: widget.businessId,
                      vanId: int.parse('${existing['id']}'),
                      payload: {
                        'name': name,
                        'user_id': userId,
                      },
                    );
                  } else {
                    await widget.service.createVan(
                      businessId: widget.businessId,
                      payload: {
                        'code': nextDistributionCode('VAN', _vans),
                        'name': name,
                        if (userId != null) 'user_id': userId,
                      },
                    );
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _reload();
                  if (mounted) {
                    SnackBarHelper.showSuccess(context, message: t.distributionSettingsSaved);
                  }
                } catch (e) {
                  if (mounted) {
                    SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                  }
                }
              },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTransferDialog({required bool load}) async {
    final t = AppLocalizations.of(context);
    final vanId = _selectedVanId ?? _myStock?['van_id'] as int?;
    if (vanId == null) {
      SnackBarHelper.showError(context, message: t.distributionVanStock);
      return;
    }
    int? warehouseId;
    final lines = <Map<String, dynamic>>[];
    Map<String, dynamic>? product;
    final qtyCtl = TextEditingController(text: '1');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(load ? t.distributionVanLoad : t.distributionVanUnload),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WarehouseComboboxWidget(
                    businessId: widget.businessId,
                    selectedWarehouseId: warehouseId,
                    label: load ? t.distributionSourceWarehouse : t.distributionDestWarehouse,
                    selectDefaultWhenUnset: true,
                    onChanged: (id) => setD(() => warehouseId = id),
                  ),
                  const SizedBox(height: 8),
                  ProductComboboxWidget(
                    businessId: widget.businessId,
                    label: t.distributionSelectProduct,
                    onChanged: (p) => setD(() => product = p),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qtyCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t.distributionReturnQuantity,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      if (product == null) return;
                      final pid = product!['id'];
                      setD(() {
                        lines.add({
                          'product_id': pid is int ? pid : int.parse('$pid'),
                          'product_name': product!['name'] ?? product!['product_name'],
                          'quantity': double.tryParse(qtyCtl.text) ?? 1,
                        });
                        product = null;
                        qtyCtl.text = '1';
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: Text(t.distributionReturnAddLine),
                  ),
                  ...lines.asMap().entries.map(
                    (e) => ListTile(
                      dense: true,
                      title: Text(
                        '${e.value['product_name'] ?? 'product ${e.value['product_id']}'}'
                        ' × ${e.value['quantity']}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setD(() => lines.removeAt(e.key)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: lines.isEmpty
                  ? null
                  : () async {
                      try {
                        if (load) {
                          await widget.service.loadVan(
                            businessId: widget.businessId,
                            vanId: vanId,
                            lines: lines,
                            sourceWarehouseId: warehouseId,
                          );
                        } else {
                          await widget.service.unloadVan(
                            businessId: widget.businessId,
                            vanId: vanId,
                            lines: lines,
                            destWarehouseId: warehouseId,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _reload();
                        if (mounted) {
                          SnackBarHelper.showSuccess(context, message: t.distributionSettingsSaved);
                        }
                      } catch (e) {
                        if (mounted) {
                          SnackBarHelper.showError(
                            context,
                            message: ErrorExtractor.forContext(e, context),
                          );
                        }
                      }
                    },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.enableVanSales) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.distributionEnableVanSales, textAlign: TextAlign.center),
        ),
      );
    }
    if (_loading && _myStock == null && _vans.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final vanId = _selectedVanId ?? _myStock?['van_id'];
    final items = (_myStock?['items'] as List?) ?? [];

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.canManage) ...[
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _showVanDialog(),
                  icon: const Icon(Icons.add),
                  label: Text(t.distributionVanCreate),
                ),
                const SizedBox(width: 8),
                if (_vans.isNotEmpty)
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedVanId,
                      decoration: InputDecoration(
                        labelText: t.distributionVanStock,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _vans.map((raw) {
                        final m = Map<String, dynamic>.from(raw as Map);
                        return DropdownMenuItem<int>(
                          value: m['id'] as int,
                          child: Text(
                            '${distributionEntityLabel(m)} · ${m['user_name'] ?? m['user_id'] ?? '—'}',
                          ),
                        );
                      }).toList(),
                      onChanged: (id) async {
                        setState(() => _selectedVanId = id);
                        if (id == null) return;
                        try {
                          final stock = await widget.service.getVanStock(
                            businessId: widget.businessId,
                            vanId: id,
                          );
                          if (mounted) setState(() => _myStock = stock);
                        } catch (e) {
                          if (mounted) {
                            SnackBarHelper.showError(
                              context,
                              message: ErrorExtractor.forContext(e, context),
                            );
                          }
                        }
                      },
                    ),
                  ),
                if (_selectedVanId != null)
                  IconButton(
                    tooltip: t.distributionVanEdit,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () {
                      final row = _vans.cast<dynamic>().map((raw) => Map<String, dynamic>.from(raw as Map)).firstWhere(
                            (m) => m['id'] == _selectedVanId,
                            orElse: () => <String, dynamic>{},
                          );
                      if (row.isNotEmpty) _showVanDialog(existing: row);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showTransferDialog(load: true),
                  icon: const Icon(Icons.upload),
                  label: Text(t.distributionVanLoad),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showTransferDialog(load: false),
                  icon: const Icon(Icons.download),
                  label: Text(t.distributionVanUnload),
                ),
              ),
            ],
          ),
          if (vanId != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final bytes = await widget.service.downloadVanLoadingListPdf(
                    businessId: widget.businessId,
                    vanId: int.parse('$vanId'),
                  );
                  await BytesExportService.export(
                    bytes: bytes,
                    filename: 'distribution_van_loading_$vanId.pdf',
                    mimeType: 'application/pdf',
                  );
                  if (mounted) {
                    SnackBarHelper.showSuccess(context, message: t.distributionPdfExported);
                  }
                } catch (e) {
                  if (mounted) {
                    SnackBarHelper.showError(
                      context,
                      message: ErrorExtractor.forContext(e, context),
                    );
                  }
                }
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(t.distributionPrintLoadingList),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            vanId == null ? t.distributionVanStock : '${t.distributionVanStock} · #$vanId',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (vanId == null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(t.distributionNoVanAssigned),
              ),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(t.distributionVanStockEmpty)),
            )
          else
            ...items.map((raw) {
              final m = Map<String, dynamic>.from(raw as Map);
              return Card(
                child: ListTile(
                  title: Text(m['product_name']?.toString() ?? 'product ${m['product_id']}'),
                  trailing: Text('× ${m['quantity'] ?? 0}'),
                ),
              );
            }),
        ],
      ),
    );
  }
}
