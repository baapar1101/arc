import 'package:flutter/material.dart';

import '../../../core/android_sms_bank_platform.dart';
import '../../system_settings/models/settings_category.dart';
import '../../system_settings/models/settings_item.dart';
import 'business_settings_context.dart';

/// Builds categorized, permission-filtered business settings for the hub page.
class BusinessSettingsCategorizationService {
  static List<SettingsCategory> buildCategories(BusinessSettingsContext ctx) {
    final categories = <SettingsCategory>[
      _businessFinance(ctx),
      _salesDocuments(ctx),
      _integrations(ctx),
      _modules(ctx),
      _administration(ctx),
      _personalization(ctx),
      _advanced(ctx),
      if (ctx.canShowLeaveButton) _membership(ctx),
      if (ctx.isOwner || ctx.canFiscalYearRollback) _dangerZone(ctx),
    ];

    return categories
        .map((c) => c.copyWith(items: _sorted(c.items)))
        .where((c) =>
            c.items.isNotEmpty ||
            (!ctx.pluginsLoaded &&
                (c.id == 'integrations' || c.id == 'modules')))
        .toList();
  }

  /// Essential setup steps shown to business owners at the top of the hub.
  static List<SettingsItem> buildSetupChecklist(BusinessSettingsContext ctx) {
    if (!ctx.isOwner || !ctx.canJoinSettings) return [];

    final items = <SettingsItem>[
      if (ctx.canJoinSettings)
        _item(
          id: 'setup_business_info',
          title: 'businessSettings',
          description: 'businessSettingsDescription',
          icon: Icons.business_outlined,
          color: const Color(0xFF1976D2),
          route: ctx.panelRoute('settings/business'),
          categoryId: 'setup',
          order: 1,
          tags: const ['setup'],
        ),
      if (ctx.canEditFiscalYear)
        _item(
          id: 'setup_fiscal_year',
          title: 'businessSettingsFiscalYearEdit',
          description: 'businessSettingsFiscalYearEditDescription',
          icon: Icons.calendar_today_outlined,
          color: const Color(0xFF00897B),
          route: ctx.panelRoute('settings/fiscal-year'),
          categoryId: 'setup',
          order: 2,
          tags: const ['setup'],
        ),
      if (ctx.canManageBusiness)
        _item(
          id: 'setup_currencies',
          title: 'settingsSideCurrenciesTitle',
          description: 'settingsSideCurrenciesSubtitle',
          icon: Icons.currency_exchange,
          color: const Color(0xFF5E35B1),
          route: ctx.panelRoute('settings/currencies'),
          categoryId: 'setup',
          order: 3,
          tags: const ['setup'],
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'setup_print',
          title: 'printDocuments',
          description: 'printDocumentsDescription',
          icon: Icons.print_outlined,
          color: const Color(0xFF455A64),
          route: ctx.panelRoute('settings/print'),
          categoryId: 'setup',
          order: 4,
          tags: const ['setup'],
        ),
      if (ctx.canManageUsers)
        _item(
          id: 'setup_users',
          title: 'usersAndPermissions',
          description: 'usersAndPermissionsDescription',
          icon: Icons.people_outline,
          color: const Color(0xFF6D4C41),
          route: ctx.panelRoute('users-permissions'),
          categoryId: 'setup',
          order: 5,
          tags: const ['setup'],
        ),
    ];

    return _sorted(items);
  }

