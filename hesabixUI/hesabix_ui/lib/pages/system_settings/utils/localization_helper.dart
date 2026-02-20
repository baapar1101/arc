import 'package:hesabix_ui/l10n/app_localizations.dart';

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
      case 'systemLogs':
        return t.systemLogs;
      case 'emailSettings':
        return t.emailSettings;
      case 'settingsShareLinks':
        return t.settingsShareLinks;
      case 'settingsRedisCache':
        return t.settingsRedisCache;
      case 'settingsStoragePlans':
        return t.settingsStoragePlans;
      case 'settingsDocumentMonetization':
        return t.settingsDocumentMonetization;
      case 'settingsMarketplacePlugins':
        return t.settingsMarketplacePlugins;
      case 'settingsWalletSettings':
        return t.settingsWalletSettings;
      case 'settingsPaymentGateways':
        return t.settingsPaymentGateways;
      case 'settingsBusinessesManagement':
        return t.settingsBusinessesManagement;
      case 'settingsAnnouncements':
        return t.settingsAnnouncements;
      case 'settingsNotifications':
        return t.settingsNotifications;
      case 'settingsNotificationTemplates':
        return t.settingsNotificationTemplates;
      case 'settingsAISettings':
        return t.settingsAISettings;
      case 'settingsAIPlans':
        return t.settingsAIPlans;
      case 'settingsAIPrompts':
        return t.settingsAIPrompts;
      case 'settingsZohalServices':
        return t.settingsZohalServices;
      case 'settingsZohalSettings':
        return t.settingsZohalSettings;
      case 'settingsTaxProductCodes':
        return t.settingsTaxProductCodes;
      case 'settingsSystemMonitoring':
        return t.settingsSystemMonitoring;
      case 'settingsServiceLogs':
        return t.settingsServiceLogs;
      case 'settingsDatabaseBackup':
        return t.settingsDatabaseBackup;
      default:
        return key;
    }
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
      case 'systemLogsDescription':
        return t.systemLogsDescription;
      case 'emailSettingsDescription':
        return t.emailSettingsDescription;
      case 'settingsShareLinksDescription':
        return t.settingsShareLinksDescription;
      case 'settingsRedisCacheDescription':
        return t.settingsRedisCacheDescription;
      case 'settingsStoragePlansDescription':
        return t.settingsStoragePlansDescription;
      case 'settingsDocumentMonetizationDescription':
        return t.settingsDocumentMonetizationDescription;
      case 'settingsMarketplacePluginsDescription':
        return t.settingsMarketplacePluginsDescription;
      case 'settingsWalletSettingsDescription':
        return t.settingsWalletSettingsDescription;
      case 'settingsPaymentGatewaysDescription':
        return t.settingsPaymentGatewaysDescription;
      case 'settingsBusinessesManagementDescription':
        return t.settingsBusinessesManagementDescription;
      case 'settingsAnnouncementsDescription':
        return t.settingsAnnouncementsDescription;
      case 'settingsNotificationsDescription':
        return t.settingsNotificationsDescription;
      case 'settingsNotificationTemplatesDescription':
        return t.settingsNotificationTemplatesDescription;
      case 'settingsAISettingsDescription':
        return t.settingsAISettingsDescription;
      case 'settingsAIPlansDescription':
        return t.settingsAIPlansDescription;
      case 'settingsAIPromptsDescription':
        return t.settingsAIPromptsDescription;
      case 'settingsZohalServicesDescription':
        return t.settingsZohalServicesDescription;
      case 'settingsZohalSettingsDescription':
        return t.settingsZohalSettingsDescription;
      case 'settingsTaxProductCodesDescription':
        return t.settingsTaxProductCodesDescription;
      case 'settingsSystemMonitoringDescription':
        return t.settingsSystemMonitoringDescription;
      case 'settingsServiceLogsDescription':
        return t.settingsServiceLogsDescription;
      case 'settingsDatabaseBackupDescription':
        return t.settingsDatabaseBackupDescription;
      default:
        return key;
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
      default:
        return key;
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
      default:
        return key;
    }
  }
}

