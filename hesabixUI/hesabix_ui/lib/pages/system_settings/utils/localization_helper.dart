import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../models/settings_category.dart';
import '../models/settings_item.dart';

/// Helper class for getting localized strings from keys
class LocalizationHelper {
  /// Get localized title for a settings item
  static String getTitle(AppLocalizations t, String key) {
    switch (key) {
      case 'storageManagement':
        return t.storageManagement;
      case 'systemConfiguration':
        return t.systemConfiguration;
      case 'userManagement':
        return t.userManagement;
      case 'settingsSystemReports':
        return t.settingsSystemReports;
      case 'emailSettings':
        return t.emailSettings;
      case 'settingsShareLinks':
        return t.settingsShareLinks;
      case 'settingsRedisCache':
        return t.settingsRedisCache;
      case 'settingsFirewall':
        return t.settingsFirewall;
      case 'settingsStoragePlans':
        return t.settingsStoragePlans;
      case 'settingsDocumentMonetization':
        return t.settingsDocumentMonetization;
      case 'settingsMarketplacePlugins':
        return t.settingsMarketplacePlugins;
      case 'settingsWalletSettings':
        return t.settingsWalletSettings;
      case 'settingsCurrenciesAdmin':
        return t.settingsCurrenciesAdmin;
      case 'settingsFxProvidersAdmin':
        return t.settingsFxProvidersAdmin;
      case 'settingsWalletPayoutsAdmin':
        return t.settingsWalletPayoutsAdmin;
      case 'settingsSupportOperators':
        return t.settingsSupportOperators;
      case 'settingsSupportPlans':
        return t.settingsSupportPlans;
      case 'settingsSupportBillingStats':
        return t.settingsSupportBillingStats;
      case 'settingsPaymentGateways':
        return t.settingsPaymentGateways;
      case 'settingsPayPageDomain':
        return t.settingsPayPageDomain;
      case 'settingsPayPageAbuseReports':
        return t.settingsPayPageAbuseReports;
      case 'settingsBusinessesManagement':
        return t.settingsBusinessesManagement;
      case 'settingsAnnouncements':
        return t.settingsAnnouncements;
      case 'settingsNotifications':
        return t.settingsNotifications;
      case 'settingsNotificationTemplates':
        return t.settingsNotificationTemplates;
      case 'settingsNotificationEventDefaults':
        return t.settingsNotificationEventDefaults;
      case 'settingsNotificationModeration':
        return t.settingsNotificationModeration;
      case 'settingsNotificationSmsPricing':
        return t.settingsNotificationSmsPricing;
      case 'settingsAISettings':
        return t.settingsAISettings;
      case 'settingsAIModels':
        return t.settingsAIModels;
      case 'settingsAIVoiceModels':
        return t.settingsAIVoiceModels;
      case 'settingsAIProviderCredentials':
        return t.settingsAIProviderCredentials;
      case 'settingsAIPlans':
        return t.settingsAIPlans;
      case 'settingsAIPrompts':
        return t.settingsAIPrompts;
      case 'settingsAISkills':
        return t.settingsAISkills;
      case 'settingsAIMarketplace':
        return t.settingsAIMarketplace;
      case 'settingsAIEval':
        return t.settingsAIEval;
      case 'settingsZohalServices':
        return t.settingsZohalServices;
      case 'settingsZohalSettings':
        return t.settingsZohalSettings;
      case 'settingsZohalStatistics':
        return t.settingsZohalStatistics;
      case 'settingsTaxProductCodes':
        return t.settingsTaxProductCodes;
      case 'settingsTaxProviders':
        return t.settingsTaxProviders;
      case 'settingsMotamedAsa':
        return t.settingsMotamedAsa;
      case 'settingsSystemMonitoring':
        return t.settingsSystemMonitoring;
      case 'settingsServiceLogs':
        return t.settingsServiceLogs;
      case 'settingsBusinessActivityLogs':
        return t.settingsBusinessActivityLogs;
      case 'settingsDatabaseBackup':
        return t.settingsDatabaseBackup;
      case 'settingsLegacyDatabaseImport':
        return t.settingsLegacyDatabaseImport;
      case 'settingsSystemScripts':
        return t.settingsSystemScripts;
      default:
        return _extra(t, key) ?? key;
    }
  }