  static SettingsCategory _businessFinance(BusinessSettingsContext ctx) {
    final items = <SettingsItem>[
      if (ctx.canJoinSettings)
        _item(
          id: 'business_info',
          title: 'businessSettings',
          description: 'businessSettingsDescription',
          icon: Icons.business_outlined,
          color: const Color(0xFF1976D2),
          route: ctx.panelRoute('settings/business'),
          categoryId: 'business_finance',
          order: 1,
        ),
      if (ctx.canManageBusiness)
        _item(
          id: 'currencies',
          title: 'settingsSideCurrenciesTitle',
          description: 'settingsSideCurrenciesSubtitle',
          icon: Icons.currency_exchange,
          color: const Color(0xFF5E35B1),
          route: ctx.panelRoute('settings/currencies'),
          categoryId: 'business_finance',
          order: 2,
        ),
      if (ctx.canManageBusiness && ctx.isMultiCurrency)
        _item(
          id: 'fx_revaluation',
          title: 'settingsInvoiceFxPolicyTitle',
          description: 'settingsInvoiceFxPolicySubtitle',
          icon: Icons.tune,
          color: const Color(0xFF7B1FA2),
          route: ctx.panelRoute('settings/fx-revaluation'),
          categoryId: 'business_finance',
          order: 3,
        ),
      if (ctx.canManageBusiness && ctx.isMultiCurrency)
        _item(
          id: 'fx_auto_sync',
          title: 'settingsFxAutoSyncTitle',
          description: 'settingsFxAutoSyncSubtitle',
          icon: Icons.autorenew_rounded,
          color: const Color(0xFF00695C),
          route: ctx.panelRoute('settings/fx-auto-sync'),
          categoryId: 'business_finance',
          order: 4,
        ),
      if (ctx.canManageBusiness && ctx.isMultiCurrency)
        _item(
          id: 'period_end_fx',
          title: 'تسعیر پایان دوره',
          description: 'سند تعدیلی سود/زیان تسعیر تحقق‌نیافته برای مانده‌های ارزی',
          icon: Icons.balance_outlined,
          color: const Color(0xFF455A64),
          route: ctx.panelRoute('settings/period-end-fx'),
          categoryId: 'business_finance',
          order: 5,
        ),
      if (ctx.canEditFiscalYear)
        _item(
          id: 'fiscal_year',
          title: 'businessSettingsFiscalYearEdit',
          description: 'businessSettingsFiscalYearEditDescription',
          icon: Icons.calendar_today_outlined,
          color: const Color(0xFF00897B),
          route: ctx.panelRoute('settings/fiscal-year'),
          categoryId: 'business_finance',
          order: 6,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'credit',
          title: 'creditSettingsTitle',
          description: 'creditSettingsSubtitle',
          icon: Icons.credit_score_outlined,
          color: const Color(0xFFEF6C00),
          route: ctx.panelRoute('settings/credit'),
          categoryId: 'business_finance',
          order: 7,
        ),
    ];

    return SettingsCategory(
      id: 'business_finance',
      title: 'businessSettingsCategoryBusinessFinance',
      description: 'businessSettingsCategoryBusinessFinanceDescription',
      icon: Icons.account_balance_wallet_outlined,
      color: const Color(0xFF1976D2),
      order: 1,
      items: items,
    );
  }

  static SettingsCategory _salesDocuments(BusinessSettingsContext ctx) {
    final items = <SettingsItem>[
      if (ctx.canManageBusiness)
        _item(
          id: 'quick_sales',
          title: 'businessSettingsQuickSales',
          description: 'businessSettingsQuickSalesDescription',
          icon: Icons.point_of_sale_outlined,
          color: const Color(0xFF2E7D32),
          route: ctx.panelRoute('settings/quick-sales'),
          categoryId: 'sales_documents',
          order: 1,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'installments',
          title: 'installmentsTitle',
          description: 'installmentsSettingsSubtitle',
          icon: Icons.dashboard_customize_outlined,
          color: const Color(0xFF558B2F),
          route: ctx.panelRoute('settings/installments'),
          categoryId: 'sales_documents',
          order: 2,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'document_numbering',
          title: 'businessSettingsDocumentNumbering',
          description: 'businessSettingsDocumentNumberingDescription',
          icon: Icons.numbers,
          color: const Color(0xFF455A64),
          route: ctx.panelRoute('settings/document-numbering'),
          categoryId: 'sales_documents',
          order: 3,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'print',
          title: 'printDocuments',
          description: 'printDocumentsDescription',
          icon: Icons.print_outlined,
          color: const Color(0xFF546E7A),
          route: ctx.panelRoute('settings/print'),
          categoryId: 'sales_documents',
          order: 4,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'invoice_share_payment',
          title: 'businessSettingsInvoiceSharePayment',
          description: 'businessSettingsInvoiceSharePaymentDescription',
          icon: Icons.payment_outlined,
          color: const Color(0xFF00695C),
          route: ctx.panelRoute('settings/invoice-share-payment'),
          categoryId: 'sales_documents',
          order: 5,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'report_templates',
          title: 'templates',
          description: 'businessSettingsTemplatesDescription',
          icon: Icons.picture_as_pdf_outlined,
          color: const Color(0xFFC62828),
          route: ctx.panelRoute('report-templates'),
          categoryId: 'sales_documents',
          order: 6,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'document_monetization',
          title: 'documentMonetizationTitle',
          description: 'documentMonetizationSubtitle',
          icon: Icons.receipt_long_outlined,
          color: const Color(0xFF6A1B9A),
          route: ctx.panelRoute('document-monetization'),
          categoryId: 'sales_documents',
          order: 7,
        ),
    ];

    return SettingsCategory(
      id: 'sales_documents',
      title: 'businessSettingsCategorySalesDocuments',
      description: 'businessSettingsCategorySalesDocumentsDescription',
      icon: Icons.receipt_long_outlined,
      color: const Color(0xFF2E7D32),
      order: 2,
      items: items,
    );
  }

