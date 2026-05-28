import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';

import '../../services/distribution_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class _ReturnLineRow {
  Map<String, dynamic>? product;
  final TextEditingController qtyCtl = TextEditingController(text: '1');
  final TextEditingController reasonCtl = TextEditingController();

  void dispose() {
    qtyCtl.dispose();
    reasonCtl.dispose();
  }

  Map<String, dynamic> toPayload() {
    final pid = product!['id'];
    return {
      'product_id': pid is int ? pid : int.parse('$pid'),
      'quantity': double.tryParse(qtyCtl.text.trim().replaceAll(',', '.')) ?? 1,
      if (reasonCtl.text.trim().isNotEmpty) 'reason': reasonCtl.text.trim(),
    };
  }
}

Future<void> showDistributionReturnDialog({
  required BuildContext context,
  required int businessId,
  required DistributionService service,
  Person? initialPerson,
  required VoidCallback onSubmitted,
}) async {
  final t = AppLocalizations.of(context);
  Person? person = initialPerson;
  final lines = <_ReturnLineRow>[_ReturnLineRow()];
  final noteCtl = TextEditingController();

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setD) {
        return AlertDialog(
          title: Text(t.distributionReturnCreate),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PersonComboboxWidget(
                    businessId: businessId,
                    selectedPerson: person,
                    label: t.distributionSelectPerson,
                    hintText: t.distributionSelectPerson,
                    isRequired: true,
                    onChanged: (p) => setD(() => person = p),
                  ),
                  const SizedBox(height: 12),
                  ...lines.asMap().entries.map((e) {
                    final i = e.key;
                    final row = e.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            ProductComboboxWidget(
                              businessId: businessId,
                              selectedProduct: row.product,
                              label: t.distributionSelectProduct,
                              onChanged: (p) => setD(() => row.product = p),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: row.qtyCtl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: t.distributionReturnQuantity,
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: row.reasonCtl,
                                    decoration: InputDecoration(
                                      labelText: t.distributionReturnReason,
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                if (lines.length > 1)
                                  IconButton(
                                    onPressed: () {
                                      setD(() {
                                        row.dispose();
                                        lines.removeAt(i);
                                      });
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => setD(() => lines.add(_ReturnLineRow())),
                      icon: const Icon(Icons.add),
                      label: Text(t.distributionReturnAddLine),
                    ),
                  ),
                  TextField(
                    controller: noteCtl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: t.distributionNotesLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                if (person == null) {
                  SnackBarHelper.showError(context, message: t.distributionSelectPerson);
                  return;
                }
                final validLines = lines.where((r) => r.product != null).toList();
                if (validLines.isEmpty) {
                  SnackBarHelper.showError(context, message: t.distributionSelectProduct);
                  return;
                }
                try {
                  await service.createReturnRequest(
                    businessId: businessId,
                    payload: <String, dynamic>{
                      'person_id': person!.id,
                      'lines': validLines.map((r) => r.toPayload()).toList(),
                      if (noteCtl.text.trim().isNotEmpty) 'notes': noteCtl.text.trim(),
                    },
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  for (final r in lines) {
                    r.dispose();
                  }
                  noteCtl.dispose();
                  onSubmitted();
                  if (context.mounted) {
                    SnackBarHelper.showSuccess(context, message: t.distributionReturnCreate);
                  }
                } catch (e) {
                  if (context.mounted) {
                    SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                  }
                }
              },
              child: Text(t.distributionReturnCreate),
            ),
          ],
        );
      },
    ),
  );
}