  static String? _extra(AppLocalizations t, String key) {
    const fa = {
      'systemAdminOpsHomeTitle': 'خانه عملیاتی',
      'systemAdminOpsHomeDescription': 'صف اعلان، ورود ناموفق، ذخیره‌سازی و زمان‌بندی',
      'systemAdminAuditTitle': 'لاگ کارهای مدیر',
      'systemAdminAuditDescription': 'چه کسی پیکربندی، بکاپ، هدیه یا صف را عوض کرده',
      'systemAdminSchedulesTitle': 'کارهای زمان‌بندی‌شده',
      'systemAdminSchedulesDescription': 'کرون ورک‌فلو و ارزیابی AI',
      'systemAdminWalletsTitle': 'فهرست کیف‌پول',
      'systemAdminWalletsDescription': 'مانده کسب‌وکارها و استرداد مدیریتی',
      'systemAdminHscriptTitle': 'اجرای HScript',
      'systemAdminHscriptDescription': 'ممیزی اجرای گزارش سفارشی در همه کسب‌وکارها',
      'systemAdminLicensesTitle': 'انقضای لایسنس',
      'systemAdminLicensesDescription': 'تا ۳۰ روز آینده، تازه‌منقضی، یا هنوز فعال ولی سررسیدشده',
      'systemAdminOutboxTitle': 'صف اعلان',
      'systemAdminOutboxDescription': 'رها کردن صف ناموفق؛ فقط مدیر کل',
      'systemAdminAiHubTitle': 'هوش مصنوعی',
      'systemAdminAiHubDescription': 'تنظیمات، کلید، مدل، پلن و ارزیابی در یک بخش',
      'systemAdminNotificationChannelsTitle': 'کانال‌های اعلان سیستم',
      'systemAdminNotificationChannelsDescription': 'توکن ربات، وب‌هوک و پیامک سراسری',
      'settingsCategoryOperationsHome': 'عملیات',
      'settingsCategoryOperationsHomeDescription': 'وضعیت لحظه‌ای، لاگ مدیر و زمان‌بندی',
    };
    const en = {
      'systemAdminOpsHomeTitle': 'Operations home',
      'systemAdminOpsHomeDescription': 'Notification queue, failed logins, storage, and schedules',
      'systemAdminAuditTitle': 'Admin audit log',
      'systemAdminAuditDescription': 'Who changed configuration, backups, gifts, or the queue',
      'systemAdminSchedulesTitle': 'Scheduled jobs',
      'systemAdminSchedulesDescription': 'Workflow cron and AI evaluation',
      'systemAdminWalletsTitle': 'Wallet directory',
      'systemAdminWalletsDescription': 'Business balances and admin refunds',
      'systemAdminHscriptTitle': 'HScript runs',
      'systemAdminHscriptDescription': 'Custom report runs across businesses',
      'systemAdminLicensesTitle': 'License expiry',
      'systemAdminLicensesDescription': 'Next 30 days, recently expired, or overdue but still active',
      'systemAdminOutboxTitle': 'Notification queue',
      'systemAdminOutboxDescription': 'Abandon failed rows; super admin only',
      'systemAdminAiHubTitle': 'Artificial intelligence',
      'systemAdminAiHubDescription': 'Settings, keys, models, plans, and evaluation',
      'systemAdminNotificationChannelsTitle': 'System notification channels',
      'systemAdminNotificationChannelsDescription': 'Bot tokens, webhooks, and system SMS',
      'settingsCategoryOperationsHome': 'Operations',
      'settingsCategoryOperationsHomeDescription': 'Live status, admin audit, and schedules',
    };
    final table = t.localeName.startsWith('fa') ? fa : en;
    return table[key];
  }

