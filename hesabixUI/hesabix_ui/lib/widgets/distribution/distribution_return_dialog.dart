import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';

import '../../services/distribution_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'distribution_field_helpers.dart';

class _ReturnLineRow {
  Map<String, dynamic>? product;
  final TextEditingController qtyCtl = TextEditingController(text: '1');
  String reasonCode = 'damaged';
  final TextEditingController noteCtl = TextEditingController();

  void dispose() {
    qtyCtl.dispose();
    noteCtl.dispose();
  }

  Map<String, dynamic> toPayload() {
    final pid = product!['id'];
    return {
      'product_id': pid is int ? pid : int.parse('$pid'),
      'quantity': double.tryParse(qtyCtl.text.trim().replaceAll(',', '.')) ?? 1,
      'reason_code': reasonCode,
      'reason': [
        reasonCode,
        if (noteCtl.text.trim().isNotEmpty) noteCtl.text.trim(),
      ].join(' · '),
    };
  }
}

Future<void> showDistributionReturnDialog({
  required BuildContext context,
  required int businessId,
  required DistributionService service,
  Person? initialPerson,
  int? visitId,
  required VoidCallback onSubmitted,
}) async {
  final t = AppLocalizations.of(context);
  Person? person = initialPerson;
  final lines = <_ReturnLineRow>[_ReturnLineRow()];
  final noteCtl = TextEditingController();
  List<Map<String, dynamic>> invoices = const [];
  int? sourceDocumentId;

  Future<void> loadInvoices(void Function(void Function()) setD) async {
    if (person == null) {
      setD(() {
        invoices = const [];
        sourceDocumentId = null;
      });
      return;
    }
    try {
      final personId = person!.id;
      if (personId == null) {
        setD(() {
          invoices = const [];
          sourceDocumentId = null;
        });
        return;
      }
      final items = await service.listPersonInvoices(businessId: businessId, personId: personId);
      setD(() {
        invoices = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {
      setD(() => invoices = const []);
    }
  }

  await showGlassDialog<void>(
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
                    onChanged: (p) async {
                      setD(() => person = p);
                      await loadInvoices(setD);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (person != null)
                    DropdownButtonFormField<int?>(
                      value: sourceDocumentId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: t.distributionSourceInvoice,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem<int?>(value: null, child: Text(t.distributionNoInvoiceLink)),
                        ...invoices.map(
                          (inv) => DropdownMenuItem<int?>(
                            value: int.tryParse('${inv['id']}'),
                            child: Text(
                              '${inv['code'] ?? inv['id']} · ${inv['net'] ?? ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setD(() => sourceDocumentId = v),
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
                                if (lines.length > 1)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () {
                                      setD(() {
                                        lines[i].dispose();
                                        lines.removeAt(i);
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: row.reasonCode,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: t.distributionReturnReason,
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: distributionReturnCodes
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(distributionReturnReasonLabel(t, c)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setD(() => row.reasonCode = v ?? row.reasonCode),
                            ),
                            if (row.reasonCode == 'other') ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: row.noteCtl,
                                decoration: InputDecoration(
                                  labelText: t.distributionNotesLabel,
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  TextButton.icon(
                    onPressed: () => setD(() => lines.add(_ReturnLineRow())),
                    icon: const Icon(Icons.add),
                    label: Text(t.distributionReturnAddLine),
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
                      if (visitId != null) 'visit_id': visitId,
                      if (sourceDocumentId != null) 'source_document_id': sourceDocumentId,
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