  static SettingsCategory _integrations(BusinessSettingsContext ctx) {
    if (!ctx.pluginsLoaded) {
      return SettingsCategory(
        id: 'integrations',
        title: 'businessSettingsCategoryIntegrations',
        description: 'businessSettingsCategoryIntegrationsDescription',
        icon: Icons.hub_outlined,
        color: const Color(0xFF00838F),
        order: 3,
        items: const [],
      );
    }

    final items = <SettingsItem>[
      if (ctx.canReadCrm)
        _item(
          id: 'crm',
          title: 'businessSettingsCrm',
          description: 'businessSettingsCrmDescription',
          icon: Icons.support_agent_outlined,
          color: const Color(0xFF0277BD),
          route: ctx.panelRoute('settings/crm'),
          categoryId: 'integrations',
          order: 1,
        ),
      if (ctx.canAccessMoadian)
        _item(
          id: 'tax',
          title: 'taxIntegrationTitle',
          description: 'taxIntegrationSubtitle',
          icon: Icons.cloud_sync_outlined,
          color: const Color(0xFF1565C0),
          route: ctx.panelRoute('settings/tax'),
          categoryId: 'integrations',
          order: 2,
        ),
      if (ctx.canAccessBasalam)
        _item(
          id: 'basalam',
          title: 'settingsBasalamTitle',
          description: 'settingsBasalamSubtitle',
          icon: Icons.storefront_outlined,
          color: const Color(0xFFE65100),
          route: ctx.panelRoute('settings/basalam'),
          categoryId: 'integrations',
          order: 3,
        ),
      if (ctx.canAccessWooCommerce)
        _item(
          id: 'woocommerce',
          title: 'settingsWooCommerceTitle',
          description: 'settingsWooCommerceSubtitle',
          icon: Icons.shopping_cart_outlined,
          color: const Color(0xFF4527A0),
          route: ctx.panelRoute('settings/woocommerce'),
          categoryId: 'integrations',
          order: 4,
        ),
    ];

    return SettingsCategory(
      id: 'integrations',
      title: 'businessSettingsCategoryIntegrations',
      description: 'businessSettingsCategoryIntegrationsDescription',
      icon: Icons.hub_outlined,
      color: const Color(0xFF00838F),
      order: 3,
      items: items,
    );
  }

  static SettingsCategory _modules(BusinessSettingsContext ctx) {
    if (!ctx.pluginsLoaded) {
      return SettingsCategory(
        id: 'modules',
        title: 'businessSettingsCategoryModules',
        description: 'businessSettingsCategoryModulesDescription',
        icon: Icons.extension_outlined,
        color: const Color(0xFF6A1B9A),
        order: 4,
        items: const [],
      );
    }

    final items = <SettingsItem>[
      if (ctx.canAccessWarranty)
        _item(
          id: 'warranty',
          title: 'warrantySettings',
          description: 'businessSettingsWarrantyDescription',
          icon: Icons.verified_user_outlined,
          color: const Color(0xFF283593),
          route: ctx.panelRoute('warranty/settings'),
          categoryId: 'modules',
          order: 1,
        ),
      if (ctx.canAccessRepairShop)
        _item(
          id: 'repair_shop',
          title: 'businessSettingsRepairShop',
          description: 'businessSettingsRepairShopDescription',
          icon: Icons.build_circle_outlined,
          color: const Color(0xFF4E342E),
          route: ctx.panelRoute('repair-shop-settings'),
          categoryId: 'modules',
          order: 2,
        ),
      if (ctx.canAccessCustomerClub)
        _item(
          id: 'customer_club',
          title: 'customerClubTitle',
          description: 'customerClubSettingsSubtitle',
          icon: Icons.card_giftcard,
          color: const Color(0xFFAD1457),
          route: ctx.panelRoute('settings/customer-club'),
          categoryId: 'modules',
          order: 3,
        ),
      if (ctx.canAccessDistribution)
        _item(
          id: 'distribution',
          title: 'distributionMenu',
          description: 'distributionSettingsSubtitle',
          icon: Icons.local_shipping_outlined,
          color: const Color(0xFF006064),
          route: ctx.panelRoute('distribution'),
          categoryId: 'modules',
          order: 4,
        ),
      if (ctx.canAccessPayroll)
        _item(
          id: 'payroll',
          title: 'businessSettingsPayroll',
          description: 'businessSettingsPayrollDescription',
          icon: Icons.payments_outlined,
          color: const Color(0xFF283593),
          route: ctx.panelRoute('settings/payroll'),
          categoryId: 'modules',
          order: 5,
        ),
    ];

    return SettingsCategory(
      id: 'modules',
      title: 'businessSettingsCategoryModules',
      description: 'businessSettingsCategoryModulesDescription',
      icon: Icons.extension_outlined,
      color: const Color(0xFF6A1B9A),
      order: 4,
      items: items,
    );
  }

