import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../system_settings/models/settings_category.dart';
import '../../system_settings/models/settings_item.dart';

/// Localized strings for business settings hub keys.
class BusinessSettingsLocalizationHelper {
  static String getTitle(AppLocalizations t, String key) {
    switch (key) {
      case 'businessSettings':
        return t.businessSettings;
      case 'settingsSideCurrenciesTitle':
        return t.settingsSideCurrenciesTitle;
      case 'settingsInvoiceFxPolicyTitle':
        return t.settingsInvoiceFxPolicyTitle;
      case 'settingsFxAutoSyncTitle':
        return t.settingsFxAutoSyncTitle;
      case 'businessSettingsFiscalYearEdit':
        return t.businessSettingsFiscalYearEdit;
      case 'creditSettingsTitle':
        return t.creditSettingsTitle;
      case 'businessSettingsQuickSales':
        return t.businessSettingsQuickSales;
      case 'installmentsTitle':
        return t.installmentsTitle;
      case 'printDocuments':
        return t.printDocuments;
      case 'businessSettingsDocumentNumbering':
        return t.businessSettingsDocumentNumbering;
      case 'businessSettingsInvoiceSharePayment':
        return t.businessSettingsInvoiceSharePayment;
      case 'templates':
        return t.templates;
      case 'documentMonetizationTitle':
        return t.documentMonetizationTitle;
      case 'businessSettingsCrm':
        return t.businessSettingsCrm;
      case 'taxIntegrationTitle':
        return t.taxIntegrationTitle;
      case 'settingsBasalamTitle':
        return t.settingsBasalamTitle;
      case 'settingsWooCommerceTitle':
        return t.settingsWooCommerceTitle;
      case 'warrantySettings':
        return t.warrantySettings;
      case 'businessSettingsRepairShop':
        return t.businessSettingsRepairShop;
      case 'customerClubTitle':
        return t.customerClubTitle;
      case 'distributionMenu':
        return t.distributionMenu;
      case 'usersAndPermissions':
        return t.usersAndPermissions;
      case 'businessSettingsProjects':
        return t.businessSettingsProjects;
      case 'businessSettingsNotificationTemplates':
        return t.businessSettingsNotificationTemplates;
      case 'businessSettingsAppearanceProfile':
        return t.appearanceSettingsPageTitle;
      case 'dataBackup':
        return t.dataBackup;
      case 'ftpBackupSettingsTitle':
        return t.ftpBackupSettingsTitle;
      case 'businessSettingsAiProviderTitle':
        return 'ارائه‌دهنده هوش مصنوعی';
      case 'dataRestore':
        return t.dataRestore;
      case 'systemLogs':
        return t.systemLogs;
      case 'businessSettingsLeaveBusiness':
        return t.businessSettingsLeaveBusiness;
      case 'businessSettingsDeleteBusiness':
        return t.businessSettingsDeleteBusiness;
      case 'businessSettingsFiscalYearRollback':
        return t.businessSettingsFiscalYearRollback;
      default:
        return key;
    }
  }

  static String getDescription(AppLocalizations t, String key) {
    switch (key) {
      case 'businessSettingsDescription':
        return t.businessSettingsDescription;
      case 'settingsSideCurrenciesSubtitle':
        return t.settingsSideCurrenciesSubtitle;
      case 'settingsInvoiceFxPolicySubtitle':
        return t.settingsInvoiceFxPolicySubtitle;
      case 'settingsFxAutoSyncSubtitle':
        return t.settingsFxAutoSyncSubtitle;
      case 'businessSettingsFiscalYearEditDescription':
        return t.businessSettingsFiscalYearEditDescription;
      case 'creditSettingsSubtitle':
        return t.creditSettingsSubtitle;
      case 'businessSettingsQuickSalesDescription':
        return t.businessSettingsQuickSalesDescription;
      case 'installmentsSettingsSubtitle':
        return t.installmentsSettingsSubtitle;
      case 'printDocumentsDescription':
        return t.printDocumentsDescription;
      case 'businessSettingsDocumentNumberingDescription':
        return t.businessSettingsDocumentNumberingDescription;
      case 'businessSettingsInvoiceSharePaymentDescription':
        return t.businessSettingsInvoiceSharePaymentDescription;
      case 'businessSettingsTemplatesDescription':
        return t.businessSettingsTemplatesDescription;
      case 'documentMonetizationSubtitle':
        return t.documentMonetizationSubtitle;
      case 'businessSettingsCrmDescription':
        return t.businessSettingsCrmDescription;
      case 'taxIntegrationSubtitle':
        return t.taxIntegrationSubtitle;
      case 'settingsBasalamSubtitle':
        return t.settingsBasalamSubtitle;
      case 'settingsWooCommerceSubtitle':
        return t.settingsWooCommerceSubtitle;
      case 'businessSettingsWarrantyDescription':
        return t.businessSettingsWarrantyDescription;
      case 'businessSettingsRepairShopDescription':
        return t.businessSettingsRepairShopDescription;
      case 'customerClubSettingsSubtitle':
        return t.customerClubSettingsSubtitle;
      case 'distributionSettingsSubtitle':
        return t.distributionSettingsSubtitle;
      case 'usersAndPermissionsDescription':
        return t.usersAndPermissionsDescription;
      case 'businessSettingsProjectsDescription':
        return t.businessSettingsProjectsDescription;
      case 'businessSettingsNotificationTemplatesDescription':
        return t.businessSettingsNotificationTemplatesDescription;
      case 'businessSettingsAppearanceProfileDescription':
        return t.businessSettingsAppearanceProfileDescription;
      case 'dataBackupDescription':
        return t.dataBackupDescription;
      case 'ftpBackupSettingsDescription':
        return t.ftpBackupSettingsDescription;
      case 'businessSettingsAiProviderDescription':
        return 'اتصال URL، API Key و مدل‌های اختصاصی کسب‌وکار';
      case 'dataRestoreDescription':
        return t.dataRestoreDescription;
      case 'systemLogsDescription':
        return t.systemLogsDescription;
      case 'businessSettingsLeaveBusinessDescription':
        return t.businessSettingsLeaveBusinessDescription;
      case 'businessSettingsDeleteBusinessDescription':
        return t.businessSettingsDeleteBusinessDescription;
      case 'businessSettingsFiscalYearRollbackDescription':
        return t.businessSettingsFiscalYearRollbackDescription;
      default:
        return key;
    }
  }

