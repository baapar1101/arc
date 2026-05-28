import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/api_client.dart';
import '../../services/business_storage_service.dart';
import '../../services/distribution_service.dart';
import '../../utils/distribution_location_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import '../invoice/product_combobox_widget.dart';

/// پایان ویزیت میدانی — چک‌لیست، فروش ون، عکس، GPS پایان.
Future<void> showDistributionVisitCompleteSheet({
  required BuildContext context,
  required int businessId,
  required int visitId,
  int? personId,
  required DistributionService service,
  required VoidCallback onCompleted,
  List<dynamic> checklistTemplate = const [],
  bool enableVanSales = false,
}) async {
  final t = AppLocalizations.of(context);
  String outcome = 'order';
  final docCtl = TextEditingController();
  final dealCtl = TextEditingController();
  final reasonCtl = TextEditingController();
  final noteCtl = TextEditingController();
  final checklistState = <String, bool>{};
  for (final raw in checklistTemplate) {
    if (raw is Map) {
      final id = '${raw['id'] ?? raw['label']}';
      checklistState[id] = false;
    }
  }
  final vanLines = <Map<String, dynamic>>[];
  int? shelfPhotoFileId;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          top: 8,
        ),
        child: StatefulBuilder(
          builder: (context, setModal) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.distributionCompleteVisit, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'order',
                        label: Text(t.distributionOutcomeOrder),
                        icon: const Icon(Icons.receipt_long),
                      ),
                      ButtonSegment(
                        value: 'no_order',
                        label: Text(t.distributionOutcomeNoOrder),
                        icon: const Icon(Icons.remove_shopping_cart_outlined),
                      ),
                    ],
                    selected: {outcome},
                    onSelectionChanged: (s) => setModal(() => outcome = s.first),
                  ),
                  if (checklistState.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(t.distributionChecklistTitle, style: Theme.of(context).textTheme.titleSmall),
                    ...checklistTemplate.map((raw) {
                      final m = Map<String, dynamic>.from(raw as Map);
                      final id = '${m['id'] ?? m['label']}';
                      final label = m['label']?.toString() ?? id;
                      final required = m['required'] == true;
                      return CheckboxListTile(
                        value: checklistState[id] ?? false,
                        onChanged: (v) => setModal(() => checklistState[id] = v ?? false),
                        title: Text(required ? '$label *' : label),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  if (personId != null) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push('/business/$businessId/invoice/new?person_id=$personId');
                      },
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                      label: Text(t.distributionCreateSalesInvoice),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (enableVanSales && outcome == 'order') ...[
                    Text(t.distributionVanSaleLines, style: Theme.of(context).textTheme.titleSmall),
                    ...vanLines.asMap().entries.map((e) {
                      final ln = e.value;
                      return ListTile(
                        dense: true,
                        title: Text('product ${ln['product_id']} × ${ln['quantity']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setModal(() => vanLines.removeAt(e.key)),
                        ),
                      );
                    }),
                    OutlinedButton.icon(
                      onPressed: () async {
                        Map<String, dynamic>? product;
                        final qtyCtl = TextEditingController(text: '1');
                        await showDialog<void>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            title: Text(t.distributionVanSaleLines),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ProductComboboxWidget(
                                  businessId: businessId,
                                  label: t.distributionSelectProduct,
                                  onChanged: (p) => product = p,
                                ),
                                TextField(
                                  controller: qtyCtl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: t.distributionReturnQuantity,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dctx), child: Text(t.cancel)),
                              FilledButton(
                                onPressed: () {
                                  if (product == null) return;
                                  final pid = product!['id'];
                                  setModal(() {
                                    vanLines.add({
                                      'product_id': pid is int ? pid : int.parse('$pid'),
                                      'quantity': double.tryParse(qtyCtl.text) ?? 1,
                                    });
                                  });
                                  Navigator.pop(dctx);
                                },
                                child: Text(t.save),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: Text(t.distributionReturnAddLine),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () async {
                      final pick = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        withData: true,
                      );
                      if (pick == null || pick.files.isEmpty) return;
                      final f = pick.files.first;
                      if (f.bytes == null) return;
                      try {
                        final uploaded = await BusinessStorageService(ApiClient()).uploadFile(
                          businessId: businessId,
                          fileBytes: f.bytes!,
                          filename: f.name,
                          moduleContext: 'distribution',
                          contextId: '$visitId',
                        );
                        setModal(() => shelfPhotoFileId = uploaded['id'] as int?);
                        if (context.mounted) {
                          SnackBarHelper.showSuccess(context, message: t.distributionShelfPhoto);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                        }
                      }
                    },
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(
                      shelfPhotoFileId != null ? '${t.distributionShelfPhoto} ✓' : t.distributionShelfPhoto,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: docCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t.distributionDocumentIdHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dealCtl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t.distributionDealIdHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (outcome == 'no_order') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonCtl,
                      decoration: InputDecoration(
                        labelText: t.distributionNoOrderReason,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: t.distributionNotesLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      for (final raw in checklistTemplate) {
                        final m = Map<String, dynamic>.from(raw as Map);
                        if (m['required'] == true) {
                          final id = '${m['id'] ?? m['label']}';
                          if (checklistState[id] != true) {
                            SnackBarHelper.showError(context, message: t.distributionChecklistTitle);
                            return;
                          }
                        }
                      }
                      final endLoc = await readDistributionVisitLocation();
                      final payload = <String, dynamic>{
                        'outcome': outcome,
                        if (docCtl.text.trim().isNotEmpty) 'document_id': int.tryParse(docCtl.text.trim()),
                        if (dealCtl.text.trim().isNotEmpty) 'deal_id': int.tryParse(dealCtl.text.trim()),
                        if (noteCtl.text.trim().isNotEmpty) 'notes': noteCtl.text.trim(),
                        if (outcome == 'no_order' && reasonCtl.text.trim().isNotEmpty)
                          'no_order_reason': reasonCtl.text.trim(),
                        if (endLoc.latitude != null) 'end_latitude': endLoc.latitude,
                        if (endLoc.longitude != null) 'end_longitude': endLoc.longitude,
                        if (checklistState.isNotEmpty) 'checklist_answers': checklistState,
                        if (shelfPhotoFileId != null) 'shelf_photo_file_id': shelfPhotoFileId,
                        if (enableVanSales && outcome == 'order' && vanLines.isNotEmpty)
                          'van_sale_lines': vanLines,
                      };
                      try {
                        await service.completeVisit(
                          businessId: businessId,
                          visitId: visitId,
                          payload: payload,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        onCompleted();
                        if (context.mounted) {
                          SnackBarHelper.showSuccess(context, message: t.distributionCompleteVisit);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                        }
                      }
                    },
                    child: Text(t.distributionCompleteVisit),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