  /// Get localized description for a settings item
  static String getDescription(AppLocalizations t, String key) {
    switch (key) {
      case 'storageManagementDescription':
        return t.storageManagementDescription;
      case 'systemConfigurationDescription':
        return t.systemConfigurationDescription;
      case 'userManagementDescription':
        return t.userManagementDescription;
      case 'settingsSystemReportsDescription':
        return t.settingsSystemReportsDescription;
      case 'emailSettingsDescription':
        return t.emailSettingsDescription;
      case 'settingsShareLinksDescription':
        return t.settingsShareLinksDescription;
      case 'settingsRedisCacheDescription':
        return t.settingsRedisCacheDescription;
      case 'settingsFirewallDescription':
        return t.settingsFirewallDescription;
      case 'settingsStoragePlansDescription':
        return t.settingsStoragePlansDescription;
      case 'settingsDocumentMonetizationDescription':
        return t.settingsDocumentMonetizationDescription;
      case 'settingsMarketplacePluginsDescription':
        return t.settingsMarketplacePluginsDescription;
      case 'settingsWalletSettingsDescription':
        return t.settingsWalletSettingsDescription;
      case 'settingsCurrenciesAdminDescription':
        return t.settingsCurrenciesAdminDescription;
      case 'settingsFxProvidersAdminDescription':
        return t.settingsFxProvidersAdminDescription;
      case 'settingsWalletPayoutsAdminDescription':
        return t.settingsWalletPayoutsAdminDescription;
      case 'settingsSupportOperatorsDescription':
        return t.settingsSupportOperatorsDescription;
      case 'settingsSupportPlansDescription':
        return t.settingsSupportPlansDescription;
      case 'settingsSupportBillingStatsDescription':
        return t.settingsSupportBillingStatsDescription;
      case 'settingsPaymentGatewaysDescription':
        return t.settingsPaymentGatewaysDescription;
      case 'settingsPayPageDomainDescription':
        return t.settingsPayPageDomainDescription;
      case 'settingsPayPageAbuseReportsDescription':
        return t.settingsPayPageAbuseReportsDescription;
      case 'settingsBusinessesManagementDescription':
        return t.settingsBusinessesManagementDescription;
      case 'settingsAnnouncementsDescription':
        return t.settingsAnnouncementsDescription;
      case 'settingsNotificationsDescription':
        return t.settingsNotificationsDescription;
      case 'settingsNotificationTemplatesDescription':
        return t.settingsNotificationTemplatesDescription;
      case 'settingsNotificationEventDefaultsDescription':
        return t.settingsNotificationEventDefaultsDescription;
      case 'settingsNotificationModerationDescription':
        return t.settingsNotificationModerationDescription;
      case 'settingsNotificationSmsPricingDescription':
        return t.settingsNotificationSmsPricingDescription;
      case 'settingsAISettingsDescription':
        return t.settingsAISettingsDescription;
      case 'settingsAIModelsDescription':
        return t.settingsAIModelsDescription;
      case 'settingsAIVoiceModelsDescription':
        return t.settingsAIVoiceModelsDescription;
      case 'settingsAIProviderCredentialsDescription':
        return t.settingsAIProviderCredentialsDescription;
      case 'settingsAIPlansDescription':
        return t.settingsAIPlansDescription;
      case 'settingsAIPromptsDescription':
        return t.settingsAIPromptsDescription;
      case 'settingsAISkillsDescription':
        return t.settingsAISkillsDescription;
      case 'settingsAIMarketplaceDescription':
        return t.settingsAIMarketplaceDescription;
      case 'settingsAIEvalDescription':
        return t.settingsAIEvalDescription;
      case 'settingsZohalServicesDescription':
        return t.settingsZohalServicesDescription;
      case 'settingsZohalSettingsDescription':
        return t.settingsZohalSettingsDescription;
      case 'settingsZohalStatisticsDescription':
        return t.settingsZohalStatisticsDescription;
      case 'settingsTaxProductCodesDescription':
        return t.settingsTaxProductCodesDescription;
      case 'settingsTaxProvidersDescription':
        return t.settingsTaxProvidersDescription;
      case 'settingsMotamedAsaDescription':
        return t.settingsMotamedAsaDescription;
      case 'settingsSystemMonitoringDescription':
        return t.settingsSystemMonitoringDescription;
      case 'settingsServiceLogsDescription':
        return t.settingsServiceLogsDescription;
      case 'settingsBusinessActivityLogsDescription':
        return t.settingsBusinessActivityLogsDescription;
      case 'settingsDatabaseBackupDescription':
        return t.settingsDatabaseBackupDescription;
      case 'settingsLegacyDatabaseImportDescription':
        return t.settingsLegacyDatabaseImportDescription;
      case 'settingsSystemScriptsDescription':
        return t.settingsSystemScriptsDescription;
      default:
        return _extra(t, key) ?? key;
    }
  }