  static String getCategoryTitle(AppLocalizations t, String key) {
    switch (key) {
      case 'businessSettingsCategoryBusinessFinance':
        return t.businessSettingsCategoryBusinessFinance;
      case 'businessSettingsCategorySalesDocuments':
        return t.businessSettingsCategorySalesDocuments;
      case 'businessSettingsCategoryIntegrations':
        return t.businessSettingsCategoryIntegrations;
      case 'businessSettingsCategoryModules':
        return t.businessSettingsCategoryModules;
      case 'businessSettingsCategoryAdministration':
        return t.businessSettingsCategoryAdministration;
      case 'businessSettingsCategoryPersonalization':
        return t.businessSettingsCategoryPersonalization;
      case 'businessSettingsCategoryAdvanced':
        return t.businessSettingsCategoryAdvanced;
      case 'businessSettingsCategoryMembership':
        return t.businessSettingsCategoryMembership;
      case 'businessSettingsCategoryDangerZone':
        return t.businessSettingsCategoryDangerZone;
      default:
        return key;
    }
  }

  static String getCategoryDescription(AppLocalizations t, String? key) {
    if (key == null) return '';
    switch (key) {
      case 'businessSettingsCategoryBusinessFinanceDescription':
        return t.businessSettingsCategoryBusinessFinanceDescription;
      case 'businessSettingsCategorySalesDocumentsDescription':
        return t.businessSettingsCategorySalesDocumentsDescription;
      case 'businessSettingsCategoryIntegrationsDescription':
        return t.businessSettingsCategoryIntegrationsDescription;
      case 'businessSettingsCategoryModulesDescription':
        return t.businessSettingsCategoryModulesDescription;
      case 'businessSettingsCategoryAdministrationDescription':
        return t.businessSettingsCategoryAdministrationDescription;
      case 'businessSettingsCategoryPersonalizationDescription':
        return t.businessSettingsCategoryPersonalizationDescription;
      case 'businessSettingsCategoryAdvancedDescription':
        return t.businessSettingsCategoryAdvancedDescription;
      case 'businessSettingsCategoryMembershipDescription':
        return t.businessSettingsCategoryMembershipDescription;
      case 'businessSettingsCategoryDangerZoneDescription':
        return t.businessSettingsCategoryDangerZoneDescription;
      default:
        return key;
    }
  }

  static bool itemMatchesSearch(
    AppLocalizations t,
    SettingsItem item,
    String lowerQuery,
  ) {
    if (lowerQuery.isEmpty) return false;
    final title = getTitle(t, item.title).toLowerCase();
    final desc = getDescription(t, item.description).toLowerCase();
    return item.id.toLowerCase().contains(lowerQuery) ||
        item.title.toLowerCase().contains(lowerQuery) ||
        item.description.toLowerCase().contains(lowerQuery) ||
        title.contains(lowerQuery) ||
        desc.contains(lowerQuery);
  }

  static bool categoryMatchesSearch(
    AppLocalizations t,
    SettingsCategory category,
    String lowerQuery,
  ) {
    if (lowerQuery.isEmpty) return false;
    final title = getCategoryTitle(t, category.title).toLowerCase();
    final descKey = category.description;
    final desc = descKey != null
        ? getCategoryDescription(t, descKey).toLowerCase()
        : '';
    return title.contains(lowerQuery) || desc.contains(lowerQuery);
  }

  static List<SettingsItem> searchItems({
    required String query,
    required AppLocalizations t,
    required List<SettingsCategory> categories,
  }) {
    final lowerQuery = query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return [];

    final results = <SettingsItem>[];
    for (final category in categories) {
      if (categoryMatchesSearch(t, category, lowerQuery)) {
        results.addAll(category.items);
        continue;
      }
      for (final item in category.items) {
        if (itemMatchesSearch(t, item, lowerQuery)) {
          results.add(item);
        }
      }
    }
    return results;
  }
}
