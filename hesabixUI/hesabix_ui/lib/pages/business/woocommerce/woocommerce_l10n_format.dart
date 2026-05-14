import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

String formatWooInteger(BuildContext context, Object? value) {
  if (value == null) return '';
  final n = value is num ? value.toInt() : int.tryParse('$value');
  if (n == null) return '$value';
  final loc = Localizations.localeOf(context);
  return NumberFormat.decimalPattern(loc.toString()).format(n);
}

String formatWooDecimal(BuildContext context, Object? value, {int maxFractionDigits = 2}) {
  if (value == null) return '';
  final n = value is num ? value.toDouble() : double.tryParse('$value');
  if (n == null || n.isNaN) return '$value';
  final loc = Localizations.localeOf(context).toString();
  final fmt = NumberFormat.decimalPattern(loc);
  fmt.maximumFractionDigits = maxFractionDigits;
  fmt.minimumFractionDigits = 0;
  return fmt.format(n);
}

/// سلول وضعیت سینک با Tooltip برای خطای همگام‌سازی (گزارش‌ها و مرکز عملیات).
Widget wooReportSyncStatusCell(AppLocalizations t, dynamic item) {
  if (item is! Map<String, dynamic>) return const SizedBox.shrink();
  final err = '${item['hesabix_error_message'] ?? ''}'.trim();
  final label = wooSyncStatusLabel(t, item['sync_status'] as String?);
  final textWidget = Text(label, maxLines: 2, overflow: TextOverflow.ellipsis);
  if (err.isEmpty) return textWidget;
  return Tooltip(
    message: err,
    waitDuration: const Duration(milliseconds: 400),
    child: textWidget,
  );
}

String wooOrderStorageLabel(AppLocalizations t, Object? raw) {
  final code = '${raw ?? ''}'.trim().toLowerCase();
  switch (code) {
    case 'hpos':
      return t.reportsWooOrderStorageHpos;
    case 'posts':
      return t.reportsWooOrderStoragePosts;
    case '':
      return '-';
    default:
      return t.reportsWooOrderStorageUnknown(code);
  }
}

String wooOrderStatusLabel(AppLocalizations t, String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return '';
  switch (s) {
    case 'pending':
      return t.woocommerceOrderStatusPending;
    case 'processing':
      return t.woocommerceOrderStatusProcessing;
    case 'on-hold':
      return t.woocommerceOrderStatusOnHold;
    case 'completed':
      return t.woocommerceOrderStatusCompleted;
    case 'cancelled':
      return t.woocommerceOrderStatusCancelled;
    case 'refunded':
      return t.woocommerceOrderStatusRefunded;
    case 'failed':
      return t.woocommerceOrderStatusFailed;
    case 'draft':
      return t.woocommerceOrderStatusDraft;
    case 'trash':
      return t.woocommerceOrderStatusTrash;
    case 'auto-draft':
      return t.woocommerceOrderStatusAutoDraft;
    case 'checkout-draft':
      return t.woocommerceOrderStatusCheckoutDraft;
    default:
      return t.woocommerceOrderStatusUnknown(s);
  }
}

String wooProductTypeLabel(AppLocalizations t, String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return '';
  switch (s) {
    case 'simple':
      return t.woocommerceProductTypeSimple;
    case 'grouped':
      return t.woocommerceProductTypeGrouped;
    case 'external':
      return t.woocommerceProductTypeExternal;
    case 'variable':
      return t.woocommerceProductTypeVariable;
    case 'variation':
      return t.woocommerceProductTypeVariation;
    default:
      return t.woocommerceProductTypeUnknown(s);
  }
}

String wooOrderTypeLabel(AppLocalizations t, String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return '';
  switch (s) {
    case 'shop_order':
      return t.woocommerceOrderTypeShopOrder;
    case 'shop_order_refund':
      return t.woocommerceOrderTypeShopOrderRefund;
    default:
      return t.woocommerceOrderTypeUnknown(s);
  }
}

String wooSyncStatusLabel(AppLocalizations t, String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return t.woocommerceSyncStatusNone;
  switch (s) {
    case 'synced':
      return t.woocommerceSyncStatusSynced;
    case 'pending':
      return t.woocommerceSyncStatusPending;
    case 'error':
      return t.woocommerceSyncStatusError;
    default:
      return (raw ?? '').trim();
  }
}

String wooBridgeFieldTitle(AppLocalizations t, String key) {
  switch (key) {
    case 'bridge_version':
      return t.wooBridgeFieldBridgeVersion;
    case 'wc_version':
      return t.wooBridgeFieldWcVersion;
    case 'wp_version':
      return t.wooBridgeFieldWpVersion;
    case 'plugin_version':
      return t.wooBridgeFieldPluginVersion;
    case 'site_url':
      return t.wooBridgeFieldSiteUrl;
    case 'bridge_enabled':
      return t.wooBridgeFieldBridgeEnabled;
    default:
      return t.wooBridgeFieldGenericTitle(key);
  }
}

String wooBridgeFieldDisplayValue(AppLocalizations t, String key, Object? raw) {
  if (key == 'bridge_enabled' && raw is bool) {
    return raw ? t.wooBridgeValueTrue : t.wooBridgeValueFalse;
  }
  if (raw == null) return '-';
  return '$raw';
}

String formatOrderTotalDisplay(BuildContext context, Map<String, dynamic> row) {
  final total = row['total'];
  final cur = '${row['currency'] ?? ''}'.trim();
  final amount = formatWooDecimal(context, total);
  if (cur.isEmpty) return amount;
  return '$amount $cur';
}

String formatProductPriceDisplay(BuildContext context, Map<String, dynamic> row) {
  final price = row['price'];
  final sale = row['sale_price'];
  final main = formatWooDecimal(context, price);
  final saleNum = sale is num ? sale : double.tryParse('$sale');
  if (saleNum != null && saleNum > 0) {
    return '${formatWooDecimal(context, sale)} ($main)';
  }
  return main;
}
