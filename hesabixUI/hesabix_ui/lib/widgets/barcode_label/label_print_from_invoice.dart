import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/auth_store.dart';
import '../../models/invoice_line_item.dart';
import '../../services/marketplace_service.dart';
import '../../services/product_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/general_barcode_utils.dart';
import '../../utils/snackbar_helper.dart';
import 'label_print_job_dialog.dart';

Future<bool> _isBarcodeLabelPluginActive(int businessId) async {
  try {
    final plugins = await MarketplaceService().listBusinessPlugins(businessId: businessId);
    for (final p in plugins) {
      if (p['plugin_code'] != 'barcode_label_studio') continue;
      if (p['is_active'] == true || p['is_active'] == 1) return true;
      if (p['is_trial'] == true && p['is_expired'] != true) return true;
    }
  } catch (_) {}
  return false;
}

/// Opens the label print dialog with purchase-invoice lines (qty = purchased quantity).
Future<void> showBarcodePrintFromInvoiceLines({
  required BuildContext context,
  required int businessId,
  required AuthStore authStore,
  required List<InvoiceLineItem> lines,
}) async {
  final t = AppLocalizations.of(context);
  if (!authStore.hasBusinessPermission('barcode_labels', 'print') &&
      !authStore.hasBusinessPermission('barcode_labels', 'view') &&
      !authStore.hasBusinessPermission('products', 'view')) {
    SnackBarHelper.showError(context, message: t.accessDenied);
    return;
  }
  if (!await _isBarcodeLabelPluginActive(businessId)) {
    if (!context.mounted) return;
    SnackBarHelper.showError(context, message: t.barcodeLabelPluginNotActive);
    return;
  }
  final productLines = lines.where((l) => l.productId != null && l.quantity > 0).toList();
  if (productLines.isEmpty) {
    SnackBarHelper.showError(context, message: t.barcodeLabelPrintFromInvoiceEmpty);
    return;
  }

  Map<int, Map<String, dynamic>> meta = {};
  try {
    meta = await ProductService().getProductsMetadata(
      businessId: businessId,
      productIds: productLines.map((l) => l.productId!).toList(),
    );
  } catch (_) {}

  final rows = <LabelPrintJobRow>[];
  for (final line in productLines) {
    final qty = line.quantity.round().clamp(1, 9999);
    final p = Map<String, dynamic>.from(meta[line.productId] ?? const {});
    p['id'] = line.productId;
    p['name'] ??= line.productName;
    p['code'] ??= line.productCode;
    p['base_sales_price'] ??= line.baseSalesPriceMainUnit;
    p['base_purchase_price'] ??= line.basePurchasePriceMainUnit;
    final tokens = parseGeneralBarcodeTokens(p['general_barcodes']?.toString());
    if (tokens.isEmpty) {
      rows.add(LabelPrintJobDialog.fromProductMap(p, qty: qty, sourceQty: qty));
    } else {
      for (final tok in tokens) {
        rows.add(LabelPrintJobDialog.fromProductMap(p, barcodeOverride: tok, qty: qty, sourceQty: qty));
      }
    }
  }
  if (!context.mounted) return;
  if (rows.isEmpty) {
    SnackBarHelper.showError(context, message: t.barcodeLabelPrintFromInvoiceEmpty);
    return;
  }
  try {
    await LabelPrintJobDialog.show(context, businessId: businessId, rows: rows);
  } catch (e) {
    if (!context.mounted) return;
    SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
  }
}
