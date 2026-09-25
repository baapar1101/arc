import '../../../core/auth_store.dart';
import '../../../core/business_panel_ui_store.dart';
import '../../../core/business_route_paths.dart';

/// Context for building the business settings hub (permissions, plugins, routes).
class BusinessSettingsContext {
  final int businessId;
  final AuthStore authStore;
  final List<Map<String, dynamic>> plugins;
  final bool pluginsLoaded;
  final bool pluginsLoadFailed;

  const BusinessSettingsContext({
    required this.businessId,
    required this.authStore,
    required this.plugins,
    required this.pluginsLoaded,
    this.pluginsLoadFailed = false,
  });

  bool get isOwner {
    final current = authStore.currentBusiness;
    return current != null && current.id == businessId && current.isOwner == true;
  }

  String? get businessName => authStore.currentBusiness?.id == businessId
      ? authStore.currentBusiness?.name
      : null;

  bool get canShowLeaveButton {
    final current = authStore.currentBusiness;
    return current != null && current.id == businessId && !isOwner;
  }

  /// چندارزی بودن کسب‌وکار فعلی (برای مخفی‌سازی تنظیمات تسعیر و …).
  bool get isMultiCurrency {
    final current = authStore.currentBusiness;
    if (current == null || current.id != businessId) return false;
    return current.isMultiCurrency;
  }

  String route(String relativePath) => '/business/$businessId/$relativePath';

  /// Tab-aware route for settings opened from a specific business panel tab.
  String panelRoute(String relativePath) {
    var slot = 0;
    if (BusinessPanelUiStore.instance.mode == BusinessPanelNavigationMode.tabs) {
      final session = BusinessPanelUiStore.instance.tabsForBusiness(businessId);
      slot = BusinessRoutePaths.parseTabSlotFromPath(session?.activePath ?? '') ?? 0;
    }
    return BusinessRoutePaths.uri(businessId, slot, relativePath);
  }

  bool pluginActive(String code) {
    return plugins.any(
      (p) => p['plugin_code'] == code && p['is_active'] == true,
    );
  }

  bool get canJoinSettings => authStore.hasBusinessPermission('settings', 'join');

  bool get canManageBusiness =>
      isOwner || authStore.hasBusinessPermission('settings', 'business');

  bool get canEditFiscalYear =>
      isOwner || authStore.hasBusinessPermission('fiscal_years', 'edit');

  bool get canFiscalYearRollback =>
      isOwner || authStore.hasBusinessPermission('fiscal_years', 'rollback');

  bool get canManageFtp =>
      isOwner || authStore.hasBusinessPermission('settings', 'manage_ftp');

  bool get canManageAiProvider =>
      isOwner || authStore.hasBusinessPermission('settings', 'manage_ai_provider');

  bool get canManageUsers =>
      isOwner || authStore.hasBusinessPermission('settings', 'users');

  bool get canReadCrm => authStore.canReadSection('crm');

  bool get canAccessWarranty {
    if (!pluginActive('product_warranty')) return false;
    if (isOwner) return true;
    return authStore.hasBusinessPermission('warranty', 'manage') ||
        authStore.hasBusinessPermission('warranty', 'read');
  }

  bool get canAccessRepairShop {
    if (!pluginActive('repair_shop_management')) return false;
    if (isOwner) return true;
    return authStore.hasBusinessPermission('repair_shop', 'manage') ||
        authStore.hasBusinessPermission('repair_shop', 'read');
  }

  bool get canAccessCustomerClub {
    if (!pluginActive('customer_club')) return false;
    if (isOwner) return true;
    return authStore.hasBusinessPermission('customer_club', 'view') ||
        authStore.hasBusinessPermission('customer_club', 'manage');
  }

  bool get canAccessDistribution {
    if (!pluginActive('distribution')) return false;
    if (isOwner) return true;
    return authStore.hasBusinessPermission('distribution', 'view');
  }

  bool get canAccessPayroll {
    if (!pluginActive('payroll')) return false;
    if (isOwner) return true;
    return authStore.hasBusinessPermission('payroll', 'view') ||
        authStore.hasBusinessPermission('payroll', 'manage');
  }

  bool get canAccessMoadian {
    if (!pluginActive('moadian_tax_integration')) return false;
    if (isOwner) return true;
    return authStore.hasBusinessPermission('moadian', 'manage_settings');
  }

  bool get canAccessBasalam {
    if (!canJoinSettings || !pluginActive('basalam_connector')) return false;
    if (isOwner) return true;
    return authStore.hasBusinessPermission('basalam', 'view') ||
        authStore.hasBusinessPermission('basalam', 'manage');
  }

  bool get canAccessWooCommerce {
    if (!canJoinSettings || !pluginActive('woocommerce_hesabix')) return false;
    if (isOwner) return true;
    return authStore.hasBusinessPermission('woocommerce', 'view') ||
        authStore.hasBusinessPermission('woocommerce', 'manage');
  }
}