  /// Get localized title for a category
  static String getCategoryTitle(AppLocalizations t, String key) {
    switch (key) {
      case 'settingsCategoryCoreConfiguration':
        return t.settingsCategoryCoreConfiguration;
      case 'settingsCategoryStorageFiles':
        return t.settingsCategoryStorageFiles;
      case 'settingsCategoryFinancialPayment':
        return t.settingsCategoryFinancialPayment;
      case 'settingsCategoryUsersBusinesses':
        return t.settingsCategoryUsersBusinesses;
      case 'settingsCategoryCommunications':
        return t.settingsCategoryCommunications;
      case 'settingsCategoryAI':
        return t.settingsCategoryAI;
      case 'settingsCategoryExternalServices':
        return t.settingsCategoryExternalServices;
      case 'settingsCategoryMonitoringLogs':
        return t.settingsCategoryMonitoringLogs;
      case 'settingsCategoryMaintenance':
        return t.settingsCategoryMaintenance;
      default:
        return _extra(t, key) ?? key;
    }
  }

  /// Get localized description for a category
  static String getCategoryDescription(AppLocalizations t, String? key) {
    if (key == null) return '';
    switch (key) {
      case 'settingsCategoryCoreConfigurationDescription':
        return t.settingsCategoryCoreConfigurationDescription;
      case 'settingsCategoryStorageFilesDescription':
        return t.settingsCategoryStorageFilesDescription;
      case 'settingsCategoryFinancialPaymentDescription':
        return t.settingsCategoryFinancialPaymentDescription;
      case 'settingsCategoryUsersBusinessesDescription':
        return t.settingsCategoryUsersBusinessesDescription;
      case 'settingsCategoryCommunicationsDescription':
        return t.settingsCategoryCommunicationsDescription;
      case 'settingsCategoryAIDescription':
        return t.settingsCategoryAIDescription;
      case 'settingsCategoryExternalServicesDescription':
        return t.settingsCategoryExternalServicesDescription;
      case 'settingsCategoryMonitoringLogsDescription':
        return t.settingsCategoryMonitoringLogsDescription;
      case 'settingsCategoryMaintenanceDescription':
        return t.settingsCategoryMaintenanceDescription;
      default:
        final extra = _extra(t, key);
        return extra ?? key;
    }
  }

  /// جستجو روی کلیدهای داخلی، متن لوکالایز شده عنوان/توضیح آیتم
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

  /// اگر عنوان/توضیح دسته با جُستار هم‌خوان باشد، همهٔ آیتم‌های همان دسته در نتیجه می‌آیند
  static bool categoryMatchesSearch(AppLocalizations t, SettingsCategory category, String lowerQuery) {
    if (lowerQuery.isEmpty) return false;
    final title = getCategoryTitle(t, category.title).toLowerCase();
    final descKey = category.description;
    final desc =
        descKey != null ? getCategoryDescription(t, descKey).toLowerCase() : '';
    return title.contains(lowerQuery) || desc.contains(lowerQuery);
  }
}

