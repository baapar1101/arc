import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/permission_guard.dart';
import 'woocommerce_plugin_settings_body.dart';

/// تنظیمات افزونهٔ ووکامرس زیر مسیر `.../settings/woocommerce`.
class WoocommerceSettingsPage extends StatelessWidget {
  final int businessId;
  final AuthStore authStore;

  const WoocommerceSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final canView = authStore.hasBusinessPermission('woocommerce', 'view') ||
        authStore.currentBusiness?.isOwner == true;
    final canManage = authStore.hasBusinessPermission('woocommerce', 'manage') ||
        authStore.currentBusiness?.isOwner == true;

    if (!canView) {
      return Scaffold(
        appBar: AppBar(title: Text(t.woocommerceSettingsPageTitle)),
        body: PermissionGuard.buildAccessDeniedPage(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t.woocommerceSettingsPageTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: t.woocommerceOpenReportsOverviewTooltip,
            icon: const Icon(Icons.assessment_outlined),
            onPressed: () => context.push(
                  context.businessPanelUrl(businessId, 'reports/woocommerce/overview'),
                ),
          ),
          IconButton(
            tooltip: t.woocommerceOpenIntegrationHub,
            onPressed: () => context.push(
                  context.businessPanelUrl(businessId, 'woocommerce'),
                ),
            icon: const Icon(Icons.shopping_cart_outlined),
          ),
          if (canManage)
            IconButton(
              tooltip: t.woocommerceOpenOpeningInventoryTooltip,
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () => context.push(
                context.businessPanelUrl(
                  businessId,
                  'woocommerce/opening-inventory',
                ),
              ),
            ),
        ],
      ),
      body: WoocommercePluginSettingsBody(
        businessId: businessId,
        authStore: authStore,
      ),
    );
  }
}