  static SettingsCategory _administration(BusinessSettingsContext ctx) {
    final items = <SettingsItem>[
      if (ctx.canJoinSettings)
        _item(
          id: 'users_permissions',
          title: 'usersAndPermissions',
          description: 'usersAndPermissionsDescription',
          icon: Icons.people_outline,
          color: const Color(0xFF5D4037),
          route: ctx.panelRoute('users-permissions'),
          categoryId: 'administration',
          order: 1,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'projects',
          title: 'businessSettingsProjects',
          description: 'businessSettingsProjectsDescription',
          icon: Icons.account_tree_outlined,
          color: const Color(0xFF37474F),
          route: ctx.panelRoute('projects'),
          categoryId: 'administration',
          order: 2,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'notification_templates',
          title: 'businessSettingsNotificationTemplates',
          description: 'businessSettingsNotificationTemplatesDescription',
          icon: Icons.notifications_active_outlined,
          color: const Color(0xFFF57F17),
          route: ctx.panelRoute('notification-templates'),
          categoryId: 'administration',
          order: 3,
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'activity_logs',
          title: 'systemLogs',
          description: 'systemLogsDescription',
          icon: Icons.assignment_outlined,
          color: const Color(0xFF455A64),
          route: ctx.panelRoute('reports/activity-logs'),
          categoryId: 'administration',
          order: 4,
        ),
    ];

    return SettingsCategory(
      id: 'administration',
      title: 'businessSettingsCategoryAdministration',
      description: 'businessSettingsCategoryAdministrationDescription',
      icon: Icons.admin_panel_settings_outlined,
      color: const Color(0xFF5D4037),
      order: 5,
      items: items,
    );
  }

  static SettingsCategory _personalization(BusinessSettingsContext ctx) {
    return SettingsCategory(
      id: 'personalization',
      title: 'businessSettingsCategoryPersonalization',
      description: 'businessSettingsCategoryPersonalizationDescription',
      icon: Icons.palette_outlined,
      color: const Color(0xFF7B1FA2),
      order: 6,
      items: [
        _item(
          id: 'appearance_profile',
          title: 'businessSettingsAppearanceProfile',
          description: 'businessSettingsAppearanceProfileDescription',
          icon: Icons.palette_outlined,
          color: const Color(0xFF7B1FA2),
          route: '/user/profile/appearance-settings',
          categoryId: 'personalization',
          order: 1,
        ),
        if (supportsAndroidSmsBankAssistant && ctx.canJoinSettings)
          _item(
            id: 'sms_bank_assistant',
            title: 'smsBankAssistantSettingsTitle',
            description: 'smsBankAssistantSettingsDescription',
            icon: Icons.sms_outlined,
            color: const Color(0xFF00838F),
            route: ctx.panelRoute('settings/sms-bank'),
            categoryId: 'personalization',
            order: 2,
            tags: const ['android', 'new'],
          ),
      ],
    );
  }

