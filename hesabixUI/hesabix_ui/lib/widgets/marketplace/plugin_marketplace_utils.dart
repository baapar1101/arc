import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../core/date_utils.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;

/// مسیر تنظیمات پس از خرید موفق بر اساس کد افزونه.
const Map<String, String> pluginSetupRouteByCode = {
  'moadian_tax_integration': 'business_tax_workspace',
  'basalam_connector': 'business_basalam',
  'repair_shop_management': 'business_repair_shop',
  'product_warranty': 'business_warranty',
  'distribution': 'business_distribution',
  'woocommerce_hesabix': 'business_woocommerce',
  'customer_club': 'business_customer_club',
};

/// دسته‌های شناخته‌شده در seed/API.
const Set<String> kPluginMarketplaceCategories = {
  'integration',
  'operations',
  'product_management',
  'sales',
  'crm_marketing',
};

String pluginCategoryLabel(AppLocalizations t, String? category) {
  switch (category) {
    case 'integration':
      return t.pluginMarketplaceCategoryIntegration;
    case 'operations':
      return t.pluginMarketplaceCategoryOperations;
    case 'product_management':
      return t.pluginMarketplaceCategoryProductManagement;
    case 'sales':
      return t.pluginMarketplaceCategorySales;
    case 'crm_marketing':
      return t.pluginMarketplaceCategoryCrmMarketing;
    default:
      return category ?? t.pluginMarketplaceCategoryAll;
  }
}

String pluginPeriodLabel(AppLocalizations t, String? period) {
  switch (period) {
    case 'monthly':
      return t.pluginMarketplacePlanMonthly;
    case 'yearly':
      return t.pluginMarketplacePlanYearly;
    case 'lifetime':
      return t.pluginMarketplacePlanLifetime;
    default:
      return period ?? '-';
  }
}

IconData pluginCategoryIcon(String? category) {
  switch (category) {
    case 'integration':
      return Icons.hub_outlined;
    case 'operations':
      return Icons.build_circle_outlined;
    case 'product_management':
      return Icons.inventory_2_outlined;
    case 'sales':
      return Icons.local_shipping_outlined;
    case 'crm_marketing':
      return Icons.loyalty_outlined;
    default:
      return Icons.extension_outlined;
  }
}

bool pluginIconIsSvg(String? url) {
  if (url == null || url.isEmpty) return false;
  final lower = url.toLowerCase();
  return lower.endsWith('.svg') || lower.contains('.svg?');
}

String? resolvePluginIconUrl(String? iconUrl) {
  if (iconUrl == null || iconUrl.isEmpty) return null;
  if (pluginIconIsSvg(iconUrl)) return null;
  if (iconUrl.startsWith('http://') || iconUrl.startsWith('https://')) {
    return iconUrl;
  }
  // مسیر نسبی assets — در وب معمولاً از ریشه سرو می‌شود
  if (iconUrl.startsWith('/')) return iconUrl;
  return '/$iconUrl';
}

String formatPluginPrice(double price, String symbol) {
  return '${formatWithThousands(price, decimalPlaces: 0)} $symbol';
}

String currencySymbolFromPlan(Map<String, dynamic>? plan, String walletFallback) {
  if (plan == null) return walletFallback;
  final currency = plan['currency'] as Map<String, dynamic>?;
  if (currency != null) {
    final symbol = currency['symbol']?.toString();
    if (symbol != null && symbol.isNotEmpty) return symbol;
    final code = currency['code']?.toString();
    if (code != null && code.isNotEmpty) return code;
  }
  return walletFallback;
}

String walletCurrencySymbol(Map<String, dynamic>? walletOverview) {
  final symbol = walletOverview?['base_currency_symbol']?.toString();
  if (symbol != null && symbol.isNotEmpty) return symbol;
  return walletOverview?['base_currency_code']?.toString() ?? 'IRR';
}

Map<String, dynamic>? businessPluginForId(
  List<Map<String, dynamic>> businessPlugins,
  int pluginId,
) {
  for (final bp in businessPlugins) {
    if ((bp['plugin_id'] as num?)?.toInt() == pluginId) {
      return bp.isNotEmpty ? bp : null;
    }
  }
  return null;
}

bool hasUsedTrial(Map<String, dynamic>? pluginStatus) {
  if (pluginStatus == null || pluginStatus.isEmpty) return false;
  return pluginStatus['is_trial'] == true ||
      (pluginStatus['is_trial'] == false && pluginStatus['trial_started_at'] != null);
}

double? cheapestPlanPrice(List<Map<String, dynamic>> plans) {
  if (plans.isEmpty) return null;
  double? min;
  for (final pl in plans) {
    final p = (pl['price'] ?? 0).toDouble();
    if (min == null || p < min) min = p;
  }
  return min;
}

Map<String, dynamic>? planByPeriod(List<Map<String, dynamic>> plans, String period) {
  for (final pl in plans) {
    if (pl['period'] == period) return pl;
  }
  return null;
}

/// درصد صرفه‌جویی سالانه نسبت به ۱۲× ماهانه.
int? yearlySavingsPercent(List<Map<String, dynamic>> plans) {
  final monthly = planByPeriod(plans, 'monthly');
  final yearly = planByPeriod(plans, 'yearly');
  if (monthly == null || yearly == null) return null;
  final m = (monthly['price'] ?? 0).toDouble();
  final y = (yearly['price'] ?? 0).toDouble();
  if (m <= 0) return null;
  final fullYear = m * 12;
  if (fullYear <= y) return null;
  return ((1 - y / fullYear) * 100).round();
}

String? equivalentMonthlyPrice(
  Map<String, dynamic> plan,
  String symbol,
) {
  final period = plan['period']?.toString();
  final price = (plan['price'] ?? 0).toDouble();
  if (period == 'yearly' && price > 0) {
    return formatPluginPrice(price / 12, symbol);
  }
  if (period == 'lifetime' && price > 0) {
    return formatPluginPrice(price / 120, symbol);
  }
  return null;
}

String formatPluginEndsAt(dynamic endsAt, {bool isJalali = true}) {
  if (endsAt == null) return '-';
  DateTime? dt;
  if (endsAt is DateTime) {
    dt = endsAt;
  } else {
    dt = DateTime.tryParse(endsAt.toString());
  }
  if (dt == null) return endsAt.toString();
  return HesabixDateUtils.formatDateTime(dt.toLocal(), isJalali);
}

List<String> pluginDescriptionHighlights(String description, {int maxLines = 3}) {
  final lines = description.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty);
  final bullets = <String>[];
  for (final line in lines) {
    var t = line;
    if (t.startsWith('✅') || t.startsWith('🔧') || t.startsWith('📱')) {
      t = t.substring(1).trim();
    }
    if (t.startsWith('-') || t.startsWith('•')) {
      t = t.substring(1).trim();
    }
    if (t.isNotEmpty) bullets.add(t);
    if (bullets.length >= maxLines) break;
  }
  if (bullets.isNotEmpty) return bullets;
  final plain = description.trim();
  if (plain.length <= 120) return [plain];
  return ['${plain.substring(0, 120)}…'];
}
