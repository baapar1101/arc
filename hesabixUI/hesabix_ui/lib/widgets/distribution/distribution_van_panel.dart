import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/business_user_model.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_form_helpers.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_van_transfer_sheet.dart';

/// تب ون: موجودی، ساخت، بارگیری و تخلیه.
class DistributionVanPanel extends StatefulWidget {
  final int businessId;
  final DistributionService service;
  final bool enableVanSales;
  final bool canManage;
  final AuthStore? authStore;

  const DistributionVanPanel({
    super.key,
    required this.businessId,
    required this.service,
    required this.enableVanSales,
    required this.canManage,
    this.authStore,
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
    final plateCtl = TextEditingController(text: existing?['plate_number']?.toString() ?? '');
    final weightCtl = TextEditingController(text: existing?['max_weight_kg']?.toString() ?? '');
    final volumeCtl = TextEditingController(text: existing?['max_volume_m3']?.toString() ?? '');
    int? userId = int.tryParse('${existing?['user_id'] ?? ''}');
    List<BusinessUser> users = const [];
    try {
      final res = await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId);
      users = res.users;
    } catch (_) {}

    if (!mounted) return;
    final editing = existing != null;
    await showGlassDialog<void>(
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
              TextField(
                controller: plateCtl,
                decoration: InputDecoration(
                  labelText: t.distributionVanPlate,
                  border: const OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: weightCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: t.distributionWeightKg,
                  border: const OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: volumeCtl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: t.distributionVolumeM3,
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
                final payload = <String, dynamic>{
                  'name': name,
                  'user_id': userId,
                  'plate_number': plateCtl.text.trim().isEmpty ? null : plateCtl.text.trim(),
                  'max_weight_kg': double.tryParse(weightCtl.text.trim().replaceAll(',', '.')),
                  'max_volume_m3': double.tryParse(volumeCtl.text.trim().replaceAll(',', '.')),
                };
                try {
                  if (editing) {
                    await widget.service.updateVan(
                      businessId: widget.businessId,
                      vanId: int.parse('${existing['id']}'),
                      payload: payload,
                    );
                  } else {
                    await widget.service.createVan(
                      businessId: widget.businessId,
                      payload: {
                        'code': nextDistributionCode('VAN', _vans),
                        ...payload,
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

  int? get _activeVanId {
    final selected = _selectedVanId ?? _myStock?['van_id'];
    if (selected is int) return selected;
    return int.tryParse('$selected');
  }

  String? get _activeVanName {
    final id = _activeVanId;
    for (final raw in _vans) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (m['id'] == id) return distributionEntityLabel(m);
    }
    return id != null ? '#$id' : null;
  }

  List<Map<String, dynamic>> get _stockItems {
    return ((_myStock?['items'] as List?) ?? [])
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList();
  }

  Map<String, dynamic> get _capacity {
    final cap = _myStock?['capacity'];
    return cap is Map ? Map<String, dynamic>.from(cap) : <String, dynamic>{};
  }

  Widget _capacityCard(AppLocalizations t, ThemeData theme, ColorScheme cs) {
    final cap = _capacity;
    final plate = (_myStock?['plate_number'] ?? '').toString();
    final weight = cap['weight_kg'];
    final maxW = cap['max_weight_kg'] ?? _myStock?['max_weight_kg'];
    final volume = cap['volume_m3'];
    final maxV = cap['max_volume_m3'] ?? _myStock?['max_volume_m3'];
    final wPct = cap['weight_util_percent'];
    final vPct = cap['volume_util_percent'];
    final over = cap['over_capacity'] == true;
    final nearLots = cap['near_expiry_lots'] ?? 0;
    if (plate.isEmpty && maxW == null && maxV == null && nearLots == 0 && weight == null) {
      return const SizedBox.shrink();
    }
    return Card(
      color: over ? cs.errorContainer.withValues(alpha: 0.45) : cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.distributionVanCapacity, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            if (plate.isNotEmpty) Text('${t.distributionVanPlate}: $plate'),
            if (maxW != null)
              Text('${t.distributionCapacityUsed}: ${weight ?? 0} / $maxW kg${wPct != null ? ' ($wPct%)' : ''}'),
            if (maxV != null)
              Text('${t.distributionVolumeM3}: ${volume ?? 0} / $maxV${vPct != null ? ' ($vPct%)' : ''}'),
            if (nearLots is num && nearLots > 0)
              Text('${t.distributionNearExpiry}: $nearLots'),
            const SizedBox(height: 4),
            Text(t.distributionFefoHint, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            if (over)
              Text(t.distributionCapacityOver, style: theme.textTheme.bodySmall?.copyWith(color: cs.error)),
          ],
        ),
      ),
    );
  }

  Future<void> _openTransfer({required bool load}) async {
    final t = AppLocalizations.of(context);
    final vanId = _activeVanId;
    if (vanId == null) {
      SnackBarHelper.showError(context, message: t.distributionNoVanAssigned);
      return;
    }
    if (!load && _stockItems.isEmpty) {
      SnackBarHelper.showError(context, message: t.distributionVanEmptyStockUnload);
      return;
    }
    final saved = await showDistributionVanTransferSheet(
      context: context,
      businessId: widget.businessId,
      service: widget.service,
      vanId: vanId,
      load: load,
      vanName: _activeVanName,
      authStore: widget.authStore,
      vanStockItems: _stockItems,
    );
    if (!mounted) return;
    if (saved) {
      await _reload();
      if (mounted) {
        SnackBarHelper.showSuccess(context, message: t.distributionSettingsSaved);
      }
    }
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
    final vanId = _activeVanId;
    final items = _stockItems;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final vanName = _activeVanName;

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
                child: _VanActionCard(
                  icon: Icons.north_east,
                  color: cs.primary,
                  title: t.distributionVanLoad,
                  subtitle: t.distributionVanLoadHint,
                  onTap: () => _openTransfer(load: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _VanActionCard(
                  icon: Icons.south_west,
                  color: cs.tertiary,
                  title: t.distributionVanUnload,
                  subtitle: t.distributionVanUnloadHint,
                  onTap: () => _openTransfer(load: false),
                ),
              ),
            ],
          ),
          if (vanId != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final bytes = await widget.service.downloadVanLoadingListPdf(
                    businessId: widget.businessId,
                    vanId: vanId,
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
          const SizedBox(height: 20),
          _capacityCard(t, theme, cs),
          const SizedBox(height: 12),
          Text(
            vanName == null ? t.distributionVanStock : '${t.distributionVanStock} · $vanName',
            style: theme.textTheme.titleMedium,
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 40, color: cs.outline),
                    const SizedBox(height: 8),
                    Text(t.distributionVanStockEmpty, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _openTransfer(load: true),
                      icon: const Icon(Icons.north_east),
                      label: Text(t.distributionVanLoad),
                    ),
                  ],
                ),
              ),
            )
          else
            ...items.map((m) {
              final lots = (m['lots'] is List) ? m['lots'] as List : const [];
              final near = m['near_expiry'] == true;
              final variance = double.tryParse('${m['lot_variance'] ?? 0}') ?? 0;
              final subtitleParts = <String>[
                if (near) t.distributionNearExpiry,
                if (lots.isNotEmpty) '${lots.length} lot',
                if (variance.abs() > 0.001) '${t.distributionLotVariance}: ${variance.toStringAsFixed(1)}',
              ];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: near ? cs.errorContainer : cs.primaryContainer,
                    child: Icon(
                      near ? Icons.warning_amber_outlined : Icons.inventory_2_outlined,
                      color: near ? cs.onErrorContainer : cs.onPrimaryContainer,
                    ),
                  ),
                  title: Text(m['product_name']?.toString() ?? 'product ${m['product_id']}'),
                  subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' · ')),
                  trailing: Text(
                    '× ${m['quantity'] ?? 0}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _VanActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _VanActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 10),
              Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