  static SettingsCategory _advanced(BusinessSettingsContext ctx) {
    final items = <SettingsItem>[
      if (ctx.canJoinSettings)
        _item(
          id: 'backup',
          title: 'dataBackup',
          description: 'dataBackupDescription',
          icon: Icons.backup_outlined,
          color: const Color(0xFF0277BD),
          route: ctx.panelRoute('settings/backup'),
          categoryId: 'advanced',
          order: 1,
          tags: const ['advanced'],
        ),
      if (ctx.canManageFtp)
        _item(
          id: 'ftp_backup',
          title: 'ftpBackupSettingsTitle',
          description: 'ftpBackupSettingsDescription',
          icon: Icons.cloud_upload_outlined,
          color: const Color(0xFF01579B),
          route: ctx.panelRoute('settings/ftp-backup'),
          categoryId: 'advanced',
          order: 2,
          tags: const ['advanced'],
        ),
      if (ctx.canManageAiProvider)
        _item(
          id: 'ai_provider',
          title: 'businessSettingsAiProviderTitle',
          description: 'businessSettingsAiProviderDescription',
          icon: Icons.smart_toy_outlined,
          color: const Color(0xFF00695C),
          route: ctx.panelRoute('settings/ai-provider'),
          categoryId: 'advanced',
          order: 3,
          tags: const ['advanced', 'ai'],
        ),
      if (ctx.canJoinSettings)
        _item(
          id: 'restore',
          title: 'dataRestore',
          description: 'dataRestoreDescription',
          icon: Icons.restore_outlined,
          color: const Color(0xFF006064),
          route: ctx.panelRoute('settings/restore'),
          categoryId: 'advanced',
          order: 4,
          tags: const ['advanced'],
        ),
    ];

    return SettingsCategory(
      id: 'advanced',
      title: 'businessSettingsCategoryAdvanced',
      description: 'businessSettingsCategoryAdvancedDescription',
      icon: Icons.engineering_outlined,
      color: const Color(0xFF37474F),
      order: 7,
      items: items,
    );
  }

  static SettingsCategory _membership(BusinessSettingsContext ctx) {
    return SettingsCategory(
      id: 'membership',
      title: 'businessSettingsCategoryMembership',
      description: 'businessSettingsCategoryMembershipDescription',
      icon: Icons.group_outlined,
      color: const Color(0xFF546E7A),
      order: 8,
      items: [
        _item(
          id: 'leave_business',
          title: 'businessSettingsLeaveBusiness',
          description: 'businessSettingsLeaveBusinessDescription',
          icon: Icons.exit_to_app,
          color: const Color(0xFFC62828),
          route: '',
          categoryId: 'membership',
          order: 1,
          tags: const ['danger'],
        ),
      ],
    );
  }

  static SettingsCategory _dangerZone(BusinessSettingsContext ctx) {
    final items = <SettingsItem>[
      if (ctx.isOwner)
        _item(
          id: 'delete_business',
          title: 'businessSettingsDeleteBusiness',
          description: 'businessSettingsDeleteBusinessDescription',
          icon: Icons.delete_forever_outlined,
          color: const Color(0xFFC62828),
          route: ctx.panelRoute('settings/delete'),
          categoryId: 'danger_zone',
          order: 1,
          tags: const ['danger'],
        ),
      if (ctx.canFiscalYearRollback)
        _item(
          id: 'fiscal_year_rollback',
          title: 'businessSettingsFiscalYearRollback',
          description: 'businessSettingsFiscalYearRollbackDescription',
          icon: Icons.restore_from_trash_outlined,
          color: const Color(0xFFB71C1C),
          route: ctx.panelRoute('settings/fiscal-year-rollback'),
          categoryId: 'danger_zone',
          order: 2,
          tags: const ['danger'],
        ),
    ];

    return SettingsCategory(
      id: 'danger_zone',
      title: 'businessSettingsCategoryDangerZone',
      description: 'businessSettingsCategoryDangerZoneDescription',
      icon: Icons.warning_amber_rounded,
      color: const Color(0xFFC62828),
      order: 9,
      items: items,
    );
  }

  static SettingsItem _item({
    required String id,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String route,
    required String categoryId,
    required int order,
    List<String> tags = const [],
  }) {
    return SettingsItem(
      id: id,
      title: title,
      description: description,
      icon: icon,
      color: color,
      route: route,
      categoryId: categoryId,
      order: order,
      tags: tags,
    );
  }

  static List<SettingsItem> _sorted(List<SettingsItem> items) {
    final copy = List<SettingsItem>.from(items);
    copy.sort((a, b) => a.order.compareTo(b.order));
    return copy;
  }
}
