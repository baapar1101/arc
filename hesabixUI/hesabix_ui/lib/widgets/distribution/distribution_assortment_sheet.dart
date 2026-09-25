import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';

Future<void> showDistributionAssortmentSheet({
  required BuildContext context,
  required int businessId,
  required DistributionService service,
}) async {
  await showGlassModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AssortmentSheet(businessId: businessId, service: service),
  );
}

class _AssortmentSheet extends StatefulWidget {
  const _AssortmentSheet({required this.businessId, required this.service});
  final int businessId;
  final DistributionService service;

  @override
  State<_AssortmentSheet> createState() => _AssortmentSheetState();
}

class _AssortmentSheetState extends State<_AssortmentSheet> {
  List<dynamic> _items = const [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final items = await widget.service.listAssortments(businessId: widget.businessId);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final nameCtl = TextEditingController(text: existing?['name']?.toString() ?? '');
    var outlet = (existing?['outlet_type'] ?? 'grocery').toString();
    final must = <int>{
      ...((existing?['must_sell_product_ids'] as List?) ?? [])
          .map((e) => int.tryParse('$e'))
          .whereType<int>(),
    };
    final names = <int, String>{};
    await showGlassDialog<void>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(existing == null ? t.distributionAssortmentCreate : t.distributionAssortment),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtl,
                    decoration: InputDecoration(
                      labelText: t.distributionAssortment,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: outlet,
                    decoration: InputDecoration(
                      labelText: t.distributionOutletType,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'grocery', child: Text(t.distributionOutletGrocery)),
                      DropdownMenuItem(value: 'supermarket', child: Text(t.distributionOutletSupermarket)),
                      DropdownMenuItem(value: 'horeca', child: Text(t.distributionOutletHoreca)),
                      DropdownMenuItem(value: 'kiosk', child: Text(t.distributionOutletKiosk)),
                      DropdownMenuItem(value: 'wholesale', child: Text(t.distributionOutletWholesale)),
                      DropdownMenuItem(value: 'other', child: Text(t.distributionOutletOther)),
                    ],
                    onChanged: (v) => setD(() => outlet = v ?? outlet),
                  ),
                  const SizedBox(height: 10),
                  ProductComboboxWidget(
                    businessId: widget.businessId,
                    label: t.distributionMustSellPick,
                    onChanged: (p) {
                      final id = int.tryParse('${p?['id']}');
                      if (id == null) return;
                      setD(() {
                        must.add(id);
                        names[id] = '${p?['name'] ?? id}';
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  ...must.map(
                    (id) => ListTile(
                      dense: true,
                      title: Text(names[id] ?? '#$id'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setD(() => must.remove(id)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                if (nameCtl.text.trim().isEmpty) return;
                try {
                  await widget.service.upsertAssortment(
                    businessId: widget.businessId,
                    assortmentId: existing == null ? null : int.tryParse('${existing['id']}'),
                    payload: {
                      'name': nameCtl.text.trim(),
                      'outlet_type': outlet,
                      'must_sell_product_ids': must.toList(),
                      'product_ids': must.toList(),
                      'is_active': true,
                    },
                  );
                  if (dctx.mounted) Navigator.pop(dctx);
                  await _reload();
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.distributionAssortmentsTitle, style: Theme.of(context).textTheme.titleLarge)),
                FilledButton.tonalIcon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add),
                  label: Text(t.distributionAssortmentCreate),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_items.isEmpty)
              Expanded(child: Center(child: Text(t.distributionAssortmentEmpty)))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final m = Map<String, dynamic>.from(_items[i] as Map);
                    final must = (m['must_sell_product_ids'] as List?) ?? const [];
                    return Card(
                      child: ListTile(
                        title: Text('${m['name'] ?? m['code'] ?? m['id']}'),
                        subtitle: Text('${m['outlet_type'] ?? '—'} · ${t.distributionMustSell}: ${must.length}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _edit(existing: m),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
