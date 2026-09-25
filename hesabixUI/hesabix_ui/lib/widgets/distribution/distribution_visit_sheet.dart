import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/widgets/invoice/product_combobox_widget.dart';

import '../../core/api_client.dart';
import '../../services/business_storage_service.dart';
import '../../services/bytes_export/bytes_export_service.dart';
import '../../services/distribution_service.dart';
import '../../services/invoice_service.dart';
import '../../utils/distribution_location_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';
import 'distribution_customer_360_card.dart';
import 'distribution_field_helpers.dart';
import 'distribution_form_helpers.dart';
import 'distribution_signature_pad.dart';

/// پایان ویزیت میدانی — ویزارد سه‌مرحله‌ای: نتیجه، فروش، تحویل.
Future<void> showDistributionVisitCompleteSheet({
  required BuildContext context,
  required int businessId,
  required int visitId,
  int? personId,
  required DistributionService service,
  required VoidCallback onCompleted,
  List<dynamic> checklistTemplate = const [],
  bool enableVanSales = false,
  bool enablePresell = false,
  bool enableSuggestedOrder = true,
  bool enablePromotions = false,
  bool autoApplyPromotions = true,
  bool requirePodSignature = false,
  bool requirePodPhoto = false,
  bool enablePerfectStore = true,
  String navProvider = 'neshan',
  Future<void> Function(Map<String, dynamic> payload)? onOfflineEnqueue,
}) async {
  final t = AppLocalizations.of(context);
  var step = 0;
  String outcome = 'order';
  /// van | presell | invoice
  String saleMode = enableVanSales ? 'van' : (enablePresell ? 'presell' : 'invoice');
  int? linkedDocumentId;
  String? linkedDocumentLabel;
  String? noOrderCode;
  final noteCtl = TextEditingController();
  final checklistState = <String, bool>{};
  for (final raw in checklistTemplate) {
    if (raw is Map) {
      final id = '${raw['id'] ?? raw['label']}';
      checklistState[id] = false;
    }
  }
  final vanLines = <Map<String, dynamic>>[];
  final presellLines = <Map<String, dynamic>>[];
  int? shelfPhotoFileId;
  List<Map<String, dynamic>> vanStock = const [];
  List<Map<String, dynamic>> recentInvoices = const [];
  List<Map<String, dynamic>> suggestedLines = const [];
  List<Map<String, dynamic>> activePromos = const [];
  final selectedPromoIds = <int>{};
  Map<String, dynamic>? creditSummary;
  var loadingExtras = true;
  var submitting = false;
  var podConfirmed = requirePodSignature || requirePodPhoto;
  final podNameCtl = TextEditingController();
  final podNoteCtl = TextEditingController();
  String? podSignaturePng;
  int? podPhotoFileId;
  var shelfFacingOk = true;
  var shelfPriceOk = true;
  var shelfStockOk = true;
  var osaOk = true;
  var planogramOk = true;
  double shareOfShelf = 70;

  Future<void> loadExtras(void Function(void Function()) setModal) async {
    try {
      final futures = <Future>[];
      if (enableVanSales) {
        futures.add(service.getMyVanStock(businessId: businessId).then((d) {
          final items = d['items'];
          vanStock = items is List
              ? items.map((e) => Map<String, dynamic>.from(e as Map)).toList()
              : const [];
        }));
      }
      if (personId != null) {
        futures.add(service.listPersonInvoices(businessId: businessId, personId: personId).then((items) {
          recentInvoices = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }));
        futures.add(service.getPersonCreditSummary(businessId: businessId, personId: personId).then((d) {
          creditSummary = d;
        }));
        if (enableSuggestedOrder) {
          futures.add(service.getSuggestedOrder(businessId: businessId, personId: personId).then((d) {
            final lines = d['lines'];
            suggestedLines = lines is List
                ? lines.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                : const [];
          }));
        }
      }
      if (enablePromotions) {
        futures.add(service.listPromotions(businessId: businessId).then((items) {
          activePromos = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          if (autoApplyPromotions) {
            for (final p in activePromos) {
              final id = int.tryParse('${p['id']}');
              if (id != null) selectedPromoIds.add(id);
            }
          }
        }));
      }
      await Future.wait(futures);
    } catch (_) {
      // اختیاری — UI بدون داده هم کار می‌کند
    } finally {
      setModal(() => loadingExtras = false);
    }
  }

  bool validateChecklist(BuildContext ctx) {
    for (final raw in checklistTemplate) {
      final m = Map<String, dynamic>.from(raw as Map);
      if (m['required'] == true) {
        final id = '${m['id'] ?? m['label']}';
        if (checklistState[id] != true) {
          SnackBarHelper.showError(ctx, message: t.distributionChecklistTitle);
          return false;
        }
      }
    }
    return true;
  }

  bool creditBlocksVanSale() {
    return creditSummary != null &&
        creditSummary!['credit_check_enabled'] == true &&
        creditSummary!['blocked'] == true;
  }

  Future<void> submitVisit(BuildContext sheetCtx, BuildContext rootCtx) async {
    if (!validateChecklist(rootCtx)) return;
    if (outcome == 'no_order') {
      if (noOrderCode == null || noOrderCode!.isEmpty) {
        SnackBarHelper.showError(rootCtx, message: t.distributionReasonRequired);
        return;
      }
    }
    if (outcome == 'order' && (requirePodSignature || requirePodPhoto || podConfirmed)) {
      if (podNameCtl.text.trim().length < 2) {
        SnackBarHelper.showError(rootCtx, message: t.distributionPodSignerRequired);
        return;
      }
      if (requirePodSignature && (podSignaturePng == null || podSignaturePng!.length < 40)) {
        SnackBarHelper.showError(rootCtx, message: t.distributionPodSignatureRequired);
        return;
      }
      if (requirePodPhoto && podPhotoFileId == null && shelfPhotoFileId == null) {
        SnackBarHelper.showError(rootCtx, message: t.distributionPodPhotoRequired);
        return;
      }
    }
    if (outcome == 'order' && creditBlocksVanSale() && (vanLines.isNotEmpty || (saleMode == 'presell' && presellLines.isNotEmpty))) {
      SnackBarHelper.showError(rootCtx, message: t.distributionCustomerCreditBlocked);
      return;
    }

    final saleLines = saleMode == 'van' ? vanLines : presellLines;
    final missingMust = suggestedLines
        .where((s) => s['must_sell'] == true)
        .where((s) => !saleLines.any((e) => e['product_id'] == int.tryParse('${s['product_id']}')))
        .toList();
    if (outcome == 'order' && missingMust.isNotEmpty && (saleMode == 'van' || saleMode == 'presell')) {
      SnackBarHelper.showError(rootCtx, message: t.distributionMustSellMissing);
      return;
    }

    final endLoc = await readDistributionVisitLocation();
    final extra = <String, dynamic>{
      if (selectedPromoIds.isNotEmpty) 'promotion_ids': selectedPromoIds.toList(),
      'lines_count': saleLines.length,
      if (noOrderCode != null) 'no_order_reason_code': noOrderCode,
    };
    final payload = <String, dynamic>{
      'outcome': outcome,
      if (linkedDocumentId != null) 'document_id': linkedDocumentId,
      if (noteCtl.text.trim().isNotEmpty) 'notes': noteCtl.text.trim(),
      if (outcome == 'no_order') ...{
        'no_order_reason_code': noOrderCode,
        'no_order_reason': distributionNoOrderReasonLabel(t, noOrderCode ?? 'other'),
      },
      if (endLoc.latitude != null) 'end_latitude': endLoc.latitude,
      if (endLoc.longitude != null) 'end_longitude': endLoc.longitude,
      if (checklistState.isNotEmpty) 'checklist_answers': checklistState,
      if (shelfPhotoFileId != null) 'shelf_photo_file_id': shelfPhotoFileId,
      if (enableVanSales && saleMode == 'van' && outcome == 'order' && vanLines.isNotEmpty)
        'van_sale_lines': vanLines
            .map(
              (ln) => {
                'product_id': ln['product_id'],
                'quantity': ln['quantity'],
                if (ln['unit_price'] != null) 'unit_price': ln['unit_price'],
                if (ln['tax_rate'] != null) 'tax_rate': ln['tax_rate'],
                if (ln['line_discount'] != null) 'line_discount': ln['line_discount'],
              },
            )
            .toList(),
      'extra_info': extra,
      if (outcome == 'order' && (podConfirmed || requirePodSignature || requirePodPhoto)) ...{
        'pod_confirmed': true,
        'pod_signer_name': podNameCtl.text.trim(),
        if (podNoteCtl.text.trim().isNotEmpty) 'pod_note': podNoteCtl.text.trim(),
        if (podSignaturePng != null) 'pod_signature_png': podSignaturePng,
        if (podPhotoFileId != null) 'pod_photo_file_id': podPhotoFileId,
      },
    };

    try {
      // پیش‌فروش: ابتدا سفارش، سپس تکمیل ویزیت
      if (enablePresell && saleMode == 'presell' && outcome == 'order' && personId != null && presellLines.isNotEmpty) {
        final orderPayload = <String, dynamic>{
          'person_id': personId,
          'visit_id': visitId,
          'lines': presellLines
              .map(
                (ln) => {
                  'product_id': ln['product_id'],
                  'quantity': ln['quantity'],
                  if (ln['unit_price'] != null) 'unit_price': ln['unit_price'],
                  if (ln['line_discount'] != null) 'line_discount': ln['line_discount'],
                },
              )
              .toList(),
          if (selectedPromoIds.isNotEmpty) 'promotion_ids': selectedPromoIds.toList(),
          'confirm': true,
        };
        try {
          final order = await service.createOrder(businessId: businessId, payload: orderPayload);
          if (order['document_id'] != null) {
            payload['document_id'] = order['document_id'];
          }
          payload['extra_info'] = {
            ...?payload['extra_info'] as Map?,
            'presell_order_id': order['id'],
          };
        } catch (e) {
          final msg = ErrorExtractor.forContext(e, rootCtx);
          if (onOfflineEnqueue != null && !msg.contains('CREDIT') && !msg.contains('اعتبار')) {
            // C3: سفارش + تکمیل ویزیت به‌صورت یک عمل آفلاین ترکیبی
            await onOfflineEnqueue({
              'op_hint': 'complete_visit_with_presell',
              'order': orderPayload,
              'visit': {
                'visit_id': visitId,
                ...payload,
              },
            });
            if (personId != null) {
              try {
          await service.createShelfAudit(
            businessId: businessId,
            payload: {
              'person_id': personId,
              'visit_id': visitId,
              'answers': {
                'facing_ok': shelfFacingOk,
                'price_ok': shelfPriceOk,
                'stock_ok': shelfStockOk,
                'shelf_facing': shelfFacingOk,
                'price_tag': shelfPriceOk,
                'osa': osaOk,
                'planogram': planogramOk,
                'share_of_shelf': shareOfShelf,
              },
              if (shelfPhotoFileId != null) 'photo_file_ids': [shelfPhotoFileId],
            },
          );
              } catch (_) {}
            }
            if (sheetCtx.mounted) Navigator.pop(sheetCtx);
            onCompleted();
            if (rootCtx.mounted) {
              SnackBarHelper.showSuccess(rootCtx, message: t.distributionOfflineQueued);
            }
            return;
          }
          if (rootCtx.mounted) {
            SnackBarHelper.showError(rootCtx, message: msg);
          }
          return;
        }
      }

      await service.completeVisit(
        businessId: businessId,
        visitId: visitId,
        payload: payload,
      );
      if (personId != null) {
        try {
          await service.createShelfAudit(
            businessId: businessId,
            payload: {
              'person_id': personId,
              'visit_id': visitId,
              'answers': {
                'facing_ok': shelfFacingOk,
                'price_ok': shelfPriceOk,
                'stock_ok': shelfStockOk,
                'shelf_facing': shelfFacingOk,
                'price_tag': shelfPriceOk,
                'osa': osaOk,
                'planogram': planogramOk,
                'share_of_shelf': shareOfShelf,
              },
              if (shelfPhotoFileId != null) 'photo_file_ids': [shelfPhotoFileId],
            },
          );
        } catch (_) {
          // امتیاز قفسه اختیاری است
        }
      }
      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
      onCompleted();
      if (rootCtx.mounted) {
        SnackBarHelper.showSuccess(rootCtx, message: t.distributionCompleteVisit);
        final docId = payload['document_id'] is int
            ? payload['document_id'] as int
            : int.tryParse('${payload['document_id'] ?? ''}');
        if (docId != null && docId > 0) {
          try {
            final bytes = await InvoiceService(apiClient: ApiClient()).downloadInvoicePdf(
              businessId: businessId,
              invoiceId: docId,
            );
            await BytesExportService.export(
              bytes: bytes,
              filename: 'distribution_invoice_$docId.pdf',
              mimeType: 'application/pdf',
            );
          } catch (_) {}
        }
      }
    } catch (e) {
      final msg = ErrorExtractor.forContext(e, rootCtx);
      final friendly = msg.contains('CREDIT_LIMIT') || msg.contains('CREDIT_AUTO')
          ? t.distributionCustomerCreditBlocked
          : msg;
      if (onOfflineEnqueue != null && !msg.contains('CREDIT') && !msg.contains('اعتبار')) {
        await onOfflineEnqueue({
          'visit_id': visitId,
          ...payload,
        });
        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
        onCompleted();
      }
      if (rootCtx.mounted) {
        SnackBarHelper.showError(rootCtx, message: friendly);
      }
    }
  }

  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final sheetH = MediaQuery.of(ctx).size.height * 0.88;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SizedBox(
            height: sheetH,
            child: StatefulBuilder(
              builder: (context, setModal) {
                if (loadingExtras) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (loadingExtras) loadExtras(setModal);
                  });
                }
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final stepTitles = [
                  t.distributionVisitWizardStepOutcome,
                  t.distributionVisitWizardStepSale,
                  t.distributionVisitWizardStepDelivery,
                ];

                Future<void> openVanLineDialog() async {
                  if (creditBlocksVanSale()) {
                    SnackBarHelper.showError(context, message: t.distributionCustomerCreditBlocked);
                    return;
                  }
                  Map<String, dynamic>? selected;
                  final qtyCtl = TextEditingController(text: '1');
                  try {
                    await showDialog<void>(
                      context: context,
                      builder: (dctx) => StatefulBuilder(
                        builder: (context, setD) => AlertDialog(
                          title: Text(t.distributionVanSaleFromStock),
                          content: SizedBox(
                            width: 360,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DistributionChoiceField<Map<String, dynamic>>(
                                  label: t.distributionSelectProduct,
                                  items: vanStock,
                                  selectedLabel: selected == null
                                      ? null
                                      : '${selected!['product_name']} · ${t.distributionVanStock}: ${selected!['quantity']}'
                                          '${selected!['unit_price'] != null ? ' · ${selected!['unit_price']}' : ''}',
                                  labelOf: (s) =>
                                      '${s['product_name']} · ${t.distributionVanStock}: ${s['quantity']}'
                                      '${s['unit_price'] != null ? ' · ${s['unit_price']}' : ''}'
                                      '${s['near_expiry'] == true ? ' · ${t.distributionNearExpiry}' : ''}',
                                  selectedOf: (s) =>
                                      selected != null &&
                                      int.tryParse('${s['product_id']}') ==
                                          int.tryParse('${selected!['product_id']}'),
                                  onSelected: (s) => setD(() => selected = s),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: qtyCtl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(
                                    labelText: t.distributionReturnQuantity,
                                    border: const OutlineInputBorder(),
                                    helperText: selected == null
                                        ? null
                                        : '${t.distributionVanStock}: ${selected!['quantity']}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dctx), child: Text(t.cancel)),
                            FilledButton(
                              onPressed: () {
                                if (selected == null || selected!.isEmpty) return;
                                final qty =
                                    double.tryParse(qtyCtl.text.trim().replaceAll(',', '.')) ?? 0;
                                final avail = double.tryParse('${selected!['quantity']}') ?? 0;
                                if (qty <= 0 || qty > avail + 1e-9) {
                                  SnackBarHelper.showError(
                                    context,
                                    message: t.distributionVanQtyExceedsStock,
                                  );
                                  return;
                                }
                                setModal(() {
                                  vanLines.add({
                                    'product_id': int.parse('${selected!['product_id']}'),
                                    'product_name': selected!['product_name'],
                                    'quantity': qty,
                                    'unit_price': selected!['unit_price'],
                                    'tax_rate': selected!['tax_rate'],
                                  });
                                });
                                Navigator.pop(dctx);
                              },
                              child: Text(t.save),
                            ),
                          ],
                        ),
                      ),
                    );
                  } finally {
                    qtyCtl.dispose();
                  }
                }

                Widget buildStepIndicator() {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: List.generate(3, (i) {
                          final reached = i <= step;
                          final current = i == step;
                          return Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: EdgeInsetsDirectional.only(end: i < 2 ? 6 : 0),
                              height: current ? 5 : 4,
                              decoration: BoxDecoration(
                                color: reached ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: List.generate(3, (i) {
                          final reached = i <= step;
                          final current = i == step;
                          return Expanded(
                            child: Column(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: current
                                        ? cs.primary
                                        : reached
                                            ? cs.primary.withValues(alpha: 0.14)
                                            : cs.surfaceContainerHighest,
                                    border: Border.all(
                                      color: reached ? cs.primary : cs.outlineVariant,
                                      width: current ? 0 : 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: reached && !current
                                        ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
                                        : Text(
                                            '${i + 1}',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: current ? cs.onPrimary : cs.onSurfaceVariant,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  stepTitles[i],
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                                    color: current ? cs.onSurface : cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                }

                Widget outcomeTile({
                  required String value,
                  required String label,
                  required IconData icon,
                }) {
                  final selected = outcome == value;
                  return Material(
                    color: selected
                        ? cs.primaryContainer.withValues(alpha: 0.65)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setModal(() => outcome = value),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              icon,
                              size: 32,
                              color: selected ? cs.primary : cs.onSurfaceVariant,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: selected ? cs.onPrimaryContainer : cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                Widget buildOutcomeStep() {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t.distributionVisitCompleteHint,
                        style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: outcomeTile(
                              value: 'order',
                              label: t.distributionOutcomeOrder,
                              icon: Icons.receipt_long_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: outcomeTile(
                              value: 'no_order',
                              label: t.distributionOutcomeNoOrder,
                              icon: Icons.remove_shopping_cart_outlined,
                            ),
                          ),
                        ],
                      ),
                      if (checklistState.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Text(t.distributionChecklistTitle, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
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
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          );
                        }),
                      ],
                      if (outcome == 'no_order') ...[
                        const SizedBox(height: 16),
                        Text(t.distributionNoOrderReason, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: distributionNoOrderCodes.map((code) {
                            return ChoiceChip(
                              label: Text(distributionNoOrderReasonLabel(t, code)),
                              selected: noOrderCode == code,
                              onSelected: (_) => setModal(() => noOrderCode = code),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  );
                }

                Widget buildSaleStep() {
                  if (outcome == 'no_order') {
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 36, color: cs.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(
                            t.distributionOutcomeNoOrder,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.distributionVisitWizardStepDelivery,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  }

                  final blocked = creditBlocksVanSale();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (personId != null)
                        DistributionCustomer360Card(
                          businessId: businessId,
                          personId: personId,
                          service: service,
                          navProvider: navProvider,
                          onAddSuggested: suggestedLines.isEmpty
                              ? null
                              : () {
                                  setModal(() {
                                    final target = saleMode == 'van' ? vanLines : presellLines;
                                    for (final s in suggestedLines) {
                                      final pid = int.tryParse('${s['product_id']}');
                                      if (pid == null) continue;
                                      if (target.any((e) => e['product_id'] == pid)) continue;
                                      target.add({
                                        'product_id': pid,
                                        'product_name': s['product_name'],
                                        'quantity': s['suggested_qty'] ?? 1,
                                        'unit_price': s['unit_price'],
                                        if (s['must_sell'] == true) 'must_sell': true,
                                      });
                                    }
                                  });
                                },
                        ),
                        if (enableVanSales || enablePresell) ...[
                          Text(t.distributionSaleMode, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            segments: [
                              if (enableVanSales)
                                ButtonSegment(
                                  value: 'van',
                                  label: Text(t.distributionSaleModeVan),
                                  icon: const Icon(Icons.local_shipping_outlined, size: 18),
                                ),
                              if (enablePresell)
                                ButtonSegment(
                                  value: 'presell',
                                  label: Text(t.distributionSaleModePresell),
                                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                                ),
                              ButtonSegment(
                                value: 'invoice',
                                label: Text(t.distributionSaleModeInvoice),
                                icon: const Icon(Icons.link_outlined, size: 18),
                              ),
                            ],
                            selected: {saleMode},
                            onSelectionChanged: (s) => setModal(() => saleMode = s.first),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (creditSummary != null && creditSummary!['credit_check_enabled'] == true)
                          Card(
                            elevation: 0,
                            color: blocked ? cs.errorContainer : cs.surfaceContainerHighest,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            child: ListTile(
                              leading: Icon(
                                blocked ? Icons.gpp_bad_outlined : Icons.account_balance_wallet_outlined,
                                color: blocked ? cs.onErrorContainer : cs.primary,
                              ),
                              title: Text(
                                t.distributionCustomerCredit,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                blocked
                                    ? t.distributionCustomerCreditBlocked
                                    : '${t.distributionAvailableCredit}: ${creditSummary!['available_credit'] ?? '—'}'
                                      ' · ${t.distributionCreditLimit}: ${creditSummary!['credit_limit'] ?? '—'}',
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        if (saleMode == 'invoice') ...[
                        Text(t.distributionLinkInvoice, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          t.distributionBackToVisit,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await context.push('/business/$businessId/invoice/new?person_id=$personId');
                            try {
                              if (personId == null) return;
                              final items = await service.listPersonInvoices(
                                businessId: businessId,
                                personId: personId,
                              );
                              setModal(() {
                                recentInvoices =
                                    items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                                if (recentInvoices.isNotEmpty && linkedDocumentId == null) {
                                  final first = recentInvoices.first;
                                  linkedDocumentId = int.tryParse('${first['id']}');
                                  linkedDocumentLabel =
                                      '${first['code'] ?? first['id']} · ${first['net'] ?? ''}';
                                }
                              });
                            } catch (_) {}
                          },
                          icon: const Icon(Icons.add_shopping_cart_outlined),
                          label: Text(t.distributionOpenInvoiceKeepVisit),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (loadingExtras)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: LinearProgressIndicator(),
                          )
                        else if (recentInvoices.isEmpty)
                          Text(
                            t.distributionNoRecentInvoices,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          )
                        else
                          DropdownButtonFormField<int?>(
                            value: linkedDocumentId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: t.distributionSelectInvoice,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              DropdownMenuItem<int?>(
                                value: null,
                                child: Text(t.distributionNoInvoiceLink),
                              ),
                              ...recentInvoices.map((inv) {
                                final id = int.tryParse('${inv['id']}');
                                return DropdownMenuItem<int?>(
                                  value: id,
                                  child: Text(
                                    '${inv['code'] ?? id} · ${inv['net'] ?? '—'}'
                                    '${inv['remaining'] != null ? ' (${t.distributionRemaining}: ${inv['remaining']})' : ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (v) => setModal(() {
                              linkedDocumentId = v;
                              if (v == null) {
                                linkedDocumentLabel = null;
                              } else {
                                final match =
                                    recentInvoices.where((e) => int.tryParse('${e['id']}') == v);
                                linkedDocumentLabel = match.isEmpty
                                    ? '$v'
                                    : '${match.first['code'] ?? match.first['id']}';
                              }
                            }),
                          ),
                        if (linkedDocumentLabel != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${t.distributionLinkedDocument}: $linkedDocumentLabel',
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                          ),
                        ],
                        ], // end saleMode == invoice
                        if ((saleMode == 'presell' || saleMode == 'van') &&
                            suggestedLines.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(t.distributionApplySuggestedOrder, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          ...suggestedLines.map((s) {
                            final must = s['must_sell'] == true;
                            final cover = s['days_of_cover'];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                dense: true,
                                title: Text('${s['product_name'] ?? s['product_id']}'),
                                subtitle: Text(
                                  [
                                    '× ${s['suggested_qty'] ?? 1}',
                                    if (cover != null) '${t.distributionDaysOfCover}: $cover',
                                    if (must) t.distributionMustSell,
                                  ].join(' · '),
                                ),
                                trailing: must
                                    ? Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(t.distributionMustSell),
                                      )
                                    : null,
                              ),
                            );
                          }),
                          OutlinedButton.icon(
                            onPressed: () {
                              setModal(() {
                                final target = saleMode == 'van' ? vanLines : presellLines;
                                for (final s in suggestedLines) {
                                  final pid = int.tryParse('${s['product_id']}');
                                  if (pid == null) continue;
                                  if (target.any((e) => e['product_id'] == pid)) continue;
                                  target.add({
                                    'product_id': pid,
                                    'product_name': s['product_name'],
                                    'quantity': s['suggested_qty'] ?? 1,
                                    'unit_price': s['unit_price'],
                                    if (s['must_sell'] == true) 'must_sell': true,
                                  });
                                }
                              });
                            },
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: Text(t.distributionApplySuggestedOrder),
                          ),
                        ],
                        if (enablePromotions &&
                            activePromos.isNotEmpty &&
                            (saleMode == 'presell' || saleMode == 'van')) ...[
                          const SizedBox(height: 12),
                          Text(t.distributionApplyPromos, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: activePromos.map((p) {
                              final id = int.tryParse('${p['id']}') ?? 0;
                              final selected = selectedPromoIds.contains(id);
                              return FilterChip(
                                label: Text('${p['name']}'),
                                selected: selected,
                                onSelected: (v) => setModal(() {
                                  if (v) {
                                    selectedPromoIds.add(id);
                                  } else {
                                    selectedPromoIds.remove(id);
                                  }
                                }),
                              );
                            }).toList(),
                          ),
                        ],
                      if (enableVanSales && saleMode == 'van') ...[
                        const SizedBox(height: 22),
                        Text(t.distributionVanSaleFromStock, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          t.distributionVanSaleFromStockHint,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (blocked) ...[
                          const SizedBox(height: 8),
                          Text(
                            t.distributionCustomerCreditBlocked,
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                          ),
                        ],
                        const SizedBox(height: 10),
                        ...vanLines.asMap().entries.map((e) {
                          final ln = e.value;
                          final name = ln['product_name']?.toString() ?? 'product ${ln['product_id']}';
                          final price = ln['unit_price'];
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              dense: true,
                              title: Text(name),
                              subtitle: Text(
                                '× ${ln['quantity']}'
                                '${price != null ? ' · $price' : ''}'
                                '${ln['tax_rate'] != null && (ln['tax_rate'] as num) > 0 ? ' · tax ${ln['tax_rate']}%' : ''}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => setModal(() => vanLines.removeAt(e.key)),
                              ),
                            ),
                          );
                        }),
                        OutlinedButton.icon(
                          onPressed: (vanStock.isEmpty || blocked) ? null : openVanLineDialog,
                          icon: const Icon(Icons.add),
                          label: Text(
                            vanStock.isEmpty ? t.distributionVanStockEmpty : t.distributionReturnAddLine,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: blocked
                              ? null
                              : () async {
                                  final code = await scanDistributionBarcode(context);
                                  if (code == null || code.isEmpty) return;
                                  try {
                                    final p = await service.lookupBarcode(
                                      businessId: businessId,
                                      barcode: code,
                                      personId: personId,
                                    );
                                    final pid = int.tryParse('${p['product_id']}') ?? 0;
                                    if (pid <= 0) return;
                                    final stock = vanStock.cast<Map<String, dynamic>>().where(
                                          (s) => int.tryParse('${s['product_id']}') == pid,
                                        );
                                    final avail = stock.isEmpty
                                        ? 0.0
                                        : (double.tryParse('${stock.first['quantity']}') ?? 0);
                                    if (avail <= 0) {
                                      SnackBarHelper.showError(context, message: t.distributionVanQtyExceedsStock);
                                      return;
                                    }
                                    setModal(() {
                                      vanLines.add({
                                        'product_id': pid,
                                        'product_name': p['product_name'],
                                        'quantity': 1,
                                        'unit_price': p['unit_price'],
                                        'tax_rate': p['tax_rate'],
                                      });
                                    });
                                  } catch (e) {
                                    SnackBarHelper.showError(
                                      context,
                                      message: ErrorExtractor.forContext(e, context),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(t.distributionScanBarcode),
                        ),
                      ],
                      if (enablePresell && saleMode == 'presell') ...[
                        const SizedBox(height: 22),
                        Text(t.distributionPresellLinesTitle, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          t.distributionPresellLinesHint,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        ...presellLines.asMap().entries.map((e) {
                          final ln = e.value;
                          final name = ln['product_name']?.toString() ?? 'product ${ln['product_id']}';
                          final disc = ln['line_discount'];
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              dense: true,
                              title: Text(name),
                              subtitle: Text(
                                '× ${ln['quantity']}'
                                '${disc != null && (disc as num) > 0 ? ' · ${t.distributionLineDiscount}: $disc' : ''}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => setModal(() => presellLines.removeAt(e.key)),
                              ),
                            ),
                          );
                        }),
                        OutlinedButton.icon(
                          onPressed: blocked
                              ? null
                              : () async {
                                  Map<String, dynamic>? picked;
                                  final qtyCtl = TextEditingController(text: '1');
                                  final discCtl = TextEditingController(text: '0');
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (dctx) => StatefulBuilder(
                                      builder: (context, setD) => AlertDialog(
                                        title: Text(t.distributionReturnAddLine),
                                        content: SizedBox(
                                          width: 420,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ProductComboboxWidget(
                                                businessId: businessId,
                                                selectedProduct: picked,
                                                label: t.distributionSelectProduct,
                                                onChanged: (p) => setD(() => picked = p),
                                              ),
                                              const SizedBox(height: 8),
                                              TextField(
                                                controller: qtyCtl,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                decoration: InputDecoration(
                                                  labelText: t.quantity,
                                                  border: const OutlineInputBorder(),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              TextField(
                                                controller: discCtl,
                                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                decoration: InputDecoration(
                                                  labelText: t.distributionLineDiscount,
                                                  border: const OutlineInputBorder(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t.cancel)),
                                          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: Text(t.save)),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (ok != true || picked == null) return;
                                  final pid = int.tryParse('${picked!['id']}');
                                  final qty = double.tryParse(qtyCtl.text.trim().replaceAll(',', '.')) ?? 0;
                                  final disc = double.tryParse(discCtl.text.trim().replaceAll(',', '.')) ?? 0;
                                  if (pid == null || pid <= 0 || qty <= 0) return;
                                  setModal(() {
                                    presellLines.add({
                                      'product_id': pid,
                                      'product_name': picked!['name']?.toString() ?? 'product $pid',
                                      'quantity': qty,
                                      if (disc > 0) 'line_discount': disc,
                                    });
                                  });
                                },
                          icon: const Icon(Icons.add),
                          label: Text(t.distributionReturnAddLine),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final code = await scanDistributionBarcode(context);
                            if (code == null || code.isEmpty) return;
                            try {
                              final p = await service.lookupBarcode(
                                businessId: businessId,
                                barcode: code,
                                personId: personId,
                              );
                              final pid = int.tryParse('${p['product_id']}') ?? 0;
                              if (pid <= 0) return;
                              setModal(() {
                                presellLines.add({
                                  'product_id': pid,
                                  'product_name': p['product_name'],
                                  'quantity': 1,
                                  'unit_price': p['unit_price'],
                                });
                              });
                            } catch (e) {
                              SnackBarHelper.showError(
                                context,
                                message: ErrorExtractor.forContext(e, context),
                              );
                            }
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(t.distributionScanBarcode),
                        ),
                      ],
                      if (personId != null) ...[
                        const SizedBox(height: 16),
                        Text(t.distributionShelfAuditTitle, style: theme.textTheme.titleSmall),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.distributionShelfFacingOk),
                          value: shelfFacingOk,
                          onChanged: (v) => setModal(() => shelfFacingOk = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.distributionShelfPriceOk),
                          value: shelfPriceOk,
                          onChanged: (v) => setModal(() => shelfPriceOk = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.distributionShelfStockOk),
                          value: shelfStockOk,
                          onChanged: (v) => setModal(() => shelfStockOk = v),
                        ),
                        if (enablePerfectStore) ...[
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.distributionOsaOk),
                            value: osaOk,
                            onChanged: (v) => setModal(() => osaOk = v),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.distributionPlanogram),
                            value: planogramOk,
                            onChanged: (v) => setModal(() => planogramOk = v),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(t.distributionShareOfShelf),
                            subtitle: Slider(
                              value: shareOfShelf,
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '${shareOfShelf.round()}%',
                              onChanged: (v) => setModal(() => shareOfShelf = v),
                            ),
                          ),
                        ],
                      ],
                    ],
                  );
                }

                Widget buildDeliveryStep() {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (outcome == 'order') ...[
                        Text(t.distributionPodTitle, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          t.distributionPodHint,
                          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.distributionPodConfirm),
                          value: podConfirmed,
                          onChanged: (v) => setModal(() => podConfirmed = v),
                        ),
                        if (podConfirmed) ...[
                          TextField(
                            controller: podNameCtl,
                            decoration: InputDecoration(
                              labelText: t.distributionPodSignerName,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: podNoteCtl,
                            decoration: InputDecoration(
                              labelText: t.distributionPodNote,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DistributionSignaturePad(
                            onChanged: (v) => setModal(() => podSignaturePng = v),
                          ),
                          const SizedBox(height: 12),
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
                                setModal(() => podPhotoFileId = uploaded['id'] as int?);
                              } catch (e) {
                                if (context.mounted) {
                                  SnackBarHelper.showError(
                                    context,
                                    message: ErrorExtractor.forContext(e, context),
                                  );
                                }
                              }
                            },
                            icon: Icon(podPhotoFileId != null ? Icons.check_circle_outline : Icons.photo_camera_outlined),
                            label: Text(t.distributionPodPhoto),
                          ),
                          const SizedBox(height: 16),
                        ] else
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
                              SnackBarHelper.showError(
                                context,
                                message: ErrorExtractor.forContext(e, context),
                              );
                            }
                          }
                        },
                        icon: Icon(
                          shelfPhotoFileId != null
                              ? Icons.check_circle_outline
                              : Icons.photo_camera_outlined,
                        ),
                        label: Text(t.distributionShelfPhoto),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: shelfPhotoFileId != null ? cs.primary : null,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: noteCtl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: t.distributionNotesLabel,
                          border: const OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  );
                }

                Widget stepBody;
                switch (step) {
                  case 0:
                    stepBody = buildOutcomeStep();
                    break;
                  case 1:
                    stepBody = buildSaleStep();
                    break;
                  default:
                    stepBody = buildDeliveryStep();
                }

                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t.distributionCompleteVisit,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        buildStepIndicator(),
                        const SizedBox(height: 18),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: stepBody,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (step > 0)
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: submitting
                                      ? null
                                      : () => setModal(() {
                                            if (outcome == 'no_order' && step == 2) {
                                              step = 0;
                                            } else {
                                              step -= 1;
                                            }
                                          }),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(t.distributionVisitWizardBack),
                                ),
                              ),
                            if (step > 0) const SizedBox(width: 12),
                            Expanded(
                              flex: step > 0 ? 1 : 1,
                              child: FilledButton(
                                onPressed: submitting
                                    ? null
                                    : () async {
                                        if (step == 0) {
                                          if (!validateChecklist(context)) return;
                                          if (outcome == 'no_order' && (noOrderCode == null || noOrderCode!.isEmpty)) {
                                            SnackBarHelper.showError(context, message: t.distributionReasonRequired);
                                            return;
                                          }
                                          setModal(() {
                                            step = outcome == 'no_order' ? 2 : 1;
                                          });
                                          return;
                                        }
                                        if (step == 1) {
                                          setModal(() => step = 2);
                                          return;
                                        }
                                        setModal(() => submitting = true);
                                        try {
                                          await submitVisit(ctx, context);
                                        } finally {
                                          if (ctx.mounted) {
                                            setModal(() => submitting = false);
                                          }
                                        }
                                      },
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: submitting
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: cs.onPrimary,
                                        ),
                                      )
                                    : Text(
                                        step == 2
                                            ? t.distributionVisitWizardFinish
                                            : t.distributionVisitWizardNext,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  } finally {
    noteCtl.dispose();
    podNameCtl.dispose();
    podNoteCtl.dispose();
  }
}
