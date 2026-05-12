import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Hesabix'**
  String get appTitle;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please try again.'**
  String get loginFailed;

  /// No description provided for @homeWelcome.
  ///
  /// In en, this message translates to:
  /// **'Signed in successfully!'**
  String get homeWelcome;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'is required'**
  String get requiredField;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password'**
  String get forgotPassword;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get lastName;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @mobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get mobile;

  /// No description provided for @registerSuccess.
  ///
  /// In en, this message translates to:
  /// **'Registration successful.'**
  String get registerSuccess;

  /// No description provided for @forgotSent.
  ///
  /// In en, this message translates to:
  /// **'Reset link sent to your email.'**
  String get forgotSent;

  /// No description provided for @identifier.
  ///
  /// In en, this message translates to:
  /// **'Email or mobile'**
  String get identifier;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Hesabix Cloud Accounting'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Smart, secure, and always available accounting for your business.'**
  String get welcomeSubtitle;

  /// No description provided for @brandTagline.
  ///
  /// In en, this message translates to:
  /// **'Manage your finances anywhere, anytime with confidence.'**
  String get brandTagline;

  /// No description provided for @captcha.
  ///
  /// In en, this message translates to:
  /// **'Captcha'**
  String get captcha;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @captchaRequired.
  ///
  /// In en, this message translates to:
  /// **'Captcha is required.'**
  String get captchaRequired;

  /// No description provided for @acceptTermsPrefix.
  ///
  /// In en, this message translates to:
  /// **'I accept '**
  String get acceptTermsPrefix;

  /// No description provided for @acceptTermsSuffix.
  ///
  /// In en, this message translates to:
  /// **''**
  String get acceptTermsSuffix;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get and;

  /// No description provided for @acceptTermsRequired.
  ///
  /// In en, this message translates to:
  /// **'You must accept the Privacy Policy and Terms of Service to register.'**
  String get acceptTermsRequired;

  /// No description provided for @sendReset.
  ///
  /// In en, this message translates to:
  /// **'Send reset code'**
  String get sendReset;

  /// No description provided for @registerFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed. Please try again.'**
  String get registerFailed;

  /// No description provided for @resetFailed.
  ///
  /// In en, this message translates to:
  /// **'Request failed. Please try again.'**
  String get resetFailed;

  /// No description provided for @fixFormErrors.
  ///
  /// In en, this message translates to:
  /// **'Please fix the form errors.'**
  String get fixFormErrors;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @logoutDone.
  ///
  /// In en, this message translates to:
  /// **'Signed out.'**
  String get logoutDone;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get logoutConfirmMessage;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @systemSettings.
  ///
  /// In en, this message translates to:
  /// **'System Settings'**
  String get systemSettings;

  /// No description provided for @adminTools.
  ///
  /// In en, this message translates to:
  /// **'Admin Tools'**
  String get adminTools;

  /// No description provided for @emailSettings.
  ///
  /// In en, this message translates to:
  /// **'Email Settings'**
  String get emailSettings;

  /// No description provided for @emailSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure SMTP settings for email sending'**
  String get emailSettingsDescription;

  /// No description provided for @emailConfigurations.
  ///
  /// In en, this message translates to:
  /// **'Email Configurations'**
  String get emailConfigurations;

  /// No description provided for @noEmailConfigurations.
  ///
  /// In en, this message translates to:
  /// **'No email configurations found'**
  String get noEmailConfigurations;

  /// No description provided for @addEmailConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Add Email Configuration'**
  String get addEmailConfiguration;

  /// No description provided for @configurationName.
  ///
  /// In en, this message translates to:
  /// **'Configuration Name'**
  String get configurationName;

  /// No description provided for @smtpHost.
  ///
  /// In en, this message translates to:
  /// **'SMTP Host'**
  String get smtpHost;

  /// No description provided for @smtpPort.
  ///
  /// In en, this message translates to:
  /// **'SMTP Port'**
  String get smtpPort;

  /// No description provided for @smtpUsername.
  ///
  /// In en, this message translates to:
  /// **'SMTP Username'**
  String get smtpUsername;

  /// No description provided for @smtpPassword.
  ///
  /// In en, this message translates to:
  /// **'SMTP Password'**
  String get smtpPassword;

  /// No description provided for @fromEmail.
  ///
  /// In en, this message translates to:
  /// **'From Email'**
  String get fromEmail;

  /// No description provided for @fromName.
  ///
  /// In en, this message translates to:
  /// **'From Name'**
  String get fromName;

  /// No description provided for @useTls.
  ///
  /// In en, this message translates to:
  /// **'Use TLS'**
  String get useTls;

  /// No description provided for @useSsl.
  ///
  /// In en, this message translates to:
  /// **'Use SSL'**
  String get useSsl;

  /// No description provided for @isActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get isActive;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

  /// No description provided for @sendTestEmail.
  ///
  /// In en, this message translates to:
  /// **'Send Test Email'**
  String get sendTestEmail;

  /// No description provided for @saveConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Save Configuration'**
  String get saveConfiguration;

  /// No description provided for @deleteConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Delete Configuration'**
  String get deleteConfiguration;

  /// No description provided for @deleteConfigurationConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this configuration?'**
  String get deleteConfigurationConfirm;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @invalidPort.
  ///
  /// In en, this message translates to:
  /// **'Invalid port'**
  String get invalidPort;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email'**
  String get invalidEmail;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @columnSettings.
  ///
  /// In en, this message translates to:
  /// **'Column Settings'**
  String get columnSettings;

  /// No description provided for @columnSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage column visibility and order for this table'**
  String get columnSettingsDescription;

  /// No description provided for @columnName.
  ///
  /// In en, this message translates to:
  /// **'Column Name'**
  String get columnName;

  /// No description provided for @visibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get visibility;

  /// No description provided for @order.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get order;

  /// No description provided for @visible.
  ///
  /// In en, this message translates to:
  /// **'Visible'**
  String get visible;

  /// No description provided for @hidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hidden;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get resetToDefaults;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @bulkDefaultWarehouseTitle.
  ///
  /// In en, this message translates to:
  /// **'Bulk default warehouse'**
  String get bulkDefaultWarehouseTitle;

  /// No description provided for @bulkDefaultWarehouseAction.
  ///
  /// In en, this message translates to:
  /// **'Change default warehouse'**
  String get bulkDefaultWarehouseAction;

  /// No description provided for @bulkDefaultWarehouseNewWarehouseLabel.
  ///
  /// In en, this message translates to:
  /// **'New warehouse'**
  String get bulkDefaultWarehouseNewWarehouseLabel;

  /// No description provided for @bulkDefaultWarehouseClearOption.
  ///
  /// In en, this message translates to:
  /// **'Clear default warehouse (empty)'**
  String get bulkDefaultWarehouseClearOption;

  /// No description provided for @bulkDefaultWarehouseScopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Apply scope (Policy):'**
  String get bulkDefaultWarehouseScopeLabel;

  /// No description provided for @bulkDefaultWarehouseScopeAll.
  ///
  /// In en, this message translates to:
  /// **'All selected'**
  String get bulkDefaultWarehouseScopeAll;

  /// No description provided for @bulkDefaultWarehouseScopeTrackInventoryTrue.
  ///
  /// In en, this message translates to:
  /// **'Only inventory-tracked items (track_inventory=true)'**
  String get bulkDefaultWarehouseScopeTrackInventoryTrue;

  /// No description provided for @bulkDefaultWarehouseScopeTrackInventoryFalse.
  ///
  /// In en, this message translates to:
  /// **'Only non-inventory items (track_inventory=false)'**
  String get bulkDefaultWarehouseScopeTrackInventoryFalse;

  /// No description provided for @bulkDefaultWarehouseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply changes'**
  String get bulkDefaultWarehouseConfirmTitle;

  /// No description provided for @bulkDefaultWarehouseConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to apply this default warehouse change to the selected items?'**
  String get bulkDefaultWarehouseConfirmMessage;

  /// No description provided for @bulkDefaultWarehouseApplySuccess.
  ///
  /// In en, this message translates to:
  /// **'Done. Updated: {count}'**
  String bulkDefaultWarehouseApplySuccess(String count);

  /// No description provided for @bulkDefaultWarehouseSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'Selected items: {count}'**
  String bulkDefaultWarehouseSelectedCount(int count);

  /// No description provided for @bulkDefaultWarehousePreviewSummary.
  ///
  /// In en, this message translates to:
  /// **'Requested: {total} | Found: {found} | Will update: {willUpdate}'**
  String bulkDefaultWarehousePreviewSummary(
    String total,
    String found,
    String willUpdate,
  );

  /// No description provided for @bulkDefaultWarehouseSkippedCount.
  ///
  /// In en, this message translates to:
  /// **'Skipped: {count}'**
  String bulkDefaultWarehouseSkippedCount(int count);

  /// No description provided for @bulkDefaultWarehouseNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes:'**
  String get bulkDefaultWarehouseNotesLabel;

  /// No description provided for @bulkDefaultWarehouseForcedServiceNull.
  ///
  /// In en, this message translates to:
  /// **'Service items forced to null default warehouse: {count}'**
  String bulkDefaultWarehouseForcedServiceNull(int count);

  /// No description provided for @bulkDefaultWarehouseApplySummary.
  ///
  /// In en, this message translates to:
  /// **'Requested: {total} | Found: {found} | Updated: {updated} | Skipped: {skipped}'**
  String bulkDefaultWarehouseApplySummary(
    String total,
    String found,
    String updated,
    String skipped,
  );

  /// No description provided for @bulkDefaultWarehouseReasonAlreadySet.
  ///
  /// In en, this message translates to:
  /// **'Already set'**
  String get bulkDefaultWarehouseReasonAlreadySet;

  /// No description provided for @bulkDefaultWarehouseReasonScopeMismatch.
  ///
  /// In en, this message translates to:
  /// **'Out of selected scope'**
  String get bulkDefaultWarehouseReasonScopeMismatch;

  /// No description provided for @bulkDefaultWarehouseReasonNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get bulkDefaultWarehouseReasonNotFound;

  /// No description provided for @bulkDefaultWarehouseReasonServiceAlreadyNull.
  ///
  /// In en, this message translates to:
  /// **'Service item must have no default warehouse'**
  String get bulkDefaultWarehouseReasonServiceAlreadyNull;

  /// No description provided for @bulkDefaultWarehouseReasonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get bulkDefaultWarehouseReasonUnknown;

  /// No description provided for @newBusiness.
  ///
  /// In en, this message translates to:
  /// **'New business'**
  String get newBusiness;

  /// No description provided for @businesses.
  ///
  /// In en, this message translates to:
  /// **'Businesses'**
  String get businesses;

  /// No description provided for @deleteBusiness.
  ///
  /// In en, this message translates to:
  /// **'Delete Business'**
  String get deleteBusiness;

  /// No description provided for @loanFacilities.
  ///
  /// In en, this message translates to:
  /// **'Loan facilities'**
  String get loanFacilities;

  /// No description provided for @loanFacilityReloadTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get loanFacilityReloadTooltip;

  /// No description provided for @loanFacilitySearchTitlesLabel.
  ///
  /// In en, this message translates to:
  /// **'Search titles'**
  String get loanFacilitySearchTitlesLabel;

  /// No description provided for @loanFacilityEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No contracts yet. Tap add to create one.'**
  String get loanFacilityEmptyState;

  /// No description provided for @loanFacilityLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loanFacilityLoadMore;

  /// No description provided for @loanFacilityValidationTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get loanFacilityValidationTitleRequired;

  /// No description provided for @loanFacilityValidationSelectCurrency.
  ///
  /// In en, this message translates to:
  /// **'Select a currency'**
  String get loanFacilityValidationSelectCurrency;

  /// No description provided for @loanFacilityValidationPrincipalInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid principal amount'**
  String get loanFacilityValidationPrincipalInvalid;

  /// No description provided for @loanFacilityDialogNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New contract'**
  String get loanFacilityDialogNewTitle;

  /// No description provided for @loanFacilityDialogEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit contract'**
  String get loanFacilityDialogEditTitle;

  /// No description provided for @loanFacilityFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title *'**
  String get loanFacilityFieldTitle;

  /// No description provided for @loanFacilityFieldCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency *'**
  String get loanFacilityFieldCurrency;

  /// No description provided for @loanFacilityFieldCurrencyHint.
  ///
  /// In en, this message translates to:
  /// **'Choose currency'**
  String get loanFacilityFieldCurrencyHint;

  /// No description provided for @loanFacilityFieldPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Principal *'**
  String get loanFacilityFieldPrincipal;

  /// No description provided for @loanFacilityFieldContractDate.
  ///
  /// In en, this message translates to:
  /// **'Contract date *'**
  String get loanFacilityFieldContractDate;

  /// No description provided for @loanFacilityFieldContractDateHint.
  ///
  /// In en, this message translates to:
  /// **'Pick'**
  String get loanFacilityFieldContractDateHint;

  /// No description provided for @loanFacilityFieldAnnualRate.
  ///
  /// In en, this message translates to:
  /// **'Annual rate (%)'**
  String get loanFacilityFieldAnnualRate;

  /// No description provided for @loanFacilityFieldInstallmentCountOptional.
  ///
  /// In en, this message translates to:
  /// **'Installment count (optional)'**
  String get loanFacilityFieldInstallmentCountOptional;

  /// No description provided for @loanFacilityFieldFirstInstallment.
  ///
  /// In en, this message translates to:
  /// **'First installment date'**
  String get loanFacilityFieldFirstInstallment;

  /// No description provided for @loanFacilityFieldFirstInstallmentHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get loanFacilityFieldFirstInstallmentHint;

  /// No description provided for @loanFacilityFieldLenderBank.
  ///
  /// In en, this message translates to:
  /// **'Facility receipt/payment bank account'**
  String get loanFacilityFieldLenderBank;

  /// No description provided for @loanFacilityFieldNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get loanFacilityFieldNotes;

  /// No description provided for @loanFacilityCurrencyId.
  ///
  /// In en, this message translates to:
  /// **'Currency #{id}'**
  String loanFacilityCurrencyId(String id);

  /// No description provided for @loanFacilityConfirmDeleteDraftTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete facility?'**
  String get loanFacilityConfirmDeleteDraftTitle;

  /// No description provided for @loanFacilityConfirmDeleteDraftBody.
  ///
  /// In en, this message translates to:
  /// **'If accounting constraints allow it, this facility, installments, payments, and linked vouchers will be removed.'**
  String get loanFacilityConfirmDeleteDraftBody;

  /// No description provided for @loanFacilityDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get loanFacilityDeleted;

  /// No description provided for @loanFacilityScheduleUpdated.
  ///
  /// In en, this message translates to:
  /// **'Schedule updated'**
  String get loanFacilityScheduleUpdated;

  /// No description provided for @loanFacilityDeletePaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete payment?'**
  String get loanFacilityDeletePaymentTitle;

  /// No description provided for @loanFacilityDeletePaymentBody.
  ///
  /// In en, this message translates to:
  /// **'Linked accounting voucher will be removed and installment balances will be rolled back.'**
  String get loanFacilityDeletePaymentBody;

  /// No description provided for @loanFacilityPaymentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Payment deleted'**
  String get loanFacilityPaymentDeleted;

  /// No description provided for @loanFacilityRecordPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Record installment payment'**
  String get loanFacilityRecordPaymentTitle;

  /// No description provided for @loanFacilityAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get loanFacilityAmount;

  /// No description provided for @loanFacilityBankAccount.
  ///
  /// In en, this message translates to:
  /// **'Bank account'**
  String get loanFacilityBankAccount;

  /// No description provided for @loanFacilityValidationAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get loanFacilityValidationAmountInvalid;

  /// No description provided for @loanFacilityValidationPickBank.
  ///
  /// In en, this message translates to:
  /// **'Pick a bank account'**
  String get loanFacilityValidationPickBank;

  /// No description provided for @loanFacilityPaymentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded'**
  String get loanFacilityPaymentRecorded;

  /// No description provided for @loanFacilityRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get loanFacilityRetry;

  /// No description provided for @loanFacilityTooltipEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get loanFacilityTooltipEdit;

  /// No description provided for @loanFacilityTooltipDeleteDraft.
  ///
  /// In en, this message translates to:
  /// **'Delete facility'**
  String get loanFacilityTooltipDeleteDraft;

  /// No description provided for @loanFacilityContractSummary.
  ///
  /// In en, this message translates to:
  /// **'Contract summary'**
  String get loanFacilityContractSummary;

  /// No description provided for @loanFacilitySummaryStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get loanFacilitySummaryStatus;

  /// No description provided for @loanFacilitySummaryCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get loanFacilitySummaryCurrency;

  /// No description provided for @loanFacilitySummaryPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Principal'**
  String get loanFacilitySummaryPrincipal;

  /// No description provided for @loanFacilitySummaryAnnualRate.
  ///
  /// In en, this message translates to:
  /// **'Annual rate'**
  String get loanFacilitySummaryAnnualRate;

  /// No description provided for @loanFacilitySummaryContractDate.
  ///
  /// In en, this message translates to:
  /// **'Contract date'**
  String get loanFacilitySummaryContractDate;

  /// No description provided for @loanFacilitySummaryFirstInstallment.
  ///
  /// In en, this message translates to:
  /// **'First installment'**
  String get loanFacilitySummaryFirstInstallment;

  /// No description provided for @loanFacilitySummaryInstallmentCount.
  ///
  /// In en, this message translates to:
  /// **'Installments'**
  String get loanFacilitySummaryInstallmentCount;

  /// No description provided for @loanFacilitySummaryScheduleMethod.
  ///
  /// In en, this message translates to:
  /// **'Schedule method'**
  String get loanFacilitySummaryScheduleMethod;

  /// No description provided for @loanFacilitySummaryLenderBankId.
  ///
  /// In en, this message translates to:
  /// **'Facility bank account'**
  String get loanFacilitySummaryLenderBankId;

  /// No description provided for @loanFacilitySummaryNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get loanFacilitySummaryNotes;

  /// No description provided for @loanFacilityDisbursementDocument.
  ///
  /// In en, this message translates to:
  /// **'Facility receipt voucher'**
  String get loanFacilityDisbursementDocument;

  /// No description provided for @loanFacilityScheduleSection.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get loanFacilityScheduleSection;

  /// No description provided for @loanFacilityRegenerateSchedule.
  ///
  /// In en, this message translates to:
  /// **'Generate / rebuild schedule'**
  String get loanFacilityRegenerateSchedule;

  /// No description provided for @loanFacilityInstallmentLine.
  ///
  /// In en, this message translates to:
  /// **'Installment {seq} · {due}'**
  String loanFacilityInstallmentLine(String seq, String due);

  /// No description provided for @loanFacilityRemainingPrincipalInterest.
  ///
  /// In en, this message translates to:
  /// **'Rem. pr./int.: {principal} / {interest}'**
  String loanFacilityRemainingPrincipalInterest(
    String principal,
    String interest,
  );

  /// No description provided for @loanFacilityRecordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get loanFacilityRecordPayment;

  /// No description provided for @loanFacilityDocumentNumber.
  ///
  /// In en, this message translates to:
  /// **'Doc #{id}'**
  String loanFacilityDocumentNumber(String id);

  /// No description provided for @loanFacilityViewVoucher.
  ///
  /// In en, this message translates to:
  /// **'View voucher'**
  String get loanFacilityViewVoucher;

  /// No description provided for @loanFacilityDeletePayment.
  ///
  /// In en, this message translates to:
  /// **'Delete payment'**
  String get loanFacilityDeletePayment;

  /// No description provided for @loanFacilityPaymentPostingHint.
  ///
  /// In en, this message translates to:
  /// **'If posting is enabled, standard system vouchers are created.'**
  String get loanFacilityPaymentPostingHint;

  /// No description provided for @loanFacilityRegenerateValidationCount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid installment count'**
  String get loanFacilityRegenerateValidationCount;

  /// No description provided for @loanFacilityRegenerateValidationFirstDue.
  ///
  /// In en, this message translates to:
  /// **'First due date is required'**
  String get loanFacilityRegenerateValidationFirstDue;

  /// No description provided for @loanFacilityRegenerateValidationDisburseBank.
  ///
  /// In en, this message translates to:
  /// **'Pick a bank account for facility receipt posting'**
  String get loanFacilityRegenerateValidationDisburseBank;

  /// No description provided for @loanFacilityRegenerateDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Installment schedule'**
  String get loanFacilityRegenerateDialogTitle;

  /// No description provided for @loanFacilityRegenerateMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get loanFacilityRegenerateMethod;

  /// No description provided for @loanFacilityScheduleMethodAnnuity.
  ///
  /// In en, this message translates to:
  /// **'Annuity'**
  String get loanFacilityScheduleMethodAnnuity;

  /// No description provided for @loanFacilityScheduleMethodEqualPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Equal principal'**
  String get loanFacilityScheduleMethodEqualPrincipal;

  /// No description provided for @loanFacilityRegenerateCountRequired.
  ///
  /// In en, this message translates to:
  /// **'Installment count *'**
  String get loanFacilityRegenerateCountRequired;

  /// No description provided for @loanFacilityRegenerateFirstDueRequired.
  ///
  /// In en, this message translates to:
  /// **'First due *'**
  String get loanFacilityRegenerateFirstDueRequired;

  /// No description provided for @loanFacilityRegenerateDisburseBank.
  ///
  /// In en, this message translates to:
  /// **'Facility receipt bank account'**
  String get loanFacilityRegenerateDisburseBank;

  /// No description provided for @loanFacilityRegeneratePostAccounting.
  ///
  /// In en, this message translates to:
  /// **'Post facility receipt voucher'**
  String get loanFacilityRegeneratePostAccounting;

  /// No description provided for @loanFacilityRegenerateApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get loanFacilityRegenerateApply;

  /// No description provided for @apiErrorLoanFacilityFinancialLocked.
  ///
  /// In en, this message translates to:
  /// **'Financial details cannot be changed after scheduling or activating the contract.'**
  String get apiErrorLoanFacilityFinancialLocked;

  /// No description provided for @apiErrorLoanFacilityNotDraft.
  ///
  /// In en, this message translates to:
  /// **'Only draft contracts can be deleted.'**
  String get apiErrorLoanFacilityNotDraft;

  /// No description provided for @apiErrorLoanFacilityHasPayments.
  ///
  /// In en, this message translates to:
  /// **'This action is not allowed because payments already exist.'**
  String get apiErrorLoanFacilityHasPayments;

  /// No description provided for @apiErrorLoanInvalidCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency is required or invalid.'**
  String get apiErrorLoanInvalidCurrency;

  /// No description provided for @apiErrorLoanInvalidPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Principal must be a positive amount.'**
  String get apiErrorLoanInvalidPrincipal;

  /// No description provided for @apiErrorLoanContractDateRequired.
  ///
  /// In en, this message translates to:
  /// **'Contract date is required or invalid.'**
  String get apiErrorLoanContractDateRequired;

  /// No description provided for @apiErrorLoanInvalidScheduleMethod.
  ///
  /// In en, this message translates to:
  /// **'Schedule method must be annuity or equal principal.'**
  String get apiErrorLoanInvalidScheduleMethod;

  /// No description provided for @apiErrorLoanInvalidInstallmentCount.
  ///
  /// In en, this message translates to:
  /// **'Installment count is required and must be at least 1.'**
  String get apiErrorLoanInvalidInstallmentCount;

  /// No description provided for @apiErrorLoanFirstDueRequired.
  ///
  /// In en, this message translates to:
  /// **'First installment due date is required.'**
  String get apiErrorLoanFirstDueRequired;

  /// No description provided for @apiErrorLoanBadSchedulePayload.
  ///
  /// In en, this message translates to:
  /// **'Invalid installment count or due date.'**
  String get apiErrorLoanBadSchedulePayload;

  /// No description provided for @apiErrorLoanBankRequiredAccounting.
  ///
  /// In en, this message translates to:
  /// **'A bank account is required to post the accounting voucher.'**
  String get apiErrorLoanBankRequiredAccounting;

  /// No description provided for @apiErrorLoanBankCurrencyMismatch.
  ///
  /// In en, this message translates to:
  /// **'The bank account currency must match the contract currency.'**
  String get apiErrorLoanBankCurrencyMismatch;

  /// No description provided for @apiErrorLoanFacilityDraft.
  ///
  /// In en, this message translates to:
  /// **'Generate the installment schedule before recording payments.'**
  String get apiErrorLoanFacilityDraft;

  /// No description provided for @apiErrorLoanInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount is required and must be positive.'**
  String get apiErrorLoanInvalidAmount;

  /// No description provided for @apiErrorLoanInvalidPaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Payment date is invalid.'**
  String get apiErrorLoanInvalidPaymentDate;

  /// No description provided for @apiErrorLoanScheduleError.
  ///
  /// In en, this message translates to:
  /// **'Could not calculate the installment schedule.'**
  String get apiErrorLoanScheduleError;

  /// No description provided for @apiErrorLoanInvalidBankAccount.
  ///
  /// In en, this message translates to:
  /// **'Bank account is missing or invalid.'**
  String get apiErrorLoanInvalidBankAccount;

  /// No description provided for @apiErrorLoanInvalidRate.
  ///
  /// In en, this message translates to:
  /// **'Annual interest rate is invalid.'**
  String get apiErrorLoanInvalidRate;

  /// No description provided for @apiErrorLoanInvalidFirstInstallmentDate.
  ///
  /// In en, this message translates to:
  /// **'First installment date is invalid.'**
  String get apiErrorLoanInvalidFirstInstallmentDate;

  /// No description provided for @apiErrorLoanPaymentExceedsBalance.
  ///
  /// In en, this message translates to:
  /// **'Payment amount exceeds the remaining balance for this installment.'**
  String get apiErrorLoanPaymentExceedsBalance;

  /// No description provided for @apiErrorLoanAllocationError.
  ///
  /// In en, this message translates to:
  /// **'The payment could not be applied correctly. Try a smaller amount or contact support.'**
  String get apiErrorLoanAllocationError;

  /// No description provided for @apiErrorLoanFacilityNotFound.
  ///
  /// In en, this message translates to:
  /// **'This loan contract was not found.'**
  String get apiErrorLoanFacilityNotFound;

  /// No description provided for @apiErrorLoanInstallmentNotFound.
  ///
  /// In en, this message translates to:
  /// **'This installment was not found.'**
  String get apiErrorLoanInstallmentNotFound;

  /// No description provided for @apiErrorLoanPaymentNotFound.
  ///
  /// In en, this message translates to:
  /// **'This payment record was not found.'**
  String get apiErrorLoanPaymentNotFound;

  /// No description provided for @apiErrorLoanFacilityMissingAfterCommit.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while saving the schedule. Refresh the page and try again.'**
  String get apiErrorLoanFacilityMissingAfterCommit;

  /// No description provided for @apiErrorLoanPaymentAccountingFailed.
  ///
  /// In en, this message translates to:
  /// **'The accounting voucher for this payment could not be created.'**
  String get apiErrorLoanPaymentAccountingFailed;

  /// No description provided for @apiErrorLoanChartAccountNotFound.
  ///
  /// In en, this message translates to:
  /// **'Required chart accounts for loan posting are missing. Contact support.'**
  String get apiErrorLoanChartAccountNotFound;

  /// No description provided for @apiErrorLoanAccountingLinesUnbalanced.
  ///
  /// In en, this message translates to:
  /// **'Loan accounting totals do not balance. Contact support.'**
  String get apiErrorLoanAccountingLinesUnbalanced;

  /// No description provided for @apiErrorLoanBankRequiredForPaymentDocument.
  ///
  /// In en, this message translates to:
  /// **'A bank account is required to register the accounting voucher.'**
  String get apiErrorLoanBankRequiredForPaymentDocument;

  /// No description provided for @deleteBusinessConfirmTypeInstruction.
  ///
  /// In en, this message translates to:
  /// **'To confirm, type DELETE in English or «حذف» in Persian, exactly as shown.'**
  String get deleteBusinessConfirmTypeInstruction;

  /// No description provided for @deleteBusinessConfirmTypeHint.
  ///
  /// In en, this message translates to:
  /// **'DELETE or حذف'**
  String get deleteBusinessConfirmTypeHint;

  /// No description provided for @invoiceLineItemsAddRowKeyboardHint.
  ///
  /// In en, this message translates to:
  /// **'Tip: Press Q then I in quick succession to add rows (outside text fields).'**
  String get invoiceLineItemsAddRowKeyboardHint;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @marketing.
  ///
  /// In en, this message translates to:
  /// **'Marketing'**
  String get marketing;

  /// No description provided for @marketingReport.
  ///
  /// In en, this message translates to:
  /// **'Marketing report'**
  String get marketingReport;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get thisMonth;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @dateFrom.
  ///
  /// In en, this message translates to:
  /// **'From date'**
  String get dateFrom;

  /// No description provided for @dateTo.
  ///
  /// In en, this message translates to:
  /// **'To date'**
  String get dateTo;

  /// No description provided for @applyFilter.
  ///
  /// In en, this message translates to:
  /// **'Apply filter'**
  String get applyFilter;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmPassword;

  /// No description provided for @changePasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get changePasswordSuccess;

  /// No description provided for @changePasswordFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to change password. Please try again.'**
  String get changePasswordFailed;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'New password and confirm password do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @samePassword.
  ///
  /// In en, this message translates to:
  /// **'New password must be different from current password'**
  String get samePassword;

  /// No description provided for @invalidCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect'**
  String get invalidCurrentPassword;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get passwordChanged;

  /// No description provided for @changePasswordDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password and choose a new secure password'**
  String get changePasswordDescription;

  /// No description provided for @changePasswordButton.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordButton;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordMinLength;

  /// No description provided for @passwordMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Password must not exceed 72 bytes (about 72 ASCII characters)'**
  String get passwordMaxLength;

  /// No description provided for @calendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendar;

  /// No description provided for @gregorian.
  ///
  /// In en, this message translates to:
  /// **'Gregorian'**
  String get gregorian;

  /// No description provided for @jalali.
  ///
  /// In en, this message translates to:
  /// **'Jalali'**
  String get jalali;

  /// No description provided for @calendarType.
  ///
  /// In en, this message translates to:
  /// **'Calendar Type'**
  String get calendarType;

  /// No description provided for @dataLoadingError.
  ///
  /// In en, this message translates to:
  /// **'Error loading data'**
  String get dataLoadingError;

  /// No description provided for @yourReferralLink.
  ///
  /// In en, this message translates to:
  /// **'Your referral link'**
  String get yourReferralLink;

  /// No description provided for @filtersAndSearch.
  ///
  /// In en, this message translates to:
  /// **'Filters and search'**
  String get filtersAndSearch;

  /// No description provided for @hideFilters.
  ///
  /// In en, this message translates to:
  /// **'Hide filters'**
  String get hideFilters;

  /// No description provided for @showFilters.
  ///
  /// In en, this message translates to:
  /// **'Show filters'**
  String get showFilters;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @searchInNameEmail.
  ///
  /// In en, this message translates to:
  /// **'Search in name, last name and email...'**
  String get searchInNameEmail;

  /// No description provided for @recordsPerPage.
  ///
  /// In en, this message translates to:
  /// **'Records per page'**
  String get recordsPerPage;

  /// No description provided for @records.
  ///
  /// In en, this message translates to:
  /// **'records'**
  String get records;

  /// No description provided for @installmentsReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Installments report'**
  String get installmentsReportTitle;

  /// No description provided for @installmentsFiltersFiscalYear.
  ///
  /// In en, this message translates to:
  /// **'Fiscal year'**
  String get installmentsFiltersFiscalYear;

  /// No description provided for @installmentsFiltersStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get installmentsFiltersStatus;

  /// No description provided for @installmentsFiltersDueFrom.
  ///
  /// In en, this message translates to:
  /// **'Due date from'**
  String get installmentsFiltersDueFrom;

  /// No description provided for @installmentsFiltersDueTo.
  ///
  /// In en, this message translates to:
  /// **'Due date to'**
  String get installmentsFiltersDueTo;

  /// No description provided for @installmentsFiltersPerson.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get installmentsFiltersPerson;

  /// No description provided for @installmentsFiltersPersonHint.
  ///
  /// In en, this message translates to:
  /// **'Search and select a person'**
  String get installmentsFiltersPersonHint;

  /// No description provided for @installmentsFiltersInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get installmentsFiltersInvoice;

  /// No description provided for @installmentsFiltersInvoiceHint.
  ///
  /// In en, this message translates to:
  /// **'Selected invoice number'**
  String get installmentsFiltersInvoiceHint;

  /// No description provided for @installmentsFiltersInvoiceButton.
  ///
  /// In en, this message translates to:
  /// **'Select invoice'**
  String get installmentsFiltersInvoiceButton;

  /// No description provided for @installmentsStatusAll.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get installmentsStatusAll;

  /// No description provided for @installmentsStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get installmentsStatusPending;

  /// No description provided for @installmentsStatusPartial.
  ///
  /// In en, this message translates to:
  /// **'Partially paid'**
  String get installmentsStatusPartial;

  /// No description provided for @installmentsStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get installmentsStatusPaid;

  /// No description provided for @installmentsStatusOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get installmentsStatusOverdue;

  /// No description provided for @installmentsSummaryPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Principal total'**
  String get installmentsSummaryPrincipal;

  /// No description provided for @installmentsSummaryInterest.
  ///
  /// In en, this message translates to:
  /// **'Interest total'**
  String get installmentsSummaryInterest;

  /// No description provided for @installmentsSummaryTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand total'**
  String get installmentsSummaryTotal;

  /// No description provided for @installmentsSummaryPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid total'**
  String get installmentsSummaryPaid;

  /// No description provided for @installmentsSummaryRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining total'**
  String get installmentsSummaryRemaining;

  /// No description provided for @installmentsSummaryLateFee.
  ///
  /// In en, this message translates to:
  /// **'Late fee total'**
  String get installmentsSummaryLateFee;

  /// No description provided for @installmentsFetchError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load installments'**
  String get installmentsFetchError;

  /// No description provided for @installmentsExportError.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get installmentsExportError;

  /// No description provided for @installmentsExportWebOnly.
  ///
  /// In en, this message translates to:
  /// **'File download is only available on the web version'**
  String get installmentsExportWebOnly;

  /// No description provided for @installmentsInvoicePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Select installment invoice'**
  String get installmentsInvoicePickerTitle;

  /// No description provided for @installmentsInvoicePickerSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search by code, description...'**
  String get installmentsInvoicePickerSearchLabel;

  /// No description provided for @installmentInvoicesLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get installmentInvoicesLoadMore;

  /// No description provided for @installmentInvoicesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} installment invoice(s)'**
  String installmentInvoicesCount(Object count);

  /// No description provided for @installmentsTableInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get installmentsTableInvoice;

  /// No description provided for @installmentsTableInstallment.
  ///
  /// In en, this message translates to:
  /// **'Installment'**
  String get installmentsTableInstallment;

  /// No description provided for @installmentsTablePerson.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get installmentsTablePerson;

  /// No description provided for @installmentsTableDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get installmentsTableDueDate;

  /// No description provided for @installmentsTableStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get installmentsTableStatus;

  /// No description provided for @installmentsTablePrincipal.
  ///
  /// In en, this message translates to:
  /// **'Principal'**
  String get installmentsTablePrincipal;

  /// No description provided for @installmentsTableInterest.
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get installmentsTableInterest;

  /// No description provided for @installmentsTableTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get installmentsTableTotal;

  /// No description provided for @installmentsTablePaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get installmentsTablePaid;

  /// No description provided for @installmentsTableRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get installmentsTableRemaining;

  /// No description provided for @installmentsTableLateFee.
  ///
  /// In en, this message translates to:
  /// **'Late fee'**
  String get installmentsTableLateFee;

  /// No description provided for @installmentsTableOverdueDays.
  ///
  /// In en, this message translates to:
  /// **'Overdue days'**
  String get installmentsTableOverdueDays;

  /// No description provided for @installmentsRowsPerPage.
  ///
  /// In en, this message translates to:
  /// **'Rows per page'**
  String get installmentsRowsPerPage;

  /// No description provided for @installmentsViewPortfolios.
  ///
  /// In en, this message translates to:
  /// **'Installment files'**
  String get installmentsViewPortfolios;

  /// No description provided for @installmentsViewFlat.
  ///
  /// In en, this message translates to:
  /// **'All installments'**
  String get installmentsViewFlat;

  /// No description provided for @installmentsFiltersBucket.
  ///
  /// In en, this message translates to:
  /// **'Quick filter'**
  String get installmentsFiltersBucket;

  /// No description provided for @installmentsBucketAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get installmentsBucketAll;

  /// No description provided for @installmentsBucketUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid (open)'**
  String get installmentsBucketUnpaid;

  /// No description provided for @installmentsBucketUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming due dates'**
  String get installmentsBucketUpcoming;

  /// No description provided for @installmentsBucketOverdueOnly.
  ///
  /// In en, this message translates to:
  /// **'Overdue only'**
  String get installmentsBucketOverdueOnly;

  /// No description provided for @installmentsMinOverdueDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Min. overdue days'**
  String get installmentsMinOverdueDaysLabel;

  /// No description provided for @installmentsTableMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get installmentsTableMobile;

  /// No description provided for @installmentsGroupedNextDue.
  ///
  /// In en, this message translates to:
  /// **'Next due'**
  String get installmentsGroupedNextDue;

  /// No description provided for @installmentsGroupedWorstStatus.
  ///
  /// In en, this message translates to:
  /// **'Worst status'**
  String get installmentsGroupedWorstStatus;

  /// No description provided for @installmentsGroupedInstallments.
  ///
  /// In en, this message translates to:
  /// **'Installments (matched)'**
  String get installmentsGroupedInstallments;

  /// No description provided for @installmentsGroupedPaidCount.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get installmentsGroupedPaidCount;

  /// No description provided for @installmentsGroupedOverdueCount.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get installmentsGroupedOverdueCount;

  /// No description provided for @installmentsGroupedRemainingSum.
  ///
  /// In en, this message translates to:
  /// **'Remaining (sum)'**
  String get installmentsGroupedRemainingSum;

  /// No description provided for @installmentsDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Installment plan'**
  String get installmentsDetailTitle;

  /// No description provided for @installmentsPaymentsColumn.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get installmentsPaymentsColumn;

  /// No description provided for @installmentsNoPaymentsYet.
  ///
  /// In en, this message translates to:
  /// **'No receipt allocations yet'**
  String get installmentsNoPaymentsYet;

  /// No description provided for @installmentsPaymentsDetailMissing.
  ///
  /// In en, this message translates to:
  /// **'Payment is recorded on this installment, but linked receipt rows could not be listed. Try reopening the dialog after saving receipts with installment allocation.'**
  String get installmentsPaymentsDetailMissing;

  /// No description provided for @test.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get test;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @showingRecords.
  ///
  /// In en, this message translates to:
  /// **'Showing {start} to {end} of {total} records'**
  String showingRecords(Object end, Object start, Object total);

  /// No description provided for @previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get previousPage;

  /// No description provided for @nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get nextPage;

  /// No description provided for @pageOf.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String pageOf(Object current, Object total);

  /// No description provided for @referralList.
  ///
  /// In en, this message translates to:
  /// **'Referral List'**
  String get referralList;

  /// No description provided for @dateRangeFilter.
  ///
  /// In en, this message translates to:
  /// **'Date Range Filter'**
  String get dateRangeFilter;

  /// No description provided for @columnSearch.
  ///
  /// In en, this message translates to:
  /// **'Column Search'**
  String get columnSearch;

  /// No description provided for @searchInColumn.
  ///
  /// In en, this message translates to:
  /// **'Search in {column}'**
  String searchInColumn(Object column);

  /// No description provided for @searchType.
  ///
  /// In en, this message translates to:
  /// **'Search Type'**
  String get searchType;

  /// No description provided for @contains.
  ///
  /// In en, this message translates to:
  /// **'contains'**
  String get contains;

  /// No description provided for @startsWith.
  ///
  /// In en, this message translates to:
  /// **'Starts With'**
  String get startsWith;

  /// No description provided for @endsWith.
  ///
  /// In en, this message translates to:
  /// **'Ends With'**
  String get endsWith;

  /// No description provided for @exactMatch.
  ///
  /// In en, this message translates to:
  /// **'Exact Match'**
  String get exactMatch;

  /// No description provided for @searchValue.
  ///
  /// In en, this message translates to:
  /// **'Search Value'**
  String get searchValue;

  /// No description provided for @applyColumnFilter.
  ///
  /// In en, this message translates to:
  /// **'Apply Column Filter'**
  String get applyColumnFilter;

  /// No description provided for @clearColumnFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear Column Filter'**
  String get clearColumnFilter;

  /// No description provided for @activeFilters.
  ///
  /// In en, this message translates to:
  /// **'Active Filters'**
  String get activeFilters;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select Date'**
  String get selectDate;

  /// No description provided for @noDataFound.
  ///
  /// In en, this message translates to:
  /// **'No data found'**
  String get noDataFound;

  /// No description provided for @marketingReportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage and analyze user referrals'**
  String get marketingReportSubtitle;

  /// No description provided for @showing.
  ///
  /// In en, this message translates to:
  /// **'Showing'**
  String get showing;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get to;

  /// No description provided for @ofText.
  ///
  /// In en, this message translates to:
  /// **'of'**
  String get ofText;

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'results'**
  String get results;

  /// No description provided for @firstPage.
  ///
  /// In en, this message translates to:
  /// **'First page'**
  String get firstPage;

  /// No description provided for @lastPage.
  ///
  /// In en, this message translates to:
  /// **'Last page'**
  String get lastPage;

  /// No description provided for @exportToExcel.
  ///
  /// In en, this message translates to:
  /// **'Export to Excel'**
  String get exportToExcel;

  /// No description provided for @exportToPdf.
  ///
  /// In en, this message translates to:
  /// **'Export to PDF'**
  String get exportToPdf;

  /// No description provided for @exportSelected.
  ///
  /// In en, this message translates to:
  /// **'Export Selected'**
  String get exportSelected;

  /// No description provided for @exportAll.
  ///
  /// In en, this message translates to:
  /// **'Export All'**
  String get exportAll;

  /// No description provided for @exporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting...'**
  String get exporting;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Export completed successfully'**
  String get exportSuccess;

  /// No description provided for @exportError.
  ///
  /// In en, this message translates to:
  /// **'Export error'**
  String get exportError;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @importFromExcel.
  ///
  /// In en, this message translates to:
  /// **'Import from Excel'**
  String get importFromExcel;

  /// No description provided for @rowNumber.
  ///
  /// In en, this message translates to:
  /// **'Row'**
  String get rowNumber;

  /// No description provided for @registrationDate.
  ///
  /// In en, this message translates to:
  /// **'Registration Date'**
  String get registrationDate;

  /// No description provided for @selectedRange.
  ///
  /// In en, this message translates to:
  /// **'Selected Range'**
  String get selectedRange;

  /// No description provided for @page.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get page;

  /// No description provided for @equals.
  ///
  /// In en, this message translates to:
  /// **'equals'**
  String get equals;

  /// No description provided for @greater_than.
  ///
  /// In en, this message translates to:
  /// **'greater than'**
  String get greater_than;

  /// No description provided for @greater_equal.
  ///
  /// In en, this message translates to:
  /// **'greater or equal'**
  String get greater_equal;

  /// No description provided for @less_than.
  ///
  /// In en, this message translates to:
  /// **'less than'**
  String get less_than;

  /// No description provided for @less_equal.
  ///
  /// In en, this message translates to:
  /// **'less or equal'**
  String get less_equal;

  /// No description provided for @not_equals.
  ///
  /// In en, this message translates to:
  /// **'not equals'**
  String get not_equals;

  /// No description provided for @starts_with.
  ///
  /// In en, this message translates to:
  /// **'starts with'**
  String get starts_with;

  /// No description provided for @ends_with.
  ///
  /// In en, this message translates to:
  /// **'ends with'**
  String get ends_with;

  /// No description provided for @in_list.
  ///
  /// In en, this message translates to:
  /// **'in list'**
  String get in_list;

  /// No description provided for @businessBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic Business Information'**
  String get businessBasicInfo;

  /// No description provided for @includeSampleDataLabel.
  ///
  /// In en, this message translates to:
  /// **'Add sample data for a quick start'**
  String get includeSampleDataLabel;

  /// No description provided for @includeSampleDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Creates sample customers, product, warehouse, and cash/bank accounts (not used when restoring from a .hbx backup).'**
  String get includeSampleDataSubtitle;

  /// No description provided for @sampleDataSeedWarning.
  ///
  /// In en, this message translates to:
  /// **'Business created but sample data could not be completed'**
  String get sampleDataSeedWarning;

  /// No description provided for @businessContactInfo.
  ///
  /// In en, this message translates to:
  /// **'Contact Information'**
  String get businessContactInfo;

  /// No description provided for @businessLegalInfo.
  ///
  /// In en, this message translates to:
  /// **'Legal Information'**
  String get businessLegalInfo;

  /// No description provided for @businessGeographicInfo.
  ///
  /// In en, this message translates to:
  /// **'Geographic Information'**
  String get businessGeographicInfo;

  /// No description provided for @businessConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirmation'**
  String get businessConfirmation;

  /// No description provided for @businessName.
  ///
  /// In en, this message translates to:
  /// **'Business Name'**
  String get businessName;

  /// No description provided for @businessType.
  ///
  /// In en, this message translates to:
  /// **'Business Type'**
  String get businessType;

  /// No description provided for @businessField.
  ///
  /// In en, this message translates to:
  /// **'Business Field'**
  String get businessField;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @postalCode.
  ///
  /// In en, this message translates to:
  /// **'Postal Code'**
  String get postalCode;

  /// No description provided for @nationalId.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get nationalId;

  /// No description provided for @registrationNumber.
  ///
  /// In en, this message translates to:
  /// **'Registration Number'**
  String get registrationNumber;

  /// No description provided for @economicId.
  ///
  /// In en, this message translates to:
  /// **'Economic ID'**
  String get economicId;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @province.
  ///
  /// In en, this message translates to:
  /// **'Province'**
  String get province;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @step.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get step;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @createBusiness.
  ///
  /// In en, this message translates to:
  /// **'Create Business'**
  String get createBusiness;

  /// No description provided for @confirmInfo.
  ///
  /// In en, this message translates to:
  /// **'Confirm Information'**
  String get confirmInfo;

  /// No description provided for @confirmInfoMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure about the entered information?'**
  String get confirmInfoMessage;

  /// No description provided for @businessCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Business created successfully'**
  String get businessCreatedSuccessfully;

  /// No description provided for @businessCreationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create business'**
  String get businessCreationFailed;

  /// No description provided for @pleaseFillRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill all required fields'**
  String get pleaseFillRequiredFields;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'required'**
  String get required;

  /// No description provided for @example.
  ///
  /// In en, this message translates to:
  /// **'Example'**
  String get example;

  /// No description provided for @phoneExample.
  ///
  /// In en, this message translates to:
  /// **'02112345678'**
  String get phoneExample;

  /// No description provided for @mobileExample.
  ///
  /// In en, this message translates to:
  /// **'09123456789'**
  String get mobileExample;

  /// No description provided for @nationalIdExample.
  ///
  /// In en, this message translates to:
  /// **'1234567890'**
  String get nationalIdExample;

  /// No description provided for @company.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get company;

  /// No description provided for @shop.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get shop;

  /// No description provided for @store.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get store;

  /// No description provided for @union.
  ///
  /// In en, this message translates to:
  /// **'Union'**
  String get union;

  /// No description provided for @club.
  ///
  /// In en, this message translates to:
  /// **'Club'**
  String get club;

  /// No description provided for @institute.
  ///
  /// In en, this message translates to:
  /// **'Institute'**
  String get institute;

  /// No description provided for @individual.
  ///
  /// In en, this message translates to:
  /// **'Individual'**
  String get individual;

  /// No description provided for @manufacturing.
  ///
  /// In en, this message translates to:
  /// **'Manufacturing'**
  String get manufacturing;

  /// No description provided for @trading.
  ///
  /// In en, this message translates to:
  /// **'Trading'**
  String get trading;

  /// No description provided for @service.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get service;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @newTicket.
  ///
  /// In en, this message translates to:
  /// **'New Ticket'**
  String get newTicket;

  /// No description provided for @ticketTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket Title'**
  String get ticketTitle;

  /// No description provided for @ticketDescription.
  ///
  /// In en, this message translates to:
  /// **'Problem Description'**
  String get ticketDescription;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @priority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priority;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @messages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messages;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send Message'**
  String get sendMessage;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Type your message...'**
  String get messageHint;

  /// No description provided for @createTicket.
  ///
  /// In en, this message translates to:
  /// **'Create Ticket'**
  String get createTicket;

  /// No description provided for @ticketCreated.
  ///
  /// In en, this message translates to:
  /// **'Ticket created successfully'**
  String get ticketCreated;

  /// No description provided for @messageSent.
  ///
  /// In en, this message translates to:
  /// **'Message sent'**
  String get messageSent;

  /// No description provided for @loadingTickets.
  ///
  /// In en, this message translates to:
  /// **'Loading tickets...'**
  String get loadingTickets;

  /// No description provided for @noTickets.
  ///
  /// In en, this message translates to:
  /// **'No tickets found'**
  String get noTickets;

  /// No description provided for @ticketDetails.
  ///
  /// In en, this message translates to:
  /// **'Ticket Details'**
  String get ticketDetails;

  /// No description provided for @supportTickets.
  ///
  /// In en, this message translates to:
  /// **'Support Tickets'**
  String get supportTickets;

  /// No description provided for @ticketCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created At'**
  String get ticketCreatedAt;

  /// No description provided for @ticketUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Last Updated'**
  String get ticketUpdatedAt;

  /// No description provided for @ticketLoadingError.
  ///
  /// In en, this message translates to:
  /// **'Error loading ticket'**
  String get ticketLoadingError;

  /// No description provided for @ticketId.
  ///
  /// In en, this message translates to:
  /// **'Ticket ID'**
  String get ticketId;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created At'**
  String get createdAt;

  /// No description provided for @updatedAt.
  ///
  /// In en, this message translates to:
  /// **'Updated At'**
  String get updatedAt;

  /// No description provided for @assignedTo.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get assignedTo;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @urgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get urgent;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get inProgress;

  /// No description provided for @waitingForUser.
  ///
  /// In en, this message translates to:
  /// **'Waiting for User'**
  String get waitingForUser;

  /// No description provided for @closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed;

  /// No description provided for @resolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get resolved;

  /// No description provided for @technicalIssue.
  ///
  /// In en, this message translates to:
  /// **'Technical Issue'**
  String get technicalIssue;

  /// No description provided for @featureRequest.
  ///
  /// In en, this message translates to:
  /// **'Feature Request'**
  String get featureRequest;

  /// No description provided for @question.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get question;

  /// No description provided for @complaint.
  ///
  /// In en, this message translates to:
  /// **'Complaint'**
  String get complaint;

  /// No description provided for @operatorPanel.
  ///
  /// In en, this message translates to:
  /// **'Operator Panel'**
  String get operatorPanel;

  /// No description provided for @allTickets.
  ///
  /// In en, this message translates to:
  /// **'All Tickets'**
  String get allTickets;

  /// No description provided for @assignTicket.
  ///
  /// In en, this message translates to:
  /// **'Assign Ticket'**
  String get assignTicket;

  /// No description provided for @createNewTicket.
  ///
  /// In en, this message translates to:
  /// **'Create New Ticket'**
  String get createNewTicket;

  /// No description provided for @createSupportTicket.
  ///
  /// In en, this message translates to:
  /// **'Create Support Ticket'**
  String get createSupportTicket;

  /// No description provided for @ticketTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Ticket Title'**
  String get ticketTitleLabel;

  /// No description provided for @ticketTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a short and clear title for your issue'**
  String get ticketTitleHint;

  /// No description provided for @categoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryLabel;

  /// No description provided for @priorityLabel.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get priorityLabel;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Problem Description'**
  String get descriptionLabel;

  /// No description provided for @descriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Please describe your problem or question in detail...'**
  String get descriptionHint;

  /// No description provided for @submitTicket.
  ///
  /// In en, this message translates to:
  /// **'Submit Ticket'**
  String get submitTicket;

  /// No description provided for @submittingTicket.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get submittingTicket;

  /// No description provided for @ticketTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Ticket title is required'**
  String get ticketTitleRequired;

  /// No description provided for @ticketTitleMinLength.
  ///
  /// In en, this message translates to:
  /// **'Title must be at least 5 characters'**
  String get ticketTitleMinLength;

  /// No description provided for @categoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select a category'**
  String get categoryRequired;

  /// No description provided for @priorityRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select a priority'**
  String get priorityRequired;

  /// No description provided for @descriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Problem description is required'**
  String get descriptionRequired;

  /// No description provided for @descriptionMinLength.
  ///
  /// In en, this message translates to:
  /// **'Description must be at least 10 characters'**
  String get descriptionMinLength;

  /// No description provided for @loadingData.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingData;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @ticketCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Ticket created successfully'**
  String get ticketCreatedSuccessfully;

  /// No description provided for @pleaseSelectCategoryAndPriority.
  ///
  /// In en, this message translates to:
  /// **'Please select category and priority'**
  String get pleaseSelectCategoryAndPriority;

  /// No description provided for @changeStatus.
  ///
  /// In en, this message translates to:
  /// **'Change Status'**
  String get changeStatus;

  /// No description provided for @multiSelectFilter.
  ///
  /// In en, this message translates to:
  /// **'Multi-Select Filter'**
  String get multiSelectFilter;

  /// No description provided for @selectFilterOptions.
  ///
  /// In en, this message translates to:
  /// **'Select Filter Options'**
  String get selectFilterOptions;

  /// No description provided for @noFilterOptionsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No filter options available'**
  String get noFilterOptionsAvailable;

  /// No description provided for @marketingDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage referrals and marketing codes'**
  String get marketingDescription;

  /// No description provided for @referralCode.
  ///
  /// In en, this message translates to:
  /// **'Referral Code'**
  String get referralCode;

  /// No description provided for @internalMessage.
  ///
  /// In en, this message translates to:
  /// **'Internal Message'**
  String get internalMessage;

  /// No description provided for @operator.
  ///
  /// In en, this message translates to:
  /// **'Operator'**
  String get operator;

  /// No description provided for @ticketNumber.
  ///
  /// In en, this message translates to:
  /// **'Ticket #{number}'**
  String ticketNumber(Object number);

  /// No description provided for @ticketNotFound.
  ///
  /// In en, this message translates to:
  /// **'Ticket not found'**
  String get ticketNotFound;

  /// No description provided for @noMessagesFound.
  ///
  /// In en, this message translates to:
  /// **'No messages found'**
  String get noMessagesFound;

  /// No description provided for @writeYourMessage.
  ///
  /// In en, this message translates to:
  /// **'Write your message...'**
  String get writeYourMessage;

  /// No description provided for @writeYourResponse.
  ///
  /// In en, this message translates to:
  /// **'Write your response...'**
  String get writeYourResponse;

  /// No description provided for @sendingMessage.
  ///
  /// In en, this message translates to:
  /// **'Sending message...'**
  String get sendingMessage;

  /// No description provided for @messageSentSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Message sent successfully'**
  String get messageSentSuccessfully;

  /// No description provided for @errorSendingMessage.
  ///
  /// In en, this message translates to:
  /// **'Error sending message'**
  String get errorSendingMessage;

  /// No description provided for @statusUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Status updated successfully'**
  String get statusUpdatedSuccessfully;

  /// No description provided for @errorUpdatingStatus.
  ///
  /// In en, this message translates to:
  /// **'Error updating status'**
  String get errorUpdatingStatus;

  /// No description provided for @ticketClosed.
  ///
  /// In en, this message translates to:
  /// **'Ticket is closed'**
  String get ticketClosed;

  /// No description provided for @ticketResolved.
  ///
  /// In en, this message translates to:
  /// **'Ticket is resolved'**
  String get ticketResolved;

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String daysAgo(Object count);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String hoursAgo(Object count);

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String minutesAgo(Object count);

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @conversation.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get conversation;

  /// No description provided for @ticketInfo.
  ///
  /// In en, this message translates to:
  /// **'Ticket Information'**
  String get ticketInfo;

  /// No description provided for @createdBy.
  ///
  /// In en, this message translates to:
  /// **'Created by'**
  String get createdBy;

  /// No description provided for @lastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get lastUpdated;

  /// No description provided for @messageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} messages'**
  String messageCount(Object count);

  /// No description provided for @replyAsOperator.
  ///
  /// In en, this message translates to:
  /// **'Reply as Operator'**
  String get replyAsOperator;

  /// No description provided for @replyAsUser.
  ///
  /// In en, this message translates to:
  /// **'Reply as User'**
  String get replyAsUser;

  /// No description provided for @internalNote.
  ///
  /// In en, this message translates to:
  /// **'Internal Note'**
  String get internalNote;

  /// No description provided for @publicMessage.
  ///
  /// In en, this message translates to:
  /// **'Public Message'**
  String get publicMessage;

  /// No description provided for @markAsInternal.
  ///
  /// In en, this message translates to:
  /// **'Mark as Internal'**
  String get markAsInternal;

  /// No description provided for @markAsPublic.
  ///
  /// In en, this message translates to:
  /// **'Mark as Public'**
  String get markAsPublic;

  /// No description provided for @ticketDetailsDialog.
  ///
  /// In en, this message translates to:
  /// **'Ticket Details'**
  String get ticketDetailsDialog;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @fileStorage.
  ///
  /// In en, this message translates to:
  /// **'File Management'**
  String get fileStorage;

  /// No description provided for @fileStorageSettings.
  ///
  /// In en, this message translates to:
  /// **'File Settings'**
  String get fileStorageSettings;

  /// No description provided for @storageConfigurations.
  ///
  /// In en, this message translates to:
  /// **'Storage Configurations'**
  String get storageConfigurations;

  /// No description provided for @addStorageConfig.
  ///
  /// In en, this message translates to:
  /// **'Add Storage Configuration'**
  String get addStorageConfig;

  /// No description provided for @editStorageConfig.
  ///
  /// In en, this message translates to:
  /// **'Edit Storage Configuration'**
  String get editStorageConfig;

  /// No description provided for @storageName.
  ///
  /// In en, this message translates to:
  /// **'Configuration Name'**
  String get storageName;

  /// No description provided for @storageType.
  ///
  /// In en, this message translates to:
  /// **'Storage Type'**
  String get storageType;

  /// No description provided for @localStorage.
  ///
  /// In en, this message translates to:
  /// **'Local Storage'**
  String get localStorage;

  /// No description provided for @ftpStorage.
  ///
  /// In en, this message translates to:
  /// **'FTP Storage'**
  String get ftpStorage;

  /// No description provided for @isDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get isDefault;

  /// No description provided for @configData.
  ///
  /// In en, this message translates to:
  /// **'Configuration Data'**
  String get configData;

  /// No description provided for @basePath.
  ///
  /// In en, this message translates to:
  /// **'Base Path'**
  String get basePath;

  /// No description provided for @ftpHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get ftpHost;

  /// No description provided for @ftpPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get ftpPort;

  /// No description provided for @ftpUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get ftpUsername;

  /// No description provided for @ftpPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get ftpPassword;

  /// No description provided for @ftpDirectory.
  ///
  /// In en, this message translates to:
  /// **'FTP Directory'**
  String get ftpDirectory;

  /// No description provided for @connectionSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Connection Successful'**
  String get connectionSuccessful;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection Failed'**
  String get connectionFailed;

  /// No description provided for @setAsDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as Default'**
  String get setAsDefault;

  /// No description provided for @defaultConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Default Configuration'**
  String get defaultConfiguration;

  /// No description provided for @setDefaultConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to set this configuration as default?'**
  String get setDefaultConfirm;

  /// No description provided for @defaultSetSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Default configuration set successfully'**
  String get defaultSetSuccessfully;

  /// No description provided for @defaultSetFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to set default configuration'**
  String get defaultSetFailed;

  /// No description provided for @cannotDeleteDefault.
  ///
  /// In en, this message translates to:
  /// **'Cannot delete default configuration'**
  String get cannotDeleteDefault;

  /// No description provided for @defaultConfigurationNote.
  ///
  /// In en, this message translates to:
  /// **'Default configuration is used for sending emails and cannot be deleted'**
  String get defaultConfigurationNote;

  /// No description provided for @setAsDefaultEmail.
  ///
  /// In en, this message translates to:
  /// **'Set as Default Email'**
  String get setAsDefaultEmail;

  /// No description provided for @defaultEmailServer.
  ///
  /// In en, this message translates to:
  /// **'Default Email Server'**
  String get defaultEmailServer;

  /// No description provided for @changeDefaultEmail.
  ///
  /// In en, this message translates to:
  /// **'Change Default Email'**
  String get changeDefaultEmail;

  /// No description provided for @currentDefault.
  ///
  /// In en, this message translates to:
  /// **'Current Default'**
  String get currentDefault;

  /// No description provided for @makeDefault.
  ///
  /// In en, this message translates to:
  /// **'Make Default'**
  String get makeDefault;

  /// No description provided for @defaultEmailNote.
  ///
  /// In en, this message translates to:
  /// **'Emails are sent from the default server'**
  String get defaultEmailNote;

  /// No description provided for @noDefaultSet.
  ///
  /// In en, this message translates to:
  /// **'No default email server is set'**
  String get noDefaultSet;

  /// No description provided for @selectDefaultServer.
  ///
  /// In en, this message translates to:
  /// **'Select Default Server'**
  String get selectDefaultServer;

  /// No description provided for @defaultServerChanged.
  ///
  /// In en, this message translates to:
  /// **'Default server changed'**
  String get defaultServerChanged;

  /// No description provided for @defaultServerChangeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to change default server'**
  String get defaultServerChangeFailed;

  /// No description provided for @emailConfigSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Email configuration saved successfully'**
  String get emailConfigSavedSuccessfully;

  /// No description provided for @emailConfigUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Email configuration updated successfully'**
  String get emailConfigUpdatedSuccessfully;

  /// No description provided for @editEmailConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Edit Email Configuration'**
  String get editEmailConfiguration;

  /// No description provided for @updateConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Update Configuration'**
  String get updateConfiguration;

  /// No description provided for @testEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'Test Email'**
  String get testEmailSubject;

  /// No description provided for @testEmailBody.
  ///
  /// In en, this message translates to:
  /// **'This is a test email.'**
  String get testEmailBody;

  /// No description provided for @testEmailSentSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Test email sent successfully'**
  String get testEmailSentSuccessfully;

  /// No description provided for @emailConfigDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Configuration deleted successfully'**
  String get emailConfigDeletedSuccessfully;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @fileStatistics.
  ///
  /// In en, this message translates to:
  /// **'File Statistics'**
  String get fileStatistics;

  /// No description provided for @totalFiles.
  ///
  /// In en, this message translates to:
  /// **'Total Files'**
  String get totalFiles;

  /// No description provided for @totalSize.
  ///
  /// In en, this message translates to:
  /// **'Total Size'**
  String get totalSize;

  /// No description provided for @temporaryFiles.
  ///
  /// In en, this message translates to:
  /// **'Temporary Files'**
  String get temporaryFiles;

  /// No description provided for @unverifiedFiles.
  ///
  /// In en, this message translates to:
  /// **'Unverified Files'**
  String get unverifiedFiles;

  /// No description provided for @cleanupTemporaryFiles.
  ///
  /// In en, this message translates to:
  /// **'Cleanup Temporary Files'**
  String get cleanupTemporaryFiles;

  /// No description provided for @cleanupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Cleanup Completed'**
  String get cleanupCompleted;

  /// No description provided for @filesCleaned.
  ///
  /// In en, this message translates to:
  /// **'{count} files cleaned'**
  String filesCleaned(Object count);

  /// No description provided for @fileManagement.
  ///
  /// In en, this message translates to:
  /// **'File Management'**
  String get fileManagement;

  /// No description provided for @allFiles.
  ///
  /// In en, this message translates to:
  /// **'All Files'**
  String get allFiles;

  /// No description provided for @unverifiedFilesList.
  ///
  /// In en, this message translates to:
  /// **'Unverified Files'**
  String get unverifiedFilesList;

  /// No description provided for @fileName.
  ///
  /// In en, this message translates to:
  /// **'File Name'**
  String get fileName;

  /// No description provided for @fileSize.
  ///
  /// In en, this message translates to:
  /// **'File Size'**
  String get fileSize;

  /// No description provided for @mimeType.
  ///
  /// In en, this message translates to:
  /// **'MIME Type'**
  String get mimeType;

  /// No description provided for @moduleContext.
  ///
  /// In en, this message translates to:
  /// **'Module Context'**
  String get moduleContext;

  /// No description provided for @expiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires At'**
  String get expiresAt;

  /// No description provided for @isTemporary.
  ///
  /// In en, this message translates to:
  /// **'Temporary'**
  String get isTemporary;

  /// No description provided for @isVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get isVerified;

  /// No description provided for @forceDelete.
  ///
  /// In en, this message translates to:
  /// **'Force Delete'**
  String get forceDelete;

  /// No description provided for @restoreFile.
  ///
  /// In en, this message translates to:
  /// **'Restore File'**
  String get restoreFile;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure to delete \"{name}\"?'**
  String deleteConfirm(Object name);

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this file?'**
  String get deleteConfirmMessage;

  /// No description provided for @restoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm Restore'**
  String get restoreConfirm;

  /// No description provided for @restoreConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to restore this file?'**
  String get restoreConfirmMessage;

  /// No description provided for @fileDeleted.
  ///
  /// In en, this message translates to:
  /// **'File deleted'**
  String get fileDeleted;

  /// No description provided for @fileRestored.
  ///
  /// In en, this message translates to:
  /// **'File restored'**
  String get fileRestored;

  /// No description provided for @errorDeletingFile.
  ///
  /// In en, this message translates to:
  /// **'Error deleting file'**
  String get errorDeletingFile;

  /// No description provided for @errorRestoringFile.
  ///
  /// In en, this message translates to:
  /// **'Error restoring file'**
  String get errorRestoringFile;

  /// No description provided for @noFilesFound.
  ///
  /// In en, this message translates to:
  /// **'No files found'**
  String get noFilesFound;

  /// No description provided for @loadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Loading files...'**
  String get loadingFiles;

  /// No description provided for @errorLoadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Error loading files'**
  String get errorLoadingFiles;

  /// No description provided for @refreshFiles.
  ///
  /// In en, this message translates to:
  /// **'Refresh Files'**
  String get refreshFiles;

  /// No description provided for @fileDetails.
  ///
  /// In en, this message translates to:
  /// **'File Details'**
  String get fileDetails;

  /// No description provided for @originalName.
  ///
  /// In en, this message translates to:
  /// **'Original Name'**
  String get originalName;

  /// No description provided for @storedName.
  ///
  /// In en, this message translates to:
  /// **'Stored Name'**
  String get storedName;

  /// No description provided for @filePath.
  ///
  /// In en, this message translates to:
  /// **'File Path'**
  String get filePath;

  /// No description provided for @checksum.
  ///
  /// In en, this message translates to:
  /// **'Checksum'**
  String get checksum;

  /// No description provided for @uploadedBy.
  ///
  /// In en, this message translates to:
  /// **'Uploaded by'**
  String get uploadedBy;

  /// No description provided for @lastVerified.
  ///
  /// In en, this message translates to:
  /// **'Last Verified'**
  String get lastVerified;

  /// No description provided for @developerData.
  ///
  /// In en, this message translates to:
  /// **'Developer Data'**
  String get developerData;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @itemsPerPage.
  ///
  /// In en, this message translates to:
  /// **'Items per page'**
  String get itemsPerPage;

  /// No description provided for @first.
  ///
  /// In en, this message translates to:
  /// **'First'**
  String get first;

  /// No description provided for @last.
  ///
  /// In en, this message translates to:
  /// **'Last'**
  String get last;

  /// No description provided for @systemSettingsWelcome.
  ///
  /// In en, this message translates to:
  /// **'System Settings'**
  String get systemSettingsWelcome;

  /// No description provided for @systemSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage system configuration and administration'**
  String get systemSettingsDescription;

  /// No description provided for @storageManagement.
  ///
  /// In en, this message translates to:
  /// **'Storage Management'**
  String get storageManagement;

  /// No description provided for @storageManagementDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure file storage, public app URL for share links (file sharing), and manage files'**
  String get storageManagementDescription;

  /// No description provided for @systemConfiguration.
  ///
  /// In en, this message translates to:
  /// **'System Configuration'**
  String get systemConfiguration;

  /// No description provided for @systemConfigurationDescription.
  ///
  /// In en, this message translates to:
  /// **'General system settings and preferences'**
  String get systemConfigurationDescription;

  /// No description provided for @userManagement.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userManagement;

  /// No description provided for @userManagementDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage users, roles and permissions'**
  String get userManagementDescription;

  /// No description provided for @systemLogs.
  ///
  /// In en, this message translates to:
  /// **'System Logs'**
  String get systemLogs;

  /// No description provided for @systemLogsDescription.
  ///
  /// In en, this message translates to:
  /// **'View system reports and user activity logs'**
  String get systemLogsDescription;

  /// No description provided for @backToSettings.
  ///
  /// In en, this message translates to:
  /// **'Back to Settings'**
  String get backToSettings;

  /// No description provided for @settingsOverview.
  ///
  /// In en, this message translates to:
  /// **'Settings Overview'**
  String get settingsOverview;

  /// No description provided for @availableSettings.
  ///
  /// In en, this message translates to:
  /// **'Available Settings'**
  String get availableSettings;

  /// No description provided for @systemAdministration.
  ///
  /// In en, this message translates to:
  /// **'System Administration'**
  String get systemAdministration;

  /// No description provided for @generalSettings.
  ///
  /// In en, this message translates to:
  /// **'General Settings'**
  String get generalSettings;

  /// No description provided for @securitySettings.
  ///
  /// In en, this message translates to:
  /// **'Security Settings'**
  String get securitySettings;

  /// No description provided for @maintenanceSettings.
  ///
  /// In en, this message translates to:
  /// **'Maintenance Settings'**
  String get maintenanceSettings;

  /// No description provided for @smsDestinationRateSettings.
  ///
  /// In en, this message translates to:
  /// **'SMS rate limit (per destination number)'**
  String get smsDestinationRateSettings;

  /// No description provided for @smsDestinationRateEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enforce per-number send cap within a time window'**
  String get smsDestinationRateEnabled;

  /// No description provided for @smsDestinationRateMaxSends.
  ///
  /// In en, this message translates to:
  /// **'Max sends per number in the window'**
  String get smsDestinationRateMaxSends;

  /// No description provided for @smsDestinationRateWindowMinutes.
  ///
  /// In en, this message translates to:
  /// **'Window length (minutes)'**
  String get smsDestinationRateWindowMinutes;

  /// No description provided for @smsDestinationRateMaxSendsHelper.
  ///
  /// In en, this message translates to:
  /// **'0 means no cap (this per-number limit is off)'**
  String get smsDestinationRateMaxSendsHelper;

  /// No description provided for @initializing.
  ///
  /// In en, this message translates to:
  /// **'Initializing...'**
  String get initializing;

  /// No description provided for @loadingLanguageSettings.
  ///
  /// In en, this message translates to:
  /// **'Loading language settings...'**
  String get loadingLanguageSettings;

  /// No description provided for @loadingCalendarSettings.
  ///
  /// In en, this message translates to:
  /// **'Loading calendar settings...'**
  String get loadingCalendarSettings;

  /// No description provided for @loadingThemeSettings.
  ///
  /// In en, this message translates to:
  /// **'Loading theme settings...'**
  String get loadingThemeSettings;

  /// No description provided for @loadingAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Loading authentication...'**
  String get loadingAuthentication;

  /// No description provided for @businessManagementPlatform.
  ///
  /// In en, this message translates to:
  /// **'Business Management Platform'**
  String get businessManagementPlatform;

  /// No description provided for @businessDashboard.
  ///
  /// In en, this message translates to:
  /// **'Business Dashboard'**
  String get businessDashboard;

  /// No description provided for @businessStatistics.
  ///
  /// In en, this message translates to:
  /// **'Business Statistics'**
  String get businessStatistics;

  /// No description provided for @recentActivities.
  ///
  /// In en, this message translates to:
  /// **'Recent Activities'**
  String get recentActivities;

  /// No description provided for @sales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get sales;

  /// No description provided for @accounting.
  ///
  /// In en, this message translates to:
  /// **'Accounting'**
  String get accounting;

  /// No description provided for @inventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventory;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// No description provided for @backToProfile.
  ///
  /// In en, this message translates to:
  /// **'Back to Profile'**
  String get backToProfile;

  /// No description provided for @noBusinessesFound.
  ///
  /// In en, this message translates to:
  /// **'No businesses found'**
  String get noBusinessesFound;

  /// No description provided for @createFirstBusiness.
  ///
  /// In en, this message translates to:
  /// **'Create your first business'**
  String get createFirstBusiness;

  /// No description provided for @accessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get accessDenied;

  /// No description provided for @basicTools.
  ///
  /// In en, this message translates to:
  /// **'Basic Tools'**
  String get basicTools;

  /// No description provided for @businessSettings.
  ///
  /// In en, this message translates to:
  /// **'Business Settings'**
  String get businessSettings;

  /// No description provided for @printDocuments.
  ///
  /// In en, this message translates to:
  /// **'Print Documents'**
  String get printDocuments;

  /// No description provided for @people.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get people;

  /// No description provided for @peopleList.
  ///
  /// In en, this message translates to:
  /// **'People List'**
  String get peopleList;

  /// No description provided for @personCode.
  ///
  /// In en, this message translates to:
  /// **'Person Code'**
  String get personCode;

  /// No description provided for @receipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get receipts;

  /// No description provided for @payments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get payments;

  /// No description provided for @receiptsAndPayments.
  ///
  /// In en, this message translates to:
  /// **'Receipts and Payments'**
  String get receiptsAndPayments;

  /// No description provided for @productsAndServices.
  ///
  /// In en, this message translates to:
  /// **'Products/Services'**
  String get productsAndServices;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products and Services'**
  String get products;

  /// No description provided for @product.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get product;

  /// No description provided for @services.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get services;

  /// No description provided for @priceLists.
  ///
  /// In en, this message translates to:
  /// **'Price Lists'**
  String get priceLists;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @productAttributes.
  ///
  /// In en, this message translates to:
  /// **'Product Attributes'**
  String get productAttributes;

  /// No description provided for @addAttribute.
  ///
  /// In en, this message translates to:
  /// **'Add Attribute'**
  String get addAttribute;

  /// No description provided for @viewAttributes.
  ///
  /// In en, this message translates to:
  /// **'View Attributes'**
  String get viewAttributes;

  /// No description provided for @editAttributes.
  ///
  /// In en, this message translates to:
  /// **'Edit Attributes'**
  String get editAttributes;

  /// No description provided for @deleteAttributes.
  ///
  /// In en, this message translates to:
  /// **'Delete Attributes'**
  String get deleteAttributes;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @banking.
  ///
  /// In en, this message translates to:
  /// **'Banking'**
  String get banking;

  /// No description provided for @accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accounts;

  /// No description provided for @pettyCash.
  ///
  /// In en, this message translates to:
  /// **'Petty Cash'**
  String get pettyCash;

  /// No description provided for @cashBox.
  ///
  /// In en, this message translates to:
  /// **'Cash Box'**
  String get cashBox;

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// No description provided for @checks.
  ///
  /// In en, this message translates to:
  /// **'Checks'**
  String get checks;

  /// No description provided for @transfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transfers;

  /// No description provided for @invoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoice;

  /// No description provided for @expenseAndIncome.
  ///
  /// In en, this message translates to:
  /// **'Expense and Income'**
  String get expenseAndIncome;

  /// No description provided for @accountingMenu.
  ///
  /// In en, this message translates to:
  /// **'Accounting'**
  String get accountingMenu;

  /// No description provided for @documents.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documents;

  /// No description provided for @chartOfAccounts.
  ///
  /// In en, this message translates to:
  /// **'Chart of Accounts'**
  String get chartOfAccounts;

  /// No description provided for @openingBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance'**
  String get openingBalance;

  /// No description provided for @yearEndClosing.
  ///
  /// In en, this message translates to:
  /// **'Year End Closing'**
  String get yearEndClosing;

  /// No description provided for @currencyRevaluation.
  ///
  /// In en, this message translates to:
  /// **'FX rates & revaluation'**
  String get currencyRevaluation;

  /// No description provided for @accountingSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get accountingSettings;

  /// No description provided for @servicesAndPlugins.
  ///
  /// In en, this message translates to:
  /// **'Services and Plugins'**
  String get servicesAndPlugins;

  /// No description provided for @warehouseManagement.
  ///
  /// In en, this message translates to:
  /// **'Warehouse Management'**
  String get warehouseManagement;

  /// No description provided for @warehouses.
  ///
  /// In en, this message translates to:
  /// **'Warehouse Management'**
  String get warehouses;

  /// No description provided for @inquiries.
  ///
  /// In en, this message translates to:
  /// **'Inquiries'**
  String get inquiries;

  /// No description provided for @storageSpace.
  ///
  /// In en, this message translates to:
  /// **'Storage Space'**
  String get storageSpace;

  /// No description provided for @taxpayers.
  ///
  /// In en, this message translates to:
  /// **'Taxpayers'**
  String get taxpayers;

  /// No description provided for @others.
  ///
  /// In en, this message translates to:
  /// **'Others'**
  String get others;

  /// No description provided for @pluginMarketplace.
  ///
  /// In en, this message translates to:
  /// **'Plugin Marketplace'**
  String get pluginMarketplace;

  /// No description provided for @practicalTools.
  ///
  /// In en, this message translates to:
  /// **'Practical Tools'**
  String get practicalTools;

  /// No description provided for @usersAndPermissions.
  ///
  /// In en, this message translates to:
  /// **'Users and Permissions'**
  String get usersAndPermissions;

  /// No description provided for @businessUsers.
  ///
  /// In en, this message translates to:
  /// **'Business Users'**
  String get businessUsers;

  /// No description provided for @addNewUser.
  ///
  /// In en, this message translates to:
  /// **'Add New User'**
  String get addNewUser;

  /// No description provided for @userEmailOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Email or Phone'**
  String get userEmailOrPhone;

  /// No description provided for @userEmailOrPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Enter user email or phone number'**
  String get userEmailOrPhoneHint;

  /// No description provided for @addUser.
  ///
  /// In en, this message translates to:
  /// **'Add User'**
  String get addUser;

  /// No description provided for @userAddedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'User added successfully'**
  String get userAddedSuccessfully;

  /// No description provided for @userAddFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to add user'**
  String get userAddFailed;

  /// No description provided for @userRemovedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'User removed successfully'**
  String get userRemovedSuccessfully;

  /// No description provided for @userRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove user'**
  String get userRemoveFailed;

  /// No description provided for @permissionsUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Permissions updated successfully'**
  String get permissionsUpdatedSuccessfully;

  /// No description provided for @permissionsUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update permissions'**
  String get permissionsUpdateFailed;

  /// No description provided for @userNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found'**
  String get userNotFound;

  /// No description provided for @invalidEmailOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Invalid email or phone number'**
  String get invalidEmailOrPhone;

  /// No description provided for @userAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'User already exists'**
  String get userAlreadyExists;

  /// No description provided for @removeUser.
  ///
  /// In en, this message translates to:
  /// **'Remove User'**
  String get removeUser;

  /// No description provided for @removeUserConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove this user?'**
  String get removeUserConfirm;

  /// No description provided for @userPermissions.
  ///
  /// In en, this message translates to:
  /// **'User Permissions'**
  String get userPermissions;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @permission.
  ///
  /// In en, this message translates to:
  /// **'Permission'**
  String get permission;

  /// No description provided for @hasPermission.
  ///
  /// In en, this message translates to:
  /// **'Has Permission'**
  String get hasPermission;

  /// No description provided for @noPermission.
  ///
  /// In en, this message translates to:
  /// **'No Permission'**
  String get noPermission;

  /// No description provided for @viewUsers.
  ///
  /// In en, this message translates to:
  /// **'View Users'**
  String get viewUsers;

  /// No description provided for @managePermissions.
  ///
  /// In en, this message translates to:
  /// **'Manage Permissions'**
  String get managePermissions;

  /// No description provided for @totalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total Users'**
  String get totalUsers;

  /// No description provided for @activeUsers.
  ///
  /// In en, this message translates to:
  /// **'Active Users'**
  String get activeUsers;

  /// No description provided for @pendingUsers.
  ///
  /// In en, this message translates to:
  /// **'Pending Users'**
  String get pendingUsers;

  /// No description provided for @userName.
  ///
  /// In en, this message translates to:
  /// **'User Name'**
  String get userName;

  /// No description provided for @userEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get userEmail;

  /// No description provided for @userPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get userPhone;

  /// No description provided for @userStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get userStatus;

  /// No description provided for @userRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get userRole;

  /// No description provided for @userAddedAt.
  ///
  /// In en, this message translates to:
  /// **'Added At'**
  String get userAddedAt;

  /// No description provided for @lastActive.
  ///
  /// In en, this message translates to:
  /// **'Last Active'**
  String get lastActive;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @viewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get viewer;

  /// No description provided for @editPermissions.
  ///
  /// In en, this message translates to:
  /// **'Edit Permissions'**
  String get editPermissions;

  /// No description provided for @savePermissions.
  ///
  /// In en, this message translates to:
  /// **'Save Permissions'**
  String get savePermissions;

  /// No description provided for @permissionsEnableAll.
  ///
  /// In en, this message translates to:
  /// **'Enable all'**
  String get permissionsEnableAll;

  /// No description provided for @permissionsDisableAll.
  ///
  /// In en, this message translates to:
  /// **'Disable all'**
  String get permissionsDisableAll;

  /// No description provided for @permissionsConfirmEnableAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable all permissions?'**
  String get permissionsConfirmEnableAllTitle;

  /// No description provided for @permissionsConfirmEnableAllBody.
  ///
  /// In en, this message translates to:
  /// **'This turns on every permission for this user, including sensitive actions such as fiscal year rollback and user management. Continue?'**
  String get permissionsConfirmEnableAllBody;

  /// No description provided for @permissionsConfirmDisableAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Disable all permissions?'**
  String get permissionsConfirmDisableAllTitle;

  /// No description provided for @permissionsConfirmDisableAllBody.
  ///
  /// In en, this message translates to:
  /// **'This turns off every permission for this user. They will lose access to most features until you change settings again. Continue?'**
  String get permissionsConfirmDisableAllBody;

  /// No description provided for @permissionsConfirmDisableCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Disable this category?'**
  String get permissionsConfirmDisableCategoryTitle;

  /// No description provided for @permissionsConfirmDisableCategoryBody.
  ///
  /// In en, this message translates to:
  /// **'All permissions under \"{categoryName}\" will be turned off for this user. Continue?'**
  String permissionsConfirmDisableCategoryBody(String categoryName);

  /// No description provided for @appLevelPermissionsConfirmEnableBody.
  ///
  /// In en, this message translates to:
  /// **'All application-level privileges listed below will be enabled for this user. Continue?'**
  String get appLevelPermissionsConfirmEnableBody;

  /// No description provided for @appLevelPermissionsConfirmDisableBody.
  ///
  /// In en, this message translates to:
  /// **'All application-level privileges listed below will be disabled for this user. Continue?'**
  String get appLevelPermissionsConfirmDisableBody;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get noUsersFound;

  /// No description provided for @searchUsers.
  ///
  /// In en, this message translates to:
  /// **'Search users...'**
  String get searchUsers;

  /// No description provided for @filterByStatus.
  ///
  /// In en, this message translates to:
  /// **'Filter by Status'**
  String get filterByStatus;

  /// No description provided for @filterByRole.
  ///
  /// In en, this message translates to:
  /// **'Filter by Role'**
  String get filterByRole;

  /// No description provided for @allStatuses.
  ///
  /// In en, this message translates to:
  /// **'All Statuses'**
  String get allStatuses;

  /// No description provided for @allRoles.
  ///
  /// In en, this message translates to:
  /// **'All Roles'**
  String get allRoles;

  /// No description provided for @permissionDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Access'**
  String get permissionDashboard;

  /// No description provided for @permissionPeople.
  ///
  /// In en, this message translates to:
  /// **'People Access'**
  String get permissionPeople;

  /// No description provided for @permissionReceipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts Access'**
  String get permissionReceipts;

  /// No description provided for @permissionPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments Access'**
  String get permissionPayments;

  /// No description provided for @permissionReports.
  ///
  /// In en, this message translates to:
  /// **'Reports Access'**
  String get permissionReports;

  /// No description provided for @permissionSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings Access'**
  String get permissionSettings;

  /// No description provided for @permissionUsers.
  ///
  /// In en, this message translates to:
  /// **'Users Access'**
  String get permissionUsers;

  /// No description provided for @permissionPrint.
  ///
  /// In en, this message translates to:
  /// **'Print Access'**
  String get permissionPrint;

  /// No description provided for @ownerWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning: Business owner does not need to be added and always has full access to all sections'**
  String get ownerWarning;

  /// No description provided for @ownerWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Business Owner'**
  String get ownerWarningTitle;

  /// No description provided for @alreadyAddedWarning.
  ///
  /// In en, this message translates to:
  /// **'This user has already been added to the business'**
  String get alreadyAddedWarning;

  /// No description provided for @alreadyAddedWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Existing User'**
  String get alreadyAddedWarningTitle;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version 1.0.23'**
  String get version;

  /// No description provided for @motto.
  ///
  /// In en, this message translates to:
  /// **'The world becomes beautiful through cooperation'**
  String get motto;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Manage Drafts'**
  String get draft;

  /// No description provided for @addPerson.
  ///
  /// In en, this message translates to:
  /// **'Add Person'**
  String get addPerson;

  /// No description provided for @viewPeople.
  ///
  /// In en, this message translates to:
  /// **'View People List'**
  String get viewPeople;

  /// No description provided for @editPeople.
  ///
  /// In en, this message translates to:
  /// **'Edit People Information'**
  String get editPeople;

  /// No description provided for @deletePeople.
  ///
  /// In en, this message translates to:
  /// **'Delete People'**
  String get deletePeople;

  /// No description provided for @addReceipt.
  ///
  /// In en, this message translates to:
  /// **'Add New Receipt'**
  String get addReceipt;

  /// No description provided for @viewReceipts.
  ///
  /// In en, this message translates to:
  /// **'View Receipts'**
  String get viewReceipts;

  /// No description provided for @editReceipts.
  ///
  /// In en, this message translates to:
  /// **'Edit Receipts'**
  String get editReceipts;

  /// No description provided for @deleteReceipts.
  ///
  /// In en, this message translates to:
  /// **'Delete Receipts'**
  String get deleteReceipts;

  /// No description provided for @manageReceiptDrafts.
  ///
  /// In en, this message translates to:
  /// **'Manage Receipt Drafts'**
  String get manageReceiptDrafts;

  /// No description provided for @addPayment.
  ///
  /// In en, this message translates to:
  /// **'Add New Payment'**
  String get addPayment;

  /// No description provided for @viewPayments.
  ///
  /// In en, this message translates to:
  /// **'View Payments'**
  String get viewPayments;

  /// No description provided for @editPayments.
  ///
  /// In en, this message translates to:
  /// **'Edit Payments'**
  String get editPayments;

  /// No description provided for @deletePayments.
  ///
  /// In en, this message translates to:
  /// **'Delete Payments'**
  String get deletePayments;

  /// No description provided for @managePaymentDrafts.
  ///
  /// In en, this message translates to:
  /// **'Manage Payment Drafts'**
  String get managePaymentDrafts;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product or Service'**
  String get addProduct;

  /// No description provided for @duplicateProduct.
  ///
  /// In en, this message translates to:
  /// **'Copy Product / Service'**
  String get duplicateProduct;

  /// No description provided for @productDuplicatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Product copy was created successfully'**
  String get productDuplicatedSuccessfully;

  /// No description provided for @viewProducts.
  ///
  /// In en, this message translates to:
  /// **'View Products and Services'**
  String get viewProducts;

  /// No description provided for @editProducts.
  ///
  /// In en, this message translates to:
  /// **'Edit Products and Services'**
  String get editProducts;

  /// No description provided for @deleteProducts.
  ///
  /// In en, this message translates to:
  /// **'Delete Products and Services'**
  String get deleteProducts;

  /// No description provided for @addPriceList.
  ///
  /// In en, this message translates to:
  /// **'Add Price List'**
  String get addPriceList;

  /// No description provided for @viewPriceLists.
  ///
  /// In en, this message translates to:
  /// **'View Price Lists'**
  String get viewPriceLists;

  /// No description provided for @editPriceLists.
  ///
  /// In en, this message translates to:
  /// **'Edit Price Lists'**
  String get editPriceLists;

  /// No description provided for @deletePriceLists.
  ///
  /// In en, this message translates to:
  /// **'Delete Price Lists'**
  String get deletePriceLists;

  /// No description provided for @addCategory.
  ///
  /// In en, this message translates to:
  /// **'Add Category'**
  String get addCategory;

  /// No description provided for @viewCategories.
  ///
  /// In en, this message translates to:
  /// **'View Categories'**
  String get viewCategories;

  /// No description provided for @editCategories.
  ///
  /// In en, this message translates to:
  /// **'Edit Categories'**
  String get editCategories;

  /// No description provided for @deleteCategories.
  ///
  /// In en, this message translates to:
  /// **'Delete Categories'**
  String get deleteCategories;

  /// No description provided for @addInventory.
  ///
  /// In en, this message translates to:
  /// **'Add Inventory'**
  String get addInventory;

  /// No description provided for @viewInventory.
  ///
  /// In en, this message translates to:
  /// **'View Inventory'**
  String get viewInventory;

  /// No description provided for @editInventory.
  ///
  /// In en, this message translates to:
  /// **'Edit Inventory'**
  String get editInventory;

  /// No description provided for @deleteInventory.
  ///
  /// In en, this message translates to:
  /// **'Delete Inventory'**
  String get deleteInventory;

  /// No description provided for @viewReports.
  ///
  /// In en, this message translates to:
  /// **'View Reports'**
  String get viewReports;

  /// No description provided for @generateReports.
  ///
  /// In en, this message translates to:
  /// **'Generate Reports'**
  String get generateReports;

  /// No description provided for @exportReports.
  ///
  /// In en, this message translates to:
  /// **'Export Reports'**
  String get exportReports;

  /// No description provided for @viewSettings.
  ///
  /// In en, this message translates to:
  /// **'View Settings'**
  String get viewSettings;

  /// No description provided for @editSettings.
  ///
  /// In en, this message translates to:
  /// **'Edit Settings'**
  String get editSettings;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @manageUsers.
  ///
  /// In en, this message translates to:
  /// **'Manage Users'**
  String get manageUsers;

  /// No description provided for @print.
  ///
  /// In en, this message translates to:
  /// **'Print Documents'**
  String get print;

  /// No description provided for @peopleReceipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts from People'**
  String get peopleReceipts;

  /// No description provided for @peoplePayments.
  ///
  /// In en, this message translates to:
  /// **'Payments to People'**
  String get peoplePayments;

  /// No description provided for @storageConfigUpdated.
  ///
  /// In en, this message translates to:
  /// **'Storage configuration updated'**
  String get storageConfigUpdated;

  /// No description provided for @storageConfigCreated.
  ///
  /// In en, this message translates to:
  /// **'Storage configuration created'**
  String get storageConfigCreated;

  /// No description provided for @storageConfigDeleted.
  ///
  /// In en, this message translates to:
  /// **'Storage configuration deleted'**
  String get storageConfigDeleted;

  /// No description provided for @storageConfigHasFiles.
  ///
  /// In en, this message translates to:
  /// **'This storage configuration has files and cannot be deleted'**
  String get storageConfigHasFiles;

  /// No description provided for @storageConfigNotFound.
  ///
  /// In en, this message translates to:
  /// **'Storage configuration not found'**
  String get storageConfigNotFound;

  /// No description provided for @storageConfigSetAsDefault.
  ///
  /// In en, this message translates to:
  /// **'Configuration set as default'**
  String get storageConfigSetAsDefault;

  /// No description provided for @storageConfigSetDefaultFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to set as default'**
  String get storageConfigSetDefaultFailed;

  /// No description provided for @adminStorageFtpPurposeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used as the default file storage backend for uploads (not the same as per-business backup FTP).'**
  String get adminStorageFtpPurposeSubtitle;

  /// No description provided for @adminStorageFtpInsecureWarning.
  ///
  /// In en, this message translates to:
  /// **'Without TLS, credentials and data can be read on the network. Enable TLS when the server supports it.'**
  String get adminStorageFtpInsecureWarning;

  /// No description provided for @adminStorageFtpPasswordOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep the current password'**
  String get adminStorageFtpPasswordOptionalHint;

  /// No description provided for @adminStorageFtpPassive.
  ///
  /// In en, this message translates to:
  /// **'Passive mode (PASV)'**
  String get adminStorageFtpPassive;

  /// No description provided for @adminStorageFormSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic information'**
  String get adminStorageFormSectionBasic;

  /// No description provided for @adminStorageFormSectionDetails.
  ///
  /// In en, this message translates to:
  /// **'Configuration details'**
  String get adminStorageFormSectionDetails;

  /// No description provided for @adminStorageFormSectionOptions.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get adminStorageFormSectionOptions;

  /// No description provided for @adminStorageNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a name for this storage profile'**
  String get adminStorageNameHint;

  /// No description provided for @adminStorageFtpHostLabel.
  ///
  /// In en, this message translates to:
  /// **'FTP host'**
  String get adminStorageFtpHostLabel;

  /// No description provided for @adminStorageFtpHostHint.
  ///
  /// In en, this message translates to:
  /// **'Hostname or IP of the FTP server'**
  String get adminStorageFtpHostHint;

  /// No description provided for @adminStorageFtpPortHintPlain.
  ///
  /// In en, this message translates to:
  /// **'Default 21 without TLS'**
  String get adminStorageFtpPortHintPlain;

  /// No description provided for @adminStorageFtpPortHintTls.
  ///
  /// In en, this message translates to:
  /// **'Often 990 with implicit TLS, or 21 with explicit TLS'**
  String get adminStorageFtpPortHintTls;

  /// No description provided for @adminStorageFtpDirectoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Remote folder'**
  String get adminStorageFtpDirectoryLabel;

  /// No description provided for @adminStorageFtpDirectoryHint.
  ///
  /// In en, this message translates to:
  /// **'Remote folder for stored files (e.g. /hesabix_files)'**
  String get adminStorageFtpDirectoryHint;

  /// No description provided for @adminStorageLocalBasePath.
  ///
  /// In en, this message translates to:
  /// **'Base path'**
  String get adminStorageLocalBasePath;

  /// No description provided for @adminStorageFtpUseTlsTitle.
  ///
  /// In en, this message translates to:
  /// **'Use TLS'**
  String get adminStorageFtpUseTlsTitle;

  /// No description provided for @adminStorageFtpUseTlsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'FTP over TLS (FTPS) when supported'**
  String get adminStorageFtpUseTlsSubtitle;

  /// No description provided for @adminStorageDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get adminStorageDefaultTitle;

  /// No description provided for @adminStorageDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use this profile as the default storage'**
  String get adminStorageDefaultSubtitle;

  /// No description provided for @adminStorageActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminStorageActiveTitle;

  /// No description provided for @adminStorageActiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Inactive profiles are not used for new uploads'**
  String get adminStorageActiveSubtitle;

  /// No description provided for @adminStorageCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create storage profile'**
  String get adminStorageCreateTitle;

  /// No description provided for @adminStorageEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit storage profile'**
  String get adminStorageEditTitle;

  /// No description provided for @adminStorageFtpServerTitle.
  ///
  /// In en, this message translates to:
  /// **'FTP server'**
  String get adminStorageFtpServerTitle;

  /// No description provided for @adminStorageTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get adminStorageTestConnection;

  /// No description provided for @adminStorageTestingConnection.
  ///
  /// In en, this message translates to:
  /// **'Testing connection…'**
  String get adminStorageTestingConnection;

  /// No description provided for @adminStorageTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection test succeeded'**
  String get adminStorageTestSuccess;

  /// No description provided for @adminStorageTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection test failed'**
  String get adminStorageTestFailed;

  /// No description provided for @adminStorageSaveInProgress.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get adminStorageSaveInProgress;

  /// No description provided for @adminStorageCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get adminStorageCreateButton;

  /// No description provided for @adminStorageUpdateButton.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get adminStorageUpdateButton;

  /// No description provided for @passwordChangeError.
  ///
  /// In en, this message translates to:
  /// **'Error changing password'**
  String get passwordChangeError;

  /// No description provided for @bankAccounts.
  ///
  /// In en, this message translates to:
  /// **'Bank Accounts'**
  String get bankAccounts;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash;

  /// No description provided for @invoices.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get invoices;

  /// No description provided for @expensesIncome.
  ///
  /// In en, this message translates to:
  /// **'Expenses & Income'**
  String get expensesIncome;

  /// No description provided for @accountingDocuments.
  ///
  /// In en, this message translates to:
  /// **'Accounting Documents'**
  String get accountingDocuments;

  /// No description provided for @warehouse.
  ///
  /// In en, this message translates to:
  /// **'Warehouse'**
  String get warehouse;

  /// No description provided for @warehouseTransfers.
  ///
  /// In en, this message translates to:
  /// **'Warehouse Transfers'**
  String get warehouseTransfers;

  /// User permissions screen: explains warehouse vs warehouse-transfer capabilities.
  ///
  /// In en, this message translates to:
  /// **'Warehouse locations and warehouse documents use different permissions. Warehouse management is for defining warehouses. To use warehouse documents (lists, creating or posting documents, issuing from invoices, stock count adjustments, and related stock operations), enable the matching options under Warehouse transfers.'**
  String get permissionsWarehouseInventoryHint;

  /// User permissions: checks group — link to accounting documents permission.
  ///
  /// In en, this message translates to:
  /// **'Creating a new check posts an accounting document. Besides check permissions, enable at least one of add, edit, or draft under Accounting documents. Some check workflows (collection, endorsement, payment, etc.) may also record documents.'**
  String get permissionsGroupHintChecks;

  /// User permissions: accounting documents group — scope of the permission.
  ///
  /// In en, this message translates to:
  /// **'These permissions apply to manual journal entries and to automatic documents generated by the system from operations such as checks, receipts and payments, and invoices (where applicable).'**
  String get permissionsGroupHintAccountingDocuments;

  /// No description provided for @permissionsCategoryInvoicesAndExpenses.
  ///
  /// In en, this message translates to:
  /// **'Invoices & expenses'**
  String get permissionsCategoryInvoicesAndExpenses;

  /// No description provided for @permissionSectionInvoiceTypes.
  ///
  /// In en, this message translates to:
  /// **'Allowed invoice types'**
  String get permissionSectionInvoiceTypes;

  /// No description provided for @permissionSectionPricing.
  ///
  /// In en, this message translates to:
  /// **'Sales / purchase price visibility'**
  String get permissionSectionPricing;

  /// No description provided for @permissionSectionCrmWebChat.
  ///
  /// In en, this message translates to:
  /// **'Web chat widget (CRM)'**
  String get permissionSectionCrmWebChat;

  /// No description provided for @permissionCrmEditAndAdd.
  ///
  /// In en, this message translates to:
  /// **'Create and edit CRM records'**
  String get permissionCrmEditAndAdd;

  /// No description provided for @permissionCrmViewReports.
  ///
  /// In en, this message translates to:
  /// **'View CRM reports'**
  String get permissionCrmViewReports;

  /// No description provided for @permissionCrmTeamPerformanceReports.
  ///
  /// In en, this message translates to:
  /// **'Team performance reports (entire team)'**
  String get permissionCrmTeamPerformanceReports;

  /// No description provided for @permissionCrmWebChatView.
  ///
  /// In en, this message translates to:
  /// **'View web chat'**
  String get permissionCrmWebChatView;

  /// No description provided for @permissionCrmWebChatReply.
  ///
  /// In en, this message translates to:
  /// **'Reply and send messages in web chat'**
  String get permissionCrmWebChatReply;

  /// No description provided for @permissionCrmWebChatManageWidgets.
  ///
  /// In en, this message translates to:
  /// **'Create and edit chat widgets'**
  String get permissionCrmWebChatManageWidgets;

  /// No description provided for @permissionCrmWebChatEditConversations.
  ///
  /// In en, this message translates to:
  /// **'Edit conversations (status, assignment, lead)'**
  String get permissionCrmWebChatEditConversations;

  /// No description provided for @permissionCrmWebChatDeleteMessages.
  ///
  /// In en, this message translates to:
  /// **'Delete messages in web chat'**
  String get permissionCrmWebChatDeleteMessages;

  /// No description provided for @permissionFiscalYearEditCurrent.
  ///
  /// In en, this message translates to:
  /// **'Edit current fiscal year'**
  String get permissionFiscalYearEditCurrent;

  /// No description provided for @permissionFiscalYearClose.
  ///
  /// In en, this message translates to:
  /// **'Close fiscal year'**
  String get permissionFiscalYearClose;

  /// No description provided for @permissionFiscalYearRollbackDangerous.
  ///
  /// In en, this message translates to:
  /// **'Revert current fiscal year (dangerous operation)'**
  String get permissionFiscalYearRollbackDangerous;

  /// User permissions dialog: save failed with server or network detail.
  ///
  /// In en, this message translates to:
  /// **'Could not update permissions: {error}'**
  String permissionsUpdateError(String error);

  /// Check form dialog when user lacks check write permissions.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to add or edit checks.'**
  String get checkFormNeedsChecksWritePermission;

  /// Check form dialog when user lacks accounting document posting permissions.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to post accounting documents. Saving a check records a journal entry; ask an admin to grant add, edit, or draft under Accounting documents.'**
  String get checkFormNeedsAccountingDocumentsPermission;

  /// Check form save error when Sayad code already exists in the business.
  ///
  /// In en, this message translates to:
  /// **'This Sayad code is already registered for another check in this business.'**
  String get checkFormDuplicateSayadCode;

  /// No description provided for @addBankAccount.
  ///
  /// In en, this message translates to:
  /// **'Add Bank Account'**
  String get addBankAccount;

  /// No description provided for @viewBankAccounts.
  ///
  /// In en, this message translates to:
  /// **'View Bank Accounts'**
  String get viewBankAccounts;

  /// No description provided for @editBankAccounts.
  ///
  /// In en, this message translates to:
  /// **'Edit Bank Accounts'**
  String get editBankAccounts;

  /// No description provided for @deleteBankAccounts.
  ///
  /// In en, this message translates to:
  /// **'Delete Bank Accounts'**
  String get deleteBankAccounts;

  /// No description provided for @addCash.
  ///
  /// In en, this message translates to:
  /// **'Add Cash'**
  String get addCash;

  /// No description provided for @viewCash.
  ///
  /// In en, this message translates to:
  /// **'View Cash'**
  String get viewCash;

  /// No description provided for @editCash.
  ///
  /// In en, this message translates to:
  /// **'Edit Cash'**
  String get editCash;

  /// No description provided for @deleteCash.
  ///
  /// In en, this message translates to:
  /// **'Delete Cash'**
  String get deleteCash;

  /// No description provided for @addPettyCash.
  ///
  /// In en, this message translates to:
  /// **'Add Petty Cash'**
  String get addPettyCash;

  /// No description provided for @viewPettyCash.
  ///
  /// In en, this message translates to:
  /// **'View Petty Cash'**
  String get viewPettyCash;

  /// No description provided for @editPettyCash.
  ///
  /// In en, this message translates to:
  /// **'Edit Petty Cash'**
  String get editPettyCash;

  /// No description provided for @deletePettyCash.
  ///
  /// In en, this message translates to:
  /// **'Delete Petty Cash'**
  String get deletePettyCash;

  /// No description provided for @addCheck.
  ///
  /// In en, this message translates to:
  /// **'Add Check'**
  String get addCheck;

  /// No description provided for @viewChecks.
  ///
  /// In en, this message translates to:
  /// **'View Checks'**
  String get viewChecks;

  /// No description provided for @editChecks.
  ///
  /// In en, this message translates to:
  /// **'Edit Checks'**
  String get editChecks;

  /// No description provided for @deleteChecks.
  ///
  /// In en, this message translates to:
  /// **'Delete Checks'**
  String get deleteChecks;

  /// No description provided for @collectChecks.
  ///
  /// In en, this message translates to:
  /// **'Collect Checks'**
  String get collectChecks;

  /// No description provided for @transferChecks.
  ///
  /// In en, this message translates to:
  /// **'Transfer Checks'**
  String get transferChecks;

  /// No description provided for @returnChecks.
  ///
  /// In en, this message translates to:
  /// **'Return Checks'**
  String get returnChecks;

  /// No description provided for @viewWallet.
  ///
  /// In en, this message translates to:
  /// **'View Wallet'**
  String get viewWallet;

  /// No description provided for @chargeWallet.
  ///
  /// In en, this message translates to:
  /// **'Charge Wallet'**
  String get chargeWallet;

  /// No description provided for @addTransfer.
  ///
  /// In en, this message translates to:
  /// **'Add Transfer'**
  String get addTransfer;

  /// No description provided for @viewTransfers.
  ///
  /// In en, this message translates to:
  /// **'View Transfers'**
  String get viewTransfers;

  /// No description provided for @editTransfers.
  ///
  /// In en, this message translates to:
  /// **'Edit Transfers'**
  String get editTransfers;

  /// No description provided for @deleteTransfers.
  ///
  /// In en, this message translates to:
  /// **'Delete Transfers'**
  String get deleteTransfers;

  /// No description provided for @manageTransferDrafts.
  ///
  /// In en, this message translates to:
  /// **'Manage Transfer Drafts'**
  String get manageTransferDrafts;

  /// No description provided for @addInvoice.
  ///
  /// In en, this message translates to:
  /// **'Add Invoice'**
  String get addInvoice;

  /// No description provided for @invoiceCopyOpenNew.
  ///
  /// In en, this message translates to:
  /// **'Copy to new invoice'**
  String get invoiceCopyOpenNew;

  /// No description provided for @invoiceCopyLoading.
  ///
  /// In en, this message translates to:
  /// **'Preparing the new invoice form from the selected document…'**
  String get invoiceCopyLoading;

  /// No description provided for @viewInvoices.
  ///
  /// In en, this message translates to:
  /// **'View Invoices'**
  String get viewInvoices;

  /// No description provided for @editInvoices.
  ///
  /// In en, this message translates to:
  /// **'Edit Invoices'**
  String get editInvoices;

  /// No description provided for @deleteInvoices.
  ///
  /// In en, this message translates to:
  /// **'Delete Invoices'**
  String get deleteInvoices;

  /// No description provided for @manageInvoiceDrafts.
  ///
  /// In en, this message translates to:
  /// **'Manage Invoice Drafts'**
  String get manageInvoiceDrafts;

  /// No description provided for @addExpenseIncome.
  ///
  /// In en, this message translates to:
  /// **'Add Expense/Income'**
  String get addExpenseIncome;

  /// No description provided for @viewExpensesIncome.
  ///
  /// In en, this message translates to:
  /// **'View Expenses & Income'**
  String get viewExpensesIncome;

  /// No description provided for @editExpensesIncome.
  ///
  /// In en, this message translates to:
  /// **'Edit Expenses & Income'**
  String get editExpensesIncome;

  /// No description provided for @deleteExpensesIncome.
  ///
  /// In en, this message translates to:
  /// **'Delete Expenses & Income'**
  String get deleteExpensesIncome;

  /// No description provided for @manageExpenseIncomeDrafts.
  ///
  /// In en, this message translates to:
  /// **'Manage Expense/Income Drafts'**
  String get manageExpenseIncomeDrafts;

  /// No description provided for @addAccountingDocument.
  ///
  /// In en, this message translates to:
  /// **'Add Accounting Document'**
  String get addAccountingDocument;

  /// No description provided for @viewAccountingDocuments.
  ///
  /// In en, this message translates to:
  /// **'View Accounting Documents'**
  String get viewAccountingDocuments;

  /// No description provided for @editAccountingDocuments.
  ///
  /// In en, this message translates to:
  /// **'Edit Accounting Documents'**
  String get editAccountingDocuments;

  /// No description provided for @deleteAccountingDocuments.
  ///
  /// In en, this message translates to:
  /// **'Delete Accounting Documents'**
  String get deleteAccountingDocuments;

  /// No description provided for @manageAccountingDocumentDrafts.
  ///
  /// In en, this message translates to:
  /// **'Manage Accounting Document Drafts'**
  String get manageAccountingDocumentDrafts;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add Account'**
  String get addAccount;

  /// No description provided for @viewChartOfAccounts.
  ///
  /// In en, this message translates to:
  /// **'View Chart of Accounts'**
  String get viewChartOfAccounts;

  /// No description provided for @editChartOfAccounts.
  ///
  /// In en, this message translates to:
  /// **'Edit Chart of Accounts'**
  String get editChartOfAccounts;

  /// No description provided for @deleteAccounts.
  ///
  /// In en, this message translates to:
  /// **'Delete Accounts'**
  String get deleteAccounts;

  /// No description provided for @viewOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'View Opening Balance'**
  String get viewOpeningBalance;

  /// No description provided for @editOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'Edit Opening Balance'**
  String get editOpeningBalance;

  /// No description provided for @addWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Add Warehouse'**
  String get addWarehouse;

  /// No description provided for @viewWarehouses.
  ///
  /// In en, this message translates to:
  /// **'View Warehouses'**
  String get viewWarehouses;

  /// No description provided for @editWarehouses.
  ///
  /// In en, this message translates to:
  /// **'Edit Warehouses'**
  String get editWarehouses;

  /// No description provided for @deleteWarehouses.
  ///
  /// In en, this message translates to:
  /// **'Delete Warehouses'**
  String get deleteWarehouses;

  /// No description provided for @addWarehouseTransfer.
  ///
  /// In en, this message translates to:
  /// **'Add Warehouse Transfer'**
  String get addWarehouseTransfer;

  /// No description provided for @viewWarehouseTransfers.
  ///
  /// In en, this message translates to:
  /// **'View Warehouse Transfers'**
  String get viewWarehouseTransfers;

  /// No description provided for @editWarehouseTransfers.
  ///
  /// In en, this message translates to:
  /// **'Edit Warehouse Transfers'**
  String get editWarehouseTransfers;

  /// No description provided for @deleteWarehouseTransfers.
  ///
  /// In en, this message translates to:
  /// **'Delete Warehouse Transfers'**
  String get deleteWarehouseTransfers;

  /// No description provided for @manageWarehouseTransferDrafts.
  ///
  /// In en, this message translates to:
  /// **'Manage Warehouse Transfer Drafts'**
  String get manageWarehouseTransferDrafts;

  /// No description provided for @printSettings.
  ///
  /// In en, this message translates to:
  /// **'Print Settings'**
  String get printSettings;

  /// No description provided for @eventHistory.
  ///
  /// In en, this message translates to:
  /// **'Event History'**
  String get eventHistory;

  /// No description provided for @viewStorage.
  ///
  /// In en, this message translates to:
  /// **'View Storage'**
  String get viewStorage;

  /// No description provided for @deleteFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get deleteFiles;

  /// No description provided for @smsPanel.
  ///
  /// In en, this message translates to:
  /// **'SMS Panel'**
  String get smsPanel;

  /// No description provided for @viewSmsHistory.
  ///
  /// In en, this message translates to:
  /// **'View SMS History'**
  String get viewSmsHistory;

  /// No description provided for @manageSmsTemplates.
  ///
  /// In en, this message translates to:
  /// **'Manage SMS Templates'**
  String get manageSmsTemplates;

  /// No description provided for @marketplace.
  ///
  /// In en, this message translates to:
  /// **'Marketplace'**
  String get marketplace;

  /// No description provided for @viewMarketplace.
  ///
  /// In en, this message translates to:
  /// **'View Marketplace'**
  String get viewMarketplace;

  /// No description provided for @buyPlugins.
  ///
  /// In en, this message translates to:
  /// **'Buy Plugins'**
  String get buyPlugins;

  /// No description provided for @appearanceSettings.
  ///
  /// In en, this message translates to:
  /// **'Appearance Settings'**
  String get appearanceSettings;

  /// No description provided for @advancedSettings.
  ///
  /// In en, this message translates to:
  /// **'Advanced Settings'**
  String get advancedSettings;

  /// No description provided for @businessSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage business information and main settings'**
  String get businessSettingsDescription;

  /// No description provided for @usersAndPermissionsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage users and set access levels'**
  String get usersAndPermissionsDescription;

  /// No description provided for @printDocumentsDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure print templates and formatting'**
  String get printDocumentsDescription;

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'Select user interface language'**
  String get languageDescription;

  /// No description provided for @themeDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose light, dark or system theme'**
  String get themeDescription;

  /// No description provided for @calendarDescription.
  ///
  /// In en, this message translates to:
  /// **'Select calendar type (Jalali or Gregorian)'**
  String get calendarDescription;

  /// No description provided for @dataBackup.
  ///
  /// In en, this message translates to:
  /// **'Data Backup'**
  String get dataBackup;

  /// No description provided for @dataBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Create backup of all business data'**
  String get dataBackupDescription;

  /// No description provided for @dataRestore.
  ///
  /// In en, this message translates to:
  /// **'Data Restore'**
  String get dataRestore;

  /// No description provided for @dataRestoreDescription.
  ///
  /// In en, this message translates to:
  /// **'Restore data from previous backup'**
  String get dataRestoreDescription;

  /// No description provided for @restoreModeNewBusiness.
  ///
  /// In en, this message translates to:
  /// **'Create a new business'**
  String get restoreModeNewBusiness;

  /// No description provided for @restoreModeReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace existing data'**
  String get restoreModeReplace;

  /// No description provided for @restoreWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Security Warning'**
  String get restoreWarningTitle;

  /// No description provided for @restoreWarningReplace.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Restoring with \"Complete replacement\" mode will DELETE all current business data and replace it with backup data. This action is IRREVERSIBLE!'**
  String get restoreWarningReplace;

  /// No description provided for @restoreWarningNewBusiness.
  ///
  /// In en, this message translates to:
  /// **'ℹ️ Restoring with \"Create new business\" mode will create a new business with backup data and will NOT affect your current data.'**
  String get restoreWarningNewBusiness;

  /// No description provided for @restoreSecurityNote.
  ///
  /// In en, this message translates to:
  /// **'Security Notes:'**
  String get restoreSecurityNote;

  /// No description provided for @restoreSecurityNote1.
  ///
  /// In en, this message translates to:
  /// **'• Create a backup of your current data before restoring'**
  String get restoreSecurityNote1;

  /// No description provided for @restoreSecurityNote2.
  ///
  /// In en, this message translates to:
  /// **'• Ensure the backup file is valid and belongs to your business'**
  String get restoreSecurityNote2;

  /// No description provided for @restoreSecurityNote3.
  ///
  /// In en, this message translates to:
  /// **'• Restore may take several minutes, please wait'**
  String get restoreSecurityNote3;

  /// No description provided for @restoreSecurityNote4.
  ///
  /// In en, this message translates to:
  /// **'• Contact support if you encounter any errors'**
  String get restoreSecurityNote4;

  /// No description provided for @restoreConfirmReplace.
  ///
  /// In en, this message translates to:
  /// **'Confirm Complete Replacement'**
  String get restoreConfirmReplace;

  /// No description provided for @restoreConfirmReplaceMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to DELETE all current data and replace it with backup data?\n\nThis action is IRREVERSIBLE!'**
  String get restoreConfirmReplaceMessage;

  /// No description provided for @restoreConfirmNewBusiness.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Business Creation'**
  String get restoreConfirmNewBusiness;

  /// No description provided for @restoreConfirmNewBusinessMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to create a new business with backup data?'**
  String get restoreConfirmNewBusinessMessage;

  /// No description provided for @restoreSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Source'**
  String get restoreSourceTitle;

  /// No description provided for @restoreModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Mode'**
  String get restoreModeTitle;

  /// No description provided for @selectBackupFile.
  ///
  /// In en, this message translates to:
  /// **'Select backup file (.hbx)'**
  String get selectBackupFile;

  /// No description provided for @defaultBackupFilename.
  ///
  /// In en, this message translates to:
  /// **'backup.hbx'**
  String get defaultBackupFilename;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get errorUnknown;

  /// No description provided for @errorConnectionTimeout.
  ///
  /// In en, this message translates to:
  /// **'Connection timeout. Please check your internet connection.'**
  String get errorConnectionTimeout;

  /// No description provided for @errorReceiveTimeout.
  ///
  /// In en, this message translates to:
  /// **'Receive timeout. Please try again.'**
  String get errorReceiveTimeout;

  /// No description provided for @errorConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection error. Please check your internet connection.'**
  String get errorConnectionError;

  /// No description provided for @errorFileUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'File upload failed. Please try again.'**
  String get errorFileUploadFailed;

  /// No description provided for @errorDataSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the data. Please try again.'**
  String get errorDataSaveFailed;

  /// No description provided for @errorSendTimeout.
  ///
  /// In en, this message translates to:
  /// **'Send timeout.'**
  String get errorSendTimeout;

  /// No description provided for @errorUnknownServer.
  ///
  /// In en, this message translates to:
  /// **'Unknown server error'**
  String get errorUnknownServer;

  /// No description provided for @errorRequestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request timeout. Please try again.'**
  String get errorRequestTimeout;

  /// No description provided for @errorExtractorSaveData.
  ///
  /// In en, this message translates to:
  /// **'Could not save data.'**
  String get errorExtractorSaveData;

  /// No description provided for @errorExtractorFileUpload.
  ///
  /// In en, this message translates to:
  /// **'File upload error.'**
  String get errorExtractorFileUpload;

  /// No description provided for @errorInternetUnavailablePleaseRetry.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Please try again.'**
  String get errorInternetUnavailablePleaseRetry;

  /// No description provided for @errorInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'Invalid input data. Please check the information.'**
  String get errorInvalidInput;

  /// No description provided for @errorBackupNotFound.
  ///
  /// In en, this message translates to:
  /// **'Backup not found.'**
  String get errorBackupNotFound;

  /// No description provided for @errorBusinessMismatch.
  ///
  /// In en, this message translates to:
  /// **'This backup belongs to a different business.'**
  String get errorBusinessMismatch;

  /// No description provided for @errorNotSupported.
  ///
  /// In en, this message translates to:
  /// **'This operation is not currently supported.'**
  String get errorNotSupported;

  /// No description provided for @errorRateLimit.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please wait a moment.'**
  String get errorRateLimit;

  /// No description provided for @errorInvalidBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup file is invalid or corrupted.'**
  String get errorInvalidBackup;

  /// No description provided for @errorBusinessCreationFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create new business. Please try again.'**
  String get errorBusinessCreationFailed;

  /// No description provided for @errorRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed'**
  String get errorRestoreFailed;

  /// No description provided for @apiErrorBusinessUsersBusinessNotFound.
  ///
  /// In en, this message translates to:
  /// **'Business not found.'**
  String get apiErrorBusinessUsersBusinessNotFound;

  /// No description provided for @apiErrorBusinessUsersUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'User not found.'**
  String get apiErrorBusinessUsersUserNotFound;

  /// No description provided for @apiErrorBusinessUsersInviteAccountMissing.
  ///
  /// In en, this message translates to:
  /// **'No user found with this email or phone number. They must register first.'**
  String get apiErrorBusinessUsersInviteAccountMissing;

  /// No description provided for @apiErrorBusinessUsersAlreadyMember.
  ///
  /// In en, this message translates to:
  /// **'This user is already a member of this business.'**
  String get apiErrorBusinessUsersAlreadyMember;

  /// No description provided for @apiErrorBusinessUsersCannotRemoveOwner.
  ///
  /// In en, this message translates to:
  /// **'You cannot remove the business owner.'**
  String get apiErrorBusinessUsersCannotRemoveOwner;

  /// No description provided for @apiErrorBusinessUsersRemoveMemberNotFound.
  ///
  /// In en, this message translates to:
  /// **'This user is not a member of this business.'**
  String get apiErrorBusinessUsersRemoveMemberNotFound;

  /// No description provided for @apiErrorBusinessUsersOwnerCannotLeave.
  ///
  /// In en, this message translates to:
  /// **'The business owner cannot leave the business here. Delete the business from settings if needed.'**
  String get apiErrorBusinessUsersOwnerCannotLeave;

  /// No description provided for @apiErrorBusinessUsersNotAMemberLeave.
  ///
  /// In en, this message translates to:
  /// **'You are not a member of this business.'**
  String get apiErrorBusinessUsersNotAMemberLeave;

  /// No description provided for @apiErrorBusinessUsersLeaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not leave the business. Please try again.'**
  String get apiErrorBusinessUsersLeaveFailed;

  /// No description provided for @apiErrorNoFiscalYearForDate.
  ///
  /// In en, this message translates to:
  /// **'No fiscal year covers this date.'**
  String get apiErrorNoFiscalYearForDate;

  /// No description provided for @apiErrorFiscalYearLockedForPosting.
  ///
  /// In en, this message translates to:
  /// **'This fiscal year is closed; posting is not allowed.'**
  String get apiErrorFiscalYearLockedForPosting;

  /// No description provided for @apiErrorDocumentCodeRace.
  ///
  /// In en, this message translates to:
  /// **'Document number conflict. Please try again.'**
  String get apiErrorDocumentCodeRace;

  /// No description provided for @byteUnitB.
  ///
  /// In en, this message translates to:
  /// **'B'**
  String get byteUnitB;

  /// No description provided for @byteUnitKB.
  ///
  /// In en, this message translates to:
  /// **'KB'**
  String get byteUnitKB;

  /// No description provided for @byteUnitMB.
  ///
  /// In en, this message translates to:
  /// **'MB'**
  String get byteUnitMB;

  /// No description provided for @byteUnitGB.
  ///
  /// In en, this message translates to:
  /// **'GB'**
  String get byteUnitGB;

  /// No description provided for @byteUnitTB.
  ///
  /// In en, this message translates to:
  /// **'TB'**
  String get byteUnitTB;

  /// No description provided for @backupCompleted.
  ///
  /// In en, this message translates to:
  /// **'Backup completed'**
  String get backupCompleted;

  /// No description provided for @restoreCompleted.
  ///
  /// In en, this message translates to:
  /// **'Restore completed'**
  String get restoreCompleted;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed'**
  String get backupFailed;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed'**
  String get restoreFailed;

  /// No description provided for @jobStartingBackup.
  ///
  /// In en, this message translates to:
  /// **'Starting backup'**
  String get jobStartingBackup;

  /// No description provided for @jobCollectingData.
  ///
  /// In en, this message translates to:
  /// **'Collecting data'**
  String get jobCollectingData;

  /// No description provided for @jobPackagingArchive.
  ///
  /// In en, this message translates to:
  /// **'Packaging archive'**
  String get jobPackagingArchive;

  /// No description provided for @jobSavingFile.
  ///
  /// In en, this message translates to:
  /// **'Saving file'**
  String get jobSavingFile;

  /// No description provided for @jobFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing'**
  String get jobFinalizing;

  /// No description provided for @jobUploadingFile.
  ///
  /// In en, this message translates to:
  /// **'Uploading file'**
  String get jobUploadingFile;

  /// No description provided for @jobStartingRestore.
  ///
  /// In en, this message translates to:
  /// **'Starting restore'**
  String get jobStartingRestore;

  /// No description provided for @jobLoadingBackup.
  ///
  /// In en, this message translates to:
  /// **'Loading backup'**
  String get jobLoadingBackup;

  /// No description provided for @jobCreatingNewBusiness.
  ///
  /// In en, this message translates to:
  /// **'Creating new business'**
  String get jobCreatingNewBusiness;

  /// No description provided for @jobNewBusinessCreated.
  ///
  /// In en, this message translates to:
  /// **'New business created'**
  String get jobNewBusinessCreated;

  /// No description provided for @jobCleaningCurrentData.
  ///
  /// In en, this message translates to:
  /// **'Cleaning current data'**
  String get jobCleaningCurrentData;

  /// No description provided for @jobPreparingToRestoreData.
  ///
  /// In en, this message translates to:
  /// **'Preparing to restore data'**
  String get jobPreparingToRestoreData;

  /// No description provided for @jobUpdatingBusinessInfo.
  ///
  /// In en, this message translates to:
  /// **'Updating business info'**
  String get jobUpdatingBusinessInfo;

  /// No description provided for @jobPreparingBusinessData.
  ///
  /// In en, this message translates to:
  /// **'Preparing business data'**
  String get jobPreparingBusinessData;

  /// No description provided for @jobRestoringData.
  ///
  /// In en, this message translates to:
  /// **'Restoring data'**
  String get jobRestoringData;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @set.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get set;

  /// No description provided for @execute.
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get execute;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @businessSettingsDialogContent.
  ///
  /// In en, this message translates to:
  /// **'In this section you can manage business information, address, contact numbers and other details.'**
  String get businessSettingsDialogContent;

  /// No description provided for @usersAndPermissionsDialogContent.
  ///
  /// In en, this message translates to:
  /// **'In this section you can add new users, set permissions and manage roles.'**
  String get usersAndPermissionsDialogContent;

  /// No description provided for @printDocumentsDialogContent.
  ///
  /// In en, this message translates to:
  /// **'In this section you can configure print templates, letterheads and printer settings.'**
  String get printDocumentsDialogContent;

  /// No description provided for @dataBackupDialogContent.
  ///
  /// In en, this message translates to:
  /// **'In this section you can create a backup of all business data.'**
  String get dataBackupDialogContent;

  /// No description provided for @dataRestoreDialogContent.
  ///
  /// In en, this message translates to:
  /// **'In this section you can restore data from a previous backup.'**
  String get dataRestoreDialogContent;

  /// No description provided for @systemLogsDialogContent.
  ///
  /// In en, this message translates to:
  /// **'In this section you can view system reports, errors and user activities.'**
  String get systemLogsDialogContent;

  /// No description provided for @accountManagement.
  ///
  /// In en, this message translates to:
  /// **'Account Management'**
  String get accountManagement;

  /// No description provided for @persons.
  ///
  /// In en, this message translates to:
  /// **'Persons'**
  String get persons;

  /// No description provided for @person.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get person;

  /// No description provided for @personsList.
  ///
  /// In en, this message translates to:
  /// **'Persons List'**
  String get personsList;

  /// No description provided for @personGroup.
  ///
  /// In en, this message translates to:
  /// **'Person group'**
  String get personGroup;

  /// No description provided for @personGroupNone.
  ///
  /// In en, this message translates to:
  /// **'No group'**
  String get personGroupNone;

  /// No description provided for @personGroupsManage.
  ///
  /// In en, this message translates to:
  /// **'Manage person groups'**
  String get personGroupsManage;

  /// No description provided for @personGroupColumn.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get personGroupColumn;

  /// No description provided for @editPerson.
  ///
  /// In en, this message translates to:
  /// **'Edit Person'**
  String get editPerson;

  /// No description provided for @personDetails.
  ///
  /// In en, this message translates to:
  /// **'Person Details'**
  String get personDetails;

  /// No description provided for @deletePerson.
  ///
  /// In en, this message translates to:
  /// **'Delete Person'**
  String get deletePerson;

  /// No description provided for @personAliasName.
  ///
  /// In en, this message translates to:
  /// **'Alias Name'**
  String get personAliasName;

  /// No description provided for @personFirstName.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get personFirstName;

  /// No description provided for @personLastName.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get personLastName;

  /// No description provided for @personType.
  ///
  /// In en, this message translates to:
  /// **'Person Type'**
  String get personType;

  /// No description provided for @personCompanyName.
  ///
  /// In en, this message translates to:
  /// **'Company Name'**
  String get personCompanyName;

  /// No description provided for @personNamePrefix.
  ///
  /// In en, this message translates to:
  /// **'Name prefix'**
  String get personNamePrefix;

  /// No description provided for @personNamePrefixNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get personNamePrefixNone;

  /// No description provided for @personLegalEntityType.
  ///
  /// In en, this message translates to:
  /// **'Legal entity type'**
  String get personLegalEntityType;

  /// No description provided for @personLegalEntityNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural person'**
  String get personLegalEntityNatural;

  /// No description provided for @personLegalEntityLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal entity'**
  String get personLegalEntityLegal;

  /// No description provided for @personPaymentId.
  ///
  /// In en, this message translates to:
  /// **'Payment ID'**
  String get personPaymentId;

  /// No description provided for @personNationalId.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get personNationalId;

  /// No description provided for @personRegistrationNumber.
  ///
  /// In en, this message translates to:
  /// **'Registration Number'**
  String get personRegistrationNumber;

  /// No description provided for @personEconomicId.
  ///
  /// In en, this message translates to:
  /// **'Economic ID'**
  String get personEconomicId;

  /// No description provided for @personCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get personCountry;

  /// No description provided for @personProvince.
  ///
  /// In en, this message translates to:
  /// **'Province'**
  String get personProvince;

  /// No description provided for @personCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get personCity;

  /// No description provided for @personAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get personAddress;

  /// No description provided for @personPostalCode.
  ///
  /// In en, this message translates to:
  /// **'Postal Code'**
  String get personPostalCode;

  /// No description provided for @personPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get personPhone;

  /// No description provided for @personMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get personMobile;

  /// No description provided for @personFax.
  ///
  /// In en, this message translates to:
  /// **'Fax'**
  String get personFax;

  /// No description provided for @personEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get personEmail;

  /// No description provided for @personWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get personWebsite;

  /// No description provided for @personSocialNetworks.
  ///
  /// In en, this message translates to:
  /// **'Messengers and social networks'**
  String get personSocialNetworks;

  /// No description provided for @personSocialPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get personSocialPlatform;

  /// No description provided for @personSocialValue.
  ///
  /// In en, this message translates to:
  /// **'Username, link or number'**
  String get personSocialValue;

  /// No description provided for @personSocialCustomName.
  ///
  /// In en, this message translates to:
  /// **'Custom platform name (for Other)'**
  String get personSocialCustomName;

  /// No description provided for @addPersonSocialRow.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get addPersonSocialRow;

  /// No description provided for @noPersonSocialRows.
  ///
  /// In en, this message translates to:
  /// **'No messenger or social entry yet.'**
  String get noPersonSocialRows;

  /// No description provided for @personBankAccounts.
  ///
  /// In en, this message translates to:
  /// **'Bank Accounts'**
  String get personBankAccounts;

  /// No description provided for @editBankAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit Bank Account'**
  String get editBankAccount;

  /// No description provided for @deleteBankAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Bank Account'**
  String get deleteBankAccount;

  /// No description provided for @bankName.
  ///
  /// In en, this message translates to:
  /// **'Bank Name'**
  String get bankName;

  /// No description provided for @accountNumber.
  ///
  /// In en, this message translates to:
  /// **'Account Number'**
  String get accountNumber;

  /// No description provided for @cardNumber.
  ///
  /// In en, this message translates to:
  /// **'Card Number'**
  String get cardNumber;

  /// No description provided for @shebaNumber.
  ///
  /// In en, this message translates to:
  /// **'Sheba Number'**
  String get shebaNumber;

  /// No description provided for @personTypeCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get personTypeCustomer;

  /// No description provided for @personTypeMarketer.
  ///
  /// In en, this message translates to:
  /// **'Marketer'**
  String get personTypeMarketer;

  /// No description provided for @personTypeEmployee.
  ///
  /// In en, this message translates to:
  /// **'Employee'**
  String get personTypeEmployee;

  /// No description provided for @personTypeSupplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get personTypeSupplier;

  /// No description provided for @personTypePartner.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get personTypePartner;

  /// No description provided for @personTypeSeller.
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get personTypeSeller;

  /// No description provided for @personTypeShareholder.
  ///
  /// In en, this message translates to:
  /// **'Shareholder'**
  String get personTypeShareholder;

  /// No description provided for @personCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Person created successfully'**
  String get personCreatedSuccessfully;

  /// No description provided for @personUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Person updated successfully'**
  String get personUpdatedSuccessfully;

  /// No description provided for @personDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Person deleted successfully'**
  String get personDeletedSuccessfully;

  /// No description provided for @personNotFound.
  ///
  /// In en, this message translates to:
  /// **'Person not found'**
  String get personNotFound;

  /// No description provided for @personAliasNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Alias name is required'**
  String get personAliasNameRequired;

  /// No description provided for @personAliasPickFromNamesHint.
  ///
  /// In en, this message translates to:
  /// **'Fill alias from name fields…'**
  String get personAliasPickFromNamesHint;

  /// No description provided for @personTypeRequired.
  ///
  /// In en, this message translates to:
  /// **'Person type is required'**
  String get personTypeRequired;

  /// No description provided for @bankAccountAddedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Bank account added successfully'**
  String get bankAccountAddedSuccessfully;

  /// No description provided for @bankAccountUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Bank account updated successfully'**
  String get bankAccountUpdatedSuccessfully;

  /// No description provided for @bankAccountDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Bank account deleted successfully'**
  String get bankAccountDeletedSuccessfully;

  /// No description provided for @bankNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Bank name is required'**
  String get bankNameRequired;

  /// No description provided for @personBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic Information'**
  String get personBasicInfo;

  /// No description provided for @personEconomicInfo.
  ///
  /// In en, this message translates to:
  /// **'Economic Information'**
  String get personEconomicInfo;

  /// No description provided for @personContactInfo.
  ///
  /// In en, this message translates to:
  /// **'Contact Information'**
  String get personContactInfo;

  /// No description provided for @personBankInfo.
  ///
  /// In en, this message translates to:
  /// **'Bank Accounts'**
  String get personBankInfo;

  /// No description provided for @personSummary.
  ///
  /// In en, this message translates to:
  /// **'Persons Summary'**
  String get personSummary;

  /// No description provided for @totalPersons.
  ///
  /// In en, this message translates to:
  /// **'Total Persons'**
  String get totalPersons;

  /// No description provided for @activePersons.
  ///
  /// In en, this message translates to:
  /// **'Active Persons'**
  String get activePersons;

  /// No description provided for @inactivePersons.
  ///
  /// In en, this message translates to:
  /// **'Inactive Persons'**
  String get inactivePersons;

  /// No description provided for @personsByType.
  ///
  /// In en, this message translates to:
  /// **'Persons by Type'**
  String get personsByType;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @collect.
  ///
  /// In en, this message translates to:
  /// **'Collect'**
  String get collect;

  /// No description provided for @transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transfer;

  /// No description provided for @charge.
  ///
  /// In en, this message translates to:
  /// **'Charge'**
  String get charge;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @userPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'User Permissions'**
  String get userPermissionsTitle;

  /// No description provided for @dialogClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get dialogClose;

  /// No description provided for @buy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get buy;

  /// No description provided for @templates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templates;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @business.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get business;

  /// No description provided for @shareCount.
  ///
  /// In en, this message translates to:
  /// **'Share Count'**
  String get shareCount;

  /// No description provided for @commissionSalePercentLabel.
  ///
  /// In en, this message translates to:
  /// **'Commission Sale Percent'**
  String get commissionSalePercentLabel;

  /// No description provided for @commissionSalesReturnPercentLabel.
  ///
  /// In en, this message translates to:
  /// **'Commission Sales Return Percent'**
  String get commissionSalesReturnPercentLabel;

  /// No description provided for @commissionSalesAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Commission Sales Amount'**
  String get commissionSalesAmountLabel;

  /// No description provided for @commissionSalesReturnAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Commission Sales Return Amount'**
  String get commissionSalesReturnAmountLabel;

  /// No description provided for @importPersonsFromExcel.
  ///
  /// In en, this message translates to:
  /// **'Import Persons from Excel'**
  String get importPersonsFromExcel;

  /// No description provided for @selectedFile.
  ///
  /// In en, this message translates to:
  /// **'Selected file'**
  String get selectedFile;

  /// No description provided for @noFileSelected.
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noFileSelected;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// No description provided for @matchBy.
  ///
  /// In en, this message translates to:
  /// **'Match by'**
  String get matchBy;

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// No description provided for @conflictPolicy.
  ///
  /// In en, this message translates to:
  /// **'Conflict policy'**
  String get conflictPolicy;

  /// No description provided for @policyInsertOnly.
  ///
  /// In en, this message translates to:
  /// **'Insert-only'**
  String get policyInsertOnly;

  /// No description provided for @policyUpdateExisting.
  ///
  /// In en, this message translates to:
  /// **'Update existing'**
  String get policyUpdateExisting;

  /// No description provided for @policyUpsert.
  ///
  /// In en, this message translates to:
  /// **'Upsert'**
  String get policyUpsert;

  /// No description provided for @dryRun.
  ///
  /// In en, this message translates to:
  /// **'Dry run'**
  String get dryRun;

  /// No description provided for @dryRunValidateOnly.
  ///
  /// In en, this message translates to:
  /// **'Dry run (validate only)'**
  String get dryRunValidateOnly;

  /// No description provided for @downloadTemplate.
  ///
  /// In en, this message translates to:
  /// **'Download template'**
  String get downloadTemplate;

  /// No description provided for @reviewDryRun.
  ///
  /// In en, this message translates to:
  /// **'Review (Dry run)'**
  String get reviewDryRun;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @importReal.
  ///
  /// In en, this message translates to:
  /// **'Import (real)'**
  String get importReal;

  /// No description provided for @templateDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Template downloaded'**
  String get templateDownloaded;

  /// No description provided for @pickFileError.
  ///
  /// In en, this message translates to:
  /// **'Error picking file'**
  String get pickFileError;

  /// No description provided for @templateDownloadError.
  ///
  /// In en, this message translates to:
  /// **'Error downloading template'**
  String get templateDownloadError;

  /// No description provided for @importError.
  ///
  /// In en, this message translates to:
  /// **'Import error'**
  String get importError;

  /// No description provided for @result.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get result;

  /// No description provided for @valid.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get valid;

  /// No description provided for @invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid'**
  String get invalid;

  /// No description provided for @inserted.
  ///
  /// In en, this message translates to:
  /// **'Inserted'**
  String get inserted;

  /// No description provided for @updated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get updated;

  /// No description provided for @skipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get skipped;

  /// No description provided for @importSkippedApply.
  ///
  /// In en, this message translates to:
  /// **'Failed on save'**
  String get importSkippedApply;

  /// No description provided for @importPreviewInsert.
  ///
  /// In en, this message translates to:
  /// **'Would insert (preview)'**
  String get importPreviewInsert;

  /// No description provided for @importPreviewUpdate.
  ///
  /// In en, this message translates to:
  /// **'Would update (preview)'**
  String get importPreviewUpdate;

  /// No description provided for @importPreviewSkipConflict.
  ///
  /// In en, this message translates to:
  /// **'Would skip existing (preview)'**
  String get importPreviewSkipConflict;

  /// No description provided for @importWarningsTitle.
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get importWarningsTitle;

  /// No description provided for @personImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Import completed'**
  String get personImportSuccess;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @row.
  ///
  /// In en, this message translates to:
  /// **'Row'**
  String get row;

  /// No description provided for @onlyForMarketerSeller.
  ///
  /// In en, this message translates to:
  /// **'This section is shown only for marketer/seller'**
  String get onlyForMarketerSeller;

  /// No description provided for @percentFromSales.
  ///
  /// In en, this message translates to:
  /// **'Percent from sales'**
  String get percentFromSales;

  /// No description provided for @percentFromSalesReturn.
  ///
  /// In en, this message translates to:
  /// **'Percent from sales return'**
  String get percentFromSalesReturn;

  /// No description provided for @salesAmount.
  ///
  /// In en, this message translates to:
  /// **'Sales amount'**
  String get salesAmount;

  /// No description provided for @salesReturnAmount.
  ///
  /// In en, this message translates to:
  /// **'Sales return amount'**
  String get salesReturnAmount;

  /// No description provided for @mustBeBetweenZeroAndHundred.
  ///
  /// In en, this message translates to:
  /// **'Must be between 0 and 100'**
  String get mustBeBetweenZeroAndHundred;

  /// No description provided for @mustBePositiveNumber.
  ///
  /// In en, this message translates to:
  /// **'Must be a positive number'**
  String get mustBePositiveNumber;

  /// No description provided for @personCodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Person code (optional)'**
  String get personCodeOptional;

  /// No description provided for @uniqueCodeNumeric.
  ///
  /// In en, this message translates to:
  /// **'Unique code (numeric)'**
  String get uniqueCodeNumeric;

  /// No description provided for @automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automatic;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @personCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Person code is required'**
  String get personCodeRequired;

  /// No description provided for @codeMustBeNumeric.
  ///
  /// In en, this message translates to:
  /// **'Code must be numeric'**
  String get codeMustBeNumeric;

  /// No description provided for @integerNoDecimal.
  ///
  /// In en, this message translates to:
  /// **'Integer number (no decimals)'**
  String get integerNoDecimal;

  /// No description provided for @shareholderShareCountRequired.
  ///
  /// In en, this message translates to:
  /// **'For shareholder, share count is required'**
  String get shareholderShareCountRequired;

  /// No description provided for @noBankAccountsAdded.
  ///
  /// In en, this message translates to:
  /// **'No bank accounts added'**
  String get noBankAccountsAdded;

  /// No description provided for @commissionExcludeDiscounts.
  ///
  /// In en, this message translates to:
  /// **'Exclude discounts from commission'**
  String get commissionExcludeDiscounts;

  /// No description provided for @commissionExcludeAdditionsDeductions.
  ///
  /// In en, this message translates to:
  /// **'Exclude additions/deductions from commission'**
  String get commissionExcludeAdditionsDeductions;

  /// No description provided for @commissionPostInInvoiceDocument.
  ///
  /// In en, this message translates to:
  /// **'Post commission in invoice accounting document'**
  String get commissionPostInInvoiceDocument;

  /// No description provided for @manageCategories.
  ///
  /// In en, this message translates to:
  /// **'Manage Categories'**
  String get manageCategories;

  /// No description provided for @categoriesDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Categories'**
  String get categoriesDialogTitle;

  /// No description provided for @addRootCategory.
  ///
  /// In en, this message translates to:
  /// **'Add Root'**
  String get addRootCategory;

  /// No description provided for @addChildCategory.
  ///
  /// In en, this message translates to:
  /// **'Add Child'**
  String get addChildCategory;

  /// No description provided for @renameCategory.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameCategory;

  /// No description provided for @deleteCategory.
  ///
  /// In en, this message translates to:
  /// **'Delete Category'**
  String get deleteCategory;

  /// No description provided for @deleteCategoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this category?'**
  String get deleteCategoryConfirm;

  /// No description provided for @categoryNameFa.
  ///
  /// In en, this message translates to:
  /// **'Name (Persian)'**
  String get categoryNameFa;

  /// No description provided for @categoryNameEn.
  ///
  /// In en, this message translates to:
  /// **'Name (English)'**
  String get categoryNameEn;

  /// No description provided for @categoryName.
  ///
  /// In en, this message translates to:
  /// **'Category Name'**
  String get categoryName;

  /// No description provided for @categoryNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Category name is required'**
  String get categoryNameRequired;

  /// No description provided for @categoryNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter category name'**
  String get categoryNameHint;

  /// No description provided for @categoryType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get categoryType;

  /// No description provided for @productType.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get productType;

  /// No description provided for @serviceType.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get serviceType;

  /// No description provided for @loadingCategories.
  ///
  /// In en, this message translates to:
  /// **'Loading categories...'**
  String get loadingCategories;

  /// No description provided for @createCategory.
  ///
  /// In en, this message translates to:
  /// **'Create Category'**
  String get createCategory;

  /// No description provided for @updateCategory.
  ///
  /// In en, this message translates to:
  /// **'Update Category'**
  String get updateCategory;

  /// No description provided for @deleteCategorySuccess.
  ///
  /// In en, this message translates to:
  /// **'Category deleted'**
  String get deleteCategorySuccess;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get operationFailed;

  /// No description provided for @productGeneralInfo.
  ///
  /// In en, this message translates to:
  /// **'General Information'**
  String get productGeneralInfo;

  /// No description provided for @pricingAndInventory.
  ///
  /// In en, this message translates to:
  /// **'Pricing & Inventory'**
  String get pricingAndInventory;

  /// No description provided for @tax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get tax;

  /// No description provided for @productStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get productStock;

  /// No description provided for @productStockInWarehouses.
  ///
  /// In en, this message translates to:
  /// **'Product Stock in Warehouses'**
  String get productStockInWarehouses;

  /// No description provided for @productCommercialPricing.
  ///
  /// In en, this message translates to:
  /// **'Commercial & Pricing'**
  String get productCommercialPricing;

  /// No description provided for @productCommercialPricingNoAccessHint.
  ///
  /// In en, this message translates to:
  /// **'To view this tab, invoice read permission is required. Ask your admin to grant invoices.view.'**
  String get productCommercialPricingNoAccessHint;

  /// No description provided for @productCommercialInsightsNotEligibleTitle.
  ///
  /// In en, this message translates to:
  /// **'This report is not active for this product'**
  String get productCommercialInsightsNotEligibleTitle;

  /// No description provided for @productCommercialInsightsNotEligibleBody.
  ///
  /// In en, this message translates to:
  /// **'This summary is not available for this product or current business configuration.'**
  String get productCommercialInsightsNotEligibleBody;

  /// No description provided for @productCommercialInsightsChecklistTitle.
  ///
  /// In en, this message translates to:
  /// **'Checklist:'**
  String get productCommercialInsightsChecklistTitle;

  /// No description provided for @productCommercialInsightsChecklistInventoryTracked.
  ///
  /// In en, this message translates to:
  /// **'Ensure inventory tracking is enabled for this product.'**
  String get productCommercialInsightsChecklistInventoryTracked;

  /// No description provided for @productCommercialInsightsChecklistConfirmedInvoice.
  ///
  /// In en, this message translates to:
  /// **'Ensure at least one confirmed purchase/sales invoice exists for this product.'**
  String get productCommercialInsightsChecklistConfirmedInvoice;

  /// No description provided for @productCommercialInsightsChecklistPostedWarehouseDoc.
  ///
  /// In en, this message translates to:
  /// **'Ensure related invoices have a posted warehouse document with source type invoice.'**
  String get productCommercialInsightsChecklistPostedWarehouseDoc;

  /// No description provided for @productCommercialInsightsReload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get productCommercialInsightsReload;

  /// No description provided for @productCommercialInsightsResetTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get productCommercialInsightsResetTooltip;

  /// No description provided for @productCommercialInsightsNoData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get productCommercialInsightsNoData;

  /// No description provided for @productCommercialInsightsDocumentDate.
  ///
  /// In en, this message translates to:
  /// **'Document date'**
  String get productCommercialInsightsDocumentDate;

  /// No description provided for @productCommercialInsightsParty.
  ///
  /// In en, this message translates to:
  /// **'Party'**
  String get productCommercialInsightsParty;

  /// No description provided for @productCommercialInsightsDocumentCode.
  ///
  /// In en, this message translates to:
  /// **'Document code'**
  String get productCommercialInsightsDocumentCode;

  /// No description provided for @productCommercialInsightsQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get productCommercialInsightsQuantity;

  /// No description provided for @productCommercialInsightsUnitPriceBase.
  ///
  /// In en, this message translates to:
  /// **'Unit price in base currency'**
  String get productCommercialInsightsUnitPriceBase;

  /// No description provided for @productCommercialInsightsFxRateToBase.
  ///
  /// In en, this message translates to:
  /// **'Document to base FX rate'**
  String get productCommercialInsightsFxRateToBase;

  /// No description provided for @productCommercialInsightsChartDataMissing.
  ///
  /// In en, this message translates to:
  /// **'Chart data is not available.'**
  String get productCommercialInsightsChartDataMissing;

  /// No description provided for @productCommercialInsightsChartNoPoints.
  ///
  /// In en, this message translates to:
  /// **'No chart points for the selected range.'**
  String get productCommercialInsightsChartNoPoints;

  /// No description provided for @productCommercialInsightsLanePurchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get productCommercialInsightsLanePurchase;

  /// No description provided for @productCommercialInsightsLaneSale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get productCommercialInsightsLaneSale;

  /// No description provided for @productCommercialInsightsLegendPurchaseAvg.
  ///
  /// In en, this message translates to:
  /// **'Weighted average purchase (base)'**
  String get productCommercialInsightsLegendPurchaseAvg;

  /// No description provided for @productCommercialInsightsLegendSaleAvg.
  ///
  /// In en, this message translates to:
  /// **'Weighted average sale (base)'**
  String get productCommercialInsightsLegendSaleAvg;

  /// No description provided for @productCommercialInsightsAvgUnitBaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Average unit in base'**
  String get productCommercialInsightsAvgUnitBaseLabel;

  /// No description provided for @productCommercialInsightsTotalQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Total quantity'**
  String get productCommercialInsightsTotalQuantityLabel;

  /// No description provided for @productCommercialInsightsBucketDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get productCommercialInsightsBucketDay;

  /// No description provided for @productCommercialInsightsBucketWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get productCommercialInsightsBucketWeek;

  /// No description provided for @productCommercialInsightsBucketMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get productCommercialInsightsBucketMonth;

  /// No description provided for @productCommercialInsightsPreset30Days.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get productCommercialInsightsPreset30Days;

  /// No description provided for @productCommercialInsightsPreset90Days.
  ///
  /// In en, this message translates to:
  /// **'90 days'**
  String get productCommercialInsightsPreset90Days;

  /// No description provided for @productCommercialInsightsPreset6Months.
  ///
  /// In en, this message translates to:
  /// **'6 months'**
  String get productCommercialInsightsPreset6Months;

  /// No description provided for @productCommercialInsightsPreset1Year.
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get productCommercialInsightsPreset1Year;

  /// No description provided for @productCommercialInsightsPresetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get productCommercialInsightsPresetCustom;

  /// No description provided for @productCommercialInsightsFromDate.
  ///
  /// In en, this message translates to:
  /// **'From date'**
  String get productCommercialInsightsFromDate;

  /// No description provided for @productCommercialInsightsToDate.
  ///
  /// In en, this message translates to:
  /// **'To date'**
  String get productCommercialInsightsToDate;

  /// No description provided for @productCommercialInsightsLastPurchase.
  ///
  /// In en, this message translates to:
  /// **'Last purchase'**
  String get productCommercialInsightsLastPurchase;

  /// No description provided for @productCommercialInsightsLastSale.
  ///
  /// In en, this message translates to:
  /// **'Last sale'**
  String get productCommercialInsightsLastSale;

  /// No description provided for @productCommercialInsightsTotalsInRange.
  ///
  /// In en, this message translates to:
  /// **'Totals in range'**
  String get productCommercialInsightsTotalsInRange;

  /// No description provided for @productCommercialInsightsPurchaseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Purchase quantity'**
  String get productCommercialInsightsPurchaseQuantity;

  /// No description provided for @productCommercialInsightsSaleQuantity.
  ///
  /// In en, this message translates to:
  /// **'Sale quantity'**
  String get productCommercialInsightsSaleQuantity;

  /// No description provided for @productCommercialInsightsPurchaseLinesCount.
  ///
  /// In en, this message translates to:
  /// **'Purchase lines count'**
  String get productCommercialInsightsPurchaseLinesCount;

  /// No description provided for @productCommercialInsightsSaleLinesCount.
  ///
  /// In en, this message translates to:
  /// **'Sale lines count'**
  String get productCommercialInsightsSaleLinesCount;

  /// No description provided for @productCommercialInsightsTrendTitle.
  ///
  /// In en, this message translates to:
  /// **'Weighted average unit price trend (base currency)'**
  String get productCommercialInsightsTrendTitle;

  /// No description provided for @productCommercialInsightsTopSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Top suppliers in range'**
  String get productCommercialInsightsTopSuppliers;

  /// No description provided for @productCommercialInsightsTopBuyers.
  ///
  /// In en, this message translates to:
  /// **'Top buyers in range'**
  String get productCommercialInsightsTopBuyers;

  /// No description provided for @productCommercialInsightsRecentEventsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent events (invoice lines)'**
  String get productCommercialInsightsRecentEventsTitle;

  /// No description provided for @productCommercialInsightsUnitShortLabel.
  ///
  /// In en, this message translates to:
  /// **'unit'**
  String get productCommercialInsightsUnitShortLabel;

  /// No description provided for @warehouseCode.
  ///
  /// In en, this message translates to:
  /// **'Warehouse Code'**
  String get warehouseCode;

  /// No description provided for @warehouseName.
  ///
  /// In en, this message translates to:
  /// **'Warehouse Name'**
  String get warehouseName;

  /// No description provided for @stockQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get stockQuantity;

  /// No description provided for @totalStock.
  ///
  /// In en, this message translates to:
  /// **'Total Stock'**
  String get totalStock;

  /// No description provided for @noStockRecorded.
  ///
  /// In en, this message translates to:
  /// **'No stock recorded'**
  String get noStockRecorded;

  /// No description provided for @inventoryNotTracked.
  ///
  /// In en, this message translates to:
  /// **'This product does not track inventory'**
  String get inventoryNotTracked;

  /// No description provided for @stockReportDate.
  ///
  /// In en, this message translates to:
  /// **'Report Date'**
  String get stockReportDate;

  /// No description provided for @showZeroStock.
  ///
  /// In en, this message translates to:
  /// **'Show Zero Stock'**
  String get showZeroStock;

  /// No description provided for @refreshStock.
  ///
  /// In en, this message translates to:
  /// **'Refresh Stock'**
  String get refreshStock;

  /// No description provided for @inventoryControl.
  ///
  /// In en, this message translates to:
  /// **'Inventory control'**
  String get inventoryControl;

  /// No description provided for @inventoryControlHelpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'On: stock is tracked and this product is included on invoice-linked warehouse documents. Off: the product is skipped when warehouse drafts are generated from invoices.'**
  String get inventoryControlHelpSubtitle;

  /// No description provided for @inventoryControlHelpDetail.
  ///
  /// In en, this message translates to:
  /// **'Turning this off does not mean “allow posting issues with negative stock.” To sometimes post outgoing warehouse documents despite insufficient stock, use the shortage / negative-stock policy in business settings—that is separate from this switch.'**
  String get inventoryControlHelpDetail;

  /// No description provided for @inventoryUniqueModeRequiresTrack.
  ///
  /// In en, this message translates to:
  /// **'To use unique inventory mode, enable “inventory control” first'**
  String get inventoryUniqueModeRequiresTrack;

  /// No description provided for @reorderPoint.
  ///
  /// In en, this message translates to:
  /// **'Reorder point'**
  String get reorderPoint;

  /// No description provided for @reorderPointRepeat.
  ///
  /// In en, this message translates to:
  /// **'Reorder point'**
  String get reorderPointRepeat;

  /// No description provided for @minOrderQty.
  ///
  /// In en, this message translates to:
  /// **'Minimum order quantity'**
  String get minOrderQty;

  /// No description provided for @leadTimeDays.
  ///
  /// In en, this message translates to:
  /// **'Lead time (days)'**
  String get leadTimeDays;

  /// No description provided for @pricing.
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get pricing;

  /// No description provided for @productName.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get productName;

  /// No description provided for @barcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get barcode;

  /// No description provided for @productGeneralBarcodes.
  ///
  /// In en, this message translates to:
  /// **'General barcodes'**
  String get productGeneralBarcodes;

  /// No description provided for @productGeneralBarcodesHint.
  ///
  /// In en, this message translates to:
  /// **'Enter multiple codes separated by commas (English or Persian comma). Used for quick product lookup on invoices and optional PDF labels.'**
  String get productGeneralBarcodesHint;

  /// No description provided for @printGeneralBarcodeLabels.
  ///
  /// In en, this message translates to:
  /// **'Print general barcode labels (PDF)'**
  String get printGeneralBarcodeLabels;

  /// No description provided for @generalBarcodeLabelsTitle.
  ///
  /// In en, this message translates to:
  /// **'General barcode labels'**
  String get generalBarcodeLabelsTitle;

  /// No description provided for @generalBarcodeLabelsNoneSelected.
  ///
  /// In en, this message translates to:
  /// **'No general barcodes found on selected products.'**
  String get generalBarcodeLabelsNoneSelected;

  /// No description provided for @labelPdfDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Print labels'**
  String get labelPdfDialogTitle;

  /// No description provided for @labelPdfContentSection.
  ///
  /// In en, this message translates to:
  /// **'Label content'**
  String get labelPdfContentSection;

  /// No description provided for @labelPdfLinearBarcode.
  ///
  /// In en, this message translates to:
  /// **'Linear barcode'**
  String get labelPdfLinearBarcode;

  /// No description provided for @labelPdfQrCode.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get labelPdfQrCode;

  /// No description provided for @labelPdfBarcodeAsText.
  ///
  /// In en, this message translates to:
  /// **'Barcode value as text'**
  String get labelPdfBarcodeAsText;

  /// No description provided for @labelPdfProductName.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get labelPdfProductName;

  /// No description provided for @labelPdfSerialLine.
  ///
  /// In en, this message translates to:
  /// **'Serial line'**
  String get labelPdfSerialLine;

  /// No description provided for @labelPdfPaperLayoutSection.
  ///
  /// In en, this message translates to:
  /// **'Paper & layout'**
  String get labelPdfPaperLayoutSection;

  /// No description provided for @labelPdfPaperSize.
  ///
  /// In en, this message translates to:
  /// **'Paper size'**
  String get labelPdfPaperSize;

  /// No description provided for @labelPdfLandscape.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get labelPdfLandscape;

  /// No description provided for @labelPdfColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get labelPdfColumns;

  /// No description provided for @labelPdfPageMarginPts.
  ///
  /// In en, this message translates to:
  /// **'Page margin (pt)'**
  String get labelPdfPageMarginPts;

  /// No description provided for @labelPdfPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get labelPdfPreview;

  /// No description provided for @labelPdfSave.
  ///
  /// In en, this message translates to:
  /// **'Save PDF'**
  String get labelPdfSave;

  /// No description provided for @labelPdfShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get labelPdfShare;

  /// No description provided for @labelPdfClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get labelPdfClose;

  /// No description provided for @labelPdfSaved.
  ///
  /// In en, this message translates to:
  /// **'PDF file saved'**
  String get labelPdfSaved;

  /// No description provided for @labelPdfSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save PDF'**
  String get labelPdfSaveFailed;

  /// No description provided for @labelPdfShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Share failed'**
  String get labelPdfShareFailed;

  /// No description provided for @labelPdfBuildError.
  ///
  /// In en, this message translates to:
  /// **'Could not build PDF'**
  String get labelPdfBuildError;

  /// No description provided for @labelPdfPreviewHintDesktop.
  ///
  /// In en, this message translates to:
  /// **'Zoom and scroll using the preview toolbar'**
  String get labelPdfPreviewHintDesktop;

  /// No description provided for @labelPdfPreviewHintWeb.
  ///
  /// In en, this message translates to:
  /// **'On web: preview uses your browser PDF viewer (zoom via menu or Ctrl±)'**
  String get labelPdfPreviewHintWeb;

  /// No description provided for @labelPdfOrientationLandscape.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get labelPdfOrientationLandscape;

  /// No description provided for @labelPdfOrientationPortrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get labelPdfOrientationPortrait;

  /// No description provided for @generalInformation.
  ///
  /// In en, this message translates to:
  /// **'General information'**
  String get generalInformation;

  /// No description provided for @imageNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Image not available'**
  String get imageNotAvailable;

  /// No description provided for @salesPrice.
  ///
  /// In en, this message translates to:
  /// **'Sales price'**
  String get salesPrice;

  /// No description provided for @salesPriceNote.
  ///
  /// In en, this message translates to:
  /// **'Sales price note'**
  String get salesPriceNote;

  /// No description provided for @purchasePrice.
  ///
  /// In en, this message translates to:
  /// **'Purchase price'**
  String get purchasePrice;

  /// No description provided for @purchasePriceNote.
  ///
  /// In en, this message translates to:
  /// **'Purchase price note'**
  String get purchasePriceNote;

  /// No description provided for @pricesInPriceLists.
  ///
  /// In en, this message translates to:
  /// **'Prices in price lists'**
  String get pricesInPriceLists;

  /// No description provided for @addPrice.
  ///
  /// In en, this message translates to:
  /// **'Add price'**
  String get addPrice;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @noPriceListsTitle.
  ///
  /// In en, this message translates to:
  /// **'No price list'**
  String get noPriceListsTitle;

  /// No description provided for @noPriceListsMessage.
  ///
  /// In en, this message translates to:
  /// **'To add a price, first create a price list.'**
  String get noPriceListsMessage;

  /// No description provided for @noPriceListsHint.
  ///
  /// In en, this message translates to:
  /// **'Use \"Manage price lists\" button in Products page to create one.'**
  String get noPriceListsHint;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @unitsTitle.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get unitsTitle;

  /// No description provided for @mainUnit.
  ///
  /// In en, this message translates to:
  /// **'Main unit'**
  String get mainUnit;

  /// No description provided for @secondaryUnit.
  ///
  /// In en, this message translates to:
  /// **'Secondary unit'**
  String get secondaryUnit;

  /// No description provided for @unitConversionFactor.
  ///
  /// In en, this message translates to:
  /// **'Unit conversion factor'**
  String get unitConversionFactor;

  /// No description provided for @itemType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get itemType;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @productPhysicalDesc.
  ///
  /// In en, this message translates to:
  /// **'Physical products'**
  String get productPhysicalDesc;

  /// No description provided for @serviceDesc.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get serviceDesc;

  /// No description provided for @taxTitle.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get taxTitle;

  /// No description provided for @taxCode.
  ///
  /// In en, this message translates to:
  /// **'Tax code'**
  String get taxCode;

  /// No description provided for @isSalesTaxable.
  ///
  /// In en, this message translates to:
  /// **'Sales taxable'**
  String get isSalesTaxable;

  /// No description provided for @salesTaxRate.
  ///
  /// In en, this message translates to:
  /// **'Sales tax rate (%)'**
  String get salesTaxRate;

  /// No description provided for @isPurchaseTaxable.
  ///
  /// In en, this message translates to:
  /// **'Purchase taxable'**
  String get isPurchaseTaxable;

  /// No description provided for @purchaseTaxRate.
  ///
  /// In en, this message translates to:
  /// **'Purchase tax rate (%)'**
  String get purchaseTaxRate;

  /// No description provided for @taxType.
  ///
  /// In en, this message translates to:
  /// **'Tax type'**
  String get taxType;

  /// No description provided for @taxTypeId.
  ///
  /// In en, this message translates to:
  /// **'Tax type id'**
  String get taxTypeId;

  /// No description provided for @taxUnit.
  ///
  /// In en, this message translates to:
  /// **'Tax unit'**
  String get taxUnit;

  /// No description provided for @taxUnitId.
  ///
  /// In en, this message translates to:
  /// **'Tax unit id'**
  String get taxUnitId;

  /// No description provided for @vatColumn.
  ///
  /// In en, this message translates to:
  /// **'VAT'**
  String get vatColumn;

  /// Formatted VAT percent value
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String taxVatPercent(Object value);

  /// No description provided for @taxVatUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get taxVatUnknown;

  /// No description provided for @bulkPriceUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Bulk price update'**
  String get bulkPriceUpdateTitle;

  /// No description provided for @bulkPriceUpdateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Increase or decrease prices with advanced filters'**
  String get bulkPriceUpdateSubtitle;

  /// No description provided for @bulkPriceUpdateApplyScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply to'**
  String get bulkPriceUpdateApplyScopeTitle;

  /// No description provided for @bulkPriceUpdateScopeBase.
  ///
  /// In en, this message translates to:
  /// **'Base prices only'**
  String get bulkPriceUpdateScopeBase;

  /// No description provided for @bulkPriceUpdateScopePriceLists.
  ///
  /// In en, this message translates to:
  /// **'Price lists only'**
  String get bulkPriceUpdateScopePriceLists;

  /// No description provided for @bulkPriceUpdateScopeBoth.
  ///
  /// In en, this message translates to:
  /// **'Base prices and price lists'**
  String get bulkPriceUpdateScopeBoth;

  /// No description provided for @bulkPriceUpdateStatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Summary stats'**
  String get bulkPriceUpdateStatsTitle;

  /// No description provided for @bulkPriceUpdateListOnlyTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Only sale prices inside price lists will change.'**
  String get bulkPriceUpdateListOnlyTargetHint;

  /// No description provided for @bulkPriceUpdatePriceListsHint.
  ///
  /// In en, this message translates to:
  /// **'If none selected, all price lists (matching currency filter) apply.'**
  String get bulkPriceUpdatePriceListsHint;

  /// No description provided for @bulkPriceUpdatePreviewListChanges.
  ///
  /// In en, this message translates to:
  /// **'Price list'**
  String get bulkPriceUpdatePreviewListChanges;

  /// No description provided for @bulkPriceUpdatePreviewListRowsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String bulkPriceUpdatePreviewListRowsCount(int count);

  /// No description provided for @bulkPriceUpdateSummaryListRows.
  ///
  /// In en, this message translates to:
  /// **'Price list rows'**
  String get bulkPriceUpdateSummaryListRows;

  /// No description provided for @bulkPriceUpdateSummaryListDelta.
  ///
  /// In en, this message translates to:
  /// **'Total price list delta'**
  String get bulkPriceUpdateSummaryListDelta;

  /// No description provided for @bulkProductPricesSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Bulk price sheet'**
  String get bulkProductPricesSheetTitle;

  /// No description provided for @bulkProductPricesSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Edit base prices in a table; each page is saved separately.'**
  String get bulkProductPricesSheetSubtitle;

  /// No description provided for @bulkProductPricesSheetSave.
  ///
  /// In en, this message translates to:
  /// **'Save this page'**
  String get bulkProductPricesSheetSave;

  /// No description provided for @bulkProductPricesSheetNext.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get bulkProductPricesSheetNext;

  /// No description provided for @bulkProductPricesSheetPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get bulkProductPricesSheetPrev;

  /// No description provided for @bulkProductPricesSheetSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get bulkProductPricesSheetSearch;

  /// No description provided for @bulkProductPricesSheetClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get bulkProductPricesSheetClearSearch;

  /// No description provided for @bulkProductPricesSheetNoChanges.
  ///
  /// In en, this message translates to:
  /// **'Nothing to save'**
  String get bulkProductPricesSheetNoChanges;

  /// No description provided for @bulkProductPricesSheetCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get bulkProductPricesSheetCode;

  /// No description provided for @bulkProductPricesSheetName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get bulkProductPricesSheetName;

  /// No description provided for @bulkProductPricesSheetPriceListsForColumns.
  ///
  /// In en, this message translates to:
  /// **'Price list columns'**
  String get bulkProductPricesSheetPriceListsForColumns;

  /// No description provided for @bulkProductPricesSheetSelectListsHint.
  ///
  /// In en, this message translates to:
  /// **'Select one or more price lists to show and edit list prices, then load the page.'**
  String get bulkProductPricesSheetSelectListsHint;

  /// No description provided for @bulkProductPricesSheetExportExcel.
  ///
  /// In en, this message translates to:
  /// **'Download Excel'**
  String get bulkProductPricesSheetExportExcel;

  /// No description provided for @bulkProductPricesSheetImportExcel.
  ///
  /// In en, this message translates to:
  /// **'Upload Excel'**
  String get bulkProductPricesSheetImportExcel;

  /// No description provided for @bulkProductPricesSheetExcelHint.
  ///
  /// In en, this message translates to:
  /// **'All products matching this search are exported. After editing prices, upload the file. Keep the worksheet name «BulkPrices»; pi_* columns are price-item IDs.'**
  String get bulkProductPricesSheetExcelHint;

  /// No description provided for @bulkProductPricesSheetGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Guide & Excel'**
  String get bulkProductPricesSheetGuideTitle;

  /// No description provided for @bulkProductPricesSheetSearchSection.
  ///
  /// In en, this message translates to:
  /// **'Search & price lists'**
  String get bulkProductPricesSheetSearchSection;

  /// No description provided for @bulkProductPricesSheetTableSection.
  ///
  /// In en, this message translates to:
  /// **'Price grid'**
  String get bulkProductPricesSheetTableSection;

  /// No description provided for @bulkProductPricesSheetMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get bulkProductPricesSheetMoreActions;

  /// No description provided for @bulkProductPricesSheetNoRows.
  ///
  /// In en, this message translates to:
  /// **'No products on this page'**
  String get bulkProductPricesSheetNoRows;

  /// No description provided for @bulkProductPricesSheetNoRowsHint.
  ///
  /// In en, this message translates to:
  /// **'Try another search or switch page.'**
  String get bulkProductPricesSheetNoRowsHint;

  /// No description provided for @bulkProductPricesSheetPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get bulkProductPricesSheetPageLabel;

  /// No description provided for @bulkProductPricesSheetPriceListPrices.
  ///
  /// In en, this message translates to:
  /// **'List prices'**
  String get bulkProductPricesSheetPriceListPrices;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @applyChanges.
  ///
  /// In en, this message translates to:
  /// **'Apply changes'**
  String get applyChanges;

  /// No description provided for @changeTypeAndDirection.
  ///
  /// In en, this message translates to:
  /// **'Change type & direction'**
  String get changeTypeAndDirection;

  /// No description provided for @changeTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get changeTarget;

  /// No description provided for @changeAmount.
  ///
  /// In en, this message translates to:
  /// **'Change amount'**
  String get changeAmount;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @previewChanges.
  ///
  /// In en, this message translates to:
  /// **'Preview changes'**
  String get previewChanges;

  /// No description provided for @percentage.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get percentage;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @samplePercent.
  ///
  /// In en, this message translates to:
  /// **'e.g. 10%'**
  String get samplePercent;

  /// No description provided for @sampleAmount.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1,000,000'**
  String get sampleAmount;

  /// No description provided for @increase.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get increase;

  /// No description provided for @decrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get decrease;

  /// No description provided for @both.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get both;

  /// No description provided for @allCurrencies.
  ///
  /// In en, this message translates to:
  /// **'All currencies'**
  String get allCurrencies;

  /// No description provided for @priceList.
  ///
  /// In en, this message translates to:
  /// **'Price list'**
  String get priceList;

  /// No description provided for @allPriceLists.
  ///
  /// In en, this message translates to:
  /// **'All lists'**
  String get allPriceLists;

  /// No description provided for @itemTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Item type'**
  String get itemTypeLabel;

  /// No description provided for @allTypes.
  ///
  /// In en, this message translates to:
  /// **'All types'**
  String get allTypes;

  /// No description provided for @productsWithInventoryOnly.
  ///
  /// In en, this message translates to:
  /// **'Only products with inventory'**
  String get productsWithInventoryOnly;

  /// No description provided for @productsWithInventoryOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only products with inventory control'**
  String get productsWithInventoryOnlySubtitle;

  /// No description provided for @productsWithBasePriceOnly.
  ///
  /// In en, this message translates to:
  /// **'Only products with base price'**
  String get productsWithBasePriceOnly;

  /// No description provided for @productsWithBasePriceOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only products that have a base price'**
  String get productsWithBasePriceOnlySubtitle;

  /// No description provided for @confirmChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm changes'**
  String get confirmChangesTitle;

  /// No description provided for @confirmApplyChangesForNProducts.
  ///
  /// In en, this message translates to:
  /// **'Apply changes to {count} products?'**
  String confirmApplyChangesForNProducts(Object count);

  /// No description provided for @irreversibleWarning.
  ///
  /// In en, this message translates to:
  /// **'This action is irreversible.'**
  String get irreversibleWarning;

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @totalProducts.
  ///
  /// In en, this message translates to:
  /// **'Total products'**
  String get totalProducts;

  /// No description provided for @affectedProducts.
  ///
  /// In en, this message translates to:
  /// **'Affected products'**
  String get affectedProducts;

  /// No description provided for @salesPriceChanges.
  ///
  /// In en, this message translates to:
  /// **'Sales price changes'**
  String get salesPriceChanges;

  /// No description provided for @purchasePriceChanges.
  ///
  /// In en, this message translates to:
  /// **'Purchase price changes'**
  String get purchasePriceChanges;

  /// No description provided for @codeLabel.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get codeLabel;

  /// No description provided for @salesLabel.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesLabel;

  /// No description provided for @purchaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get purchaseLabel;

  /// No description provided for @managePriceLists.
  ///
  /// In en, this message translates to:
  /// **'Manage price lists'**
  String get managePriceLists;

  /// No description provided for @noProductsReadAccess.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to view products & services'**
  String get noProductsReadAccess;

  /// No description provided for @productId.
  ///
  /// In en, this message translates to:
  /// **'Product ID'**
  String get productId;

  /// No description provided for @unit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unit;

  /// No description provided for @minQty.
  ///
  /// In en, this message translates to:
  /// **'Minimum quantity'**
  String get minQty;

  /// No description provided for @addPriceTitle.
  ///
  /// In en, this message translates to:
  /// **'Add price'**
  String get addPriceTitle;

  /// No description provided for @editPriceTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit price'**
  String get editPriceTitle;

  /// No description provided for @productDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Product or service deleted successfully'**
  String get productDeletedSuccessfully;

  /// No description provided for @productsDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Selected items deleted successfully'**
  String get productsDeletedSuccessfully;

  /// No description provided for @noRowsSelectedError.
  ///
  /// In en, this message translates to:
  /// **'No rows selected'**
  String get noRowsSelectedError;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete Selected'**
  String get deleteSelected;

  /// No description provided for @deletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Deleted successfully'**
  String get deletedSuccessfully;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @pettyCashManagement.
  ///
  /// In en, this message translates to:
  /// **'Petty Cash Management'**
  String get pettyCashManagement;

  /// No description provided for @pettyCashName.
  ///
  /// In en, this message translates to:
  /// **'Petty Cash Name'**
  String get pettyCashName;

  /// No description provided for @pettyCashCode.
  ///
  /// In en, this message translates to:
  /// **'Petty Cash Code'**
  String get pettyCashCode;

  /// No description provided for @pettyCashDescription.
  ///
  /// In en, this message translates to:
  /// **'Petty Cash Description'**
  String get pettyCashDescription;

  /// No description provided for @pettyCashCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get pettyCashCurrency;

  /// No description provided for @pettyCashIsActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get pettyCashIsActive;

  /// No description provided for @pettyCashIsDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get pettyCashIsDefault;

  /// No description provided for @pettyCashCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Petty cash created successfully'**
  String get pettyCashCreatedSuccessfully;

  /// No description provided for @pettyCashUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Petty cash updated successfully'**
  String get pettyCashUpdatedSuccessfully;

  /// No description provided for @pettyCashDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Petty cash deleted successfully'**
  String get pettyCashDeletedSuccessfully;

  /// No description provided for @pettyCashNotFound.
  ///
  /// In en, this message translates to:
  /// **'Petty cash not found'**
  String get pettyCashNotFound;

  /// No description provided for @pettyCashNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Petty cash name is required'**
  String get pettyCashNameRequired;

  /// No description provided for @duplicatePettyCashCode.
  ///
  /// In en, this message translates to:
  /// **'Duplicate petty cash code'**
  String get duplicatePettyCashCode;

  /// No description provided for @invalidPettyCashCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid petty cash code'**
  String get invalidPettyCashCode;

  /// No description provided for @pettyCashBulkDeleted.
  ///
  /// In en, this message translates to:
  /// **'Petty cash items deleted successfully'**
  String get pettyCashBulkDeleted;

  /// No description provided for @pettyCashListFetched.
  ///
  /// In en, this message translates to:
  /// **'Petty cash list fetched'**
  String get pettyCashListFetched;

  /// No description provided for @pettyCashDetails.
  ///
  /// In en, this message translates to:
  /// **'Petty cash details'**
  String get pettyCashDetails;

  /// No description provided for @pettyCashExportExcel.
  ///
  /// In en, this message translates to:
  /// **'Export petty cash to Excel'**
  String get pettyCashExportExcel;

  /// No description provided for @pettyCashExportPdf.
  ///
  /// In en, this message translates to:
  /// **'Export petty cash to PDF'**
  String get pettyCashExportPdf;

  /// No description provided for @pettyCashReport.
  ///
  /// In en, this message translates to:
  /// **'Petty Cash Report'**
  String get pettyCashReport;

  /// No description provided for @accountTypeBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get accountTypeBank;

  /// No description provided for @accountTypeCashRegister.
  ///
  /// In en, this message translates to:
  /// **'Cash Register'**
  String get accountTypeCashRegister;

  /// No description provided for @accountTypePettyCash.
  ///
  /// In en, this message translates to:
  /// **'Petty Cash'**
  String get accountTypePettyCash;

  /// No description provided for @accountTypeCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get accountTypeCheck;

  /// No description provided for @accountTypePerson.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get accountTypePerson;

  /// No description provided for @accountTypeProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get accountTypeProduct;

  /// No description provided for @accountTypeService.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get accountTypeService;

  /// No description provided for @accountTypeAccountingDocument.
  ///
  /// In en, this message translates to:
  /// **'Accounting Document'**
  String get accountTypeAccountingDocument;

  /// No description provided for @printTemplatePublished.
  ///
  /// In en, this message translates to:
  /// **'Print template (Published)'**
  String get printTemplatePublished;

  /// No description provided for @noCustomTemplate.
  ///
  /// In en, this message translates to:
  /// **'— No custom template —'**
  String get noCustomTemplate;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @presetInvoicesList.
  ///
  /// In en, this message translates to:
  /// **'Invoices/List'**
  String get presetInvoicesList;

  /// No description provided for @presetInvoicesDetail.
  ///
  /// In en, this message translates to:
  /// **'Invoices/Detail'**
  String get presetInvoicesDetail;

  /// No description provided for @presetReceiptsPaymentsList.
  ///
  /// In en, this message translates to:
  /// **'ReceiptsPayments/List'**
  String get presetReceiptsPaymentsList;

  /// No description provided for @presetReceiptsPaymentsDetail.
  ///
  /// In en, this message translates to:
  /// **'ReceiptsPayments/Detail'**
  String get presetReceiptsPaymentsDetail;

  /// No description provided for @presetExpenseIncomeList.
  ///
  /// In en, this message translates to:
  /// **'ExpenseIncome/List'**
  String get presetExpenseIncomeList;

  /// No description provided for @presetDocumentsList.
  ///
  /// In en, this message translates to:
  /// **'Documents/List'**
  String get presetDocumentsList;

  /// No description provided for @presetDocumentsDetail.
  ///
  /// In en, this message translates to:
  /// **'Documents/Detail'**
  String get presetDocumentsDetail;

  /// No description provided for @presetTransfersList.
  ///
  /// In en, this message translates to:
  /// **'Transfers/List'**
  String get presetTransfersList;

  /// No description provided for @presetTransfersDetail.
  ///
  /// In en, this message translates to:
  /// **'Transfers/Detail'**
  String get presetTransfersDetail;

  /// No description provided for @presetWarehousePostalLabel.
  ///
  /// In en, this message translates to:
  /// **'Warehouse / postal label'**
  String get presetWarehousePostalLabel;

  /// No description provided for @reportTemplatesScopeAll.
  ///
  /// In en, this message translates to:
  /// **'All report types'**
  String get reportTemplatesScopeAll;

  /// No description provided for @reportTemplatesScopeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom (technical keys)'**
  String get reportTemplatesScopeCustom;

  /// No description provided for @reportTemplateNewVisual.
  ///
  /// In en, this message translates to:
  /// **'New — visual builder'**
  String get reportTemplateNewVisual;

  /// No description provided for @reportTemplateNewHtml.
  ///
  /// In en, this message translates to:
  /// **'New — HTML (advanced)'**
  String get reportTemplateNewHtml;

  /// No description provided for @reportTemplateMoreMenu.
  ///
  /// In en, this message translates to:
  /// **'More tools'**
  String get reportTemplateMoreMenu;

  /// No description provided for @reportTemplateExportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON…'**
  String get reportTemplateExportJson;

  /// No description provided for @reportTemplateImportJson.
  ///
  /// In en, this message translates to:
  /// **'Import JSON…'**
  String get reportTemplateImportJson;

  /// No description provided for @reportTemplatePickExport.
  ///
  /// In en, this message translates to:
  /// **'Choose a template to export'**
  String get reportTemplatePickExport;

  /// No description provided for @reportTemplateImportDoneOpenHtml.
  ///
  /// In en, this message translates to:
  /// **'Form filled. Use \"New — HTML\" to review and save.'**
  String get reportTemplateImportDoneOpenHtml;

  /// No description provided for @reportTemplatesLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load templates: {error}'**
  String reportTemplatesLoadError(String error);

  /// No description provided for @reportTemplatePreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Template preview'**
  String get reportTemplatePreviewTitle;

  /// No description provided for @reportTemplatePreviewHtmlTab.
  ///
  /// In en, this message translates to:
  /// **'HTML'**
  String get reportTemplatePreviewHtmlTab;

  /// No description provided for @reportTemplatePreviewPdfTab.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get reportTemplatePreviewPdfTab;

  /// No description provided for @reportTemplatePreviewPdfBytes.
  ///
  /// In en, this message translates to:
  /// **'Generated PDF size: {bytes} bytes'**
  String reportTemplatePreviewPdfBytes(String bytes);

  /// No description provided for @reportTemplateCopyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Copy placeholder'**
  String get reportTemplateCopyPlaceholder;

  /// No description provided for @reportTemplateCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get reportTemplateCopied;

  /// No description provided for @reportTemplateStatusPublished.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get reportTemplateStatusPublished;

  /// No description provided for @reportTemplateStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get reportTemplateStatusDraft;

  /// No description provided for @reportTemplateDefaultBadge.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get reportTemplateDefaultBadge;

  /// No description provided for @reportTemplateRowActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get reportTemplateRowActions;

  /// No description provided for @reportTemplatePublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get reportTemplatePublish;

  /// No description provided for @reportTemplateUnpublish.
  ///
  /// In en, this message translates to:
  /// **'Unpublish'**
  String get reportTemplateUnpublish;

  /// No description provided for @reportTemplatePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get reportTemplatePreview;

  /// No description provided for @reportTemplateEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get reportTemplateEdit;

  /// No description provided for @reportTemplateSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get reportTemplateSetDefault;

  /// No description provided for @reportTemplateDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get reportTemplateDelete;

  /// No description provided for @reportTemplateExportThis.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get reportTemplateExportThis;

  /// No description provided for @reportTemplatesFilterScopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Report scope'**
  String get reportTemplatesFilterScopeLabel;

  /// No description provided for @reportTemplateStatusFilterHint.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get reportTemplateStatusFilterHint;

  /// No description provided for @reportTemplatePlaceholdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Available placeholders'**
  String get reportTemplatePlaceholdersTitle;

  /// No description provided for @reportTemplateVariablesHelpButton.
  ///
  /// In en, this message translates to:
  /// **'Placeholder help'**
  String get reportTemplateVariablesHelpButton;

  /// No description provided for @reportTemplatesSchemaFetchError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load placeholder schema: {error}'**
  String reportTemplatesSchemaFetchError(String error);

  /// No description provided for @reportTemplatesEmptyList.
  ///
  /// In en, this message translates to:
  /// **'No templates found'**
  String get reportTemplatesEmptyList;

  /// No description provided for @reportTemplateDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete template'**
  String get reportTemplateDeleteConfirmTitle;

  /// No description provided for @reportTemplateDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this template? This cannot be undone.'**
  String get reportTemplateDeleteConfirmMessage;

  /// No description provided for @reportTemplateSetDefaultTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get reportTemplateSetDefaultTitle;

  /// No description provided for @reportTemplateSetDefaultMessage.
  ///
  /// In en, this message translates to:
  /// **'Use this template as the default for its module and subtype?'**
  String get reportTemplateSetDefaultMessage;

  /// No description provided for @reportTemplateEditSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save template: {error}'**
  String reportTemplateEditSaveError(String error);

  /// No description provided for @reportTemplatePreviewError.
  ///
  /// In en, this message translates to:
  /// **'Preview failed: {error}'**
  String reportTemplatePreviewError(String error);

  /// No description provided for @reportTemplateInvalidJsonError.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON: {error}'**
  String reportTemplateInvalidJsonError(String error);

  /// No description provided for @reportTemplatePdfDownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'PDF download started'**
  String get reportTemplatePdfDownloadStarted;

  /// No description provided for @reportTemplatePdfSavedToPath.
  ///
  /// In en, this message translates to:
  /// **'Saved to: {path}'**
  String reportTemplatePdfSavedToPath(String path);

  /// No description provided for @reportTemplatePdfSavedGeneric.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get reportTemplatePdfSavedGeneric;

  /// No description provided for @reportTemplateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get reportTemplateDownload;

  /// No description provided for @reportTemplateOpenInNewTab.
  ///
  /// In en, this message translates to:
  /// **'Open in new tab'**
  String get reportTemplateOpenInNewTab;

  /// No description provided for @reportTemplatePdfInlineFailedHint.
  ///
  /// In en, this message translates to:
  /// **'In-page PDF preview failed; use the HTML tab.'**
  String get reportTemplatePdfInlineFailedHint;

  /// No description provided for @reportTemplateBuilderDesignEmpty.
  ///
  /// In en, this message translates to:
  /// **'Visual builder design is empty.'**
  String get reportTemplateBuilderDesignEmpty;

  /// No description provided for @reportTemplatePaperCustomLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom paper size (optional)'**
  String get reportTemplatePaperCustomLabel;

  /// No description provided for @reportTemplatePaperCustomHelper.
  ///
  /// In en, this message translates to:
  /// **'If set, this replaces the selected paper size (max 32 characters).'**
  String get reportTemplatePaperCustomHelper;

  /// No description provided for @reportTemplateEditorTabCss.
  ///
  /// In en, this message translates to:
  /// **'CSS'**
  String get reportTemplateEditorTabCss;

  /// No description provided for @reportTemplateEditorTabHeader.
  ///
  /// In en, this message translates to:
  /// **'Header'**
  String get reportTemplateEditorTabHeader;

  /// No description provided for @reportTemplateEditorTabFooter.
  ///
  /// In en, this message translates to:
  /// **'Footer'**
  String get reportTemplateEditorTabFooter;

  /// No description provided for @reportTemplatePageSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'Page settings'**
  String get reportTemplatePageSettingsSection;

  /// No description provided for @reportTemplateFieldName.
  ///
  /// In en, this message translates to:
  /// **'Template name'**
  String get reportTemplateFieldName;

  /// No description provided for @reportTemplateFieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get reportTemplateFieldDescription;

  /// No description provided for @reportTemplateModuleKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'module_key'**
  String get reportTemplateModuleKeyLabel;

  /// No description provided for @reportTemplateSubtypeLabel.
  ///
  /// In en, this message translates to:
  /// **'subtype'**
  String get reportTemplateSubtypeLabel;

  /// No description provided for @reportTemplateModuleKeyTooltip.
  ///
  /// In en, this message translates to:
  /// **'API report module identifier.'**
  String get reportTemplateModuleKeyTooltip;

  /// No description provided for @reportTemplateSubtypeTooltip.
  ///
  /// In en, this message translates to:
  /// **'API report subtype (e.g. list or detail).'**
  String get reportTemplateSubtypeTooltip;

  /// No description provided for @reportTemplateHintHtmlBody.
  ///
  /// In en, this message translates to:
  /// **'HTML body (Jinja2 placeholders allowed)'**
  String get reportTemplateHintHtmlBody;

  /// No description provided for @reportTemplateHintCss.
  ///
  /// In en, this message translates to:
  /// **'Optional CSS'**
  String get reportTemplateHintCss;

  /// No description provided for @reportTemplateHintHeaderHtml.
  ///
  /// In en, this message translates to:
  /// **'Optional header HTML'**
  String get reportTemplateHintHeaderHtml;

  /// No description provided for @reportTemplateHintFooterHtml.
  ///
  /// In en, this message translates to:
  /// **'Optional footer HTML'**
  String get reportTemplateHintFooterHtml;

  /// No description provided for @printPdf.
  ///
  /// In en, this message translates to:
  /// **'Print PDF'**
  String get printPdf;

  /// No description provided for @generating.
  ///
  /// In en, this message translates to:
  /// **'Generating...'**
  String get generating;

  /// No description provided for @pdfSuccess.
  ///
  /// In en, this message translates to:
  /// **'PDF generated successfully'**
  String get pdfSuccess;

  /// No description provided for @pdfError.
  ///
  /// In en, this message translates to:
  /// **'Error generating PDF'**
  String get pdfError;

  /// No description provided for @printTemplate.
  ///
  /// In en, this message translates to:
  /// **'Print template'**
  String get printTemplate;

  /// No description provided for @templateStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard template'**
  String get templateStandard;

  /// No description provided for @templateCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact template'**
  String get templateCompact;

  /// No description provided for @templateDetailed.
  ///
  /// In en, this message translates to:
  /// **'Detailed template'**
  String get templateDetailed;

  /// No description provided for @templateCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom template'**
  String get templateCustom;

  /// No description provided for @invoicesListManage.
  ///
  /// In en, this message translates to:
  /// **'Manage invoices list'**
  String get invoicesListManage;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @invoiceTypeSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get invoiceTypeSales;

  /// No description provided for @invoiceTypePurchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get invoiceTypePurchase;

  /// No description provided for @invoiceTypeSalesReturn.
  ///
  /// In en, this message translates to:
  /// **'Sales return'**
  String get invoiceTypeSalesReturn;

  /// No description provided for @invoiceTypePurchaseReturn.
  ///
  /// In en, this message translates to:
  /// **'Purchase return'**
  String get invoiceTypePurchaseReturn;

  /// No description provided for @invoiceTypeProduction.
  ///
  /// In en, this message translates to:
  /// **'Production'**
  String get invoiceTypeProduction;

  /// No description provided for @invoiceTypeDirectConsumption.
  ///
  /// In en, this message translates to:
  /// **'Direct consumption'**
  String get invoiceTypeDirectConsumption;

  /// No description provided for @invoiceTypeWaste.
  ///
  /// In en, this message translates to:
  /// **'Waste'**
  String get invoiceTypeWaste;

  /// No description provided for @documentDate.
  ///
  /// In en, this message translates to:
  /// **'Document date'**
  String get documentDate;

  /// No description provided for @totalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total amount'**
  String get totalAmount;

  /// No description provided for @invoicePaidAmount.
  ///
  /// In en, this message translates to:
  /// **'Invoice paid amount'**
  String get invoicePaidAmount;

  /// No description provided for @invoiceRemainingAmount.
  ///
  /// In en, this message translates to:
  /// **'Invoice remaining amount'**
  String get invoiceRemainingAmount;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @noInvoicesFound.
  ///
  /// In en, this message translates to:
  /// **'No invoices found'**
  String get noInvoicesFound;

  /// No description provided for @loadingInvoices.
  ///
  /// In en, this message translates to:
  /// **'Loading invoices...'**
  String get loadingInvoices;

  /// No description provided for @errorLoadingInvoices.
  ///
  /// In en, this message translates to:
  /// **'Error loading invoices'**
  String get errorLoadingInvoices;

  /// No description provided for @proforma.
  ///
  /// In en, this message translates to:
  /// **'Proforma'**
  String get proforma;

  /// No description provided for @finalized.
  ///
  /// In en, this message translates to:
  /// **'Finalized'**
  String get finalized;

  /// No description provided for @clearDateFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear date filter'**
  String get clearDateFilter;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm delete'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteInvoiceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete invoice {code}? This action is irreversible.'**
  String deleteInvoiceConfirm(String code);

  /// No description provided for @deletedInvoiceSuccess.
  ///
  /// In en, this message translates to:
  /// **'Invoice {code} deleted successfully'**
  String deletedInvoiceSuccess(String code);

  /// No description provided for @deleteInvoiceError.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete invoice'**
  String get deleteInvoiceError;

  /// No description provided for @deleteInvoiceErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete invoice: {error}'**
  String deleteInvoiceErrorWithMessage(String error);

  /// No description provided for @deleteInvoiceTaxWorkspaceError.
  ///
  /// In en, this message translates to:
  /// **'This invoice is in the tax workspace and cannot be deleted'**
  String get deleteInvoiceTaxWorkspaceError;

  /// No description provided for @deleteInvoiceReceiptPaymentsWarning.
  ///
  /// In en, this message translates to:
  /// **'Related receipt/payment documents:'**
  String get deleteInvoiceReceiptPaymentsWarning;

  /// No description provided for @deleteInvoiceWarehouseWarning.
  ///
  /// In en, this message translates to:
  /// **'Related finalized warehouse documents:'**
  String get deleteInvoiceWarehouseWarning;

  /// No description provided for @deleteInvoiceInstallmentsWarning.
  ///
  /// In en, this message translates to:
  /// **'This invoice has {count} installments that will be deleted'**
  String deleteInvoiceInstallmentsWarning(String count);

  /// No description provided for @saveInvoice.
  ///
  /// In en, this message translates to:
  /// **'Save invoice'**
  String get saveInvoice;

  /// No description provided for @invoiceInfoTab.
  ///
  /// In en, this message translates to:
  /// **'Invoice info'**
  String get invoiceInfoTab;

  /// No description provided for @productsServicesTab.
  ///
  /// In en, this message translates to:
  /// **'Products & services'**
  String get productsServicesTab;

  /// No description provided for @transactionsTab.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get transactionsTab;

  /// No description provided for @settingsTab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTab;

  /// No description provided for @invoiceCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Invoice created successfully'**
  String get invoiceCreatedSuccess;

  /// No description provided for @saveInvoiceErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to save invoice: {error}'**
  String saveInvoiceErrorWithMessage(String error);

  /// No description provided for @noRowsAdded.
  ///
  /// In en, this message translates to:
  /// **'No rows added'**
  String get noRowsAdded;

  /// No description provided for @quantityUnit.
  ///
  /// In en, this message translates to:
  /// **'Quantity/Unit'**
  String get quantityUnit;

  /// No description provided for @unitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get unitPrice;

  /// No description provided for @installmentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Installment sale'**
  String get installmentsTitle;

  /// No description provided for @installmentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If enabled, an installment plan will be saved with the invoice'**
  String get installmentsSubtitle;

  /// No description provided for @installmentsSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage installment plans and sales conditions'**
  String get installmentsSettingsSubtitle;

  /// No description provided for @installmentsCount.
  ///
  /// In en, this message translates to:
  /// **'Number of installments'**
  String get installmentsCount;

  /// No description provided for @downPayment.
  ///
  /// In en, this message translates to:
  /// **'Down payment'**
  String get downPayment;

  /// No description provided for @interestRatePercent.
  ///
  /// In en, this message translates to:
  /// **'Total period interest (%)'**
  String get interestRatePercent;

  /// No description provided for @installmentsPeriod.
  ///
  /// In en, this message translates to:
  /// **'Installment period'**
  String get installmentsPeriod;

  /// No description provided for @installmentsMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly (30 days)'**
  String get installmentsMonthly;

  /// No description provided for @installmentsDaysBased.
  ///
  /// In en, this message translates to:
  /// **'By days'**
  String get installmentsDaysBased;

  /// No description provided for @installmentDaysLength.
  ///
  /// In en, this message translates to:
  /// **'Length of each installment (days)'**
  String get installmentDaysLength;

  /// No description provided for @firstInstallmentDueDate.
  ///
  /// In en, this message translates to:
  /// **'First due date'**
  String get firstInstallmentDueDate;

  /// No description provided for @invalidInstallmentsCount.
  ///
  /// In en, this message translates to:
  /// **'Invalid number of installments'**
  String get invalidInstallmentsCount;

  /// No description provided for @unitPricePickHint.
  ///
  /// In en, this message translates to:
  /// **'Unit price (pick from list or enter manually)'**
  String get unitPricePickHint;

  /// No description provided for @lineTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Line total amount'**
  String get lineTotalAmount;

  /// No description provided for @lineDescription.
  ///
  /// In en, this message translates to:
  /// **'Line description'**
  String get lineDescription;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @discountTypeAndValue.
  ///
  /// In en, this message translates to:
  /// **'Discount (type and value)'**
  String get discountTypeAndValue;

  /// No description provided for @taxPercentAndAmount.
  ///
  /// In en, this message translates to:
  /// **'Tax (percent and amount)'**
  String get taxPercentAndAmount;

  /// No description provided for @selectUnitTitle.
  ///
  /// In en, this message translates to:
  /// **'Select unit'**
  String get selectUnitTitle;

  /// No description provided for @mainUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Main unit'**
  String get mainUnitLabel;

  /// No description provided for @secondaryUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Secondary unit'**
  String get secondaryUnitLabel;

  /// No description provided for @noUnitsDefined.
  ///
  /// In en, this message translates to:
  /// **'No units defined for this product'**
  String get noUnitsDefined;

  /// No description provided for @discountType.
  ///
  /// In en, this message translates to:
  /// **'Discount type'**
  String get discountType;

  /// No description provided for @percent.
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get percent;

  /// No description provided for @pricePickFromList.
  ///
  /// In en, this message translates to:
  /// **'Pick from price list'**
  String get pricePickFromList;

  /// No description provided for @noPricesFound.
  ///
  /// In en, this message translates to:
  /// **'No prices to show'**
  String get noPricesFound;

  /// No description provided for @baseEstimatedPrice.
  ///
  /// In en, this message translates to:
  /// **'Estimated base price'**
  String get baseEstimatedPrice;

  /// No description provided for @priceListLabel.
  ///
  /// In en, this message translates to:
  /// **'Price list'**
  String get priceListLabel;

  /// No description provided for @kardexDocuments.
  ///
  /// In en, this message translates to:
  /// **'Kardex documents'**
  String get kardexDocuments;

  /// No description provided for @documentCode.
  ///
  /// In en, this message translates to:
  /// **'Document code'**
  String get documentCode;

  /// No description provided for @documentType.
  ///
  /// In en, this message translates to:
  /// **'Document type'**
  String get documentType;

  /// No description provided for @movementDirection.
  ///
  /// In en, this message translates to:
  /// **'Movement'**
  String get movementDirection;

  /// No description provided for @movementIn.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get movementIn;

  /// No description provided for @movementOut.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get movementOut;

  /// No description provided for @debit.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get debit;

  /// No description provided for @credit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get credit;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @runningAmount.
  ///
  /// In en, this message translates to:
  /// **'Running amount'**
  String get runningAmount;

  /// No description provided for @runningQuantity.
  ///
  /// In en, this message translates to:
  /// **'Running quantity'**
  String get runningQuantity;

  /// No description provided for @viewDocument.
  ///
  /// In en, this message translates to:
  /// **'View document'**
  String get viewDocument;

  /// No description provided for @totalsDebit.
  ///
  /// In en, this message translates to:
  /// **'Total debit'**
  String get totalsDebit;

  /// No description provided for @totalsCredit.
  ///
  /// In en, this message translates to:
  /// **'Total credit'**
  String get totalsCredit;

  /// No description provided for @totalsQuantity.
  ///
  /// In en, this message translates to:
  /// **'Total quantity'**
  String get totalsQuantity;

  /// No description provided for @totalsRunningAmount.
  ///
  /// In en, this message translates to:
  /// **'Running amount'**
  String get totalsRunningAmount;

  /// No description provided for @totalsRunningQuantity.
  ///
  /// In en, this message translates to:
  /// **'Running quantity'**
  String get totalsRunningQuantity;

  /// No description provided for @addFilter.
  ///
  /// In en, this message translates to:
  /// **'Add filter'**
  String get addFilter;

  /// No description provided for @presetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presetsTitle;

  /// No description provided for @applyPreset.
  ///
  /// In en, this message translates to:
  /// **'Apply preset'**
  String get applyPreset;

  /// No description provided for @deleteSelectedPreset.
  ///
  /// In en, this message translates to:
  /// **'Delete selected preset'**
  String get deleteSelectedPreset;

  /// No description provided for @savePreset.
  ///
  /// In en, this message translates to:
  /// **'Save preset'**
  String get savePreset;

  /// No description provided for @savePresetTitle.
  ///
  /// In en, this message translates to:
  /// **'Save preset'**
  String get savePresetTitle;

  /// No description provided for @presetNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter preset name'**
  String get presetNameHint;

  /// No description provided for @presetSaved.
  ///
  /// In en, this message translates to:
  /// **'Preset saved'**
  String get presetSaved;

  /// No description provided for @presetSaveError.
  ///
  /// In en, this message translates to:
  /// **'Error saving preset: {error}'**
  String presetSaveError(String error);

  /// No description provided for @presetDeleteError.
  ///
  /// In en, this message translates to:
  /// **'Error deleting preset: {error}'**
  String presetDeleteError(String error);

  /// No description provided for @presetApplyError.
  ///
  /// In en, this message translates to:
  /// **'Error applying preset: {error}'**
  String presetApplyError(String error);

  /// No description provided for @fiscalYear.
  ///
  /// In en, this message translates to:
  /// **'Fiscal year'**
  String get fiscalYear;

  /// No description provided for @fiscalYears.
  ///
  /// In en, this message translates to:
  /// **'Fiscal years'**
  String get fiscalYears;

  /// No description provided for @addFilterPersons.
  ///
  /// In en, this message translates to:
  /// **'Add filter: People'**
  String get addFilterPersons;

  /// No description provided for @addFilterProduct.
  ///
  /// In en, this message translates to:
  /// **'Add filter: Product/Service'**
  String get addFilterProduct;

  /// No description provided for @addFilterBank.
  ///
  /// In en, this message translates to:
  /// **'Add filter: Bank'**
  String get addFilterBank;

  /// No description provided for @addFilterCash.
  ///
  /// In en, this message translates to:
  /// **'Add filter: Cash register'**
  String get addFilterCash;

  /// No description provided for @addFilterPetty.
  ///
  /// In en, this message translates to:
  /// **'Add filter: Petty cash'**
  String get addFilterPetty;

  /// No description provided for @addFilterAccount.
  ///
  /// In en, this message translates to:
  /// **'Add filter: Ledger account'**
  String get addFilterAccount;

  /// No description provided for @addFilterCheck.
  ///
  /// In en, this message translates to:
  /// **'Add filter: Check'**
  String get addFilterCheck;

  /// No description provided for @matchModeAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get matchModeAny;

  /// No description provided for @matchModeSameLine.
  ///
  /// In en, this message translates to:
  /// **'Same line'**
  String get matchModeSameLine;

  /// No description provided for @matchModeDocumentAnd.
  ///
  /// In en, this message translates to:
  /// **'Same document'**
  String get matchModeDocumentAnd;

  /// No description provided for @resultScopeLinesMatching.
  ///
  /// In en, this message translates to:
  /// **'Only matching lines'**
  String get resultScopeLinesMatching;

  /// No description provided for @resultScopeLinesOfDocument.
  ///
  /// In en, this message translates to:
  /// **'All lines of document'**
  String get resultScopeLinesOfDocument;

  /// No description provided for @includeRunningBalance.
  ///
  /// In en, this message translates to:
  /// **'Include running balance'**
  String get includeRunningBalance;

  /// No description provided for @applyManually.
  ///
  /// In en, this message translates to:
  /// **'Apply manually'**
  String get applyManually;

  /// No description provided for @ledgerAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get ledgerAccount;

  /// No description provided for @reportsGeneralSection.
  ///
  /// In en, this message translates to:
  /// **'General reports'**
  String get reportsGeneralSection;

  /// No description provided for @reportsPeopleSection.
  ///
  /// In en, this message translates to:
  /// **'People reports'**
  String get reportsPeopleSection;

  /// No description provided for @reportsProductsSection.
  ///
  /// In en, this message translates to:
  /// **'Products & services reports'**
  String get reportsProductsSection;

  /// No description provided for @reportsBankingSection.
  ///
  /// In en, this message translates to:
  /// **'Banking & cash reports'**
  String get reportsBankingSection;

  /// No description provided for @reportsSalesSection.
  ///
  /// In en, this message translates to:
  /// **'Sales reports'**
  String get reportsSalesSection;

  /// No description provided for @reportsPurchasesSection.
  ///
  /// In en, this message translates to:
  /// **'Purchase reports'**
  String get reportsPurchasesSection;

  /// No description provided for @reportsProductionSection.
  ///
  /// In en, this message translates to:
  /// **'Production reports'**
  String get reportsProductionSection;

  /// No description provided for @reportsBasicAccountingSection.
  ///
  /// In en, this message translates to:
  /// **'Basic accounting'**
  String get reportsBasicAccountingSection;

  /// No description provided for @reportsProfitLossSection.
  ///
  /// In en, this message translates to:
  /// **'Profit & loss'**
  String get reportsProfitLossSection;

  /// No description provided for @reportsKardexSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed transactions by person/product/bank/account/check with date filters'**
  String get reportsKardexSubtitle;

  /// No description provided for @reportsDebtorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Debtors list'**
  String get reportsDebtorsTitle;

  /// No description provided for @reportsDebtorsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'People with debit balances'**
  String get reportsDebtorsSubtitle;

  /// No description provided for @reportsCreditorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Creditors list'**
  String get reportsCreditorsTitle;

  /// No description provided for @reportsCreditorsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'People with credit balances'**
  String get reportsCreditorsSubtitle;

  /// No description provided for @reportsPeopleTransactionsTitle.
  ///
  /// In en, this message translates to:
  /// **'People transactions'**
  String get reportsPeopleTransactionsTitle;

  /// No description provided for @reportsPeopleTransactionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed receipts and payments by person'**
  String get reportsPeopleTransactionsSubtitle;

  /// No description provided for @reportsItemMovementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Item movements'**
  String get reportsItemMovementsTitle;

  /// No description provided for @reportsItemMovementsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'In, out and balance over a period'**
  String get reportsItemMovementsSubtitle;

  /// No description provided for @reportsInventoryKardexTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory kardex'**
  String get reportsInventoryKardexTitle;

  /// No description provided for @reportsInventoryKardexSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Per-item movement details (FIFO/LIFO/average)'**
  String get reportsInventoryKardexSubtitle;

  /// No description provided for @reportsInventoryStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory stock report'**
  String get reportsInventoryStockTitle;

  /// No description provided for @reportsInventoryStockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Product inventory by warehouse and date'**
  String get reportsInventoryStockSubtitle;

  /// No description provided for @reportsSalesByProductTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales by product'**
  String get reportsSalesByProductTitle;

  /// No description provided for @reportsSalesByProductSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Performance of each product in time range'**
  String get reportsSalesByProductSubtitle;

  /// No description provided for @reportsBankAccountsTurnoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Bank accounts turnover'**
  String get reportsBankAccountsTurnoverTitle;

  /// No description provided for @reportsBankAccountsTurnoverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Withdrawals and deposits by account'**
  String get reportsBankAccountsTurnoverSubtitle;

  /// No description provided for @reportsCashPettyTurnoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash and petty cash turnover'**
  String get reportsCashPettyTurnoverTitle;

  /// No description provided for @reportsCashPettyTurnoverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed cash in/out'**
  String get reportsCashPettyTurnoverSubtitle;

  /// No description provided for @reportsChecksTitle.
  ///
  /// In en, this message translates to:
  /// **'Checks'**
  String get reportsChecksTitle;

  /// No description provided for @reportsChecksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receivable, payable, due dates and statuses'**
  String get reportsChecksSubtitle;

  /// No description provided for @reportsDailySalesTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily sales'**
  String get reportsDailySalesTitle;

  /// No description provided for @reportsDailySalesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily sales performance and trends'**
  String get reportsDailySalesSubtitle;

  /// No description provided for @reportsMonthlySalesTitle.
  ///
  /// In en, this message translates to:
  /// **'Monthly sales'**
  String get reportsMonthlySalesTitle;

  /// No description provided for @reportsMonthlySalesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monthly comparison and sales growth'**
  String get reportsMonthlySalesSubtitle;

  /// No description provided for @reportsTopCustomersTitle.
  ///
  /// In en, this message translates to:
  /// **'Top customers'**
  String get reportsTopCustomersTitle;

  /// No description provided for @reportsTopCustomersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ranking by amount or count'**
  String get reportsTopCustomersSubtitle;

  /// No description provided for @reportsDailyPurchasesTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily purchases'**
  String get reportsDailyPurchasesTitle;

  /// No description provided for @reportsDailyPurchasesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily purchase performance and trends'**
  String get reportsDailyPurchasesSubtitle;

  /// No description provided for @reportsTopSuppliersTitle.
  ///
  /// In en, this message translates to:
  /// **'Top suppliers'**
  String get reportsTopSuppliersTitle;

  /// No description provided for @reportsTopSuppliersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Suppliers ranked by purchases'**
  String get reportsTopSuppliersSubtitle;

  /// No description provided for @reportsMaterialsConsumptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Materials consumption'**
  String get reportsMaterialsConsumptionTitle;

  /// No description provided for @reportsMaterialsConsumptionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Raw material consumption per product'**
  String get reportsMaterialsConsumptionSubtitle;

  /// No description provided for @reportsProductionTitle.
  ///
  /// In en, this message translates to:
  /// **'Production report'**
  String get reportsProductionTitle;

  /// No description provided for @reportsProductionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Production volume and waste'**
  String get reportsProductionSubtitle;

  /// No description provided for @reportsTrialBalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Trial balance'**
  String get reportsTrialBalanceTitle;

  /// No description provided for @reportsTrialBalanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'2/4/6/8-column balance'**
  String get reportsTrialBalanceSubtitle;

  /// No description provided for @reportsGeneralLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'General ledger'**
  String get reportsGeneralLedgerTitle;

  /// No description provided for @reportsGeneralLedgerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Account movements over a period'**
  String get reportsGeneralLedgerSubtitle;

  /// No description provided for @reportsJournalLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Journal Ledger'**
  String get reportsJournalLedgerTitle;

  /// No description provided for @reportsJournalLedgerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All financial transactions in chronological order'**
  String get reportsJournalLedgerSubtitle;

  /// No description provided for @debitAccount.
  ///
  /// In en, this message translates to:
  /// **'Debit Account'**
  String get debitAccount;

  /// No description provided for @creditAccount.
  ///
  /// In en, this message translates to:
  /// **'Credit Account'**
  String get creditAccount;

  /// No description provided for @reportsPnlPeriodTitle.
  ///
  /// In en, this message translates to:
  /// **'Period profit and loss'**
  String get reportsPnlPeriodTitle;

  /// No description provided for @reportsPnlPeriodSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Revenue, expenses, and net profit/loss'**
  String get reportsPnlPeriodSubtitle;

  /// No description provided for @reportsPnlCumulativeTitle.
  ///
  /// In en, this message translates to:
  /// **'Cumulative profit and loss'**
  String get reportsPnlCumulativeTitle;

  /// No description provided for @reportsAccountsReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts review report'**
  String get reportsAccountsReviewTitle;

  /// No description provided for @reportsAccountsReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Account tree structure with balances and transaction details'**
  String get reportsAccountsReviewSubtitle;

  /// No description provided for @reportsPnlCumulativeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Periodical comparison and cumulative view'**
  String get reportsPnlCumulativeSubtitle;

  /// No description provided for @reportsComingSoonMessage.
  ///
  /// In en, this message translates to:
  /// **'This report will be available soon.'**
  String get reportsComingSoonMessage;

  /// No description provided for @reportsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search reports…'**
  String get reportsSearchHint;

  /// No description provided for @reportsSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Results ({count})'**
  String reportsSearchResults(Object count);

  /// No description provided for @reportsSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No reports matched your search.'**
  String get reportsSearchNoResults;

  /// No description provided for @reportsFavoritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get reportsFavoritesTitle;

  /// No description provided for @reportsFavoritesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'For quick access, tap the star next to a report.'**
  String get reportsFavoritesEmptyMessage;

  /// No description provided for @reportsRecentTitle.
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get reportsRecentTitle;

  /// No description provided for @reportsRecentEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Reports you open will show up here.'**
  String get reportsRecentEmptyMessage;

  /// No description provided for @reportsWarehouseSection.
  ///
  /// In en, this message translates to:
  /// **'Warehouse reports'**
  String get reportsWarehouseSection;

  /// No description provided for @reportsSystemSection.
  ///
  /// In en, this message translates to:
  /// **'System reports'**
  String get reportsSystemSection;

  /// No description provided for @reportsActivityLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'User activity logs'**
  String get reportsActivityLogsTitle;

  /// No description provided for @reportsActivityLogsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View the history of user activity in the system'**
  String get reportsActivityLogsSubtitle;

  /// No description provided for @reportsSectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count} reports'**
  String reportsSectionCount(Object count);

  /// No description provided for @reportsAddToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get reportsAddToFavorites;

  /// No description provided for @reportsRemoveFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get reportsRemoveFromFavorites;

  /// No description provided for @reportsInstallmentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Installment status, due dates, and remaining balance'**
  String get reportsInstallmentsSubtitle;

  /// No description provided for @reportsStockCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock count report'**
  String get reportsStockCountTitle;

  /// No description provided for @reportsStockCountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stock count history and adjustment documents'**
  String get reportsStockCountSubtitle;

  /// No description provided for @reportsWarehouseDocumentsSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Warehouse documents summary'**
  String get reportsWarehouseDocumentsSummaryTitle;

  /// No description provided for @reportsWarehouseDocumentsSummarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Summary by document type with inbound/outbound stats'**
  String get reportsWarehouseDocumentsSummarySubtitle;

  /// No description provided for @reportsSlowMovingItemsTitle.
  ///
  /// In en, this message translates to:
  /// **'Slow-moving items'**
  String get reportsSlowMovingItemsTitle;

  /// No description provided for @reportsSlowMovingItemsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Items with no movement during the selected time range'**
  String get reportsSlowMovingItemsSubtitle;

  /// No description provided for @reportsCriticalStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Critical stock items'**
  String get reportsCriticalStockTitle;

  /// No description provided for @reportsCriticalStockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Items with stock below the defined threshold'**
  String get reportsCriticalStockSubtitle;

  /// No description provided for @reportsInterWarehouseTransfersTitle.
  ///
  /// In en, this message translates to:
  /// **'Inter-warehouse transfers'**
  String get reportsInterWarehouseTransfersTitle;

  /// No description provided for @reportsInterWarehouseTransfersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Details of transfers between warehouses'**
  String get reportsInterWarehouseTransfersSubtitle;

  /// No description provided for @reportsAdjustmentDocumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjustment documents'**
  String get reportsAdjustmentDocumentsTitle;

  /// No description provided for @reportsAdjustmentDocumentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Analysis of adjustment documents and inventory differences'**
  String get reportsAdjustmentDocumentsSubtitle;

  /// No description provided for @reportsWarehousePerformanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Warehouse performance'**
  String get reportsWarehousePerformanceTitle;

  /// No description provided for @reportsWarehousePerformanceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Compare warehouse performance'**
  String get reportsWarehousePerformanceSubtitle;

  /// No description provided for @reportsProductMovementHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Product movement history'**
  String get reportsProductMovementHistoryTitle;

  /// No description provided for @reportsProductMovementHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Full movement history of a product across all warehouses'**
  String get reportsProductMovementHistorySubtitle;

  /// No description provided for @reportsInventoryValuationTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory valuation'**
  String get reportsInventoryValuationTitle;

  /// No description provided for @reportsInventoryValuationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monetary valuation of warehouse inventories'**
  String get reportsInventoryValuationSubtitle;

  /// No description provided for @reportsPendingDocumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending documents'**
  String get reportsPendingDocumentsTitle;

  /// No description provided for @reportsPendingDocumentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Draft or pending-approval documents'**
  String get reportsPendingDocumentsSubtitle;

  /// No description provided for @reportsInventoryTurnoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory turnover'**
  String get reportsInventoryTurnoverTitle;

  /// No description provided for @reportsInventoryTurnoverSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory turnover rate for products'**
  String get reportsInventoryTurnoverSubtitle;

  /// No description provided for @reportsSortTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get reportsSortTooltip;

  /// No description provided for @reportsSortDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get reportsSortDefault;

  /// No description provided for @reportsSortAlphabetical.
  ///
  /// In en, this message translates to:
  /// **'Alphabetical'**
  String get reportsSortAlphabetical;

  /// No description provided for @operationSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Operation successful'**
  String get operationSuccessful;

  /// No description provided for @notificationsSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get notificationsSettingsTitle;

  /// No description provided for @notificationsSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable delivery channels, send test messages, and manage service credentials.'**
  String get notificationsSettingsSubtitle;

  /// No description provided for @notificationsChannelsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery channels'**
  String get notificationsChannelsSectionTitle;

  /// No description provided for @notificationsChannelsSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Any enabled channel may be used for system notifications and operational alerts.'**
  String get notificationsChannelsSectionSubtitle;

  /// No description provided for @notificationsChannelTelegram.
  ///
  /// In en, this message translates to:
  /// **'Telegram'**
  String get notificationsChannelTelegram;

  /// No description provided for @notificationsChannelTelegramDescription.
  ///
  /// In en, this message translates to:
  /// **'Send messages through a connected Telegram bot for operators.'**
  String get notificationsChannelTelegramDescription;

  /// No description provided for @notificationsChannelBale.
  ///
  /// In en, this message translates to:
  /// **'Bale'**
  String get notificationsChannelBale;

  /// No description provided for @notificationsChannelBaleDescription.
  ///
  /// In en, this message translates to:
  /// **'Send messages through Bale messenger (connected bot).'**
  String get notificationsChannelBaleDescription;

  /// No description provided for @notificationsBaleAdvancedTitle.
  ///
  /// In en, this message translates to:
  /// **'Bale advanced settings'**
  String get notificationsBaleAdvancedTitle;

  /// No description provided for @notificationsBaleAdvancedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure Bale bot for notifications'**
  String get notificationsBaleAdvancedSubtitle;

  /// No description provided for @notificationsFieldBaleToken.
  ///
  /// In en, this message translates to:
  /// **'Bale bot token'**
  String get notificationsFieldBaleToken;

  /// No description provided for @notificationsFieldBaleTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Bot token from @BotFather in Bale'**
  String get notificationsFieldBaleTokenHint;

  /// No description provided for @notificationsFieldBaleUsername.
  ///
  /// In en, this message translates to:
  /// **'Bale bot username'**
  String get notificationsFieldBaleUsername;

  /// No description provided for @notificationsFieldBaleWebhookSecret.
  ///
  /// In en, this message translates to:
  /// **'Bale webhook secret'**
  String get notificationsFieldBaleWebhookSecret;

  /// No description provided for @notificationsBaleConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get notificationsBaleConnected;

  /// No description provided for @notificationsBaleNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notificationsBaleNotConnected;

  /// No description provided for @notificationsBaleConnectButton.
  ///
  /// In en, this message translates to:
  /// **'Connect Bale'**
  String get notificationsBaleConnectButton;

  /// No description provided for @notificationsBaleDisconnectButton.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Bale'**
  String get notificationsBaleDisconnectButton;

  /// No description provided for @notificationsBaleConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get notificationsBaleConnecting;

  /// No description provided for @notificationsBaleConnectionWarning.
  ///
  /// In en, this message translates to:
  /// **'To enable Bale notifications, please connect first.'**
  String get notificationsBaleConnectionWarning;

  /// No description provided for @notificationsBaleLinkInstructions.
  ///
  /// In en, this message translates to:
  /// **'Click the link below or open the bot in Bale and send /start {token}.'**
  String notificationsBaleLinkInstructions(String token);

  /// No description provided for @notificationsBaleLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'Connection link expired. Please create a new link.'**
  String get notificationsBaleLinkExpired;

  /// No description provided for @notificationsBaleConnectedSince.
  ///
  /// In en, this message translates to:
  /// **'Connected since {date}'**
  String notificationsBaleConnectedSince(String date);

  /// No description provided for @notificationsBaleConnectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Bale connected successfully.'**
  String get notificationsBaleConnectionSuccess;

  /// No description provided for @notificationsBaleConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Error connecting Bale.'**
  String get notificationsBaleConnectionError;

  /// No description provided for @notificationsBaleDisconnectSuccess.
  ///
  /// In en, this message translates to:
  /// **'Bale disconnected.'**
  String get notificationsBaleDisconnectSuccess;

  /// No description provided for @notificationsBaleDisconnectError.
  ///
  /// In en, this message translates to:
  /// **'Error disconnecting Bale.'**
  String get notificationsBaleDisconnectError;

  /// No description provided for @notificationsChannelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get notificationsChannelEmail;

  /// No description provided for @notificationsChannelEmailDescription.
  ///
  /// In en, this message translates to:
  /// **'Send emails using the server configured in system settings.'**
  String get notificationsChannelEmailDescription;

  /// No description provided for @notificationsChannelSms.
  ///
  /// In en, this message translates to:
  /// **'SMS'**
  String get notificationsChannelSms;

  /// No description provided for @notificationsChannelSmsDescription.
  ///
  /// In en, this message translates to:
  /// **'Send SMS via your configured provider for sensitive events.'**
  String get notificationsChannelSmsDescription;

  /// No description provided for @notificationsChannelInApp.
  ///
  /// In en, this message translates to:
  /// **'In-app'**
  String get notificationsChannelInApp;

  /// No description provided for @notificationsChannelInAppDescription.
  ///
  /// In en, this message translates to:
  /// **'Display notifications inside Hesabix web and mobile in real time.'**
  String get notificationsChannelInAppDescription;

  /// No description provided for @notificationsSaveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Notification settings saved.'**
  String get notificationsSaveSuccess;

  /// No description provided for @notificationsSaveError.
  ///
  /// In en, this message translates to:
  /// **'Failed to save notification settings.'**
  String get notificationsSaveError;

  /// No description provided for @notificationsTestSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Send test message'**
  String get notificationsTestSectionTitle;

  /// No description provided for @notificationsTestSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'After any change, use the selected channel to send a test.'**
  String get notificationsTestSectionSubtitle;

  /// No description provided for @notificationsTestButton.
  ///
  /// In en, this message translates to:
  /// **'Test {channel}'**
  String notificationsTestButton(String channel);

  /// No description provided for @notificationsTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Test message sent via {channel}.'**
  String notificationsTestSuccess(String channel);

  /// No description provided for @notificationsTestError.
  ///
  /// In en, this message translates to:
  /// **'Failed to send test message via {channel}.'**
  String notificationsTestError(String channel);

  /// No description provided for @notificationsWebsocketInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Realtime in-app notifications'**
  String get notificationsWebsocketInfoTitle;

  /// No description provided for @notificationsWebsocketInfoDescription.
  ///
  /// In en, this message translates to:
  /// **'Users connect with a valid API key to the websocket endpoint {endpoint}. Web and mobile apps establish this connection automatically.'**
  String notificationsWebsocketInfoDescription(String endpoint);

  /// No description provided for @notificationsAdvancedSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced configuration (admin)'**
  String get notificationsAdvancedSectionTitle;

  /// No description provided for @notificationsAdvancedSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Telegram and SMS validation here. Requires system_settings access.'**
  String get notificationsAdvancedSectionSubtitle;

  /// No description provided for @notificationsAdvancedTelegramHeader.
  ///
  /// In en, this message translates to:
  /// **'Telegram bot setup'**
  String get notificationsAdvancedTelegramHeader;

  /// No description provided for @notificationsFieldTelegramToken.
  ///
  /// In en, this message translates to:
  /// **'Bot token'**
  String get notificationsFieldTelegramToken;

  /// No description provided for @notificationsFieldTelegramUsername.
  ///
  /// In en, this message translates to:
  /// **'Bot username'**
  String get notificationsFieldTelegramUsername;

  /// No description provided for @notificationsFieldTelegramWebhookSecret.
  ///
  /// In en, this message translates to:
  /// **'Webhook secret'**
  String get notificationsFieldTelegramWebhookSecret;

  /// No description provided for @notificationsFieldTelegramSecretHeader.
  ///
  /// In en, this message translates to:
  /// **'Secret header name'**
  String get notificationsFieldTelegramSecretHeader;

  /// No description provided for @notificationsFieldTelegramTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Issued by BotFather (format: 123456789:ABC...).'**
  String get notificationsFieldTelegramTokenHint;

  /// No description provided for @notificationsFieldTelegramWebhookSecretHint.
  ///
  /// In en, this message translates to:
  /// **'Optional; used to validate incoming requests.'**
  String get notificationsFieldTelegramWebhookSecretHint;

  /// No description provided for @notificationsAdvancedSmsHeader.
  ///
  /// In en, this message translates to:
  /// **'SMS gateway'**
  String get notificationsAdvancedSmsHeader;

  /// No description provided for @notificationsFieldSmsProvider.
  ///
  /// In en, this message translates to:
  /// **'Provider name'**
  String get notificationsFieldSmsProvider;

  /// No description provided for @notificationsFieldSmsApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get notificationsFieldSmsApiKey;

  /// No description provided for @notificationsFieldSmsApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Provided by your SMS vendor; rotate periodically.'**
  String get notificationsFieldSmsApiKeyHint;

  /// No description provided for @notificationsFieldSmsSender.
  ///
  /// In en, this message translates to:
  /// **'Sender/Number'**
  String get notificationsFieldSmsSender;

  /// No description provided for @notificationsFieldSmsSenderHint.
  ///
  /// In en, this message translates to:
  /// **'Exactly as registered in your vendor panel.'**
  String get notificationsFieldSmsSenderHint;

  /// No description provided for @notificationsProxySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Telegram proxy'**
  String get notificationsProxySectionTitle;

  /// No description provided for @notificationsProxySectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When servers are hosted inside Iran, enable the proxy to route Telegram traffic through an external relay.'**
  String get notificationsProxySectionSubtitle;

  /// No description provided for @notificationsProxyEnableLabel.
  ///
  /// In en, this message translates to:
  /// **'Enable Telegram proxy'**
  String get notificationsProxyEnableLabel;

  /// No description provided for @notificationsFieldTelegramProxyBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Proxy base URL'**
  String get notificationsFieldTelegramProxyBaseUrl;

  /// No description provided for @notificationsFieldTelegramProxyApiKey.
  ///
  /// In en, this message translates to:
  /// **'Proxy access key'**
  String get notificationsFieldTelegramProxyApiKey;

  /// No description provided for @notificationsAdvancedRestartHint.
  ///
  /// In en, this message translates to:
  /// **'After changes, restart the notification service during low traffic if needed.'**
  String get notificationsAdvancedRestartHint;

  /// No description provided for @notificationsAdvancedSave.
  ///
  /// In en, this message translates to:
  /// **'Save advanced settings'**
  String get notificationsAdvancedSave;

  /// No description provided for @notificationsAdvancedSaveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Advanced notification settings saved.'**
  String get notificationsAdvancedSaveSuccess;

  /// No description provided for @notificationsAdvancedSaveError.
  ///
  /// In en, this message translates to:
  /// **'Failed to save advanced notification settings.'**
  String get notificationsAdvancedSaveError;

  /// No description provided for @notificationsTelegramConnectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Connection status'**
  String get notificationsTelegramConnectionStatus;

  /// No description provided for @notificationsTelegramConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get notificationsTelegramConnected;

  /// No description provided for @notificationsTelegramNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notificationsTelegramNotConnected;

  /// No description provided for @notificationsTelegramConnectButton.
  ///
  /// In en, this message translates to:
  /// **'Connect Telegram'**
  String get notificationsTelegramConnectButton;

  /// No description provided for @notificationsTelegramDisconnectButton.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get notificationsTelegramDisconnectButton;

  /// No description provided for @notificationsTelegramConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get notificationsTelegramConnecting;

  /// No description provided for @notificationsTelegramConnectionWarning.
  ///
  /// In en, this message translates to:
  /// **'To enable Telegram notifications, please connect first.'**
  String get notificationsTelegramConnectionWarning;

  /// No description provided for @notificationsTelegramConnectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Telegram connection established successfully.'**
  String get notificationsTelegramConnectionSuccess;

  /// No description provided for @notificationsTelegramConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Failed to connect Telegram.'**
  String get notificationsTelegramConnectionError;

  /// No description provided for @notificationsTelegramDisconnectSuccess.
  ///
  /// In en, this message translates to:
  /// **'Telegram connection disconnected.'**
  String get notificationsTelegramDisconnectSuccess;

  /// No description provided for @notificationsTelegramDisconnectError.
  ///
  /// In en, this message translates to:
  /// **'Failed to disconnect Telegram.'**
  String get notificationsTelegramDisconnectError;

  /// No description provided for @notificationsTelegramLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'Connection link expired. Please create a new link.'**
  String get notificationsTelegramLinkExpired;

  /// No description provided for @notificationsTelegramLinkInstructions.
  ///
  /// In en, this message translates to:
  /// **'Click the link below or open the bot in Telegram and send /start {token}.'**
  String notificationsTelegramLinkInstructions(String token);

  /// No description provided for @notificationsTelegramLinkExpiresIn.
  ///
  /// In en, this message translates to:
  /// **'This link expires in {minutes} minutes.'**
  String notificationsTelegramLinkExpiresIn(int minutes);

  /// No description provided for @notificationsTelegramConnectedSince.
  ///
  /// In en, this message translates to:
  /// **'Connected since {date}'**
  String notificationsTelegramConnectedSince(String date);

  /// No description provided for @templateBuilderNew.
  ///
  /// In en, this message translates to:
  /// **'Visual Builder (New)'**
  String get templateBuilderNew;

  /// No description provided for @templateBuilderEdit.
  ///
  /// In en, this message translates to:
  /// **'Visual Builder (Edit)'**
  String get templateBuilderEdit;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @header.
  ///
  /// In en, this message translates to:
  /// **'Header'**
  String get header;

  /// No description provided for @body.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get body;

  /// No description provided for @footer.
  ///
  /// In en, this message translates to:
  /// **'Footer'**
  String get footer;

  /// No description provided for @globalCssOptional.
  ///
  /// In en, this message translates to:
  /// **'Global CSS (optional)'**
  String get globalCssOptional;

  /// No description provided for @previewPdf.
  ///
  /// In en, this message translates to:
  /// **'Preview PDF'**
  String get previewPdf;

  /// No description provided for @previewHtmlOutput.
  ///
  /// In en, this message translates to:
  /// **'Preview HTML (render output)'**
  String get previewHtmlOutput;

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get empty;

  /// No description provided for @createTemplateBuilder.
  ///
  /// In en, this message translates to:
  /// **'Create template (Builder)'**
  String get createTemplateBuilder;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @createdWithId.
  ///
  /// In en, this message translates to:
  /// **'Created (ID: {id})'**
  String createdWithId(int id);

  /// No description provided for @previewError.
  ///
  /// In en, this message translates to:
  /// **'Preview error: {error}'**
  String previewError(String error);

  /// No description provided for @createError.
  ///
  /// In en, this message translates to:
  /// **'Create error: {error}'**
  String createError(String error);

  /// No description provided for @templateCreatedWithId.
  ///
  /// In en, this message translates to:
  /// **'Template created (ID: {id})'**
  String templateCreatedWithId(int id);

  /// No description provided for @addText.
  ///
  /// In en, this message translates to:
  /// **'Add text'**
  String get addText;

  /// No description provided for @divider.
  ///
  /// In en, this message translates to:
  /// **'Divider'**
  String get divider;

  /// No description provided for @spacer.
  ///
  /// In en, this message translates to:
  /// **'Spacer'**
  String get spacer;

  /// No description provided for @addImage.
  ///
  /// In en, this message translates to:
  /// **'Add image'**
  String get addImage;

  /// No description provided for @addQr.
  ///
  /// In en, this message translates to:
  /// **'Add QR'**
  String get addQr;

  /// No description provided for @partyInfo.
  ///
  /// In en, this message translates to:
  /// **'Party info'**
  String get partyInfo;

  /// No description provided for @addTotals.
  ///
  /// In en, this message translates to:
  /// **'Add totals'**
  String get addTotals;

  /// No description provided for @stampSignature.
  ///
  /// In en, this message translates to:
  /// **'Stamp/Signature'**
  String get stampSignature;

  /// No description provided for @watermark.
  ///
  /// In en, this message translates to:
  /// **'Watermark'**
  String get watermark;

  /// No description provided for @addTable.
  ///
  /// In en, this message translates to:
  /// **'Add table'**
  String get addTable;

  /// No description provided for @textWithVariable.
  ///
  /// In en, this message translates to:
  /// **'Text (variable)'**
  String get textWithVariable;

  /// No description provided for @alignment.
  ///
  /// In en, this message translates to:
  /// **'Alignment'**
  String get alignment;

  /// No description provided for @left.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get left;

  /// No description provided for @center.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get center;

  /// No description provided for @right.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get right;

  /// No description provided for @showIfCondition.
  ///
  /// In en, this message translates to:
  /// **'Show if (condition)'**
  String get showIfCondition;

  /// No description provided for @blockType.
  ///
  /// In en, this message translates to:
  /// **'Block {type}'**
  String blockType(String type);

  /// No description provided for @pageSize.
  ///
  /// In en, this message translates to:
  /// **'Page size'**
  String get pageSize;

  /// No description provided for @orientation.
  ///
  /// In en, this message translates to:
  /// **'Orientation'**
  String get orientation;

  /// No description provided for @portrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get portrait;

  /// No description provided for @landscape.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get landscape;

  /// No description provided for @marginTop.
  ///
  /// In en, this message translates to:
  /// **'Top margin (mm)'**
  String get marginTop;

  /// No description provided for @marginRight.
  ///
  /// In en, this message translates to:
  /// **'Right (mm)'**
  String get marginRight;

  /// No description provided for @marginBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom (mm)'**
  String get marginBottom;

  /// No description provided for @marginLeft.
  ///
  /// In en, this message translates to:
  /// **'Left (mm)'**
  String get marginLeft;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @walletBusinessTitle.
  ///
  /// In en, this message translates to:
  /// **'Business wallet'**
  String get walletBusinessTitle;

  /// No description provided for @walletAvailableBalance.
  ///
  /// In en, this message translates to:
  /// **'Available balance'**
  String get walletAvailableBalance;

  /// No description provided for @walletPendingBalance.
  ///
  /// In en, this message translates to:
  /// **'Pending balance'**
  String get walletPendingBalance;

  /// No description provided for @walletRequestPayout.
  ///
  /// In en, this message translates to:
  /// **'Request payout'**
  String get walletRequestPayout;

  /// No description provided for @walletTopUp.
  ///
  /// In en, this message translates to:
  /// **'Top up'**
  String get walletTopUp;

  /// No description provided for @walletLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days report'**
  String get walletLast30Days;

  /// No description provided for @walletGrossIn.
  ///
  /// In en, this message translates to:
  /// **'Gross in'**
  String get walletGrossIn;

  /// No description provided for @walletFeesIn.
  ///
  /// In en, this message translates to:
  /// **'Fees in'**
  String get walletFeesIn;

  /// No description provided for @walletNetIn.
  ///
  /// In en, this message translates to:
  /// **'Net in'**
  String get walletNetIn;

  /// No description provided for @walletGrossOut.
  ///
  /// In en, this message translates to:
  /// **'Gross out'**
  String get walletGrossOut;

  /// No description provided for @walletFeesOut.
  ///
  /// In en, this message translates to:
  /// **'Fees out'**
  String get walletFeesOut;

  /// No description provided for @walletNetOut.
  ///
  /// In en, this message translates to:
  /// **'Net out'**
  String get walletNetOut;

  /// No description provided for @walletRecentTransactions.
  ///
  /// In en, this message translates to:
  /// **'Recent transactions'**
  String get walletRecentTransactions;

  /// No description provided for @walletTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get walletTransactions;

  /// No description provided for @moneyAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get moneyAmount;

  /// No description provided for @feeAmount.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get feeAmount;

  /// No description provided for @document.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get document;

  /// No description provided for @walletTypeTopUp.
  ///
  /// In en, this message translates to:
  /// **'Top up'**
  String get walletTypeTopUp;

  /// No description provided for @walletTypeCustomerPayment.
  ///
  /// In en, this message translates to:
  /// **'Customer payment'**
  String get walletTypeCustomerPayment;

  /// No description provided for @walletTypePayoutRequest.
  ///
  /// In en, this message translates to:
  /// **'Payout request'**
  String get walletTypePayoutRequest;

  /// No description provided for @walletTypePayoutSettlement.
  ///
  /// In en, this message translates to:
  /// **'Payout settlement'**
  String get walletTypePayoutSettlement;

  /// No description provided for @walletTypeRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get walletTypeRefund;

  /// No description provided for @walletTypeFee.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get walletTypeFee;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get statusProcessing;

  /// No description provided for @statusSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Succeeded'**
  String get statusSucceeded;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @statusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get statusCanceled;

  /// No description provided for @walletPayoutRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Payout request'**
  String get walletPayoutRequestTitle;

  /// No description provided for @walletSelectBankAccountHint.
  ///
  /// In en, this message translates to:
  /// **'Select bank account'**
  String get walletSelectBankAccountHint;

  /// No description provided for @walletPaymentGateway.
  ///
  /// In en, this message translates to:
  /// **'Payment gateway'**
  String get walletPaymentGateway;

  /// No description provided for @walletPayoutRequested.
  ///
  /// In en, this message translates to:
  /// **'Payout request submitted'**
  String get walletPayoutRequested;

  /// No description provided for @settingsWalletPayoutsAdmin.
  ///
  /// In en, this message translates to:
  /// **'Wallet payout management'**
  String get settingsWalletPayoutsAdmin;

  /// No description provided for @settingsWalletPayoutsAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'Review wallet payout requests and record bank settlement details'**
  String get settingsWalletPayoutsAdminDescription;

  /// No description provided for @walletPayoutsAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet payout requests'**
  String get walletPayoutsAdminTitle;

  /// No description provided for @walletPayoutsAdminSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor pending payout requests, review bank account details, and register settlement information after transfers are completed.'**
  String get walletPayoutsAdminSubtitle;

  /// No description provided for @walletPayoutsAdminEmpty.
  ///
  /// In en, this message translates to:
  /// **'No payout requests to show.'**
  String get walletPayoutsAdminEmpty;

  /// No description provided for @walletPayoutsAdminSettleDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Record settlement information'**
  String get walletPayoutsAdminSettleDialogTitle;

  /// No description provided for @walletPayoutsAdminSettleAction.
  ///
  /// In en, this message translates to:
  /// **'Record & settle'**
  String get walletPayoutsAdminSettleAction;

  /// No description provided for @walletPayoutsAdminSuccess.
  ///
  /// In en, this message translates to:
  /// **'Settlement information saved successfully.'**
  String get walletPayoutsAdminSuccess;

  /// No description provided for @walletPayoutsAdminFormRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get walletPayoutsAdminFormRequired;

  /// No description provided for @walletPayoutsAdminSettlementDate.
  ///
  /// In en, this message translates to:
  /// **'Settlement date'**
  String get walletPayoutsAdminSettlementDate;

  /// No description provided for @walletPayoutsAdminFeeHint.
  ///
  /// In en, this message translates to:
  /// **'If the bank charged a fee, enter the amount here'**
  String get walletPayoutsAdminFeeHint;

  /// No description provided for @bankTrackingCode.
  ///
  /// In en, this message translates to:
  /// **'Bank tracking code'**
  String get bankTrackingCode;

  /// No description provided for @walletTopUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Top up'**
  String get walletTopUpTitle;

  /// No description provided for @walletTopUpInitializing.
  ///
  /// In en, this message translates to:
  /// **'Submitting request and preparing payment gateway...'**
  String get walletTopUpInitializing;

  /// No description provided for @walletRedirectingToGateway.
  ///
  /// In en, this message translates to:
  /// **'Redirecting to payment gateway...'**
  String get walletRedirectingToGateway;

  /// No description provided for @walletTopUpNoPaymentLink.
  ///
  /// In en, this message translates to:
  /// **'Top-up request submitted, but no payment link received. Please try again later or check gateway settings.'**
  String get walletTopUpNoPaymentLink;

  /// No description provided for @walletGatewayInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Error connecting to gateway. Please check settings or try again later.'**
  String get walletGatewayInitFailed;

  /// No description provided for @walletInvalidGatewayConfig.
  ///
  /// In en, this message translates to:
  /// **'Gateway configuration is incomplete. Please check merchant ID and callback URL.'**
  String get walletInvalidGatewayConfig;

  /// No description provided for @walletGatewayDisabled.
  ///
  /// In en, this message translates to:
  /// **'This gateway is disabled.'**
  String get walletGatewayDisabled;

  /// No description provided for @walletGatewayNotFound.
  ///
  /// In en, this message translates to:
  /// **'Payment gateway not found.'**
  String get walletGatewayNotFound;

  /// No description provided for @walletGatewayServerError.
  ///
  /// In en, this message translates to:
  /// **'Server error connecting to gateway. Please try again later.'**
  String get walletGatewayServerError;

  /// No description provided for @walletOpenGatewayDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Redirect to payment gateway'**
  String get walletOpenGatewayDialogTitle;

  /// No description provided for @walletOpenGatewayDialogInstructions.
  ///
  /// In en, this message translates to:
  /// **'To continue, open the link below:'**
  String get walletOpenGatewayDialogInstructions;

  /// No description provided for @walletPaymentResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet payment result'**
  String get walletPaymentResultTitle;

  /// No description provided for @walletPaymentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment completed successfully'**
  String get walletPaymentSuccess;

  /// No description provided for @walletPaymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get walletPaymentFailed;

  /// No description provided for @transactionId.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID'**
  String get transactionId;

  /// No description provided for @paymentReference.
  ///
  /// In en, this message translates to:
  /// **'Payment reference'**
  String get paymentReference;

  /// No description provided for @walletStatusCheckErrorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error checking status:'**
  String get walletStatusCheckErrorPrefix;

  /// No description provided for @walletBackToWallet.
  ///
  /// In en, this message translates to:
  /// **'Back to wallet'**
  String get walletBackToWallet;

  /// No description provided for @walletSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet settings'**
  String get walletSettingsTitle;

  /// No description provided for @walletBaseCurrency.
  ///
  /// In en, this message translates to:
  /// **'Wallet base currency'**
  String get walletBaseCurrency;

  /// No description provided for @walletCurrencyRequired.
  ///
  /// In en, this message translates to:
  /// **'Currency selection is required'**
  String get walletCurrencyRequired;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @savedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully'**
  String get savedSuccessfully;

  /// No description provided for @currencyToman.
  ///
  /// In en, this message translates to:
  /// **'Toman'**
  String get currencyToman;

  /// No description provided for @creditSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer credit'**
  String get creditSettingsTitle;

  /// No description provided for @creditSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure credit limits and delay policies'**
  String get creditSettingsSubtitle;

  /// No description provided for @creditEnableTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable credit'**
  String get creditEnableTitle;

  /// No description provided for @creditEnableSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check customer credit limit during sales'**
  String get creditEnableSubtitle;

  /// No description provided for @creditDefaultLimit.
  ///
  /// In en, this message translates to:
  /// **'Default credit limit'**
  String get creditDefaultLimit;

  /// No description provided for @creditGraceDays.
  ///
  /// In en, this message translates to:
  /// **'Grace period (days)'**
  String get creditGraceDays;

  /// No description provided for @creditLateFeeRatePercent.
  ///
  /// In en, this message translates to:
  /// **'Late fee (%)'**
  String get creditLateFeeRatePercent;

  /// No description provided for @creditAutoBlockAfterDays.
  ///
  /// In en, this message translates to:
  /// **'Auto block after (days)'**
  String get creditAutoBlockAfterDays;

  /// No description provided for @creditStrategy.
  ///
  /// In en, this message translates to:
  /// **'Strategy'**
  String get creditStrategy;

  /// No description provided for @creditStrategySingleDefault.
  ///
  /// In en, this message translates to:
  /// **'Single default limit'**
  String get creditStrategySingleDefault;

  /// No description provided for @creditStrategyByGroup.
  ///
  /// In en, this message translates to:
  /// **'By group/role'**
  String get creditStrategyByGroup;

  /// No description provided for @creditStrategyPerUser.
  ///
  /// In en, this message translates to:
  /// **'Per-user limit'**
  String get creditStrategyPerUser;

  /// No description provided for @installmentPlansTitle.
  ///
  /// In en, this message translates to:
  /// **'Installment plans'**
  String get installmentPlansTitle;

  /// No description provided for @newInstallmentPlan.
  ///
  /// In en, this message translates to:
  /// **'New plan'**
  String get newInstallmentPlan;

  /// No description provided for @editPlan.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editPlan;

  /// No description provided for @deletePlan.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deletePlan;

  /// No description provided for @deletePlanConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete plan \"{name}\"?'**
  String deletePlanConfirm(String name);

  /// No description provided for @installmentPlanCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New installment plan'**
  String get installmentPlanCreateTitle;

  /// No description provided for @installmentPlanEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit installment plan'**
  String get installmentPlanEditTitle;

  /// No description provided for @planName.
  ///
  /// In en, this message translates to:
  /// **'Plan name'**
  String get planName;

  /// No description provided for @planMethod.
  ///
  /// In en, this message translates to:
  /// **'Calculation method'**
  String get planMethod;

  /// No description provided for @planMethodFlat.
  ///
  /// In en, this message translates to:
  /// **'Flat'**
  String get planMethodFlat;

  /// No description provided for @planMethodAmortized.
  ///
  /// In en, this message translates to:
  /// **'Amortized'**
  String get planMethodAmortized;

  /// No description provided for @planNumInstallments.
  ///
  /// In en, this message translates to:
  /// **'Number of installments'**
  String get planNumInstallments;

  /// No description provided for @planPeriodDays.
  ///
  /// In en, this message translates to:
  /// **'Interval (days)'**
  String get planPeriodDays;

  /// No description provided for @planDownPaymentPercent.
  ///
  /// In en, this message translates to:
  /// **'Down payment (%)'**
  String get planDownPaymentPercent;

  /// No description provided for @planInterestRate.
  ///
  /// In en, this message translates to:
  /// **'Total interest (%)'**
  String get planInterestRate;

  /// No description provided for @planLateFeeRate.
  ///
  /// In en, this message translates to:
  /// **'Late fee (%)'**
  String get planLateFeeRate;

  /// No description provided for @planIssueFee.
  ///
  /// In en, this message translates to:
  /// **'Issue fee (toman)'**
  String get planIssueFee;

  /// No description provided for @planIsActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get planIsActive;

  /// No description provided for @creditTabTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get creditTabTitle;

  /// No description provided for @creditPersonPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Person credit policy'**
  String get creditPersonPolicyTitle;

  /// No description provided for @creditCheckModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Credit check mode'**
  String get creditCheckModeLabel;

  /// No description provided for @creditCheckModeInherit.
  ///
  /// In en, this message translates to:
  /// **'Inherit from business settings'**
  String get creditCheckModeInherit;

  /// No description provided for @creditCheckModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Credit check enabled'**
  String get creditCheckModeEnabled;

  /// No description provided for @creditCheckModeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Credit check disabled'**
  String get creditCheckModeDisabled;

  /// No description provided for @creditLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Custom credit limit'**
  String get creditLimitLabel;

  /// No description provided for @creditLimitHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use business default'**
  String get creditLimitHint;

  /// No description provided for @creditTipText.
  ///
  /// In en, this message translates to:
  /// **'Leaving empty or choosing inherit uses the business default credit settings.'**
  String get creditTipText;

  /// No description provided for @selectInstallmentPlan.
  ///
  /// In en, this message translates to:
  /// **'Select installment plan'**
  String get selectInstallmentPlan;

  /// No description provided for @applyPlan.
  ///
  /// In en, this message translates to:
  /// **'Apply plan'**
  String get applyPlan;

  /// No description provided for @taxWorkspaceMenu.
  ///
  /// In en, this message translates to:
  /// **'Tax workspace'**
  String get taxWorkspaceMenu;

  /// No description provided for @taxWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Tax workspace'**
  String get taxWorkspaceTitle;

  /// No description provided for @taxWorkspaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review invoices before sending them to the tax system.'**
  String get taxWorkspaceSubtitle;

  /// No description provided for @taxIntegrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Tax system integration'**
  String get taxIntegrationTitle;

  /// No description provided for @taxIntegrationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage credentials and keys required to connect to the national tax platform.'**
  String get taxIntegrationSubtitle;

  /// No description provided for @taxSettingsTabConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection & basics'**
  String get taxSettingsTabConnection;

  /// No description provided for @taxSettingsTabKeys.
  ///
  /// In en, this message translates to:
  /// **'Keys & certificates'**
  String get taxSettingsTabKeys;

  /// No description provided for @taxSettingsTabDataQuality.
  ///
  /// In en, this message translates to:
  /// **'Data quality'**
  String get taxSettingsTabDataQuality;

  /// No description provided for @taxSettingsTabGuide.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get taxSettingsTabGuide;

  /// No description provided for @taxGuideIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'How to complete the Tax System setup?'**
  String get taxGuideIntroTitle;

  /// No description provided for @taxGuideIntroDescription.
  ///
  /// In en, this message translates to:
  /// **'This guide walks through the entire integration flow with the Iranian Taxpayers System in the new Hesabix version—from key generation to data quality checks and invoice submission.'**
  String get taxGuideIntroDescription;

  /// No description provided for @taxGuidePrereqTitle.
  ///
  /// In en, this message translates to:
  /// **'Prerequisites before you begin'**
  String get taxGuidePrereqTitle;

  /// No description provided for @taxGuidePrereqItem1.
  ///
  /// In en, this message translates to:
  /// **'Access to the “Tax System” menu as a business admin'**
  String get taxGuidePrereqItem1;

  /// No description provided for @taxGuidePrereqItem2.
  ///
  /// In en, this message translates to:
  /// **'Accurate registration data (national ID, economic code, corporate email)'**
  String get taxGuidePrereqItem2;

  /// No description provided for @taxGuidePrereqItem3.
  ///
  /// In en, this message translates to:
  /// **'Active access to your taxpayer workspace on my.tax.gov.ir'**
  String get taxGuidePrereqItem3;

  /// No description provided for @taxGuideStep1Title.
  ///
  /// In en, this message translates to:
  /// **'1) Generate keys inside Hesabix'**
  String get taxGuideStep1Title;

  /// No description provided for @taxGuideStep1Description.
  ///
  /// In en, this message translates to:
  /// **'Use the “Generate new keys” card to create the private/public key pair and CSR.'**
  String get taxGuideStep1Description;

  /// No description provided for @taxGuideStep1Bullet1.
  ///
  /// In en, this message translates to:
  /// **'Open the Keys & Certificates tab and tap the generate button.'**
  String get taxGuideStep1Bullet1;

  /// No description provided for @taxGuideStep1Bullet2.
  ///
  /// In en, this message translates to:
  /// **'Provide the exact taxpayer type and national ID.'**
  String get taxGuideStep1Bullet2;

  /// No description provided for @taxGuideStep1Bullet3.
  ///
  /// In en, this message translates to:
  /// **'Persian/English names and email must match the tax records.'**
  String get taxGuideStep1Bullet3;

  /// No description provided for @taxGuideStep2Title.
  ///
  /// In en, this message translates to:
  /// **'2) Download and store securely'**
  String get taxGuideStep2Title;

  /// No description provided for @taxGuideStep2Description.
  ///
  /// In en, this message translates to:
  /// **'Keys are shown only once; store them safely.'**
  String get taxGuideStep2Description;

  /// No description provided for @taxGuideStep2Bullet1.
  ///
  /// In en, this message translates to:
  /// **'Download the key files and keep them in offline, encrypted storage.'**
  String get taxGuideStep2Bullet1;

  /// No description provided for @taxGuideStep2Bullet2.
  ///
  /// In en, this message translates to:
  /// **'Never share the private key outside the tax integration team.'**
  String get taxGuideStep2Bullet2;

  /// No description provided for @taxGuideStep2Bullet3.
  ///
  /// In en, this message translates to:
  /// **'If the private key is lost you must regenerate the entire pair.'**
  String get taxGuideStep2Bullet3;

  /// No description provided for @taxGuideStep3Title.
  ///
  /// In en, this message translates to:
  /// **'3) Register the public key on my.tax.gov.ir'**
  String get taxGuideStep3Title;

  /// No description provided for @taxGuideStep3Description.
  ///
  /// In en, this message translates to:
  /// **'You must upload the Public Key to obtain the tax memory ID.'**
  String get taxGuideStep3Description;

  /// No description provided for @taxGuideStep3Bullet1.
  ///
  /// In en, this message translates to:
  /// **'Log into my.tax.gov.ir and navigate to Case Access > Enrollment > Tax Memory ID.'**
  String get taxGuideStep3Bullet1;

  /// No description provided for @taxGuideStep3Bullet2.
  ///
  /// In en, this message translates to:
  /// **'Select “By taxpayer” and upload the generated Public Key file.'**
  String get taxGuideStep3Bullet2;

  /// No description provided for @taxGuideStep3Bullet3.
  ///
  /// In en, this message translates to:
  /// **'Copy the issued memory ID and paste it back into Hesabix.'**
  String get taxGuideStep3Bullet3;

  /// No description provided for @taxGuideStep4Title.
  ///
  /// In en, this message translates to:
  /// **'4) Complete the connection form in Hesabix'**
  String get taxGuideStep4Title;

  /// No description provided for @taxGuideStep4Description.
  ///
  /// In en, this message translates to:
  /// **'Tax memory ID, economic code and private key are mandatory under the Connection tab.'**
  String get taxGuideStep4Description;

  /// No description provided for @taxGuideStep4Bullet1.
  ///
  /// In en, this message translates to:
  /// **'Enter the ID and economic code without extra spaces.'**
  String get taxGuideStep4Bullet1;

  /// No description provided for @taxGuideStep4Bullet2.
  ///
  /// In en, this message translates to:
  /// **'Paste the PEM private key and optionally store the Public Key and CSR.'**
  String get taxGuideStep4Bullet2;

  /// No description provided for @taxGuideStep4Bullet3.
  ///
  /// In en, this message translates to:
  /// **'Enable sandbox mode only for staging/testing environments.'**
  String get taxGuideStep4Bullet3;

  /// No description provided for @taxGuideStep5Title.
  ///
  /// In en, this message translates to:
  /// **'5) Request the intermediate certificate via CSR'**
  String get taxGuideStep5Title;

  /// No description provided for @taxGuideStep5Description.
  ///
  /// In en, this message translates to:
  /// **'Legal entities must submit the CSR to the national certificate authority.'**
  String get taxGuideStep5Description;

  /// No description provided for @taxGuideStep5Bullet1.
  ///
  /// In en, this message translates to:
  /// **'Visit gica.ir and choose the CSR-based request option.'**
  String get taxGuideStep5Bullet1;

  /// No description provided for @taxGuideStep5Bullet2.
  ///
  /// In en, this message translates to:
  /// **'Fill in the company details and pay the issuance fee.'**
  String get taxGuideStep5Bullet2;

  /// No description provided for @taxGuideStep5Bullet3.
  ///
  /// In en, this message translates to:
  /// **'After in-person verification upload the issued certificate into Hesabix.'**
  String get taxGuideStep5Bullet3;

  /// No description provided for @taxGuideStep6Title.
  ///
  /// In en, this message translates to:
  /// **'6) Assign product/service tax codes'**
  String get taxGuideStep6Title;

  /// No description provided for @taxGuideStep6Description.
  ///
  /// In en, this message translates to:
  /// **'Invoices will be rejected if items lack tax code and unit.'**
  String get taxGuideStep6Description;

  /// No description provided for @taxGuideStep6Bullet1.
  ///
  /// In en, this message translates to:
  /// **'Edit each item under Products & Services and add the 13-digit tax code.'**
  String get taxGuideStep6Bullet1;

  /// No description provided for @taxGuideStep6Bullet2.
  ///
  /// In en, this message translates to:
  /// **'Use the public code list from stuffid.tax.gov.ir or request dedicated codes.'**
  String get taxGuideStep6Bullet2;

  /// No description provided for @taxGuideStep6Bullet3.
  ///
  /// In en, this message translates to:
  /// **'Service codes can be obtained from portal.gs1-ir.org.'**
  String get taxGuideStep6Bullet3;

  /// No description provided for @taxGuideStep7Title.
  ///
  /// In en, this message translates to:
  /// **'7) Run data quality checks before submission'**
  String get taxGuideStep7Title;

  /// No description provided for @taxGuideStep7Description.
  ///
  /// In en, this message translates to:
  /// **'Review the Data Quality tab and the tax workspace before sending invoices.'**
  String get taxGuideStep7Description;

  /// No description provided for @taxGuideStep7Bullet1.
  ///
  /// In en, this message translates to:
  /// **'The Data Quality tab highlights missing fields for products, customers and invoices.'**
  String get taxGuideStep7Bullet1;

  /// No description provided for @taxGuideStep7Bullet2.
  ///
  /// In en, this message translates to:
  /// **'Add invoices to the tax workspace first and fix validation errors inline.'**
  String get taxGuideStep7Bullet2;

  /// No description provided for @taxGuideStep7Bullet3.
  ///
  /// In en, this message translates to:
  /// **'Send single or bulk invoices only after the checklist is green.'**
  String get taxGuideStep7Bullet3;

  /// No description provided for @taxGuideResourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts and resources'**
  String get taxGuideResourcesTitle;

  /// No description provided for @taxGuideResourcesWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Tax workspace: available under Sales > Tax Workspace.'**
  String get taxGuideResourcesWorkspace;

  /// No description provided for @taxGuideResourcesProducts.
  ///
  /// In en, this message translates to:
  /// **'Products & Services: update tax codes via the same menu or Excel import.'**
  String get taxGuideResourcesProducts;

  /// No description provided for @taxGuideResourcesSupport.
  ///
  /// In en, this message translates to:
  /// **'For integration issues review the Tax Settings logs or open a support ticket.'**
  String get taxGuideResourcesSupport;

  /// No description provided for @taxMemoryIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax memory ID'**
  String get taxMemoryIdLabel;

  /// No description provided for @taxEconomicCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Economic code'**
  String get taxEconomicCodeLabel;

  /// No description provided for @taxSandboxModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Sandbox mode'**
  String get taxSandboxModeLabel;

  /// No description provided for @taxSandboxModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When enabled, requests are sent to the sandbox environment.'**
  String get taxSandboxModeSubtitle;

  /// No description provided for @taxPrivateKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Private key (PEM)'**
  String get taxPrivateKeyLabel;

  /// No description provided for @taxPublicKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Public key (optional)'**
  String get taxPublicKeyLabel;

  /// No description provided for @taxCertificateLabel.
  ///
  /// In en, this message translates to:
  /// **'Digital certificate (optional)'**
  String get taxCertificateLabel;

  /// No description provided for @taxCertificateRequestLabel.
  ///
  /// In en, this message translates to:
  /// **'Certificate request (CSR)'**
  String get taxCertificateRequestLabel;

  /// No description provided for @taxGenerateKeys.
  ///
  /// In en, this message translates to:
  /// **'Generate new keys'**
  String get taxGenerateKeys;

  /// No description provided for @taxMemoryIdRequired.
  ///
  /// In en, this message translates to:
  /// **'Tax memory ID is required'**
  String get taxMemoryIdRequired;

  /// No description provided for @taxEconomicCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Economic code is required'**
  String get taxEconomicCodeRequired;

  /// No description provided for @taxPrivateKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Private key is required'**
  String get taxPrivateKeyRequired;

  /// No description provided for @taxKeysGenerated.
  ///
  /// In en, this message translates to:
  /// **'Keys generated successfully'**
  String get taxKeysGenerated;

  /// No description provided for @taxSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Tax integration settings saved'**
  String get taxSettingsSaved;

  /// No description provided for @taxLastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated: {date}'**
  String taxLastUpdated(String date);

  /// No description provided for @taxPersonTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Taxpayer type'**
  String get taxPersonTypeLabel;

  /// No description provided for @taxPersonTypeNatural.
  ///
  /// In en, this message translates to:
  /// **'Individual'**
  String get taxPersonTypeNatural;

  /// No description provided for @taxPersonTypeLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal entity'**
  String get taxPersonTypeLegal;

  /// No description provided for @taxNationalIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Taxpayer national ID'**
  String get taxNationalIdLabel;

  /// No description provided for @taxLegalNameFaLabel.
  ///
  /// In en, this message translates to:
  /// **'Persian company name'**
  String get taxLegalNameFaLabel;

  /// No description provided for @taxLegalNameEnLabel.
  ///
  /// In en, this message translates to:
  /// **'English company name'**
  String get taxLegalNameEnLabel;

  /// No description provided for @taxLegalEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Corporate email'**
  String get taxLegalEmailLabel;

  /// No description provided for @taxDataQualityTitle.
  ///
  /// In en, this message translates to:
  /// **'Data quality check'**
  String get taxDataQualityTitle;

  /// No description provided for @taxDataQualitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review missing tax data before submitting invoices.'**
  String get taxDataQualitySubtitle;

  /// No description provided for @taxDataQualityReload.
  ///
  /// In en, this message translates to:
  /// **'Refresh report'**
  String get taxDataQualityReload;

  /// No description provided for @taxDataQualityProductsHeader.
  ///
  /// In en, this message translates to:
  /// **'Products & services'**
  String get taxDataQualityProductsHeader;

  /// No description provided for @taxDataQualityPersonsHeader.
  ///
  /// In en, this message translates to:
  /// **'Persons & customers'**
  String get taxDataQualityPersonsHeader;

  /// No description provided for @taxDataQualityMissingTaxCode.
  ///
  /// In en, this message translates to:
  /// **'Items missing tax code'**
  String get taxDataQualityMissingTaxCode;

  /// No description provided for @taxDataQualityMissingTaxUnit.
  ///
  /// In en, this message translates to:
  /// **'Items missing tax unit'**
  String get taxDataQualityMissingTaxUnit;

  /// No description provided for @taxDataQualityMissingNationalId.
  ///
  /// In en, this message translates to:
  /// **'Persons missing national ID'**
  String get taxDataQualityMissingNationalId;

  /// No description provided for @taxDataQualityMissingEconomicId.
  ///
  /// In en, this message translates to:
  /// **'Persons missing economic ID'**
  String get taxDataQualityMissingEconomicId;

  /// No description provided for @taxDataQualitySamples.
  ///
  /// In en, this message translates to:
  /// **'Samples'**
  String get taxDataQualitySamples;

  /// No description provided for @taxDataQualityNoSamples.
  ///
  /// In en, this message translates to:
  /// **'No samples available.'**
  String get taxDataQualityNoSamples;

  /// No description provided for @taxDataQualityNoIssues.
  ///
  /// In en, this message translates to:
  /// **'All good! No pending data issues.'**
  String get taxDataQualityNoIssues;

  /// No description provided for @taxDataQualityNoData.
  ///
  /// In en, this message translates to:
  /// **'No report to display.'**
  String get taxDataQualityNoData;

  /// No description provided for @taxDataQualityFetchError.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch quality report: {error}'**
  String taxDataQualityFetchError(String error);

  /// No description provided for @taxDataQualityTaxCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax code'**
  String get taxDataQualityTaxCodeLabel;

  /// No description provided for @taxDataQualityTaxUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax unit'**
  String get taxDataQualityTaxUnitLabel;

  /// No description provided for @taxDataQualityNationalIdLabel.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get taxDataQualityNationalIdLabel;

  /// No description provided for @taxDataQualityEconomicIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Economic ID'**
  String get taxDataQualityEconomicIdLabel;

  /// No description provided for @taxValidationIssuesTitle.
  ///
  /// In en, this message translates to:
  /// **'Tax validation issues'**
  String get taxValidationIssuesTitle;

  /// No description provided for @taxValidationIssuesDescription.
  ///
  /// In en, this message translates to:
  /// **'Resolve the following items before sending invoices to the tax platform.'**
  String get taxValidationIssuesDescription;

  /// No description provided for @taxValidationIssuesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No issue details provided.'**
  String get taxValidationIssuesEmpty;

  /// No description provided for @taxValidationIssuesCategoryPerson.
  ///
  /// In en, this message translates to:
  /// **'Person Issues'**
  String get taxValidationIssuesCategoryPerson;

  /// No description provided for @taxValidationIssuesCategoryProduct.
  ///
  /// In en, this message translates to:
  /// **'Product/Service Issues'**
  String get taxValidationIssuesCategoryProduct;

  /// No description provided for @taxValidationIssuesCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other Issues'**
  String get taxValidationIssuesCategoryOther;

  /// No description provided for @taxValidationIssuesEditInvoice.
  ///
  /// In en, this message translates to:
  /// **'Edit Invoice'**
  String get taxValidationIssuesEditInvoice;

  /// No description provided for @taxValidationIssuesLineNumber.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get taxValidationIssuesLineNumber;

  /// No description provided for @taxAddToWorkspaceSingle.
  ///
  /// In en, this message translates to:
  /// **'Add to tax workspace'**
  String get taxAddToWorkspaceSingle;

  /// No description provided for @taxRemoveFromWorkspaceSingle.
  ///
  /// In en, this message translates to:
  /// **'Remove from tax workspace'**
  String get taxRemoveFromWorkspaceSingle;

  /// No description provided for @taxStatus.
  ///
  /// In en, this message translates to:
  /// **'Tax status'**
  String get taxStatus;

  /// No description provided for @taxInWorkspace.
  ///
  /// In en, this message translates to:
  /// **'In tax workspace'**
  String get taxInWorkspace;

  /// No description provided for @taxNotInWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Not in tax workspace'**
  String get taxNotInWorkspace;

  /// No description provided for @taxStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get taxStatusPending;

  /// No description provided for @taxStatusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get taxStatusSent;

  /// No description provided for @taxStatusFinalized.
  ///
  /// In en, this message translates to:
  /// **'Finalized'**
  String get taxStatusFinalized;

  /// No description provided for @taxStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get taxStatusFailed;

  /// No description provided for @installmentColumn.
  ///
  /// In en, this message translates to:
  /// **'Installment'**
  String get installmentColumn;

  /// No description provided for @documentDetailsInstallmentsTab.
  ///
  /// In en, this message translates to:
  /// **'Installments'**
  String get documentDetailsInstallmentsTab;

  /// No description provided for @documentDetailsInstallmentsEmptySchedule.
  ///
  /// In en, this message translates to:
  /// **'No installment rows were found for this invoice.'**
  String get documentDetailsInstallmentsEmptySchedule;

  /// No description provided for @documentDetailsInstallmentsAmountsNote.
  ///
  /// In en, this message translates to:
  /// **'All amounts are in {currency}.'**
  String documentDetailsInstallmentsAmountsNote(String currency);

  /// No description provided for @documentDetailsInstallmentReceive.
  ///
  /// In en, this message translates to:
  /// **'Record receipt'**
  String get documentDetailsInstallmentReceive;

  /// No description provided for @documentDetailsInstallmentReceiptTypeOnly.
  ///
  /// In en, this message translates to:
  /// **'Installment allocation is only available with a receipt for this invoice type.'**
  String get documentDetailsInstallmentReceiptTypeOnly;

  /// No description provided for @documentDetailsInstallmentDocCodeColumn.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get documentDetailsInstallmentDocCodeColumn;

  /// No description provided for @documentDetailsInstallmentPaymentDateColumn.
  ///
  /// In en, this message translates to:
  /// **'Document date'**
  String get documentDetailsInstallmentPaymentDateColumn;

  /// No description provided for @taxStatusNotSent.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get taxStatusNotSent;

  /// No description provided for @taxAddToWorkspaceNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This invoice cannot be added to the tax workspace.'**
  String get taxAddToWorkspaceNotAllowed;

  /// No description provided for @taxAddToWorkspaceDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add to tax workspace'**
  String get taxAddToWorkspaceDialogTitle;

  /// No description provided for @taxAddToWorkspaceDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Add invoice {code} to tax workspace?'**
  String taxAddToWorkspaceDialogMessage(String code);

  /// No description provided for @taxAddToWorkspaceSuccess.
  ///
  /// In en, this message translates to:
  /// **'Invoice {code} added to tax workspace.'**
  String taxAddToWorkspaceSuccess(String code);

  /// No description provided for @taxAddToWorkspaceError.
  ///
  /// In en, this message translates to:
  /// **'Failed to add to tax workspace.'**
  String get taxAddToWorkspaceError;

  /// No description provided for @taxAddToWorkspaceErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to add to tax workspace: {error}'**
  String taxAddToWorkspaceErrorWithMessage(String error);

  /// No description provided for @taxRemoveFromWorkspaceDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove from tax workspace'**
  String get taxRemoveFromWorkspaceDialogTitle;

  /// No description provided for @taxRemoveFromWorkspaceDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove invoice {code} from tax workspace?'**
  String taxRemoveFromWorkspaceDialogMessage(String code);

  /// No description provided for @taxRemoveFromWorkspaceSuccess.
  ///
  /// In en, this message translates to:
  /// **'Invoice removed from tax workspace.'**
  String get taxRemoveFromWorkspaceSuccess;

  /// No description provided for @taxRemoveFromWorkspaceError.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove from tax workspace.'**
  String get taxRemoveFromWorkspaceError;

  /// No description provided for @taxRemoveFromWorkspaceErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove from tax workspace: {error}'**
  String taxRemoveFromWorkspaceErrorWithMessage(String error);

  /// No description provided for @taxWorkspaceEmpty.
  ///
  /// In en, this message translates to:
  /// **'No invoices in tax workspace.'**
  String get taxWorkspaceEmpty;

  /// No description provided for @taxWorkspaceLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading tax workspace...'**
  String get taxWorkspaceLoading;

  /// No description provided for @taxWorkspaceError.
  ///
  /// In en, this message translates to:
  /// **'Error loading tax workspace.'**
  String get taxWorkspaceError;

  /// No description provided for @taxSendSingle.
  ///
  /// In en, this message translates to:
  /// **'Send to tax system'**
  String get taxSendSingle;

  /// No description provided for @taxTrackingCode.
  ///
  /// In en, this message translates to:
  /// **'Tracking code'**
  String get taxTrackingCode;

  /// No description provided for @taxLastSendAt.
  ///
  /// In en, this message translates to:
  /// **'Last sent at'**
  String get taxLastSendAt;

  /// No description provided for @taxSendSingleDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Send to tax system'**
  String get taxSendSingleDialogTitle;

  /// No description provided for @taxSendSingleDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Send invoice {code} to tax system?'**
  String taxSendSingleDialogMessage(String code);

  /// No description provided for @taxSendSuccess.
  ///
  /// In en, this message translates to:
  /// **'Sent to tax system.'**
  String get taxSendSuccess;

  /// No description provided for @taxSendErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to send to tax system: {error}'**
  String taxSendErrorWithMessage(String error);

  /// No description provided for @taxSendSelectedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Send selected invoices to tax system'**
  String get taxSendSelectedTooltip;

  /// No description provided for @taxSendSelectedButton.
  ///
  /// In en, this message translates to:
  /// **'Send selected ({count})'**
  String taxSendSelectedButton(int count);

  /// No description provided for @taxRemoveSelectedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove selected invoices from tax workspace'**
  String get taxRemoveSelectedTooltip;

  /// No description provided for @taxRemoveSelectedButton.
  ///
  /// In en, this message translates to:
  /// **'Remove selected ({count})'**
  String taxRemoveSelectedButton(int count);

  /// No description provided for @taxSendSelectedDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Send selected to tax system'**
  String get taxSendSelectedDialogTitle;

  /// No description provided for @taxSendSelectedDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Send {count} selected invoices to tax system?'**
  String taxSendSelectedDialogMessage(int count);

  /// No description provided for @taxSendSelectedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Selected invoices sent to tax system.'**
  String get taxSendSelectedSuccess;

  /// No description provided for @taxSendSelectedAllAlreadySent.
  ///
  /// In en, this message translates to:
  /// **'All selected invoices have already been sent.'**
  String get taxSendSelectedAllAlreadySent;

  /// No description provided for @taxSendSelectedSomeAlreadySent.
  ///
  /// In en, this message translates to:
  /// **'{skipped} invoice(s) have already been sent. Send {count} remaining invoice(s)?'**
  String taxSendSelectedSomeAlreadySent(int skipped, int count);

  /// No description provided for @taxSendSelectedErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to send selected invoices: {error}'**
  String taxSendSelectedErrorWithMessage(String error);

  /// No description provided for @taxSendSelectedPartialTitle.
  ///
  /// In en, this message translates to:
  /// **'{success} sent, {failed} failed'**
  String taxSendSelectedPartialTitle(int success, int failed);

  /// No description provided for @taxBatchFailedRow.
  ///
  /// In en, this message translates to:
  /// **'Invoice {id}'**
  String taxBatchFailedRow(String id);

  /// No description provided for @taxInquireSelectedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Inquire status for selected invoices'**
  String get taxInquireSelectedTooltip;

  /// No description provided for @taxInquireSelectedButton.
  ///
  /// In en, this message translates to:
  /// **'Inquire status ({count})'**
  String taxInquireSelectedButton(int count);

  /// No description provided for @taxInquireSelectedDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Inquire status'**
  String get taxInquireSelectedDialogTitle;

  /// No description provided for @taxInquireSelectedDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Inquire status for {count} selected invoices?'**
  String taxInquireSelectedDialogMessage(int count);

  /// No description provided for @taxInquireSelectedErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to inquire status: {error}'**
  String taxInquireSelectedErrorWithMessage(String error);

  /// No description provided for @taxInquiryResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Status inquiry result'**
  String get taxInquiryResultTitle;

  /// No description provided for @taxInquiryResultEmpty.
  ///
  /// In en, this message translates to:
  /// **'No results to display.'**
  String get taxInquiryResultEmpty;

  /// No description provided for @taxInquiryStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown status'**
  String get taxInquiryStatusUnknown;

  /// No description provided for @taxRemoveSelectedDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove selected from tax workspace'**
  String get taxRemoveSelectedDialogTitle;

  /// No description provided for @taxRemoveSelectedDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove {count} selected invoices from tax workspace?'**
  String taxRemoveSelectedDialogMessage(int count);

  /// No description provided for @taxRemoveSelectedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Selected invoices removed from tax workspace.'**
  String get taxRemoveSelectedSuccess;

  /// No description provided for @taxRemoveSelectedAllAlreadySent.
  ///
  /// In en, this message translates to:
  /// **'All selected invoices have already been sent and cannot be removed from workspace.'**
  String get taxRemoveSelectedAllAlreadySent;

  /// No description provided for @taxRemoveSelectedSomeAlreadySent.
  ///
  /// In en, this message translates to:
  /// **'{skipped} invoice(s) have already been sent. Remove {count} remaining invoice(s) from workspace?'**
  String taxRemoveSelectedSomeAlreadySent(int skipped, int count);

  /// No description provided for @taxRemoveSelectedErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove selected invoices: {error}'**
  String taxRemoveSelectedErrorWithMessage(String error);

  /// No description provided for @taxQuickActionSendAllPending.
  ///
  /// In en, this message translates to:
  /// **'Send all pending'**
  String get taxQuickActionSendAllPending;

  /// No description provided for @taxQuickActionInquireAllSent.
  ///
  /// In en, this message translates to:
  /// **'Inquire all sent'**
  String get taxQuickActionInquireAllSent;

  /// No description provided for @taxQuickActionRetryAllFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry all failed'**
  String get taxQuickActionRetryAllFailed;

  /// No description provided for @taxHelpTooltip.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get taxHelpTooltip;

  /// No description provided for @taxHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'Tax workspace guide'**
  String get taxHelpTitle;

  /// No description provided for @taxHelpSectionStatuses.
  ///
  /// In en, this message translates to:
  /// **'Invoice statuses'**
  String get taxHelpSectionStatuses;

  /// No description provided for @taxHelpStatusNotSent.
  ///
  /// In en, this message translates to:
  /// **'Not sent: Invoice has not been sent yet'**
  String get taxHelpStatusNotSent;

  /// No description provided for @taxHelpStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending: Currently being sent'**
  String get taxHelpStatusPending;

  /// No description provided for @taxHelpStatusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent: Sent and awaiting confirmation'**
  String get taxHelpStatusSent;

  /// No description provided for @taxHelpStatusFinalized.
  ///
  /// In en, this message translates to:
  /// **'Finalized: Finalized by the tax system'**
  String get taxHelpStatusFinalized;

  /// No description provided for @taxHelpStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: Sending failed'**
  String get taxHelpStatusFailed;

  /// No description provided for @taxHelpSectionQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get taxHelpSectionQuickActions;

  /// No description provided for @taxHelpQuickActionSendPending.
  ///
  /// In en, this message translates to:
  /// **'Send all pending: Send all pending invoices'**
  String get taxHelpQuickActionSendPending;

  /// No description provided for @taxHelpQuickActionInquireSent.
  ///
  /// In en, this message translates to:
  /// **'Inquire all sent: Check status of sent invoices'**
  String get taxHelpQuickActionInquireSent;

  /// No description provided for @taxHelpQuickActionRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry all failed: Retry failed invoices'**
  String get taxHelpQuickActionRetryFailed;

  /// No description provided for @taxHelpSectionImportantNotes.
  ///
  /// In en, this message translates to:
  /// **'Important notes'**
  String get taxHelpSectionImportantNotes;

  /// No description provided for @taxHelpNoteValidateBeforeSend.
  ///
  /// In en, this message translates to:
  /// **'Validate invoices before sending'**
  String get taxHelpNoteValidateBeforeSend;

  /// No description provided for @taxHelpNoteFailedInDLQ.
  ///
  /// In en, this message translates to:
  /// **'Failed invoices are stored in the error queue'**
  String get taxHelpNoteFailedInDLQ;

  /// No description provided for @taxHelpNoteTimeline.
  ///
  /// In en, this message translates to:
  /// **'You can view the change history of each invoice'**
  String get taxHelpNoteTimeline;

  /// No description provided for @taxHelpNoteExport.
  ///
  /// In en, this message translates to:
  /// **'You can export sending reports'**
  String get taxHelpNoteExport;

  /// No description provided for @taxOperationSuccess.
  ///
  /// In en, this message translates to:
  /// **'Operation completed successfully'**
  String get taxOperationSuccess;

  /// No description provided for @taxOperationError.
  ///
  /// In en, this message translates to:
  /// **'Error performing operation: {error}'**
  String taxOperationError(String error);

  /// No description provided for @taxSendingInvoices.
  ///
  /// In en, this message translates to:
  /// **'Sending invoices...'**
  String get taxSendingInvoices;

  /// No description provided for @taxSendingWithError.
  ///
  /// In en, this message translates to:
  /// **'Sending encountered an error'**
  String get taxSendingWithError;

  /// No description provided for @taxSentCountFailedCount.
  ///
  /// In en, this message translates to:
  /// **'Sent: {sentCount} | Failed: {failedCount}'**
  String taxSentCountFailedCount(int sentCount, int failedCount);

  /// No description provided for @taxProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get taxProcessing;

  /// No description provided for @taxUnknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get taxUnknownError;

  /// No description provided for @taxFailedInvoicesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} invoices encountered errors'**
  String taxFailedInvoicesCount(int count);

  /// No description provided for @taxRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get taxRetryFailed;

  /// No description provided for @taxErrorCategoryValidation.
  ///
  /// In en, this message translates to:
  /// **'Validation errors'**
  String get taxErrorCategoryValidation;

  /// No description provided for @taxErrorCategoryNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network errors'**
  String get taxErrorCategoryNetwork;

  /// No description provided for @taxErrorCategoryAccess.
  ///
  /// In en, this message translates to:
  /// **'Access errors'**
  String get taxErrorCategoryAccess;

  /// No description provided for @taxErrorCategoryStatus.
  ///
  /// In en, this message translates to:
  /// **'Status errors'**
  String get taxErrorCategoryStatus;

  /// No description provided for @taxErrorCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other errors'**
  String get taxErrorCategoryOther;

  /// No description provided for @taxErrorItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String taxErrorItemsCount(int count);

  /// No description provided for @taxInvoiceNumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice #{invoiceId}'**
  String taxInvoiceNumber(int invoiceId);

  /// No description provided for @taxCurrencyRial.
  ///
  /// In en, this message translates to:
  /// **'Rial'**
  String get taxCurrencyRial;

  /// No description provided for @documentMonetizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Packages and Tariffs'**
  String get documentMonetizationTitle;

  /// No description provided for @documentMonetizationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Packages, per-document fees and volume settlement'**
  String get documentMonetizationSubtitle;

  /// No description provided for @subscriptionPackages.
  ///
  /// In en, this message translates to:
  /// **'Subscription Packages'**
  String get subscriptionPackages;

  /// No description provided for @noActivePackage.
  ///
  /// In en, this message translates to:
  /// **'No active package has been registered for this business.'**
  String get noActivePackage;

  /// No description provided for @noPackageAvailable.
  ///
  /// In en, this message translates to:
  /// **'Currently no package is available for purchase.'**
  String get noPackageAvailable;

  /// No description provided for @activePackage.
  ///
  /// In en, this message translates to:
  /// **'Active Package'**
  String get activePackage;

  /// No description provided for @autoRenewActive.
  ///
  /// In en, this message translates to:
  /// **'Auto-renewal is active'**
  String get autoRenewActive;

  /// No description provided for @periodAmount.
  ///
  /// In en, this message translates to:
  /// **'Period Amount'**
  String get periodAmount;

  /// No description provided for @expiryDate.
  ///
  /// In en, this message translates to:
  /// **'Expiry Date'**
  String get expiryDate;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'month'**
  String get month;

  /// No description provided for @free.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get free;

  /// No description provided for @activate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// No description provided for @activating.
  ///
  /// In en, this message translates to:
  /// **'Activating...'**
  String get activating;

  /// No description provided for @activatePackage.
  ///
  /// In en, this message translates to:
  /// **'Activate {name}'**
  String activatePackage(String name);

  /// No description provided for @packageDuration.
  ///
  /// In en, this message translates to:
  /// **'Package Duration'**
  String get packageDuration;

  /// No description provided for @packagePrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get packagePrice;

  /// No description provided for @autoRenewAtEnd.
  ///
  /// In en, this message translates to:
  /// **'Auto-renewal at end of period'**
  String get autoRenewAtEnd;

  /// No description provided for @confirmAndActivate.
  ///
  /// In en, this message translates to:
  /// **'Confirm and Activate'**
  String get confirmAndActivate;

  /// No description provided for @invalidPackageId.
  ///
  /// In en, this message translates to:
  /// **'Invalid package ID'**
  String get invalidPackageId;

  /// No description provided for @packageActivatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Package activated successfully'**
  String get packageActivatedSuccess;

  /// No description provided for @packageActivationError.
  ///
  /// In en, this message translates to:
  /// **'Package activation failed'**
  String get packageActivationError;

  /// No description provided for @activePolicies.
  ///
  /// In en, this message translates to:
  /// **'Active Policies'**
  String get activePolicies;

  /// No description provided for @noPolicyDefined.
  ///
  /// In en, this message translates to:
  /// **'No policy has been defined'**
  String get noPolicyDefined;

  /// No description provided for @noInvoice.
  ///
  /// In en, this message translates to:
  /// **'No invoice exists'**
  String get noInvoice;

  /// No description provided for @chargeType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get chargeType;

  /// No description provided for @pay.
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get pay;

  /// No description provided for @paymentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment completed'**
  String get paymentSuccess;

  /// No description provided for @paymentError.
  ///
  /// In en, this message translates to:
  /// **'Payment failed'**
  String get paymentError;

  /// No description provided for @finalizeVolume.
  ///
  /// In en, this message translates to:
  /// **'Finalize Volume Period'**
  String get finalizeVolume;

  /// No description provided for @volumeFinalized.
  ///
  /// In en, this message translates to:
  /// **'Volume calculations finalized'**
  String get volumeFinalized;

  /// No description provided for @volumeFinalizeError.
  ///
  /// In en, this message translates to:
  /// **'Volume period calculation failed'**
  String get volumeFinalizeError;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get statusExpired;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusAwaitingPayment.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Payment'**
  String get statusAwaitingPayment;

  /// No description provided for @statusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// No description provided for @statusInvoiced.
  ///
  /// In en, this message translates to:
  /// **'Invoiced'**
  String get statusInvoiced;

  /// No description provided for @chargeTypePerDocument.
  ///
  /// In en, this message translates to:
  /// **'Per Document'**
  String get chargeTypePerDocument;

  /// No description provided for @chargeTypeVolumeCycle.
  ///
  /// In en, this message translates to:
  /// **'Volume Cycle'**
  String get chargeTypeVolumeCycle;

  /// No description provided for @chargeTypeSubscriptionFee.
  ///
  /// In en, this message translates to:
  /// **'Subscription Fee'**
  String get chargeTypeSubscriptionFee;

  /// No description provided for @policyTypeFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get policyTypeFree;

  /// No description provided for @policyTypeSubscription.
  ///
  /// In en, this message translates to:
  /// **'Unlimited Package'**
  String get policyTypeSubscription;

  /// No description provided for @policyTypeVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get policyTypeVolume;

  /// No description provided for @policyTypePerDocument.
  ///
  /// In en, this message translates to:
  /// **'Per Document'**
  String get policyTypePerDocument;

  /// No description provided for @policyTypeHybrid.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get policyTypeHybrid;

  /// No description provided for @warehouseDocuments.
  ///
  /// In en, this message translates to:
  /// **'Warehouse Documents'**
  String get warehouseDocuments;

  /// No description provided for @relatedWarehouseDocuments.
  ///
  /// In en, this message translates to:
  /// **'Related warehouse documents'**
  String get relatedWarehouseDocuments;

  /// No description provided for @warehouseDocumentPostSuccess.
  ///
  /// In en, this message translates to:
  /// **'Warehouse document posted.'**
  String get warehouseDocumentPostSuccess;

  /// No description provided for @warehouseDocumentPostFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not post warehouse document: {error}'**
  String warehouseDocumentPostFailed(String error);

  /// No description provided for @warehouseDocument.
  ///
  /// In en, this message translates to:
  /// **'Warehouse Document'**
  String get warehouseDocument;

  /// No description provided for @warehouseDocumentCode.
  ///
  /// In en, this message translates to:
  /// **'Document Code'**
  String get warehouseDocumentCode;

  /// No description provided for @warehouseDocumentType.
  ///
  /// In en, this message translates to:
  /// **'Document Type'**
  String get warehouseDocumentType;

  /// No description provided for @warehouseDocumentStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get warehouseDocumentStatus;

  /// No description provided for @warehouseDocumentDate.
  ///
  /// In en, this message translates to:
  /// **'Document Date'**
  String get warehouseDocumentDate;

  /// No description provided for @warehouseDocumentFrom.
  ///
  /// In en, this message translates to:
  /// **'From Warehouse'**
  String get warehouseDocumentFrom;

  /// No description provided for @warehouseDocumentTo.
  ///
  /// In en, this message translates to:
  /// **'To Warehouse'**
  String get warehouseDocumentTo;

  /// No description provided for @warehouseDocumentTotalQuantity.
  ///
  /// In en, this message translates to:
  /// **'Total Quantity'**
  String get warehouseDocumentTotalQuantity;

  /// No description provided for @warehouseDocumentTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get warehouseDocumentTotalAmount;

  /// No description provided for @docTypeReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get docTypeReceipt;

  /// No description provided for @docTypeIssue.
  ///
  /// In en, this message translates to:
  /// **'Issue'**
  String get docTypeIssue;

  /// No description provided for @docTypeTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get docTypeTransfer;

  /// No description provided for @docTypeAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get docTypeAdjustment;

  /// No description provided for @docTypeProductionIn.
  ///
  /// In en, this message translates to:
  /// **'Production In'**
  String get docTypeProductionIn;

  /// No description provided for @docTypeProductionOut.
  ///
  /// In en, this message translates to:
  /// **'Production Out'**
  String get docTypeProductionOut;

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get statusDraft;

  /// No description provided for @statusPosted.
  ///
  /// In en, this message translates to:
  /// **'Posted'**
  String get statusPosted;

  /// No description provided for @createWarehouseDocument.
  ///
  /// In en, this message translates to:
  /// **'Create Manual Document'**
  String get createWarehouseDocument;

  /// No description provided for @postWarehouseDocument.
  ///
  /// In en, this message translates to:
  /// **'Post Document'**
  String get postWarehouseDocument;

  /// No description provided for @cancelWarehouseDocument.
  ///
  /// In en, this message translates to:
  /// **'Cancel Document'**
  String get cancelWarehouseDocument;

  /// No description provided for @deleteWarehouseDocument.
  ///
  /// In en, this message translates to:
  /// **'Delete Document'**
  String get deleteWarehouseDocument;

  /// No description provided for @viewWarehouseDocument.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewWarehouseDocument;

  /// No description provided for @printWarehouseDocument.
  ///
  /// In en, this message translates to:
  /// **'Print PDF'**
  String get printWarehouseDocument;

  /// No description provided for @warehousePostalLabelTooltip.
  ///
  /// In en, this message translates to:
  /// **'Postal consignment label (PDF)'**
  String get warehousePostalLabelTooltip;

  /// No description provided for @warehousePostalLabelDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Postal consignment label'**
  String get warehousePostalLabelDialogTitle;

  /// No description provided for @warehousePostalLabelPaperSize.
  ///
  /// In en, this message translates to:
  /// **'Paper size'**
  String get warehousePostalLabelPaperSize;

  /// No description provided for @warehousePostalLabelOrientation.
  ///
  /// In en, this message translates to:
  /// **'Orientation'**
  String get warehousePostalLabelOrientation;

  /// No description provided for @warehousePostalLabelPortrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get warehousePostalLabelPortrait;

  /// No description provided for @warehousePostalLabelLandscape.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get warehousePostalLabelLandscape;

  /// No description provided for @warehousePostalLabelCustomPaperHint.
  ///
  /// In en, this message translates to:
  /// **'Custom size (max 32 chars, e.g. 120mm 80mm)'**
  String get warehousePostalLabelCustomPaperHint;

  /// No description provided for @warehousePostalLabelTemplate.
  ///
  /// In en, this message translates to:
  /// **'Print template'**
  String get warehousePostalLabelTemplate;

  /// No description provided for @warehousePostalLabelNoTemplate.
  ///
  /// In en, this message translates to:
  /// **'— System default —'**
  String get warehousePostalLabelNoTemplate;

  /// No description provided for @warehousePostalLabelFieldsSection.
  ///
  /// In en, this message translates to:
  /// **'Fields on label'**
  String get warehousePostalLabelFieldsSection;

  /// No description provided for @warehousePostalLabelShowSender.
  ///
  /// In en, this message translates to:
  /// **'Sender'**
  String get warehousePostalLabelShowSender;

  /// No description provided for @warehousePostalLabelShowReceiver.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get warehousePostalLabelShowReceiver;

  /// No description provided for @warehousePostalLabelShowWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Warehouse names'**
  String get warehousePostalLabelShowWarehouse;

  /// No description provided for @warehousePostalLabelShowLines.
  ///
  /// In en, this message translates to:
  /// **'Items summary'**
  String get warehousePostalLabelShowLines;

  /// No description provided for @warehousePostalLabelShowDelivery.
  ///
  /// In en, this message translates to:
  /// **'Shipping / notes'**
  String get warehousePostalLabelShowDelivery;

  /// No description provided for @warehousePostalLabelShowTracking.
  ///
  /// In en, this message translates to:
  /// **'Tracking number'**
  String get warehousePostalLabelShowTracking;

  /// No description provided for @warehousePostalLabelShowSource.
  ///
  /// In en, this message translates to:
  /// **'Source document code'**
  String get warehousePostalLabelShowSource;

  /// No description provided for @warehousePostalLabelDownload.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get warehousePostalLabelDownload;

  /// No description provided for @applicationName.
  ///
  /// In en, this message translates to:
  /// **'Application Name'**
  String get applicationName;

  /// No description provided for @applicationVersion.
  ///
  /// In en, this message translates to:
  /// **'Application Version'**
  String get applicationVersion;

  /// No description provided for @defaultLanguage.
  ///
  /// In en, this message translates to:
  /// **'Default Language'**
  String get defaultLanguage;

  /// No description provided for @defaultTheme.
  ///
  /// In en, this message translates to:
  /// **'Default Theme'**
  String get defaultTheme;

  /// No description provided for @enableUserRegistration.
  ///
  /// In en, this message translates to:
  /// **'Enable User Registration'**
  String get enableUserRegistration;

  /// No description provided for @enableEmailVerification.
  ///
  /// In en, this message translates to:
  /// **'Enable Email Verification'**
  String get enableEmailVerification;

  /// No description provided for @sessionTimeout.
  ///
  /// In en, this message translates to:
  /// **'Session Timeout'**
  String get sessionTimeout;

  /// No description provided for @sessionTimeoutMinutes.
  ///
  /// In en, this message translates to:
  /// **'Session Timeout (minutes)'**
  String get sessionTimeoutMinutes;

  /// No description provided for @maxFileSize.
  ///
  /// In en, this message translates to:
  /// **'Max File Size'**
  String get maxFileSize;

  /// No description provided for @maxFileSizeMB.
  ///
  /// In en, this message translates to:
  /// **'Max File Size (MB)'**
  String get maxFileSizeMB;

  /// No description provided for @maxUsers.
  ///
  /// In en, this message translates to:
  /// **'Max Users'**
  String get maxUsers;

  /// No description provided for @maintenanceMode.
  ///
  /// In en, this message translates to:
  /// **'Maintenance Mode'**
  String get maintenanceMode;

  /// No description provided for @supportTicketsUserSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'User support tickets'**
  String get supportTicketsUserSectionTitle;

  /// No description provided for @supportTicketsAllowUsersLabel.
  ///
  /// In en, this message translates to:
  /// **'Allow normal users to create and view tickets'**
  String get supportTicketsAllowUsersLabel;

  /// No description provided for @supportTicketsAllowUsersDescription.
  ///
  /// In en, this message translates to:
  /// **'When disabled, the message below is shown to users. Support operators still have access.'**
  String get supportTicketsAllowUsersDescription;

  /// No description provided for @supportTicketsDisabledNoticeLabel.
  ///
  /// In en, this message translates to:
  /// **'Notice text for users (when disabled)'**
  String get supportTicketsDisabledNoticeLabel;

  /// No description provided for @supportTicketsDisabledNoticeHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to use the built-in default message.'**
  String get supportTicketsDisabledNoticeHint;

  /// No description provided for @supportTicketsUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Support tickets are temporarily unavailable.'**
  String get supportTicketsUnavailableBody;

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @errorLoadingSettings.
  ///
  /// In en, this message translates to:
  /// **'Error loading settings'**
  String get errorLoadingSettings;

  /// No description provided for @errorSavingSettings.
  ///
  /// In en, this message translates to:
  /// **'Error saving settings'**
  String get errorSavingSettings;

  /// No description provided for @settingsSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Settings saved successfully'**
  String get settingsSavedSuccessfully;

  /// No description provided for @persian.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get persian;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @zeroMeansUnlimited.
  ///
  /// In en, this message translates to:
  /// **'0 = Unlimited'**
  String get zeroMeansUnlimited;

  /// No description provided for @otpLogin.
  ///
  /// In en, this message translates to:
  /// **'OTP Login'**
  String get otpLogin;

  /// No description provided for @otpLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Login with OTP'**
  String get otpLoginTitle;

  /// No description provided for @otpLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Login code will be sent to your email, mobile number or Telegram'**
  String get otpLoginSubtitle;

  /// No description provided for @otpLoginIdentifierHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your email or mobile number'**
  String get otpLoginIdentifierHint;

  /// No description provided for @otpLoginIdentifierRequired.
  ///
  /// In en, this message translates to:
  /// **'Email or mobile number is required'**
  String get otpLoginIdentifierRequired;

  /// No description provided for @otpCodeSent.
  ///
  /// In en, this message translates to:
  /// **'Code sent'**
  String get otpCodeSent;

  /// No description provided for @otpChannelSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Receive code via:'**
  String get otpChannelSelectionTitle;

  /// No description provided for @otpChannelSms.
  ///
  /// In en, this message translates to:
  /// **'SMS'**
  String get otpChannelSms;

  /// No description provided for @otpChannelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get otpChannelEmail;

  /// No description provided for @otpChannelTelegram.
  ///
  /// In en, this message translates to:
  /// **'Telegram'**
  String get otpChannelTelegram;

  /// No description provided for @otpSendCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Send login code'**
  String get otpSendCodeButton;

  /// No description provided for @otpChangeChannelTitle.
  ///
  /// In en, this message translates to:
  /// **'Change delivery method:'**
  String get otpChangeChannelTitle;

  /// No description provided for @otpChangeIdentifier.
  ///
  /// In en, this message translates to:
  /// **'Change identifier'**
  String get otpChangeIdentifier;

  /// No description provided for @otpSelectChannelError.
  ///
  /// In en, this message translates to:
  /// **'Please select a delivery channel'**
  String get otpSelectChannelError;

  /// No description provided for @otpCaptchaError.
  ///
  /// In en, this message translates to:
  /// **'Error loading captcha'**
  String get otpCaptchaError;

  /// No description provided for @otpCodeSentMessage.
  ///
  /// In en, this message translates to:
  /// **'Login code sent to your {channel}'**
  String otpCodeSentMessage(String channel);

  /// No description provided for @otpCodeResentMessage.
  ///
  /// In en, this message translates to:
  /// **'Login code resent'**
  String get otpCodeResentMessage;

  /// No description provided for @otpSendError.
  ///
  /// In en, this message translates to:
  /// **'Error sending login code'**
  String get otpSendError;

  /// No description provided for @otpEnterCaptchaError.
  ///
  /// In en, this message translates to:
  /// **'Please enter captcha code'**
  String get otpEnterCaptchaError;

  /// No description provided for @workflows.
  ///
  /// In en, this message translates to:
  /// **'Automations'**
  String get workflows;

  /// No description provided for @workflow.
  ///
  /// In en, this message translates to:
  /// **'Automation'**
  String get workflow;

  /// No description provided for @newWorkflow.
  ///
  /// In en, this message translates to:
  /// **'New Workflow'**
  String get newWorkflow;

  /// No description provided for @editWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Edit Workflow'**
  String get editWorkflow;

  /// No description provided for @workflowSaved.
  ///
  /// In en, this message translates to:
  /// **'Workflow saved'**
  String get workflowSaved;

  /// No description provided for @workflowDeleted.
  ///
  /// In en, this message translates to:
  /// **'Workflow deleted'**
  String get workflowDeleted;

  /// No description provided for @workflowDuplicated.
  ///
  /// In en, this message translates to:
  /// **'Workflow duplicated'**
  String get workflowDuplicated;

  /// No description provided for @workflowCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get workflowCopy;

  /// No description provided for @workflowUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get workflowUndo;

  /// No description provided for @workflowSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get workflowSave;

  /// No description provided for @workflowCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get workflowCancel;

  /// No description provided for @workflowClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get workflowClose;

  /// No description provided for @workflowValidationError.
  ///
  /// In en, this message translates to:
  /// **'Validation Error'**
  String get workflowValidationError;

  /// No description provided for @workflowErrorLoading.
  ///
  /// In en, this message translates to:
  /// **'Error loading data'**
  String get workflowErrorLoading;

  /// No description provided for @workflowErrorSaving.
  ///
  /// In en, this message translates to:
  /// **'Error saving'**
  String get workflowErrorSaving;

  /// No description provided for @workflowStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Workflow status updated'**
  String get workflowStatusUpdated;

  /// No description provided for @workflowExecuted.
  ///
  /// In en, this message translates to:
  /// **'Workflow executed'**
  String get workflowExecuted;

  /// No description provided for @workflowErrorExecuting.
  ///
  /// In en, this message translates to:
  /// **'Error executing workflow'**
  String get workflowErrorExecuting;

  /// No description provided for @workflowNoAccess.
  ///
  /// In en, this message translates to:
  /// **'You do not have access to workflows.'**
  String get workflowNoAccess;

  /// No description provided for @workflowNoAccessEditor.
  ///
  /// In en, this message translates to:
  /// **'You do not have access to workflow editor.'**
  String get workflowNoAccessEditor;

  /// No description provided for @workflowNoWorkflows.
  ///
  /// In en, this message translates to:
  /// **'No workflows yet.'**
  String get workflowNoWorkflows;

  /// No description provided for @workflowCreateFirst.
  ///
  /// In en, this message translates to:
  /// **'Use the button below to create your first automation.'**
  String get workflowCreateFirst;

  /// No description provided for @workflowCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Workflow'**
  String get workflowCreate;

  /// No description provided for @workflowRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get workflowRefresh;

  /// No description provided for @workflowRunNow.
  ///
  /// In en, this message translates to:
  /// **'Run now'**
  String get workflowRunNow;

  /// No description provided for @workflowTestRun.
  ///
  /// In en, this message translates to:
  /// **'Test run (live status)'**
  String get workflowTestRun;

  /// No description provided for @workflowFixValidationBeforeTestRun.
  ///
  /// In en, this message translates to:
  /// **'Fix validation errors on the canvas before running a test.'**
  String get workflowFixValidationBeforeTestRun;

  /// No description provided for @workflowExecutionHistory.
  ///
  /// In en, this message translates to:
  /// **'Execution history'**
  String get workflowExecutionHistory;

  /// No description provided for @workflowHistoryClearCanvasHighlight.
  ///
  /// In en, this message translates to:
  /// **'Clear highlight on canvas'**
  String get workflowHistoryClearCanvasHighlight;

  /// No description provided for @workflowEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get workflowEdit;

  /// No description provided for @workflowLastUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last update'**
  String get workflowLastUpdate;

  /// No description provided for @workflowAvailableTriggers.
  ///
  /// In en, this message translates to:
  /// **'Available triggers'**
  String get workflowAvailableTriggers;

  /// No description provided for @workflowAvailableActions.
  ///
  /// In en, this message translates to:
  /// **'Available actions'**
  String get workflowAvailableActions;

  /// No description provided for @workflowFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get workflowFilters;

  /// No description provided for @workflowStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get workflowStatus;

  /// No description provided for @workflowSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get workflowSearch;

  /// No description provided for @workflowAllStatuses.
  ///
  /// In en, this message translates to:
  /// **'All statuses'**
  String get workflowAllStatuses;

  /// No description provided for @workflowOnlyActive.
  ///
  /// In en, this message translates to:
  /// **'Only active'**
  String get workflowOnlyActive;

  /// No description provided for @workflowInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get workflowInactive;

  /// No description provided for @workflowDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get workflowDraft;

  /// No description provided for @workflowActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get workflowActive;

  /// No description provided for @workflowNodeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Node deleted'**
  String get workflowNodeDeleted;

  /// No description provided for @workflowNodeDuplicated.
  ///
  /// In en, this message translates to:
  /// **'Node duplicated'**
  String get workflowNodeDuplicated;

  /// No description provided for @workflowNodeSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get workflowNodeSettings;

  /// No description provided for @workflowNodeNoSettings.
  ///
  /// In en, this message translates to:
  /// **'This node does not require any special settings.'**
  String get workflowNodeNoSettings;

  /// No description provided for @workflowNodeFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get workflowNodeFieldRequired;

  /// No description provided for @workflowNodeArrayType.
  ///
  /// In en, this message translates to:
  /// **'Array'**
  String get workflowNodeArrayType;

  /// No description provided for @workflowNodeObjectType.
  ///
  /// In en, this message translates to:
  /// **'Object'**
  String get workflowNodeObjectType;

  /// No description provided for @workflowConfigUsePreviousNode.
  ///
  /// In en, this message translates to:
  /// **'Use previous node'**
  String get workflowConfigUsePreviousNode;

  /// No description provided for @workflowConfigSelectFromNodes.
  ///
  /// In en, this message translates to:
  /// **'Select from previous nodes'**
  String get workflowConfigSelectFromNodes;

  /// No description provided for @workflowConfigValueUsesNode.
  ///
  /// In en, this message translates to:
  /// **'This value uses a previous node'**
  String get workflowConfigValueUsesNode;

  /// No description provided for @workflowConfigSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get workflowConfigSelectDate;

  /// No description provided for @workflowConfigToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get workflowConfigToday;

  /// No description provided for @workflowConfigDateHelper.
  ///
  /// In en, this message translates to:
  /// **'Select date (ISO: YYYY-MM-DD)'**
  String get workflowConfigDateHelper;

  /// No description provided for @workflowConfigNoNodesToSelect.
  ///
  /// In en, this message translates to:
  /// **'No nodes available to select'**
  String get workflowConfigNoNodesToSelect;

  /// No description provided for @workflowConfigNoTelegramUsers.
  ///
  /// In en, this message translates to:
  /// **'No users connected to Telegram bot. Please connect users first.'**
  String get workflowConfigNoTelegramUsers;

  /// No description provided for @workflowConfigNoBaleUsers.
  ///
  /// In en, this message translates to:
  /// **'No users connected to Bale bot. Please connect users first.'**
  String get workflowConfigNoBaleUsers;

  /// No description provided for @workflowConfigOwner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get workflowConfigOwner;

  /// No description provided for @workflowConfigSearchSelectPerson.
  ///
  /// In en, this message translates to:
  /// **'Search and select person'**
  String get workflowConfigSearchSelectPerson;

  /// No description provided for @workflowConfigPersonIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Person ID'**
  String get workflowConfigPersonIdLabel;

  /// No description provided for @workflowConfigPersonIdHelper.
  ///
  /// In en, this message translates to:
  /// **'Enter ID or use previous node: \$node_id.person_id'**
  String get workflowConfigPersonIdHelper;

  /// No description provided for @workflowConfigSearchSelectProduct.
  ///
  /// In en, this message translates to:
  /// **'Search and select product/service'**
  String get workflowConfigSearchSelectProduct;

  /// No description provided for @workflowConfigProductIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Product ID'**
  String get workflowConfigProductIdLabel;

  /// No description provided for @workflowConfigProductIdHelper.
  ///
  /// In en, this message translates to:
  /// **'Product/service ID'**
  String get workflowConfigProductIdHelper;

  /// No description provided for @workflowConfigType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get workflowConfigType;

  /// No description provided for @workflowConfigPercent.
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get workflowConfigPercent;

  /// No description provided for @workflowConfigFixedAmount.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get workflowConfigFixedAmount;

  /// No description provided for @workflowConfigDiscountPercent.
  ///
  /// In en, this message translates to:
  /// **'Discount %'**
  String get workflowConfigDiscountPercent;

  /// No description provided for @workflowConfigDiscountAmount.
  ///
  /// In en, this message translates to:
  /// **'Discount amount'**
  String get workflowConfigDiscountAmount;

  /// No description provided for @workflowConfigItemN.
  ///
  /// In en, this message translates to:
  /// **'Item {n}'**
  String workflowConfigItemN(int n);

  /// No description provided for @workflowConfigAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get workflowConfigAddItem;

  /// No description provided for @workflowConfigAddLineItem.
  ///
  /// In en, this message translates to:
  /// **'Add line item'**
  String get workflowConfigAddLineItem;

  /// No description provided for @workflowConfigProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get workflowConfigProduct;

  /// No description provided for @workflowConfigQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get workflowConfigQuantity;

  /// No description provided for @workflowConfigUnitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get workflowConfigUnitPrice;

  /// No description provided for @workflowConfigTaxPercent.
  ///
  /// In en, this message translates to:
  /// **'Tax %'**
  String get workflowConfigTaxPercent;

  /// No description provided for @workflowConfigDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get workflowConfigDescription;

  /// No description provided for @workflowConfigPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get workflowConfigPaymentMethod;

  /// No description provided for @workflowConfigAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get workflowConfigAmount;

  /// No description provided for @workflowConfigAccountSelect.
  ///
  /// In en, this message translates to:
  /// **'Bank account / Cash register'**
  String get workflowConfigAccountSelect;

  /// No description provided for @workflowConfigAddPayment.
  ///
  /// In en, this message translates to:
  /// **'Add payment'**
  String get workflowConfigAddPayment;

  /// No description provided for @workflowConfigNoPaymentsYet.
  ///
  /// In en, this message translates to:
  /// **'No payments added yet. Use the button below to add.'**
  String get workflowConfigNoPaymentsYet;

  /// No description provided for @workflowConfigPaymentN.
  ///
  /// In en, this message translates to:
  /// **'Payment {n}'**
  String workflowConfigPaymentN(int n);

  /// No description provided for @workflowConfigNotSelected.
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get workflowConfigNotSelected;

  /// No description provided for @workflowConfigSelectWarehouse.
  ///
  /// In en, this message translates to:
  /// **'Select warehouse'**
  String get workflowConfigSelectWarehouse;

  /// No description provided for @workflowConfigSelectAccount.
  ///
  /// In en, this message translates to:
  /// **'Select account'**
  String get workflowConfigSelectAccount;

  /// No description provided for @workflowConfigSelectFiscalYear.
  ///
  /// In en, this message translates to:
  /// **'Select fiscal year'**
  String get workflowConfigSelectFiscalYear;

  /// No description provided for @workflowConfigInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON'**
  String get workflowConfigInvalidJson;

  /// No description provided for @workflowConfigJsonHint.
  ///
  /// In en, this message translates to:
  /// **'\'{\"key\": \"value\"}\''**
  String get workflowConfigJsonHint;

  /// No description provided for @workflowConfigCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get workflowConfigCash;

  /// No description provided for @workflowConfigBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get workflowConfigBank;

  /// No description provided for @workflowConfigCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get workflowConfigCheck;

  /// No description provided for @workflowConfigCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get workflowConfigCard;

  /// No description provided for @workflowConfigSelectTelegramUser.
  ///
  /// In en, this message translates to:
  /// **'Select user connected to Telegram bot'**
  String get workflowConfigSelectTelegramUser;

  /// No description provided for @workflowConfigSelectBaleUser.
  ///
  /// In en, this message translates to:
  /// **'Select user connected to Bale bot'**
  String get workflowConfigSelectBaleUser;

  /// No description provided for @workflowConfigSelectAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Select at least one item'**
  String get workflowConfigSelectAtLeastOne;

  /// No description provided for @workflowConfigReferenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Select from previous nodes'**
  String get workflowConfigReferenceTitle;

  /// No description provided for @workflowConfigNoNodesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No nodes available to select'**
  String get workflowConfigNoNodesAvailable;

  /// No description provided for @workflowConfigStep1Node.
  ///
  /// In en, this message translates to:
  /// **'Step 1: Select node'**
  String get workflowConfigStep1Node;

  /// No description provided for @workflowConfigStep2Data.
  ///
  /// In en, this message translates to:
  /// **'Step 2: Select data'**
  String get workflowConfigStep2Data;

  /// No description provided for @workflowConfigSelectDataFrom.
  ///
  /// In en, this message translates to:
  /// **'Select data from \"{label}\"'**
  String workflowConfigSelectDataFrom(String label);

  /// No description provided for @workflowConfigOrSelectField.
  ///
  /// In en, this message translates to:
  /// **'Or select a specific field:'**
  String get workflowConfigOrSelectField;

  /// No description provided for @workflowConfigUseFullNodeOutput.
  ///
  /// In en, this message translates to:
  /// **'Use full node output'**
  String get workflowConfigUseFullNodeOutput;

  /// No description provided for @workflowConfigFullNodeOutputDesc.
  ///
  /// In en, this message translates to:
  /// **'All output data from the node'**
  String get workflowConfigFullNodeOutputDesc;

  /// No description provided for @workflowConfigBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get workflowConfigBack;

  /// No description provided for @workflowConfigCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get workflowConfigCancel;

  /// No description provided for @workflowConfigGroupFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get workflowConfigGroupFilters;

  /// No description provided for @workflowConfigGroupScheduling.
  ///
  /// In en, this message translates to:
  /// **'Scheduling'**
  String get workflowConfigGroupScheduling;

  /// No description provided for @workflowConfigGroupErrorManagement.
  ///
  /// In en, this message translates to:
  /// **'Error management'**
  String get workflowConfigGroupErrorManagement;

  /// No description provided for @workflowConfigGroupMainSettings.
  ///
  /// In en, this message translates to:
  /// **'Main settings'**
  String get workflowConfigGroupMainSettings;

  /// No description provided for @workflowConfigGroupAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced settings'**
  String get workflowConfigGroupAdvanced;

  /// No description provided for @workflowConfigUserDefault.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get workflowConfigUserDefault;

  /// No description provided for @workflowConfigFiscalYearDefault.
  ///
  /// In en, this message translates to:
  /// **'Fiscal year'**
  String get workflowConfigFiscalYearDefault;

  /// No description provided for @workflowConfigJsonLabel.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get workflowConfigJsonLabel;

  /// No description provided for @workflowPaletteSearch.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get workflowPaletteSearch;

  /// No description provided for @workflowPaletteAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get workflowPaletteAll;

  /// No description provided for @workflowPaletteTriggers.
  ///
  /// In en, this message translates to:
  /// **'Triggers'**
  String get workflowPaletteTriggers;

  /// No description provided for @workflowPaletteActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get workflowPaletteActions;

  /// No description provided for @workflowPaletteLoops.
  ///
  /// In en, this message translates to:
  /// **'Loops'**
  String get workflowPaletteLoops;

  /// No description provided for @workflowPaletteConditions.
  ///
  /// In en, this message translates to:
  /// **'Conditions'**
  String get workflowPaletteConditions;

  /// No description provided for @workflowNodeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown node'**
  String get workflowNodeUnknown;

  /// No description provided for @workflowConfigEnumRequiredForMultiSelect.
  ///
  /// In en, this message translates to:
  /// **'Error: enum values required for multi-select'**
  String get workflowConfigEnumRequiredForMultiSelect;

  /// No description provided for @workflowConfigFieldEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get workflowConfigFieldEnabled;

  /// No description provided for @workflowConfigFieldTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get workflowConfigFieldTo;

  /// No description provided for @workflowConfigFieldSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get workflowConfigFieldSubject;

  /// No description provided for @workflowConfigFieldBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get workflowConfigFieldBody;

  /// No description provided for @workflowConfigFieldMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get workflowConfigFieldMessage;

  /// No description provided for @workflowConfigFieldMinAmount.
  ///
  /// In en, this message translates to:
  /// **'Minimum amount'**
  String get workflowConfigFieldMinAmount;

  /// No description provided for @workflowConfigFieldMaxAmount.
  ///
  /// In en, this message translates to:
  /// **'Maximum amount'**
  String get workflowConfigFieldMaxAmount;

  /// No description provided for @workflowConfigFieldStatusFilter.
  ///
  /// In en, this message translates to:
  /// **'Status filter'**
  String get workflowConfigFieldStatusFilter;

  /// No description provided for @workflowConfigFieldPersonType.
  ///
  /// In en, this message translates to:
  /// **'Person type'**
  String get workflowConfigFieldPersonType;

  /// No description provided for @workflowConfigFieldCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get workflowConfigFieldCurrency;

  /// No description provided for @workflowConfigFieldPersonId.
  ///
  /// In en, this message translates to:
  /// **'Person ID'**
  String get workflowConfigFieldPersonId;

  /// No description provided for @workflowConfigFieldProductId.
  ///
  /// In en, this message translates to:
  /// **'Product ID'**
  String get workflowConfigFieldProductId;

  /// No description provided for @workflowConfigFieldWarehouseId.
  ///
  /// In en, this message translates to:
  /// **'Warehouse ID'**
  String get workflowConfigFieldWarehouseId;

  /// No description provided for @workflowConfigFieldAccountId.
  ///
  /// In en, this message translates to:
  /// **'Account ID'**
  String get workflowConfigFieldAccountId;

  /// No description provided for @workflowConfigFieldRetryCount.
  ///
  /// In en, this message translates to:
  /// **'Retry count'**
  String get workflowConfigFieldRetryCount;

  /// No description provided for @workflowConfigFieldRetryDelay.
  ///
  /// In en, this message translates to:
  /// **'Retry delay'**
  String get workflowConfigFieldRetryDelay;

  /// No description provided for @workflowConfigFieldOnError.
  ///
  /// In en, this message translates to:
  /// **'On error'**
  String get workflowConfigFieldOnError;

  /// No description provided for @workflowConfigFieldBreakOnError.
  ///
  /// In en, this message translates to:
  /// **'Break on error'**
  String get workflowConfigFieldBreakOnError;

  /// No description provided for @workflowConfigFieldContinueOnError.
  ///
  /// In en, this message translates to:
  /// **'Continue on error'**
  String get workflowConfigFieldContinueOnError;

  /// No description provided for @workflowConfigFieldTriggerType.
  ///
  /// In en, this message translates to:
  /// **'Trigger type'**
  String get workflowConfigFieldTriggerType;

  /// No description provided for @workflowConfigFieldActionType.
  ///
  /// In en, this message translates to:
  /// **'Action type'**
  String get workflowConfigFieldActionType;

  /// No description provided for @workflowConfigFieldLoopType.
  ///
  /// In en, this message translates to:
  /// **'Loop type'**
  String get workflowConfigFieldLoopType;

  /// No description provided for @workflowConfigFieldItemsSource.
  ///
  /// In en, this message translates to:
  /// **'Items source'**
  String get workflowConfigFieldItemsSource;

  /// No description provided for @workflowConfigFieldItemVariable.
  ///
  /// In en, this message translates to:
  /// **'Item variable'**
  String get workflowConfigFieldItemVariable;

  /// No description provided for @workflowConfigFieldIndexVariable.
  ///
  /// In en, this message translates to:
  /// **'Index variable'**
  String get workflowConfigFieldIndexVariable;

  /// No description provided for @workflowConfigFieldMaxIterations.
  ///
  /// In en, this message translates to:
  /// **'Max iterations'**
  String get workflowConfigFieldMaxIterations;

  /// No description provided for @workflowConfigFieldStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get workflowConfigFieldStart;

  /// No description provided for @workflowConfigFieldEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get workflowConfigFieldEnd;

  /// No description provided for @workflowConfigFieldStep.
  ///
  /// In en, this message translates to:
  /// **'Step'**
  String get workflowConfigFieldStep;

  /// No description provided for @workflowConfigFieldConditionLeft.
  ///
  /// In en, this message translates to:
  /// **'Left value'**
  String get workflowConfigFieldConditionLeft;

  /// No description provided for @workflowConfigFieldConditionOperator.
  ///
  /// In en, this message translates to:
  /// **'Comparison operator'**
  String get workflowConfigFieldConditionOperator;

  /// No description provided for @workflowConfigFieldConditionRight.
  ///
  /// In en, this message translates to:
  /// **'Right value'**
  String get workflowConfigFieldConditionRight;

  /// No description provided for @workflowConfigFieldTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get workflowConfigFieldTimeout;

  /// No description provided for @workflowConfigFieldCooldown.
  ///
  /// In en, this message translates to:
  /// **'Cooldown'**
  String get workflowConfigFieldCooldown;

  /// No description provided for @workflowConfigFieldSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get workflowConfigFieldSchedule;

  /// No description provided for @workflowConfigFieldDelay.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get workflowConfigFieldDelay;

  /// No description provided for @workflowConfigFieldDocumentType.
  ///
  /// In en, this message translates to:
  /// **'Document type'**
  String get workflowConfigFieldDocumentType;

  /// No description provided for @workflowConfigFieldFiscalYearFilter.
  ///
  /// In en, this message translates to:
  /// **'Fiscal year filter'**
  String get workflowConfigFieldFiscalYearFilter;

  /// No description provided for @workflowConfigFieldFiscalYearId.
  ///
  /// In en, this message translates to:
  /// **'Fiscal year'**
  String get workflowConfigFieldFiscalYearId;

  /// No description provided for @workflowConfigFieldUserIdFilter.
  ///
  /// In en, this message translates to:
  /// **'User filter'**
  String get workflowConfigFieldUserIdFilter;

  /// No description provided for @workflowConfigFieldDescriptionContains.
  ///
  /// In en, this message translates to:
  /// **'Description contains'**
  String get workflowConfigFieldDescriptionContains;

  /// No description provided for @workflowConfigFieldCooldownSeconds.
  ///
  /// In en, this message translates to:
  /// **'Cooldown (seconds)'**
  String get workflowConfigFieldCooldownSeconds;

  /// No description provided for @workflowConfigFieldTimeoutSeconds.
  ///
  /// In en, this message translates to:
  /// **'Timeout (seconds)'**
  String get workflowConfigFieldTimeoutSeconds;

  /// No description provided for @workflowConfigFieldInvoiceType.
  ///
  /// In en, this message translates to:
  /// **'Invoice type'**
  String get workflowConfigFieldInvoiceType;

  /// No description provided for @workflowConfigFieldPersonTypeFilter.
  ///
  /// In en, this message translates to:
  /// **'Person type filter'**
  String get workflowConfigFieldPersonTypeFilter;

  /// No description provided for @workflowConfigFieldCurrencyId.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get workflowConfigFieldCurrencyId;

  /// No description provided for @workflowConfigFieldIncludeTaxDetails.
  ///
  /// In en, this message translates to:
  /// **'Include tax details'**
  String get workflowConfigFieldIncludeTaxDetails;

  /// No description provided for @workflowConfigFieldIncludePaymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Include payment status'**
  String get workflowConfigFieldIncludePaymentStatus;

  /// No description provided for @workflowConfigFieldAccountIdFilter.
  ///
  /// In en, this message translates to:
  /// **'Account filter'**
  String get workflowConfigFieldAccountIdFilter;

  /// No description provided for @workflowConfigFieldPaymentMethodFilter.
  ///
  /// In en, this message translates to:
  /// **'Payment method filter'**
  String get workflowConfigFieldPaymentMethodFilter;

  /// No description provided for @workflowConfigFieldIncludeBalance.
  ///
  /// In en, this message translates to:
  /// **'Include balance'**
  String get workflowConfigFieldIncludeBalance;

  /// No description provided for @workflowConfigFieldCheckDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Check duplicate'**
  String get workflowConfigFieldCheckDuplicate;

  /// No description provided for @workflowConfigFieldTypeFilter.
  ///
  /// In en, this message translates to:
  /// **'Type filter'**
  String get workflowConfigFieldTypeFilter;

  /// No description provided for @workflowConfigFieldCheckType.
  ///
  /// In en, this message translates to:
  /// **'Check type'**
  String get workflowConfigFieldCheckType;

  /// No description provided for @workflowConfigFieldDaysBefore.
  ///
  /// In en, this message translates to:
  /// **'Days before due'**
  String get workflowConfigFieldDaysBefore;

  /// No description provided for @workflowConfigFieldReferenceCode.
  ///
  /// In en, this message translates to:
  /// **'Reference code'**
  String get workflowConfigFieldReferenceCode;

  /// No description provided for @workflowConfigFieldExtraInfo.
  ///
  /// In en, this message translates to:
  /// **'Extra info'**
  String get workflowConfigFieldExtraInfo;

  /// No description provided for @workflowConfigFieldIsProforma.
  ///
  /// In en, this message translates to:
  /// **'Proforma invoice'**
  String get workflowConfigFieldIsProforma;

  /// No description provided for @workflowConnectionHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'How to Connect Nodes'**
  String get workflowConnectionHelpTitle;

  /// No description provided for @workflowConnectionHelpMethod1.
  ///
  /// In en, this message translates to:
  /// **'Method 1: Drag & Drop (Recommended)'**
  String get workflowConnectionHelpMethod1;

  /// No description provided for @workflowConnectionHelpMethod1Step1.
  ///
  /// In en, this message translates to:
  /// **'1. Click and hold on the output point of a node'**
  String get workflowConnectionHelpMethod1Step1;

  /// No description provided for @workflowConnectionHelpMethod1Step2.
  ///
  /// In en, this message translates to:
  /// **'2. Drag your mouse - a temporary line will appear'**
  String get workflowConnectionHelpMethod1Step2;

  /// No description provided for @workflowConnectionHelpMethod1Step3.
  ///
  /// In en, this message translates to:
  /// **'3. Release on the input point of another node'**
  String get workflowConnectionHelpMethod1Step3;

  /// No description provided for @workflowConnectionHelpMethod2.
  ///
  /// In en, this message translates to:
  /// **'Method 2: Click & Click'**
  String get workflowConnectionHelpMethod2;

  /// No description provided for @workflowConnectionHelpMethod2Step1.
  ///
  /// In en, this message translates to:
  /// **'1. Click on the output point of a node'**
  String get workflowConnectionHelpMethod2Step1;

  /// No description provided for @workflowConnectionHelpMethod2Step2.
  ///
  /// In en, this message translates to:
  /// **'2. Click on the input point of another node'**
  String get workflowConnectionHelpMethod2Step2;

  /// No description provided for @workflowConnectionHelpTips.
  ///
  /// In en, this message translates to:
  /// **'Tips'**
  String get workflowConnectionHelpTips;

  /// No description provided for @workflowConnectionHelpTipsText.
  ///
  /// In en, this message translates to:
  /// **'• Trigger nodes only have output points\n• Action nodes have both input and output points\n• To delete connection: click on it and press Delete'**
  String get workflowConnectionHelpTipsText;

  /// No description provided for @workflowConnectionHelpGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get workflowConnectionHelpGotIt;

  /// No description provided for @workflowEditNameDescription.
  ///
  /// In en, this message translates to:
  /// **'Edit name and description'**
  String get workflowEditNameDescription;

  /// No description provided for @workflowNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Workflow name *'**
  String get workflowNameRequired;

  /// No description provided for @workflowNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Invoice approval process'**
  String get workflowNameHint;

  /// No description provided for @workflowDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get workflowDescription;

  /// No description provided for @workflowDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Optional description for this workflow...'**
  String get workflowDescriptionHint;

  /// No description provided for @workflowSaveWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Save workflow'**
  String get workflowSaveWorkflow;

  /// No description provided for @workflowEnterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter workflow name'**
  String get workflowEnterName;

  /// No description provided for @workflowInfoUpdated.
  ///
  /// In en, this message translates to:
  /// **'Info updated. For permanent save, click the Save button.'**
  String get workflowInfoUpdated;

  /// No description provided for @workflowNoteComment.
  ///
  /// In en, this message translates to:
  /// **'Note / Comment'**
  String get workflowNoteComment;

  /// No description provided for @workflowNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Note or comment for this node...'**
  String get workflowNoteHint;

  /// No description provided for @workflowNoteDeleted.
  ///
  /// In en, this message translates to:
  /// **'Note deleted'**
  String get workflowNoteDeleted;

  /// No description provided for @workflowNoteCleared.
  ///
  /// In en, this message translates to:
  /// **'Note cleared'**
  String get workflowNoteCleared;

  /// No description provided for @workflowNoteSaved.
  ///
  /// In en, this message translates to:
  /// **'Note saved'**
  String get workflowNoteSaved;

  /// No description provided for @workflowSaveAsTemplate.
  ///
  /// In en, this message translates to:
  /// **'Save as template'**
  String get workflowSaveAsTemplate;

  /// No description provided for @workflowTemplateName.
  ///
  /// In en, this message translates to:
  /// **'Template name'**
  String get workflowTemplateName;

  /// No description provided for @workflowTemplateNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Invoice process'**
  String get workflowTemplateNameHint;

  /// No description provided for @workflowTemplateSaved.
  ///
  /// In en, this message translates to:
  /// **'Template \"{name}\" saved'**
  String workflowTemplateSaved(String name);

  /// No description provided for @workflowTemplateLoaded.
  ///
  /// In en, this message translates to:
  /// **'Template \"{name}\" loaded'**
  String workflowTemplateLoaded(String name);

  /// No description provided for @workflowSelectTemplate.
  ///
  /// In en, this message translates to:
  /// **'Select template'**
  String get workflowSelectTemplate;

  /// No description provided for @workflowBuiltinTemplates.
  ///
  /// In en, this message translates to:
  /// **'Built-in templates'**
  String get workflowBuiltinTemplates;

  /// No description provided for @workflowSavedTemplates.
  ///
  /// In en, this message translates to:
  /// **'Saved templates'**
  String get workflowSavedTemplates;

  /// No description provided for @workflowNoSavedTemplates.
  ///
  /// In en, this message translates to:
  /// **'No saved templates'**
  String get workflowNoSavedTemplates;

  /// No description provided for @workflowTemplateDefault.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get workflowTemplateDefault;

  /// No description provided for @workflowTemplateN.
  ///
  /// In en, this message translates to:
  /// **'Template {n}'**
  String workflowTemplateN(int n);

  /// No description provided for @workflowCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created: {date}'**
  String workflowCreatedAt(String date);

  /// No description provided for @workflowErrorAddNode.
  ///
  /// In en, this message translates to:
  /// **'Error adding node'**
  String get workflowErrorAddNode;

  /// No description provided for @workflowErrorSaveTemplate.
  ///
  /// In en, this message translates to:
  /// **'Error saving template'**
  String get workflowErrorSaveTemplate;

  /// No description provided for @workflowErrorLoadTemplate.
  ///
  /// In en, this message translates to:
  /// **'Error loading template'**
  String get workflowErrorLoadTemplate;

  /// No description provided for @workflowTimelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Execution timeline'**
  String get workflowTimelineTitle;

  /// No description provided for @workflowTimelineRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get workflowTimelineRefresh;

  /// No description provided for @workflowAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get workflowAnalyticsTitle;

  /// No description provided for @workflowPerformance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get workflowPerformance;

  /// No description provided for @workflowNoData.
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get workflowNoData;

  /// No description provided for @workflowErrorLoadTimeline.
  ///
  /// In en, this message translates to:
  /// **'Error loading timeline'**
  String get workflowErrorLoadTimeline;

  /// No description provided for @workflowAllLogs.
  ///
  /// In en, this message translates to:
  /// **'All logs'**
  String get workflowAllLogs;

  /// No description provided for @workflowAllNodes.
  ///
  /// In en, this message translates to:
  /// **'All nodes'**
  String get workflowAllNodes;

  /// No description provided for @workflowErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get workflowErrors;

  /// No description provided for @workflowNodeStats.
  ///
  /// In en, this message translates to:
  /// **'Node stats'**
  String get workflowNodeStats;

  /// No description provided for @workflowColumnNode.
  ///
  /// In en, this message translates to:
  /// **'Node'**
  String get workflowColumnNode;

  /// No description provided for @workflowColumnType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get workflowColumnType;

  /// No description provided for @workflowColumnExecutions.
  ///
  /// In en, this message translates to:
  /// **'Executions'**
  String get workflowColumnExecutions;

  /// No description provided for @workflowColumnAvgTime.
  ///
  /// In en, this message translates to:
  /// **'Avg. time'**
  String get workflowColumnAvgTime;

  /// No description provided for @workflowErrorLoadAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Error loading analytics'**
  String get workflowErrorLoadAnalytics;

  /// No description provided for @workflowErrorLoadErrorStats.
  ///
  /// In en, this message translates to:
  /// **'Error loading error stats'**
  String get workflowErrorLoadErrorStats;

  /// No description provided for @workflowTotalExecutions.
  ///
  /// In en, this message translates to:
  /// **'Total executions'**
  String get workflowTotalExecutions;

  /// No description provided for @workflowSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Successful'**
  String get workflowSuccessful;

  /// No description provided for @workflowFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get workflowFailed;

  /// No description provided for @workflowAvgTime.
  ///
  /// In en, this message translates to:
  /// **'Avg. time'**
  String get workflowAvgTime;

  /// No description provided for @workflowSuccessRate.
  ///
  /// In en, this message translates to:
  /// **'Success rate'**
  String get workflowSuccessRate;

  /// No description provided for @workflowNoErrorsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No errors recorded!'**
  String get workflowNoErrorsRecorded;

  /// No description provided for @workflowTotalErrors.
  ///
  /// In en, this message translates to:
  /// **'Total errors'**
  String get workflowTotalErrors;

  /// No description provided for @workflowErrorTypes.
  ///
  /// In en, this message translates to:
  /// **'Error types'**
  String get workflowErrorTypes;

  /// No description provided for @workflowErrorLoadHistory.
  ///
  /// In en, this message translates to:
  /// **'Error loading history'**
  String get workflowErrorLoadHistory;

  /// No description provided for @workflowErrorLoadLogs.
  ///
  /// In en, this message translates to:
  /// **'Error loading logs'**
  String get workflowErrorLoadLogs;

  /// No description provided for @workflowDeleteWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Delete workflow'**
  String get workflowDeleteWorkflow;

  /// No description provided for @workflowDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete workflow \"{name}\"?'**
  String workflowDeleteConfirm(String name);

  /// No description provided for @workflowDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Workflow deleted successfully'**
  String get workflowDeletedSuccess;

  /// No description provided for @workflowErrorDelete.
  ///
  /// In en, this message translates to:
  /// **'Error deleting workflow'**
  String get workflowErrorDelete;

  /// No description provided for @workflowStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get workflowStatusActive;

  /// No description provided for @workflowStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get workflowStatusInactive;

  /// No description provided for @workflowStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get workflowStatusDraft;

  /// No description provided for @workflowNoNodesDefined.
  ///
  /// In en, this message translates to:
  /// **'No nodes defined'**
  String get workflowNoNodesDefined;

  /// No description provided for @workflowEmpty.
  ///
  /// In en, this message translates to:
  /// **'This workflow is empty'**
  String get workflowEmpty;

  /// No description provided for @workflowErrorDisplay.
  ///
  /// In en, this message translates to:
  /// **'Error displaying workflow'**
  String get workflowErrorDisplay;

  /// No description provided for @workflowExecutionLogs.
  ///
  /// In en, this message translates to:
  /// **'Execution logs'**
  String get workflowExecutionLogs;

  /// No description provided for @workflowExecutionLogCopyOne.
  ///
  /// In en, this message translates to:
  /// **'Copy this log'**
  String get workflowExecutionLogCopyOne;

  /// No description provided for @workflowExecutionLogsCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all logs'**
  String get workflowExecutionLogsCopyAll;

  /// No description provided for @workflowNoLogs.
  ///
  /// In en, this message translates to:
  /// **'No logs found'**
  String get workflowNoLogs;

  /// No description provided for @workflowNoExecutions.
  ///
  /// In en, this message translates to:
  /// **'No executions yet'**
  String get workflowNoExecutions;

  /// No description provided for @workflowStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get workflowStarted;

  /// No description provided for @workflowCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get workflowCompleted;

  /// No description provided for @workflowLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get workflowLogs;

  /// No description provided for @workflowErrorLoadingLogs.
  ///
  /// In en, this message translates to:
  /// **'Error loading logs'**
  String get workflowErrorLoadingLogs;

  /// No description provided for @workflowErrorUpdatingStatus.
  ///
  /// In en, this message translates to:
  /// **'Error updating status'**
  String get workflowErrorUpdatingStatus;

  /// No description provided for @workflowHierarchicalLayoutApplied.
  ///
  /// In en, this message translates to:
  /// **'Hierarchical layout applied'**
  String get workflowHierarchicalLayoutApplied;

  /// No description provided for @workflowForceDirectedLayoutApplied.
  ///
  /// In en, this message translates to:
  /// **'Force-directed layout applied'**
  String get workflowForceDirectedLayoutApplied;

  /// No description provided for @workflowValidationSuccess.
  ///
  /// In en, this message translates to:
  /// **'Validation successful'**
  String get workflowValidationSuccess;

  /// No description provided for @workflowAllNodesValid.
  ///
  /// In en, this message translates to:
  /// **'All nodes are valid!'**
  String get workflowAllNodesValid;

  /// No description provided for @workflowNodesWithErrors.
  ///
  /// In en, this message translates to:
  /// **'{count} nodes have errors'**
  String workflowNodesWithErrors(int count);

  /// No description provided for @workflowToolbarOpenPalette.
  ///
  /// In en, this message translates to:
  /// **'Open node palette'**
  String get workflowToolbarOpenPalette;

  /// No description provided for @workflowToolbarZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get workflowToolbarZoomOut;

  /// No description provided for @workflowToolbarZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get workflowToolbarZoomIn;

  /// No description provided for @workflowToolbarResetZoom.
  ///
  /// In en, this message translates to:
  /// **'Reset zoom'**
  String get workflowToolbarResetZoom;

  /// No description provided for @workflowToolbarConnectionHelp.
  ///
  /// In en, this message translates to:
  /// **'Connection help'**
  String get workflowToolbarConnectionHelp;

  /// No description provided for @workflowToolbarHideGrid.
  ///
  /// In en, this message translates to:
  /// **'Hide Grid'**
  String get workflowToolbarHideGrid;

  /// No description provided for @workflowToolbarShowGrid.
  ///
  /// In en, this message translates to:
  /// **'Show Grid'**
  String get workflowToolbarShowGrid;

  /// No description provided for @workflowToolbarDisableSnapToGrid.
  ///
  /// In en, this message translates to:
  /// **'Disable Snap to Grid'**
  String get workflowToolbarDisableSnapToGrid;

  /// No description provided for @workflowToolbarEnableSnapToGrid.
  ///
  /// In en, this message translates to:
  /// **'Enable Snap to Grid'**
  String get workflowToolbarEnableSnapToGrid;

  /// No description provided for @workflowToolbarAlignmentTools.
  ///
  /// In en, this message translates to:
  /// **'Alignment tools'**
  String get workflowToolbarAlignmentTools;

  /// No description provided for @workflowToolbarAlignLeft.
  ///
  /// In en, this message translates to:
  /// **'Align left'**
  String get workflowToolbarAlignLeft;

  /// No description provided for @workflowToolbarAlignRight.
  ///
  /// In en, this message translates to:
  /// **'Align right'**
  String get workflowToolbarAlignRight;

  /// No description provided for @workflowToolbarAlignTop.
  ///
  /// In en, this message translates to:
  /// **'Align top'**
  String get workflowToolbarAlignTop;

  /// No description provided for @workflowToolbarAlignBottom.
  ///
  /// In en, this message translates to:
  /// **'Align bottom'**
  String get workflowToolbarAlignBottom;

  /// No description provided for @workflowToolbarDistributeHorizontally.
  ///
  /// In en, this message translates to:
  /// **'Distribute horizontally'**
  String get workflowToolbarDistributeHorizontally;

  /// No description provided for @workflowToolbarDistributeVertically.
  ///
  /// In en, this message translates to:
  /// **'Distribute vertically'**
  String get workflowToolbarDistributeVertically;

  /// No description provided for @workflowToolbarAlignToGrid.
  ///
  /// In en, this message translates to:
  /// **'Align to grid'**
  String get workflowToolbarAlignToGrid;

  /// No description provided for @workflowToolbarClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get workflowToolbarClearAll;

  /// No description provided for @workflowToolbarAutoLayout.
  ///
  /// In en, this message translates to:
  /// **'Auto layout'**
  String get workflowToolbarAutoLayout;

  /// No description provided for @workflowToolbarTemplates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get workflowToolbarTemplates;

  /// No description provided for @workflowToolbarLoadTemplate.
  ///
  /// In en, this message translates to:
  /// **'Load template'**
  String get workflowToolbarLoadTemplate;

  /// No description provided for @workflowToolbarSelectLayoutType.
  ///
  /// In en, this message translates to:
  /// **'Select layout type'**
  String get workflowToolbarSelectLayoutType;

  /// No description provided for @workflowToolbarHierarchical.
  ///
  /// In en, this message translates to:
  /// **'Hierarchical'**
  String get workflowToolbarHierarchical;

  /// No description provided for @workflowToolbarForceDirected.
  ///
  /// In en, this message translates to:
  /// **'Force-directed'**
  String get workflowToolbarForceDirected;

  /// No description provided for @workflowToolbarShowValidationErrors.
  ///
  /// In en, this message translates to:
  /// **'Show validation errors'**
  String get workflowToolbarShowValidationErrors;

  /// No description provided for @workflowToolbarUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get workflowToolbarUndo;

  /// No description provided for @workflowToolbarRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get workflowToolbarRedo;

  /// No description provided for @workflowToolbarNodes.
  ///
  /// In en, this message translates to:
  /// **'Nodes'**
  String get workflowToolbarNodes;

  /// No description provided for @workflowToolbarConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get workflowToolbarConnections;

  /// No description provided for @workflowNoSuggestedFields.
  ///
  /// In en, this message translates to:
  /// **'No suggested fields for this node'**
  String get workflowNoSuggestedFields;

  /// No description provided for @workflowTypeFieldManually.
  ///
  /// In en, this message translates to:
  /// **'You can type the field manually: {nodeId}.field_name'**
  String workflowTypeFieldManually(String nodeId);

  /// No description provided for @workflowFieldInvoiceId.
  ///
  /// In en, this message translates to:
  /// **'Invoice ID'**
  String get workflowFieldInvoiceId;

  /// No description provided for @workflowFieldDescInvoiceId.
  ///
  /// In en, this message translates to:
  /// **'Numeric invoice ID'**
  String get workflowFieldDescInvoiceId;

  /// No description provided for @workflowFieldInvoiceCode.
  ///
  /// In en, this message translates to:
  /// **'Invoice code'**
  String get workflowFieldInvoiceCode;

  /// No description provided for @workflowFieldDescInvoiceCode.
  ///
  /// In en, this message translates to:
  /// **'Unique invoice code'**
  String get workflowFieldDescInvoiceCode;

  /// No description provided for @workflowFieldInvoiceNumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice number'**
  String get workflowFieldInvoiceNumber;

  /// No description provided for @workflowFieldDescInvoiceNumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice number'**
  String get workflowFieldDescInvoiceNumber;

  /// No description provided for @workflowFieldInvoiceDate.
  ///
  /// In en, this message translates to:
  /// **'Invoice date'**
  String get workflowFieldInvoiceDate;

  /// No description provided for @workflowFieldDescInvoiceDate.
  ///
  /// In en, this message translates to:
  /// **'Invoice issue date'**
  String get workflowFieldDescInvoiceDate;

  /// No description provided for @workflowFieldTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total amount'**
  String get workflowFieldTotalAmount;

  /// No description provided for @workflowFieldDescTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total amount'**
  String get workflowFieldDescTotalAmount;

  /// No description provided for @workflowFieldDiscountAmount.
  ///
  /// In en, this message translates to:
  /// **'Discount amount'**
  String get workflowFieldDiscountAmount;

  /// No description provided for @workflowFieldDescDiscountAmount.
  ///
  /// In en, this message translates to:
  /// **'Total discounts'**
  String get workflowFieldDescDiscountAmount;

  /// No description provided for @workflowFieldTaxAmount.
  ///
  /// In en, this message translates to:
  /// **'Tax amount'**
  String get workflowFieldTaxAmount;

  /// No description provided for @workflowFieldDescTaxAmount.
  ///
  /// In en, this message translates to:
  /// **'Total tax'**
  String get workflowFieldDescTaxAmount;

  /// No description provided for @workflowFieldFinalAmount.
  ///
  /// In en, this message translates to:
  /// **'Final amount'**
  String get workflowFieldFinalAmount;

  /// No description provided for @workflowFieldDescFinalAmount.
  ///
  /// In en, this message translates to:
  /// **'Payable amount'**
  String get workflowFieldDescFinalAmount;

  /// No description provided for @workflowFieldCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get workflowFieldCustomerName;

  /// No description provided for @workflowFieldDescCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Counterparty name'**
  String get workflowFieldDescCustomerName;

  /// No description provided for @workflowFieldCustomerId.
  ///
  /// In en, this message translates to:
  /// **'Customer ID'**
  String get workflowFieldCustomerId;

  /// No description provided for @workflowFieldDescCustomerId.
  ///
  /// In en, this message translates to:
  /// **'Counterparty ID'**
  String get workflowFieldDescCustomerId;

  /// No description provided for @workflowFieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get workflowFieldDescription;

  /// No description provided for @workflowFieldDescDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get workflowFieldDescDescription;

  /// No description provided for @workflowFieldInvoiceDescription.
  ///
  /// In en, this message translates to:
  /// **'Invoice description'**
  String get workflowFieldInvoiceDescription;

  /// No description provided for @workflowFieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get workflowFieldStatus;

  /// No description provided for @workflowFieldDescStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get workflowFieldDescStatus;

  /// No description provided for @workflowFieldInvoiceStatus.
  ///
  /// In en, this message translates to:
  /// **'Invoice status'**
  String get workflowFieldInvoiceStatus;

  /// No description provided for @workflowFieldPaymentId.
  ///
  /// In en, this message translates to:
  /// **'Payment ID'**
  String get workflowFieldPaymentId;

  /// No description provided for @workflowFieldDescPaymentId.
  ///
  /// In en, this message translates to:
  /// **'Numeric payment ID'**
  String get workflowFieldDescPaymentId;

  /// No description provided for @workflowFieldAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get workflowFieldAmount;

  /// No description provided for @workflowFieldDescAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get workflowFieldDescAmount;

  /// No description provided for @workflowFieldPaymentAmount.
  ///
  /// In en, this message translates to:
  /// **'Payment amount'**
  String get workflowFieldPaymentAmount;

  /// No description provided for @workflowFieldPaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Payment date'**
  String get workflowFieldPaymentDate;

  /// No description provided for @workflowFieldDescPaymentDate.
  ///
  /// In en, this message translates to:
  /// **'Payment date'**
  String get workflowFieldDescPaymentDate;

  /// No description provided for @workflowFieldPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get workflowFieldPaymentMethod;

  /// No description provided for @workflowFieldDescPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method type'**
  String get workflowFieldDescPaymentMethod;

  /// No description provided for @workflowFieldPaymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Payment status'**
  String get workflowFieldPaymentStatus;

  /// No description provided for @workflowFieldReferenceCode.
  ///
  /// In en, this message translates to:
  /// **'Reference code'**
  String get workflowFieldReferenceCode;

  /// No description provided for @workflowFieldDescReferenceCode.
  ///
  /// In en, this message translates to:
  /// **'Transaction reference code'**
  String get workflowFieldDescReferenceCode;

  /// No description provided for @workflowFieldDocumentId.
  ///
  /// In en, this message translates to:
  /// **'Document ID'**
  String get workflowFieldDocumentId;

  /// No description provided for @workflowFieldDescDocumentId.
  ///
  /// In en, this message translates to:
  /// **'Numeric document ID'**
  String get workflowFieldDescDocumentId;

  /// No description provided for @workflowFieldDocumentType.
  ///
  /// In en, this message translates to:
  /// **'Document type'**
  String get workflowFieldDocumentType;

  /// No description provided for @workflowFieldDescDocumentType.
  ///
  /// In en, this message translates to:
  /// **'Accounting document type'**
  String get workflowFieldDescDocumentType;

  /// No description provided for @workflowFieldDocTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Document total'**
  String get workflowFieldDocTotalAmount;

  /// No description provided for @workflowFieldDescDocTotalAmount.
  ///
  /// In en, this message translates to:
  /// **'Document total amount'**
  String get workflowFieldDescDocTotalAmount;

  /// No description provided for @workflowFieldDocDescription.
  ///
  /// In en, this message translates to:
  /// **'Document description'**
  String get workflowFieldDocDescription;

  /// No description provided for @workflowFieldDescDocDescription.
  ///
  /// In en, this message translates to:
  /// **'Document description'**
  String get workflowFieldDescDocDescription;

  /// No description provided for @workflowFieldReceiptPaymentId.
  ///
  /// In en, this message translates to:
  /// **'Receipt/Payment ID'**
  String get workflowFieldReceiptPaymentId;

  /// No description provided for @workflowFieldDescReceiptPaymentId.
  ///
  /// In en, this message translates to:
  /// **'Numeric ID'**
  String get workflowFieldDescReceiptPaymentId;

  /// No description provided for @workflowFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get workflowFieldType;

  /// No description provided for @workflowFieldDescType.
  ///
  /// In en, this message translates to:
  /// **'Receipt or payment'**
  String get workflowFieldDescType;

  /// No description provided for @workflowFieldPersonId.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get workflowFieldPersonId;

  /// No description provided for @workflowFieldDescPersonId.
  ///
  /// In en, this message translates to:
  /// **'Counterparty ID'**
  String get workflowFieldDescPersonId;

  /// No description provided for @workflowFieldPersonName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get workflowFieldPersonName;

  /// No description provided for @workflowFieldDescPersonName.
  ///
  /// In en, this message translates to:
  /// **'Counterparty name'**
  String get workflowFieldDescPersonName;

  /// No description provided for @workflowFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get workflowFieldEmail;

  /// No description provided for @workflowFieldDescEmail.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get workflowFieldDescEmail;

  /// No description provided for @workflowFieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get workflowFieldPhone;

  /// No description provided for @workflowFieldDescPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get workflowFieldDescPhone;

  /// No description provided for @workflowFieldMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get workflowFieldMobile;

  /// No description provided for @workflowFieldDescMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get workflowFieldDescMobile;

  /// No description provided for @workflowFieldPersonType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get workflowFieldPersonType;

  /// No description provided for @workflowFieldDescPersonType.
  ///
  /// In en, this message translates to:
  /// **'Counterparty type'**
  String get workflowFieldDescPersonType;

  /// No description provided for @workflowFieldProductId.
  ///
  /// In en, this message translates to:
  /// **'Product ID'**
  String get workflowFieldProductId;

  /// No description provided for @workflowFieldDescProductId.
  ///
  /// In en, this message translates to:
  /// **'Numeric product ID'**
  String get workflowFieldDescProductId;

  /// No description provided for @workflowFieldProductName.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get workflowFieldProductName;

  /// No description provided for @workflowFieldDescProductName.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get workflowFieldDescProductName;

  /// No description provided for @workflowFieldProductCode.
  ///
  /// In en, this message translates to:
  /// **'Product code'**
  String get workflowFieldProductCode;

  /// No description provided for @workflowFieldDescProductCode.
  ///
  /// In en, this message translates to:
  /// **'Product code'**
  String get workflowFieldDescProductCode;

  /// No description provided for @workflowFieldPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get workflowFieldPrice;

  /// No description provided for @workflowFieldDescPrice.
  ///
  /// In en, this message translates to:
  /// **'Sale price'**
  String get workflowFieldDescPrice;

  /// No description provided for @workflowFieldQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get workflowFieldQuantity;

  /// No description provided for @workflowFieldDescQuantity.
  ///
  /// In en, this message translates to:
  /// **'Stock quantity'**
  String get workflowFieldDescQuantity;

  /// No description provided for @workflowFieldId.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get workflowFieldId;

  /// No description provided for @workflowFieldDescId.
  ///
  /// In en, this message translates to:
  /// **'Record ID'**
  String get workflowFieldDescId;

  /// No description provided for @workflowFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get workflowFieldName;

  /// No description provided for @workflowFieldDescName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get workflowFieldDescName;

  /// No description provided for @workflowFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get workflowFieldTitle;

  /// No description provided for @workflowFieldDescTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get workflowFieldDescTitle;

  /// No description provided for @workflowFieldGenDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get workflowFieldGenDescription;

  /// No description provided for @workflowFieldDescGenDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get workflowFieldDescGenDescription;

  /// No description provided for @workflowFieldGenStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get workflowFieldGenStatus;

  /// No description provided for @workflowFieldDescGenStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get workflowFieldDescGenStatus;

  /// No description provided for @workflowFieldCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created date'**
  String get workflowFieldCreatedAt;

  /// No description provided for @workflowFieldDescCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Creation date and time'**
  String get workflowFieldDescCreatedAt;

  /// No description provided for @workflowFieldInvoiceType.
  ///
  /// In en, this message translates to:
  /// **'Invoice type'**
  String get workflowFieldInvoiceType;

  /// No description provided for @workflowFieldDescInvoiceType.
  ///
  /// In en, this message translates to:
  /// **'Invoice document type (e.g. sales/purchase)'**
  String get workflowFieldDescInvoiceType;

  /// No description provided for @workflowFieldLeadId.
  ///
  /// In en, this message translates to:
  /// **'Lead ID'**
  String get workflowFieldLeadId;

  /// No description provided for @workflowFieldDescLeadId.
  ///
  /// In en, this message translates to:
  /// **'CRM lead record ID'**
  String get workflowFieldDescLeadId;

  /// No description provided for @workflowFieldDealId.
  ///
  /// In en, this message translates to:
  /// **'Deal ID'**
  String get workflowFieldDealId;

  /// No description provided for @workflowFieldDescDealId.
  ///
  /// In en, this message translates to:
  /// **'CRM deal/opportunity record ID'**
  String get workflowFieldDescDealId;

  /// No description provided for @workflowFieldProcessDefinitionId.
  ///
  /// In en, this message translates to:
  /// **'Process definition ID'**
  String get workflowFieldProcessDefinitionId;

  /// No description provided for @workflowFieldDescProcessDefinitionId.
  ///
  /// In en, this message translates to:
  /// **'Sales process definition'**
  String get workflowFieldDescProcessDefinitionId;

  /// No description provided for @workflowFieldStageId.
  ///
  /// In en, this message translates to:
  /// **'Stage ID'**
  String get workflowFieldStageId;

  /// No description provided for @workflowFieldDescStageId.
  ///
  /// In en, this message translates to:
  /// **'Current stage in the process'**
  String get workflowFieldDescStageId;

  /// No description provided for @workflowFieldOldStageId.
  ///
  /// In en, this message translates to:
  /// **'Previous stage ID'**
  String get workflowFieldOldStageId;

  /// No description provided for @workflowFieldDescOldStageId.
  ///
  /// In en, this message translates to:
  /// **'Stage before the change'**
  String get workflowFieldDescOldStageId;

  /// No description provided for @workflowFieldNewStageId.
  ///
  /// In en, this message translates to:
  /// **'New stage ID'**
  String get workflowFieldNewStageId;

  /// No description provided for @workflowFieldDescNewStageId.
  ///
  /// In en, this message translates to:
  /// **'Stage after the change'**
  String get workflowFieldDescNewStageId;

  /// No description provided for @workflowFieldIsWin.
  ///
  /// In en, this message translates to:
  /// **'Won deal'**
  String get workflowFieldIsWin;

  /// No description provided for @workflowFieldDescIsWin.
  ///
  /// In en, this message translates to:
  /// **'Whether the deal was closed as won'**
  String get workflowFieldDescIsWin;

  /// No description provided for @workflowFieldPersonTypesList.
  ///
  /// In en, this message translates to:
  /// **'Person types'**
  String get workflowFieldPersonTypesList;

  /// No description provided for @workflowFieldDescPersonTypesList.
  ///
  /// In en, this message translates to:
  /// **'Assigned person types list (on create)'**
  String get workflowFieldDescPersonTypesList;

  /// No description provided for @workflowFieldSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get workflowFieldSuccess;

  /// No description provided for @workflowFieldDescSuccess.
  ///
  /// In en, this message translates to:
  /// **'Whether the action succeeded'**
  String get workflowFieldDescSuccess;

  /// No description provided for @workflowFieldWorkflowUserId.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get workflowFieldWorkflowUserId;

  /// No description provided for @workflowFieldDescWorkflowUserId.
  ///
  /// In en, this message translates to:
  /// **'User ID in action output'**
  String get workflowFieldDescWorkflowUserId;

  /// No description provided for @workflowFieldSentMessage.
  ///
  /// In en, this message translates to:
  /// **'Sent message'**
  String get workflowFieldSentMessage;

  /// No description provided for @workflowFieldDescSentMessage.
  ///
  /// In en, this message translates to:
  /// **'Message text after send (e.g. Telegram/Bale)'**
  String get workflowFieldDescSentMessage;

  /// No description provided for @workflowFieldTelegramChatId.
  ///
  /// In en, this message translates to:
  /// **'Telegram chat ID'**
  String get workflowFieldTelegramChatId;

  /// No description provided for @workflowFieldDescTelegramChatId.
  ///
  /// In en, this message translates to:
  /// **'Recipient Telegram chat ID'**
  String get workflowFieldDescTelegramChatId;

  /// No description provided for @workflowFieldBaleChatId.
  ///
  /// In en, this message translates to:
  /// **'Bale chat ID'**
  String get workflowFieldBaleChatId;

  /// No description provided for @workflowFieldDescBaleChatId.
  ///
  /// In en, this message translates to:
  /// **'Recipient Bale chat ID'**
  String get workflowFieldDescBaleChatId;

  /// No description provided for @workflowFieldFileStorageId.
  ///
  /// In en, this message translates to:
  /// **'File ID (storage)'**
  String get workflowFieldFileStorageId;

  /// No description provided for @workflowFieldDescFileStorageId.
  ///
  /// In en, this message translates to:
  /// **'UUID of the file on the file server; use in Bale attachment_file_id as \$node_id.file_id'**
  String get workflowFieldDescFileStorageId;

  /// No description provided for @workflowFieldAttachmentFileId.
  ///
  /// In en, this message translates to:
  /// **'Attachment file ID'**
  String get workflowFieldAttachmentFileId;

  /// No description provided for @workflowFieldDescAttachmentFileId.
  ///
  /// In en, this message translates to:
  /// **'Same as file_id on backup success; alias for referencing in Bale'**
  String get workflowFieldDescAttachmentFileId;

  /// No description provided for @workflowFieldStoredFilename.
  ///
  /// In en, this message translates to:
  /// **'Stored filename'**
  String get workflowFieldStoredFilename;

  /// No description provided for @workflowFieldDescStoredFilename.
  ///
  /// In en, this message translates to:
  /// **'Original filename of the backup or attachment on the file server'**
  String get workflowFieldDescStoredFilename;

  /// No description provided for @workflowFieldSendFileAttachment.
  ///
  /// In en, this message translates to:
  /// **'Send file attachment'**
  String get workflowFieldSendFileAttachment;

  /// No description provided for @workflowFieldDescSendFileAttachment.
  ///
  /// In en, this message translates to:
  /// **'Whether the Bale action sent a document from file storage'**
  String get workflowFieldDescSendFileAttachment;

  /// No description provided for @workflowFieldCrmChatConversationId.
  ///
  /// In en, this message translates to:
  /// **'Chat conversation ID'**
  String get workflowFieldCrmChatConversationId;

  /// No description provided for @workflowFieldDescCrmChatConversationId.
  ///
  /// In en, this message translates to:
  /// **'CRM web chat conversation record ID in trigger_data'**
  String get workflowFieldDescCrmChatConversationId;

  /// No description provided for @workflowFieldCrmChatWidgetId.
  ///
  /// In en, this message translates to:
  /// **'Chat widget ID'**
  String get workflowFieldCrmChatWidgetId;

  /// No description provided for @workflowFieldDescCrmChatWidgetId.
  ///
  /// In en, this message translates to:
  /// **'Web chat widget linked to this conversation'**
  String get workflowFieldDescCrmChatWidgetId;

  /// No description provided for @workflowFieldCrmChatMessageId.
  ///
  /// In en, this message translates to:
  /// **'Chat message ID'**
  String get workflowFieldCrmChatMessageId;

  /// No description provided for @workflowFieldDescCrmChatMessageId.
  ///
  /// In en, this message translates to:
  /// **'Recorded web chat message ID'**
  String get workflowFieldDescCrmChatMessageId;

  /// No description provided for @workflowFieldCrmChatBody.
  ///
  /// In en, this message translates to:
  /// **'Message body'**
  String get workflowFieldCrmChatBody;

  /// No description provided for @workflowFieldDescCrmChatBody.
  ///
  /// In en, this message translates to:
  /// **'Visitor or agent message text in web chat'**
  String get workflowFieldDescCrmChatBody;

  /// No description provided for @workflowFieldCrmChatSenderRole.
  ///
  /// In en, this message translates to:
  /// **'Sender role'**
  String get workflowFieldCrmChatSenderRole;

  /// No description provided for @workflowFieldDescCrmChatSenderRole.
  ///
  /// In en, this message translates to:
  /// **'visitor or agent depending on the message'**
  String get workflowFieldDescCrmChatSenderRole;

  /// No description provided for @workflowFieldCrmChatVisitorFirstName.
  ///
  /// In en, this message translates to:
  /// **'Visitor first name'**
  String get workflowFieldCrmChatVisitorFirstName;

  /// No description provided for @workflowFieldDescCrmChatVisitorFirstName.
  ///
  /// In en, this message translates to:
  /// **'First name from the chat widget form'**
  String get workflowFieldDescCrmChatVisitorFirstName;

  /// No description provided for @workflowFieldCrmChatVisitorLastName.
  ///
  /// In en, this message translates to:
  /// **'Visitor last name'**
  String get workflowFieldCrmChatVisitorLastName;

  /// No description provided for @workflowFieldDescCrmChatVisitorLastName.
  ///
  /// In en, this message translates to:
  /// **'Last name from the chat widget form'**
  String get workflowFieldDescCrmChatVisitorLastName;

  /// No description provided for @workflowFieldCrmChatPageUrl.
  ///
  /// In en, this message translates to:
  /// **'Page URL'**
  String get workflowFieldCrmChatPageUrl;

  /// No description provided for @workflowFieldDescCrmChatPageUrl.
  ///
  /// In en, this message translates to:
  /// **'Site page URL when the event occurred (if present)'**
  String get workflowFieldDescCrmChatPageUrl;

  /// No description provided for @workflowFieldCrmChatConversationStatus.
  ///
  /// In en, this message translates to:
  /// **'Conversation status'**
  String get workflowFieldCrmChatConversationStatus;

  /// No description provided for @workflowFieldDescCrmChatConversationStatus.
  ///
  /// In en, this message translates to:
  /// **'e.g. open or resolved'**
  String get workflowFieldDescCrmChatConversationStatus;

  /// No description provided for @workflowFieldCrmChatAssignedToUserId.
  ///
  /// In en, this message translates to:
  /// **'Assigned user ID'**
  String get workflowFieldCrmChatAssignedToUserId;

  /// No description provided for @workflowFieldDescCrmChatAssignedToUserId.
  ///
  /// In en, this message translates to:
  /// **'Responsible agent user when assigned'**
  String get workflowFieldDescCrmChatAssignedToUserId;

  /// No description provided for @workflowFieldCrmChatAgentUserId.
  ///
  /// In en, this message translates to:
  /// **'Agent user ID'**
  String get workflowFieldCrmChatAgentUserId;

  /// No description provided for @workflowFieldDescCrmChatAgentUserId.
  ///
  /// In en, this message translates to:
  /// **'Sending user for agent-role messages (agent reply trigger)'**
  String get workflowFieldDescCrmChatAgentUserId;

  /// No description provided for @workflowFieldAutomationSource.
  ///
  /// In en, this message translates to:
  /// **'Automation source'**
  String get workflowFieldAutomationSource;

  /// No description provided for @workflowFieldDescAutomationSource.
  ///
  /// In en, this message translates to:
  /// **'e.g. workflow when the message was sent by automation'**
  String get workflowFieldDescAutomationSource;

  /// No description provided for @workflowFieldOperatorRelay.
  ///
  /// In en, this message translates to:
  /// **'Operator relay'**
  String get workflowFieldOperatorRelay;

  /// No description provided for @workflowFieldDescOperatorRelay.
  ///
  /// In en, this message translates to:
  /// **'When sent via operator bridge (Telegram/Bale)'**
  String get workflowFieldDescOperatorRelay;

  /// No description provided for @workflowFieldCrmChatOldAssignedUserId.
  ///
  /// In en, this message translates to:
  /// **'Previous assignee ID'**
  String get workflowFieldCrmChatOldAssignedUserId;

  /// No description provided for @workflowFieldDescCrmChatOldAssignedUserId.
  ///
  /// In en, this message translates to:
  /// **'Before assignment changed'**
  String get workflowFieldDescCrmChatOldAssignedUserId;

  /// No description provided for @workflowFieldCrmChatNewAssignedUserId.
  ///
  /// In en, this message translates to:
  /// **'New assignee ID'**
  String get workflowFieldCrmChatNewAssignedUserId;

  /// No description provided for @workflowFieldDescCrmChatNewAssignedUserId.
  ///
  /// In en, this message translates to:
  /// **'After assignment changed'**
  String get workflowFieldDescCrmChatNewAssignedUserId;

  /// No description provided for @workflowFieldCrmChatOldStatus.
  ///
  /// In en, this message translates to:
  /// **'Previous conversation status'**
  String get workflowFieldCrmChatOldStatus;

  /// No description provided for @workflowFieldDescCrmChatOldStatus.
  ///
  /// In en, this message translates to:
  /// **'Before status update'**
  String get workflowFieldDescCrmChatOldStatus;

  /// No description provided for @workflowFieldCrmChatNewStatus.
  ///
  /// In en, this message translates to:
  /// **'New conversation status'**
  String get workflowFieldCrmChatNewStatus;

  /// No description provided for @workflowFieldDescCrmChatNewStatus.
  ///
  /// In en, this message translates to:
  /// **'After status update'**
  String get workflowFieldDescCrmChatNewStatus;

  /// No description provided for @workflowFieldEmailTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get workflowFieldEmailTo;

  /// No description provided for @workflowFieldDescEmailTo.
  ///
  /// In en, this message translates to:
  /// **'Recipient email address (resolved after send)'**
  String get workflowFieldDescEmailTo;

  /// No description provided for @workflowFieldEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get workflowFieldEmailSubject;

  /// No description provided for @workflowFieldDescEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'Email subject line (resolved after send)'**
  String get workflowFieldDescEmailSubject;

  /// No description provided for @workflowFieldHttpStatusCode.
  ///
  /// In en, this message translates to:
  /// **'HTTP status code'**
  String get workflowFieldHttpStatusCode;

  /// No description provided for @workflowFieldDescHttpStatusCode.
  ///
  /// In en, this message translates to:
  /// **'Response status code (e.g. 200)'**
  String get workflowFieldDescHttpStatusCode;

  /// No description provided for @workflowFieldHttpResponse.
  ///
  /// In en, this message translates to:
  /// **'HTTP response'**
  String get workflowFieldHttpResponse;

  /// No description provided for @workflowFieldDescHttpResponse.
  ///
  /// In en, this message translates to:
  /// **'Response body or payload'**
  String get workflowFieldDescHttpResponse;

  /// No description provided for @workflowFieldVariableName.
  ///
  /// In en, this message translates to:
  /// **'Variable name'**
  String get workflowFieldVariableName;

  /// No description provided for @workflowFieldDescVariableName.
  ///
  /// In en, this message translates to:
  /// **'Name of variable stored in context'**
  String get workflowFieldDescVariableName;

  /// No description provided for @workflowFieldVariableValue.
  ///
  /// In en, this message translates to:
  /// **'Variable value'**
  String get workflowFieldVariableValue;

  /// No description provided for @workflowFieldDescVariableValue.
  ///
  /// In en, this message translates to:
  /// **'Stored value for the variable'**
  String get workflowFieldDescVariableValue;

  /// No description provided for @workflowFieldWebhookPayload.
  ///
  /// In en, this message translates to:
  /// **'Webhook payload'**
  String get workflowFieldWebhookPayload;

  /// No description provided for @workflowFieldDescWebhookPayload.
  ///
  /// In en, this message translates to:
  /// **'Parsed webhook payload data'**
  String get workflowFieldDescWebhookPayload;

  /// No description provided for @workflowFieldWebhookBody.
  ///
  /// In en, this message translates to:
  /// **'Request body'**
  String get workflowFieldWebhookBody;

  /// No description provided for @workflowFieldDescWebhookBody.
  ///
  /// In en, this message translates to:
  /// **'Raw HTTP request body'**
  String get workflowFieldDescWebhookBody;

  /// No description provided for @workflowFieldScheduledAt.
  ///
  /// In en, this message translates to:
  /// **'Scheduled run time'**
  String get workflowFieldScheduledAt;

  /// No description provided for @workflowFieldDescScheduledAt.
  ///
  /// In en, this message translates to:
  /// **'When the scheduled trigger ran'**
  String get workflowFieldDescScheduledAt;

  /// No description provided for @workflowFieldWarehouseId.
  ///
  /// In en, this message translates to:
  /// **'Warehouse ID'**
  String get workflowFieldWarehouseId;

  /// No description provided for @workflowFieldDescWarehouseId.
  ///
  /// In en, this message translates to:
  /// **'Warehouse related to inventory event'**
  String get workflowFieldDescWarehouseId;

  /// No description provided for @workflowFieldCurrentQuantity.
  ///
  /// In en, this message translates to:
  /// **'Current quantity'**
  String get workflowFieldCurrentQuantity;

  /// No description provided for @workflowFieldDescCurrentQuantity.
  ///
  /// In en, this message translates to:
  /// **'Current stock quantity'**
  String get workflowFieldDescCurrentQuantity;

  /// No description provided for @workflowFieldMinQuantity.
  ///
  /// In en, this message translates to:
  /// **'Minimum quantity'**
  String get workflowFieldMinQuantity;

  /// No description provided for @workflowFieldDescMinQuantity.
  ///
  /// In en, this message translates to:
  /// **'Low-stock threshold'**
  String get workflowFieldDescMinQuantity;

  /// No description provided for @workflowFieldCheckId.
  ///
  /// In en, this message translates to:
  /// **'Check ID'**
  String get workflowFieldCheckId;

  /// No description provided for @workflowFieldDescCheckId.
  ///
  /// In en, this message translates to:
  /// **'Check record ID'**
  String get workflowFieldDescCheckId;

  /// No description provided for @workflowFieldCheckNumber.
  ///
  /// In en, this message translates to:
  /// **'Check number'**
  String get workflowFieldCheckNumber;

  /// No description provided for @workflowFieldDescCheckNumber.
  ///
  /// In en, this message translates to:
  /// **'Printed check number'**
  String get workflowFieldDescCheckNumber;

  /// No description provided for @workflowFieldDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get workflowFieldDueDate;

  /// No description provided for @workflowFieldDescDueDate.
  ///
  /// In en, this message translates to:
  /// **'Maturity/due date'**
  String get workflowFieldDescDueDate;

  /// No description provided for @workflowFieldLogLevel.
  ///
  /// In en, this message translates to:
  /// **'Log level'**
  String get workflowFieldLogLevel;

  /// No description provided for @workflowFieldDescLogLevel.
  ///
  /// In en, this message translates to:
  /// **'Level recorded in workflow log'**
  String get workflowFieldDescLogLevel;

  /// No description provided for @workflowTemplateInvoiceSalesName.
  ///
  /// In en, this message translates to:
  /// **'Invoice sales notification'**
  String get workflowTemplateInvoiceSalesName;

  /// No description provided for @workflowTemplateInvoiceSalesDesc.
  ///
  /// In en, this message translates to:
  /// **'After creating sales invoice, email and Telegram are sent'**
  String get workflowTemplateInvoiceSalesDesc;

  /// No description provided for @workflowCategoryInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get workflowCategoryInvoice;

  /// No description provided for @workflowTemplateInventoryLowName.
  ///
  /// In en, this message translates to:
  /// **'Low inventory alert'**
  String get workflowTemplateInventoryLowName;

  /// No description provided for @workflowTemplateInventoryLowDesc.
  ///
  /// In en, this message translates to:
  /// **'When product stock is low, notification is sent'**
  String get workflowTemplateInventoryLowDesc;

  /// No description provided for @workflowCategoryInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get workflowCategoryInventory;

  /// No description provided for @workflowTemplateReceiptPaymentName.
  ///
  /// In en, this message translates to:
  /// **'Receipt/Payment log'**
  String get workflowTemplateReceiptPaymentName;

  /// No description provided for @workflowTemplateReceiptPaymentDesc.
  ///
  /// In en, this message translates to:
  /// **'After recording receipt/payment, log is created'**
  String get workflowTemplateReceiptPaymentDesc;

  /// No description provided for @workflowCategoryFinancial.
  ///
  /// In en, this message translates to:
  /// **'Financial'**
  String get workflowCategoryFinancial;

  /// No description provided for @workflowTemplatePersonWelcomeName.
  ///
  /// In en, this message translates to:
  /// **'New person welcome'**
  String get workflowTemplatePersonWelcomeName;

  /// No description provided for @workflowTemplatePersonWelcomeDesc.
  ///
  /// In en, this message translates to:
  /// **'After creating new person, welcome message is sent'**
  String get workflowTemplatePersonWelcomeDesc;

  /// No description provided for @workflowCategoryPersons.
  ///
  /// In en, this message translates to:
  /// **'Persons'**
  String get workflowCategoryPersons;

  /// No description provided for @workflowCategoryCrm.
  ///
  /// In en, this message translates to:
  /// **'CRM'**
  String get workflowCategoryCrm;

  /// No description provided for @workflowTemplateCrmNewLeadNotifyName.
  ///
  /// In en, this message translates to:
  /// **'New lead in-app notification'**
  String get workflowTemplateCrmNewLeadNotifyName;

  /// No description provided for @workflowTemplateCrmNewLeadNotifyDesc.
  ///
  /// In en, this message translates to:
  /// **'When a lead is created, an in-app notification is recorded'**
  String get workflowTemplateCrmNewLeadNotifyDesc;

  /// No description provided for @workflowTemplateCrmDealWonLogName.
  ///
  /// In en, this message translates to:
  /// **'Log won deal closure'**
  String get workflowTemplateCrmDealWonLogName;

  /// No description provided for @workflowTemplateCrmDealWonLogDesc.
  ///
  /// In en, this message translates to:
  /// **'Only won deals; writes an info log entry'**
  String get workflowTemplateCrmDealWonLogDesc;

  /// No description provided for @workflowTemplateReceiptUpdatedNotifyName.
  ///
  /// In en, this message translates to:
  /// **'Notify on receipt/payment edit'**
  String get workflowTemplateReceiptUpdatedNotifyName;

  /// No description provided for @workflowTemplateReceiptUpdatedNotifyDesc.
  ///
  /// In en, this message translates to:
  /// **'After a receipt or payment is edited, an in-app notification is created'**
  String get workflowTemplateReceiptUpdatedNotifyDesc;

  /// No description provided for @workflowTemplateInvoiceAmountBranchName.
  ///
  /// In en, this message translates to:
  /// **'Sales invoice: high vs low amount'**
  String get workflowTemplateInvoiceAmountBranchName;

  /// No description provided for @workflowTemplateInvoiceAmountBranchDesc.
  ///
  /// In en, this message translates to:
  /// **'If amount is at least 10M, high-priority in-app notice; otherwise only a log (simple If example)'**
  String get workflowTemplateInvoiceAmountBranchDesc;

  /// No description provided for @workflowTestRunCompletedDry.
  ///
  /// In en, this message translates to:
  /// **'Dry run succeeded (no real sends or writes).'**
  String get workflowTestRunCompletedDry;

  /// No description provided for @settingsCategoriesCount.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get settingsCategoriesCount;

  /// No description provided for @settingsCount.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsCount;

  /// No description provided for @expandAllCategories.
  ///
  /// In en, this message translates to:
  /// **'Expand All'**
  String get expandAllCategories;

  /// No description provided for @collapseAllCategories.
  ///
  /// In en, this message translates to:
  /// **'Collapse All'**
  String get collapseAllCategories;

  /// No description provided for @categoryTreeShowProductsInCategory.
  ///
  /// In en, this message translates to:
  /// **'Show products in this category'**
  String get categoryTreeShowProductsInCategory;

  /// No description provided for @categoryTreeActionsMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get categoryTreeActionsMenuTooltip;

  /// No description provided for @categoryTreeMoreActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get categoryTreeMoreActionsTooltip;

  /// No description provided for @categoryLoadProductsError.
  ///
  /// In en, this message translates to:
  /// **'Error loading products: {error}'**
  String categoryLoadProductsError(String error);

  /// No description provided for @categoryTreeNoProductsInCategory.
  ///
  /// In en, this message translates to:
  /// **'No products in this category'**
  String get categoryTreeNoProductsInCategory;

  /// No description provided for @categoryDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Optional category description'**
  String get categoryDescriptionHint;

  /// No description provided for @categorySortOrderLabel.
  ///
  /// In en, this message translates to:
  /// **'Display order'**
  String get categorySortOrderLabel;

  /// No description provided for @categorySortOrderHint.
  ///
  /// In en, this message translates to:
  /// **'Sort number (lower appears first)'**
  String get categorySortOrderHint;

  /// No description provided for @categorySortOrderRequired.
  ///
  /// In en, this message translates to:
  /// **'Display order is required'**
  String get categorySortOrderRequired;

  /// No description provided for @categorySortOrderInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid number'**
  String get categorySortOrderInvalidNumber;

  /// No description provided for @categoryParentFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Parent category'**
  String get categoryParentFieldLabel;

  /// No description provided for @productCategoryFilterBrowseAll.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get productCategoryFilterBrowseAll;

  /// No description provided for @productCategorySubcategoriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Subcategories'**
  String get productCategorySubcategoriesLabel;

  /// No description provided for @categoryPickerSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No categories found'**
  String get categoryPickerSearchEmpty;

  /// No description provided for @categoryTreeAllCategoriesOption.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get categoryTreeAllCategoriesOption;

  /// No description provided for @noSettingsFound.
  ///
  /// In en, this message translates to:
  /// **'No settings found'**
  String get noSettingsFound;

  /// No description provided for @searchResults.
  ///
  /// In en, this message translates to:
  /// **'Search Results'**
  String get searchResults;

  /// No description provided for @searchResultCount.
  ///
  /// In en, this message translates to:
  /// **'{count} result'**
  String searchResultCount(int count);

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No results found for \"{query}\"'**
  String noSearchResults(String query);

  /// No description provided for @searchSettingsPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search settings...'**
  String get searchSettingsPlaceholder;

  /// No description provided for @noSettingsInCategory.
  ///
  /// In en, this message translates to:
  /// **'No settings found in this category'**
  String get noSettingsInCategory;

  /// No description provided for @settingsCategoryCoreConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Core & Configuration'**
  String get settingsCategoryCoreConfiguration;

  /// No description provided for @settingsCategoryCoreConfigurationDescription.
  ///
  /// In en, this message translates to:
  /// **'Basic system settings and configuration'**
  String get settingsCategoryCoreConfigurationDescription;

  /// No description provided for @settingsCategoryStorageFiles.
  ///
  /// In en, this message translates to:
  /// **'Storage & Files'**
  String get settingsCategoryStorageFiles;

  /// No description provided for @settingsCategoryStorageFilesDescription.
  ///
  /// In en, this message translates to:
  /// **'File storage and storage plan management'**
  String get settingsCategoryStorageFilesDescription;

  /// No description provided for @settingsCategoryFinancialPayment.
  ///
  /// In en, this message translates to:
  /// **'Financial & Payment'**
  String get settingsCategoryFinancialPayment;

  /// No description provided for @settingsCategoryFinancialPaymentDescription.
  ///
  /// In en, this message translates to:
  /// **'Wallet and payment gateway settings'**
  String get settingsCategoryFinancialPaymentDescription;

  /// No description provided for @settingsCategoryUsersBusinesses.
  ///
  /// In en, this message translates to:
  /// **'Users & Businesses'**
  String get settingsCategoryUsersBusinesses;

  /// No description provided for @settingsCategoryUsersBusinessesDescription.
  ///
  /// In en, this message translates to:
  /// **'User and business management'**
  String get settingsCategoryUsersBusinessesDescription;

  /// No description provided for @settingsCategoryCommunications.
  ///
  /// In en, this message translates to:
  /// **'Communications'**
  String get settingsCategoryCommunications;

  /// No description provided for @settingsCategoryCommunicationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Email, notifications and announcements'**
  String get settingsCategoryCommunicationsDescription;

  /// No description provided for @settingsCategoryAI.
  ///
  /// In en, this message translates to:
  /// **'Artificial Intelligence'**
  String get settingsCategoryAI;

  /// No description provided for @settingsCategoryAIDescription.
  ///
  /// In en, this message translates to:
  /// **'AI settings, plans and prompts'**
  String get settingsCategoryAIDescription;

  /// No description provided for @settingsCategoryExternalServices.
  ///
  /// In en, this message translates to:
  /// **'External Services'**
  String get settingsCategoryExternalServices;

  /// No description provided for @settingsCategoryExternalServicesDescription.
  ///
  /// In en, this message translates to:
  /// **'External service integrations'**
  String get settingsCategoryExternalServicesDescription;

  /// No description provided for @settingsCategoryMonitoringLogs.
  ///
  /// In en, this message translates to:
  /// **'Monitoring & Logs'**
  String get settingsCategoryMonitoringLogs;

  /// No description provided for @settingsCategoryMonitoringLogsDescription.
  ///
  /// In en, this message translates to:
  /// **'System monitoring and logging'**
  String get settingsCategoryMonitoringLogsDescription;

  /// No description provided for @settingsShareLinks.
  ///
  /// In en, this message translates to:
  /// **'Share Links'**
  String get settingsShareLinks;

  /// No description provided for @settingsShareLinksDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure public share link destinations'**
  String get settingsShareLinksDescription;

  /// No description provided for @personShareLinkActive.
  ///
  /// In en, this message translates to:
  /// **'Active link'**
  String get personShareLinkActive;

  /// No description provided for @personShareCopyAndSendLink.
  ///
  /// In en, this message translates to:
  /// **'Copy and share link'**
  String get personShareCopyAndSendLink;

  /// No description provided for @personShareRevokeLink.
  ///
  /// In en, this message translates to:
  /// **'Revoke link'**
  String get personShareRevokeLink;

  /// No description provided for @personShareRevoking.
  ///
  /// In en, this message translates to:
  /// **'Revoking...'**
  String get personShareRevoking;

  /// No description provided for @personShareRefreshStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh status'**
  String get personShareRefreshStatus;

  /// No description provided for @personShareLinkHint.
  ///
  /// In en, this message translates to:
  /// **'This short link is ready to share via SMS or social networks.'**
  String get personShareLinkHint;

  /// No description provided for @personShareStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get personShareStatus;

  /// No description provided for @personShareExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get personShareExpiry;

  /// No description provided for @personShareViews.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get personShareViews;

  /// No description provided for @personShareLastView.
  ///
  /// In en, this message translates to:
  /// **'Last view'**
  String get personShareLastView;

  /// No description provided for @personShareCreateNew.
  ///
  /// In en, this message translates to:
  /// **'Create new link'**
  String get personShareCreateNew;

  /// No description provided for @personShareCreateWarning.
  ///
  /// In en, this message translates to:
  /// **'Creating a new link will deactivate the previous one (if any).'**
  String get personShareCreateWarning;

  /// No description provided for @personShareExpiryLabel.
  ///
  /// In en, this message translates to:
  /// **'Link validity'**
  String get personShareExpiryLabel;

  /// No description provided for @personShareExpiry7Days.
  ///
  /// In en, this message translates to:
  /// **'7 days (default)'**
  String get personShareExpiry7Days;

  /// No description provided for @personShareExpiry14Days.
  ///
  /// In en, this message translates to:
  /// **'14 days'**
  String get personShareExpiry14Days;

  /// No description provided for @personShareExpiry30Days.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get personShareExpiry30Days;

  /// No description provided for @personShareExpiryNone.
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get personShareExpiryNone;

  /// No description provided for @personShareMaxViewsLabel.
  ///
  /// In en, this message translates to:
  /// **'Max views allowed'**
  String get personShareMaxViewsLabel;

  /// No description provided for @personShareMaxViewsHint.
  ///
  /// In en, this message translates to:
  /// **'1–1000 or empty (unlimited). e.g. 5'**
  String get personShareMaxViewsHint;

  /// No description provided for @personShareDocumentsLimit.
  ///
  /// In en, this message translates to:
  /// **'Account card row count'**
  String get personShareDocumentsLimit;

  /// No description provided for @personShareIncludeLedger.
  ///
  /// In en, this message translates to:
  /// **'Show account card'**
  String get personShareIncludeLedger;

  /// No description provided for @personShareIncludeLedgerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'List of person account transactions'**
  String get personShareIncludeLedgerSubtitle;

  /// No description provided for @personShareIncludeInvoices.
  ///
  /// In en, this message translates to:
  /// **'Show invoice list'**
  String get personShareIncludeInvoices;

  /// No description provided for @personShareIncludeInvoicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Latest invoices for this person'**
  String get personShareIncludeInvoicesSubtitle;

  /// No description provided for @personShareCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create link'**
  String get personShareCreateButton;

  /// No description provided for @personShareCreateButtonNew.
  ///
  /// In en, this message translates to:
  /// **'Create new link'**
  String get personShareCreateButtonNew;

  /// No description provided for @personShareCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating...'**
  String get personShareCreating;

  /// No description provided for @personShareRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get personShareRefresh;

  /// No description provided for @personShareValidationAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'At least one of “Show account card” or “Show invoice list” must be enabled.'**
  String get personShareValidationAtLeastOne;

  /// No description provided for @personSharePermissionHint.
  ///
  /// In en, this message translates to:
  /// **'You need edit permission on people to create or revoke links.'**
  String get personSharePermissionHint;

  /// No description provided for @personShareLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get personShareLinkCopied;

  /// No description provided for @personShareLinkCopiedAndShare.
  ///
  /// In en, this message translates to:
  /// **'Link copied; you can share it via SMS or social networks.'**
  String get personShareLinkCopiedAndShare;

  /// No description provided for @personShareRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get personShareRetry;

  /// No description provided for @personShareNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get personShareNoExpiry;

  /// No description provided for @personShareNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get personShareNotSet;

  /// No description provided for @personShareLinkCreated.
  ///
  /// In en, this message translates to:
  /// **'Share link created successfully'**
  String get personShareLinkCreated;

  /// No description provided for @personShareLinkRevoked.
  ///
  /// In en, this message translates to:
  /// **'Share link revoked'**
  String get personShareLinkRevoked;

  /// No description provided for @personShareLinkCreateError.
  ///
  /// In en, this message translates to:
  /// **'Failed to create link'**
  String get personShareLinkCreateError;

  /// No description provided for @personShareLinkRevokeError.
  ///
  /// In en, this message translates to:
  /// **'Failed to revoke link'**
  String get personShareLinkRevokeError;

  /// No description provided for @personShareSendLinkBySms.
  ///
  /// In en, this message translates to:
  /// **'Send link via SMS'**
  String get personShareSendLinkBySms;

  /// No description provided for @personShareSendingSms.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get personShareSendingSms;

  /// No description provided for @personShareNoMobileHint.
  ///
  /// In en, this message translates to:
  /// **'Mobile number is not set for this customer.'**
  String get personShareNoMobileHint;

  /// No description provided for @personShareNoTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'No approved template found for account card link. Create and approve a template for the “Send account card link” event in Notification Templates.'**
  String get personShareNoTemplateHint;

  /// No description provided for @personShareSmsSent.
  ///
  /// In en, this message translates to:
  /// **'SMS sent successfully.'**
  String get personShareSmsSent;

  /// No description provided for @personShareCreateLinkFirst.
  ///
  /// In en, this message translates to:
  /// **'Create a link first.'**
  String get personShareCreateLinkFirst;

  /// No description provided for @personShareSendToNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Send to another number (optional)'**
  String get personShareSendToNumberLabel;

  /// No description provided for @personShareSendToNumberHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the number saved for this customer'**
  String get personShareSendToNumberHint;

  /// No description provided for @settingsRedisCache.
  ///
  /// In en, this message translates to:
  /// **'Redis Cache'**
  String get settingsRedisCache;

  /// No description provided for @settingsRedisCacheDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure Redis cache for improved performance'**
  String get settingsRedisCacheDescription;

  /// No description provided for @settingsFirewall.
  ///
  /// In en, this message translates to:
  /// **'Application firewall'**
  String get settingsFirewall;

  /// No description provided for @settingsFirewallDescription.
  ///
  /// In en, this message translates to:
  /// **'IP allow/deny, per-path rate limits (database), temporary bans, logs and reports'**
  String get settingsFirewallDescription;

  /// No description provided for @firewallTabRules.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get firewallTabRules;

  /// No description provided for @firewallTabRatePolicies.
  ///
  /// In en, this message translates to:
  /// **'Path rate limits'**
  String get firewallTabRatePolicies;

  /// No description provided for @firewallTabBlockLogs.
  ///
  /// In en, this message translates to:
  /// **'Blocked requests'**
  String get firewallTabBlockLogs;

  /// No description provided for @firewallTabAudit.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get firewallTabAudit;

  /// No description provided for @firewallTabReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get firewallTabReports;

  /// No description provided for @firewallAddRatePolicy.
  ///
  /// In en, this message translates to:
  /// **'Add rate policy'**
  String get firewallAddRatePolicy;

  /// No description provided for @firewallEditRatePolicy.
  ///
  /// In en, this message translates to:
  /// **'Edit rate policy'**
  String get firewallEditRatePolicy;

  /// No description provided for @firewallRatePolicyPathRequired.
  ///
  /// In en, this message translates to:
  /// **'Path prefix (e.g. /api/v1/public/crm-chat)'**
  String get firewallRatePolicyPathRequired;

  /// No description provided for @firewallRateMaxRequests.
  ///
  /// In en, this message translates to:
  /// **'Max requests per window'**
  String get firewallRateMaxRequests;

  /// No description provided for @firewallRateWindowSeconds.
  ///
  /// In en, this message translates to:
  /// **'Window size (seconds)'**
  String get firewallRateWindowSeconds;

  /// No description provided for @firewallNoRatePolicies.
  ///
  /// In en, this message translates to:
  /// **'No rate policies. Use this for per-IP limits on public API paths (e.g. web chat).'**
  String get firewallNoRatePolicies;

  /// No description provided for @firewallDeleteRatePolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete rate policy?'**
  String get firewallDeleteRatePolicyTitle;

  /// No description provided for @firewallDeleteRatePolicyBody.
  ///
  /// In en, this message translates to:
  /// **'The rate limit for this path will be removed.'**
  String get firewallDeleteRatePolicyBody;

  /// No description provided for @firewallEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get firewallEnabled;

  /// No description provided for @firewallAddRule.
  ///
  /// In en, this message translates to:
  /// **'Add rule'**
  String get firewallAddRule;

  /// No description provided for @firewallEditRule.
  ///
  /// In en, this message translates to:
  /// **'Edit rule'**
  String get firewallEditRule;

  /// No description provided for @firewallActionLabel.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get firewallActionLabel;

  /// No description provided for @firewallActionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get firewallActionAllow;

  /// No description provided for @firewallActionDeny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get firewallActionDeny;

  /// No description provided for @firewallIpCidr.
  ///
  /// In en, this message translates to:
  /// **'IP or CIDR'**
  String get firewallIpCidr;

  /// No description provided for @firewallPathPrefixOptional.
  ///
  /// In en, this message translates to:
  /// **'Path prefix (optional)'**
  String get firewallPathPrefixOptional;

  /// No description provided for @firewallHttpMethodsOptional.
  ///
  /// In en, this message translates to:
  /// **'HTTP methods e.g. GET,POST (optional)'**
  String get firewallHttpMethodsOptional;

  /// No description provided for @firewallPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority (lower = evaluated first)'**
  String get firewallPriority;

  /// No description provided for @firewallNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get firewallNoteOptional;

  /// No description provided for @firewallSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get firewallSaved;

  /// No description provided for @firewallBanIp.
  ///
  /// In en, this message translates to:
  /// **'Ban IP'**
  String get firewallBanIp;

  /// No description provided for @firewallDurationMinutesHint.
  ///
  /// In en, this message translates to:
  /// **'Duration in minutes (empty = permanent until removed)'**
  String get firewallDurationMinutesHint;

  /// No description provided for @firewallBanDone.
  ///
  /// In en, this message translates to:
  /// **'Ban applied'**
  String get firewallBanDone;

  /// No description provided for @firewallActiveOnlyFilter.
  ///
  /// In en, this message translates to:
  /// **'Active rules only'**
  String get firewallActiveOnlyFilter;

  /// No description provided for @firewallRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get firewallRefresh;

  /// No description provided for @firewallNoRules.
  ///
  /// In en, this message translates to:
  /// **'No rules'**
  String get firewallNoRules;

  /// No description provided for @firewallDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete rule?'**
  String get firewallDeleteConfirmTitle;

  /// No description provided for @firewallDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get firewallDeleteConfirmBody;

  /// No description provided for @firewallNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get firewallNoExpiry;

  /// No description provided for @firewallFilterByIp.
  ///
  /// In en, this message translates to:
  /// **'Filter by IP'**
  String get firewallFilterByIp;

  /// No description provided for @firewallReportsPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get firewallReportsPeriod;

  /// No description provided for @firewallReportsDays.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get firewallReportsDays;

  /// No description provided for @firewallReportsTotalBlocks.
  ///
  /// In en, this message translates to:
  /// **'Blocked requests (period)'**
  String get firewallReportsTotalBlocks;

  /// No description provided for @firewallReportsActiveDenyRules.
  ///
  /// In en, this message translates to:
  /// **'Active deny rules'**
  String get firewallReportsActiveDenyRules;

  /// No description provided for @firewallReportsTopIps.
  ///
  /// In en, this message translates to:
  /// **'Top blocked IPs'**
  String get firewallReportsTopIps;

  /// No description provided for @firewallReportsByDay.
  ///
  /// In en, this message translates to:
  /// **'Blocks by day'**
  String get firewallReportsByDay;

  /// No description provided for @settingsStoragePlans.
  ///
  /// In en, this message translates to:
  /// **'Storage Plans'**
  String get settingsStoragePlans;

  /// No description provided for @settingsStoragePlansDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage storage plans and pricing'**
  String get settingsStoragePlansDescription;

  /// No description provided for @settingsDocumentMonetization.
  ///
  /// In en, this message translates to:
  /// **'Document Monetization'**
  String get settingsDocumentMonetization;

  /// No description provided for @settingsDocumentMonetizationDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage document revenue scenarios and packages'**
  String get settingsDocumentMonetizationDescription;

  /// No description provided for @settingsMarketplacePlugins.
  ///
  /// In en, this message translates to:
  /// **'Marketplace Plugins Management'**
  String get settingsMarketplacePlugins;

  /// No description provided for @settingsMarketplacePluginsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage plugins and plans for the marketplace'**
  String get settingsMarketplacePluginsDescription;

  /// No description provided for @settingsWalletSettings.
  ///
  /// In en, this message translates to:
  /// **'Wallet Settings'**
  String get settingsWalletSettings;

  /// No description provided for @settingsWalletSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Set base currency and policies'**
  String get settingsWalletSettingsDescription;

  /// No description provided for @settingsCurrenciesAdmin.
  ///
  /// In en, this message translates to:
  /// **'Currency management'**
  String get settingsCurrenciesAdmin;

  /// No description provided for @settingsCurrenciesAdminDescription.
  ///
  /// In en, this message translates to:
  /// **'Decimal places, rounding, add or remove currencies'**
  String get settingsCurrenciesAdminDescription;

  /// No description provided for @settingsPaymentGateways.
  ///
  /// In en, this message translates to:
  /// **'Payment Gateways'**
  String get settingsPaymentGateways;

  /// No description provided for @settingsPaymentGatewaysDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage and configure payment gateways'**
  String get settingsPaymentGatewaysDescription;

  /// No description provided for @settingsBusinessesManagement.
  ///
  /// In en, this message translates to:
  /// **'Businesses Management'**
  String get settingsBusinessesManagement;

  /// No description provided for @settingsBusinessesManagementDescription.
  ///
  /// In en, this message translates to:
  /// **'View and manage all system businesses'**
  String get settingsBusinessesManagementDescription;

  /// No description provided for @settingsAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get settingsAnnouncements;

  /// No description provided for @settingsAnnouncementsDescription.
  ///
  /// In en, this message translates to:
  /// **'Create/edit/publish system announcements'**
  String get settingsAnnouncementsDescription;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsNotificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Enable/disable channels and send test messages'**
  String get settingsNotificationsDescription;

  /// No description provided for @settingsNotificationTemplates.
  ///
  /// In en, this message translates to:
  /// **'Notification Templates'**
  String get settingsNotificationTemplates;

  /// No description provided for @settingsNotificationTemplatesDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage templates for channels and languages'**
  String get settingsNotificationTemplatesDescription;

  /// No description provided for @settingsSupportOperators.
  ///
  /// In en, this message translates to:
  /// **'Support operators'**
  String get settingsSupportOperators;

  /// No description provided for @settingsSupportOperatorsDescription.
  ///
  /// In en, this message translates to:
  /// **'Grant or revoke support operator access for users'**
  String get settingsSupportOperatorsDescription;

  /// No description provided for @settingsNotificationModeration.
  ///
  /// In en, this message translates to:
  /// **'Notification template moderation'**
  String get settingsNotificationModeration;

  /// No description provided for @settingsNotificationModerationDescription.
  ///
  /// In en, this message translates to:
  /// **'Approve or reject notification templates submitted by businesses'**
  String get settingsNotificationModerationDescription;

  /// No description provided for @settingsNotificationSmsPricing.
  ///
  /// In en, this message translates to:
  /// **'Notification SMS pricing'**
  String get settingsNotificationSmsPricing;

  /// No description provided for @settingsNotificationSmsPricingDescription.
  ///
  /// In en, this message translates to:
  /// **'Set the price per SMS for business notifications'**
  String get settingsNotificationSmsPricingDescription;

  /// No description provided for @settingsSystemScripts.
  ///
  /// In en, this message translates to:
  /// **'System scripts'**
  String get settingsSystemScripts;

  /// No description provided for @settingsSystemScriptsDescription.
  ///
  /// In en, this message translates to:
  /// **'Run global corrective operations for all businesses'**
  String get settingsSystemScriptsDescription;

  /// No description provided for @supportOperatorsPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Support operators'**
  String get supportOperatorsPageTitle;

  /// No description provided for @supportOperatorsRemoveOperatorTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove operator'**
  String get supportOperatorsRemoveOperatorTitle;

  /// No description provided for @supportOperatorsRemoveOperatorConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to revoke operator access for {email}?'**
  String supportOperatorsRemoveOperatorConfirm(String email);

  /// No description provided for @supportOperatorsAccessRevokedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Operator access revoked successfully'**
  String get supportOperatorsAccessRevokedSuccess;

  /// No description provided for @supportOperatorsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No support operators found'**
  String get supportOperatorsEmpty;

  /// No description provided for @supportOperatorsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'To add an operator, use the User Management page.'**
  String get supportOperatorsEmptyHint;

  /// No description provided for @supportOperatorsTelegramConnected.
  ///
  /// In en, this message translates to:
  /// **'Telegram linked'**
  String get supportOperatorsTelegramConnected;

  /// No description provided for @supportOperatorsTelegramNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not linked'**
  String get supportOperatorsTelegramNotConnected;

  /// No description provided for @supportOperatorsStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get supportOperatorsStatusInactive;

  /// No description provided for @settingsAISettings.
  ///
  /// In en, this message translates to:
  /// **'AI Settings'**
  String get settingsAISettings;

  /// No description provided for @settingsAISettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Configure Provider, model and API Key'**
  String get settingsAISettingsDescription;

  /// No description provided for @settingsAIPlans.
  ///
  /// In en, this message translates to:
  /// **'AI Plans'**
  String get settingsAIPlans;

  /// No description provided for @settingsAIPlansDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage AI usage plans and pricing'**
  String get settingsAIPlansDescription;

  /// No description provided for @settingsAIPrompts.
  ///
  /// In en, this message translates to:
  /// **'AI Prompts'**
  String get settingsAIPrompts;

  /// No description provided for @settingsAIPromptsDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage default prompts for different roles'**
  String get settingsAIPromptsDescription;

  /// No description provided for @settingsZohalServices.
  ///
  /// In en, this message translates to:
  /// **'Zohal Services'**
  String get settingsZohalServices;

  /// No description provided for @settingsZohalServicesDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage Zohal inquiry services and API settings'**
  String get settingsZohalServicesDescription;

  /// No description provided for @settingsZohalSettings.
  ///
  /// In en, this message translates to:
  /// **'Zohal Settings'**
  String get settingsZohalSettings;

  /// No description provided for @settingsZohalSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Set API Key and configure Zohal service'**
  String get settingsZohalSettingsDescription;

  /// No description provided for @settingsTaxProductCodes.
  ///
  /// In en, this message translates to:
  /// **'Tax Product Codes'**
  String get settingsTaxProductCodes;

  /// No description provided for @settingsTaxProductCodesDescription.
  ///
  /// In en, this message translates to:
  /// **'Search and import new list from XML file'**
  String get settingsTaxProductCodesDescription;

  /// No description provided for @settingsSystemMonitoring.
  ///
  /// In en, this message translates to:
  /// **'System Monitoring'**
  String get settingsSystemMonitoring;

  /// No description provided for @settingsSystemMonitoringDescription.
  ///
  /// In en, this message translates to:
  /// **'Check system status, hardware resources and services'**
  String get settingsSystemMonitoringDescription;

  /// No description provided for @settingsServiceLogs.
  ///
  /// In en, this message translates to:
  /// **'Service Logs'**
  String get settingsServiceLogs;

  /// No description provided for @settingsServiceLogsDescription.
  ///
  /// In en, this message translates to:
  /// **'View logs for hesabix-api, hesabix-rq-worker, and hesabix-notification-moderation and manage services'**
  String get settingsServiceLogsDescription;

  /// No description provided for @settingsBusinessActivityLogs.
  ///
  /// In en, this message translates to:
  /// **'Business Activity Logs'**
  String get settingsBusinessActivityLogs;

  /// No description provided for @settingsBusinessActivityLogsDescription.
  ///
  /// In en, this message translates to:
  /// **'View activity logs across all businesses with filters by date, business, user, and action type'**
  String get settingsBusinessActivityLogsDescription;

  /// No description provided for @serviceLogsPauseAutoRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pause auto-refresh'**
  String get serviceLogsPauseAutoRefreshTooltip;

  /// No description provided for @serviceLogsResumeAutoRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Resume auto-refresh'**
  String get serviceLogsResumeAutoRefreshTooltip;

  /// No description provided for @serviceLogsRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get serviceLogsRefreshTooltip;

  /// No description provided for @serviceLogsFollowTailOnTooltip.
  ///
  /// In en, this message translates to:
  /// **'Follow latest log line is on; turn off to read older entries'**
  String get serviceLogsFollowTailOnTooltip;

  /// No description provided for @serviceLogsFollowTailOffTooltip.
  ///
  /// In en, this message translates to:
  /// **'Follow latest log line is off'**
  String get serviceLogsFollowTailOffTooltip;

  /// No description provided for @serviceLogsLinesLabel.
  ///
  /// In en, this message translates to:
  /// **'Line count'**
  String get serviceLogsLinesLabel;

  /// No description provided for @serviceLogsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search log text…'**
  String get serviceLogsSearchHint;

  /// No description provided for @serviceLogsFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get serviceLogsFilterAll;

  /// No description provided for @serviceLogsFilterErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get serviceLogsFilterErrors;

  /// No description provided for @serviceLogsFilterWarnings.
  ///
  /// In en, this message translates to:
  /// **'Warn+'**
  String get serviceLogsFilterWarnings;

  /// No description provided for @serviceLogsActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get serviceLogsActive;

  /// No description provided for @serviceLogsInactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get serviceLogsInactive;

  /// No description provided for @serviceLogsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled at boot'**
  String get serviceLogsEnabled;

  /// No description provided for @serviceLogsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled at boot'**
  String get serviceLogsDisabled;

  /// No description provided for @serviceLogsRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get serviceLogsRestart;

  /// No description provided for @serviceLogsRestartConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm restart'**
  String get serviceLogsRestartConfirmTitle;

  /// No description provided for @serviceLogsRestartConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Service «{serviceName}» may be briefly unavailable. Type the exact service name to continue.'**
  String serviceLogsRestartConfirmBody(String serviceName);

  /// No description provided for @serviceLogsRestartTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Service name'**
  String get serviceLogsRestartTypeHint;

  /// No description provided for @serviceLogsStatusDetails.
  ///
  /// In en, this message translates to:
  /// **'systemctl status details'**
  String get serviceLogsStatusDetails;

  /// No description provided for @serviceLogsNoStatusOutput.
  ///
  /// In en, this message translates to:
  /// **'No status output available.'**
  String get serviceLogsNoStatusOutput;

  /// No description provided for @serviceLogsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Failed to load logs'**
  String get serviceLogsErrorTitle;

  /// No description provided for @serviceLogsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get serviceLogsRetry;

  /// No description provided for @serviceLogsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No log entries'**
  String get serviceLogsEmpty;

  /// No description provided for @serviceLogsLogCount.
  ///
  /// In en, this message translates to:
  /// **'Log lines: {count}'**
  String serviceLogsLogCount(int count);

  /// No description provided for @serviceLogsFilteredCount.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total}'**
  String serviceLogsFilteredCount(int shown, int total);

  /// No description provided for @serviceLogsLegendError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get serviceLogsLegendError;

  /// No description provided for @serviceLogsLegendWarn.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get serviceLogsLegendWarn;

  /// No description provided for @serviceLogsLegendInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get serviceLogsLegendInfo;

  /// No description provided for @serviceLogsFetchError.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch logs: {error}'**
  String serviceLogsFetchError(String error);

  /// No description provided for @serviceLogsRestartError.
  ///
  /// In en, this message translates to:
  /// **'Restart failed: {error}'**
  String serviceLogsRestartError(String error);

  /// No description provided for @serviceLogsRestartSuccessDefault.
  ///
  /// In en, this message translates to:
  /// **'Service restarted successfully'**
  String get serviceLogsRestartSuccessDefault;

  /// No description provided for @serviceLogsFollowTailChip.
  ///
  /// In en, this message translates to:
  /// **'Follow tail'**
  String get serviceLogsFollowTailChip;

  /// No description provided for @serviceLogsEmptyAllowedList.
  ///
  /// In en, this message translates to:
  /// **'The server returned an empty allowed-service list.'**
  String get serviceLogsEmptyAllowedList;

  /// No description provided for @serviceLogsNoFilterMatches.
  ///
  /// In en, this message translates to:
  /// **'No lines match the current filters or search'**
  String get serviceLogsNoFilterMatches;

  /// No description provided for @serviceLogsAllowedServicesFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh the service list from the server; using defaults. {error}'**
  String serviceLogsAllowedServicesFetchFailed(String error);

  /// No description provided for @serviceLogsStatusLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load service status: {error}'**
  String serviceLogsStatusLoadFailed(String error);

  /// No description provided for @settingsDatabaseBackup.
  ///
  /// In en, this message translates to:
  /// **'Database Backup'**
  String get settingsDatabaseBackup;

  /// No description provided for @settingsDatabaseBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Create full database backup and send to email, FTP or download directly'**
  String get settingsDatabaseBackupDescription;

  /// No description provided for @warranty.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get warranty;

  /// No description provided for @warrantyManagement.
  ///
  /// In en, this message translates to:
  /// **'Warranty Management'**
  String get warrantyManagement;

  /// No description provided for @warrantySettings.
  ///
  /// In en, this message translates to:
  /// **'Warranty Settings'**
  String get warrantySettings;

  /// No description provided for @warrantyCodes.
  ///
  /// In en, this message translates to:
  /// **'Warranty Codes'**
  String get warrantyCodes;

  /// No description provided for @warrantyCode.
  ///
  /// In en, this message translates to:
  /// **'Warranty Code'**
  String get warrantyCode;

  /// No description provided for @warrantySerial.
  ///
  /// In en, this message translates to:
  /// **'Warranty Serial'**
  String get warrantySerial;

  /// No description provided for @generateWarrantyCodes.
  ///
  /// In en, this message translates to:
  /// **'Generate Warranty Codes'**
  String get generateWarrantyCodes;

  /// No description provided for @warrantyActivation.
  ///
  /// In en, this message translates to:
  /// **'Warranty Activation'**
  String get warrantyActivation;

  /// No description provided for @warrantyTracking.
  ///
  /// In en, this message translates to:
  /// **'Warranty Tracking'**
  String get warrantyTracking;

  /// No description provided for @warrantyStatus.
  ///
  /// In en, this message translates to:
  /// **'Warranty Status'**
  String get warrantyStatus;

  /// No description provided for @warrantyGenerated.
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get warrantyGenerated;

  /// No description provided for @warrantyActivated.
  ///
  /// In en, this message translates to:
  /// **'Activated'**
  String get warrantyActivated;

  /// No description provided for @warrantyExpired.
  ///
  /// In en, this message translates to:
  /// **'This warranty has expired'**
  String get warrantyExpired;

  /// No description provided for @warrantyUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get warrantyUsed;

  /// No description provided for @warrantyRevoked.
  ///
  /// In en, this message translates to:
  /// **'This warranty has been revoked'**
  String get warrantyRevoked;

  /// No description provided for @warrantyDuration.
  ///
  /// In en, this message translates to:
  /// **'Warranty Duration'**
  String get warrantyDuration;

  /// No description provided for @warrantyDurationDays.
  ///
  /// In en, this message translates to:
  /// **'Warranty Duration (Days)'**
  String get warrantyDurationDays;

  /// No description provided for @warrantyExpiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires At'**
  String get warrantyExpiresAt;

  /// No description provided for @warrantyGeneratedAt.
  ///
  /// In en, this message translates to:
  /// **'Generated At'**
  String get warrantyGeneratedAt;

  /// No description provided for @warrantyActivatedAt.
  ///
  /// In en, this message translates to:
  /// **'Activated At'**
  String get warrantyActivatedAt;

  /// No description provided for @warrantyProduct.
  ///
  /// In en, this message translates to:
  /// **'Warranty Product'**
  String get warrantyProduct;

  /// No description provided for @warrantyCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get warrantyCustomer;

  /// No description provided for @warrantyCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Customer Name'**
  String get warrantyCustomerName;

  /// No description provided for @warrantyCustomerPhone.
  ///
  /// In en, this message translates to:
  /// **'Customer Phone'**
  String get warrantyCustomerPhone;

  /// No description provided for @warrantyCustomerEmail.
  ///
  /// In en, this message translates to:
  /// **'Customer Email'**
  String get warrantyCustomerEmail;

  /// No description provided for @warrantyProductSerial.
  ///
  /// In en, this message translates to:
  /// **'Product Serial'**
  String get warrantyProductSerial;

  /// No description provided for @activateWarranty.
  ///
  /// In en, this message translates to:
  /// **'Activate Warranty'**
  String get activateWarranty;

  /// No description provided for @trackWarranty.
  ///
  /// In en, this message translates to:
  /// **'Track Warranty'**
  String get trackWarranty;

  /// No description provided for @warrantyTrackingLink.
  ///
  /// In en, this message translates to:
  /// **'Warranty Tracking Link'**
  String get warrantyTrackingLink;

  /// No description provided for @warrantyCodeFormat.
  ///
  /// In en, this message translates to:
  /// **'Code Format'**
  String get warrantyCodeFormat;

  /// No description provided for @warrantyCodePrefix.
  ///
  /// In en, this message translates to:
  /// **'Code Prefix'**
  String get warrantyCodePrefix;

  /// No description provided for @warrantySerialFormat.
  ///
  /// In en, this message translates to:
  /// **'Serial Format'**
  String get warrantySerialFormat;

  /// No description provided for @warrantySerialLength.
  ///
  /// In en, this message translates to:
  /// **'Serial Length'**
  String get warrantySerialLength;

  /// No description provided for @warrantyRandom.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get warrantyRandom;

  /// No description provided for @warrantySequential.
  ///
  /// In en, this message translates to:
  /// **'Sequential'**
  String get warrantySequential;

  /// No description provided for @warrantyCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get warrantyCustom;

  /// No description provided for @warrantySecuritySettings.
  ///
  /// In en, this message translates to:
  /// **'Security Settings'**
  String get warrantySecuritySettings;

  /// No description provided for @warrantyRequireSerialVerification.
  ///
  /// In en, this message translates to:
  /// **'Require Product Serial Verification'**
  String get warrantyRequireSerialVerification;

  /// No description provided for @warrantyRequireProductInstanceMatch.
  ///
  /// In en, this message translates to:
  /// **'Require Product Instance Match'**
  String get warrantyRequireProductInstanceMatch;

  /// No description provided for @warrantyMaxActivationAttempts.
  ///
  /// In en, this message translates to:
  /// **'Max Activation Attempts'**
  String get warrantyMaxActivationAttempts;

  /// No description provided for @warrantyActivationLockoutDuration.
  ///
  /// In en, this message translates to:
  /// **'Lockout Duration (Minutes)'**
  String get warrantyActivationLockoutDuration;

  /// No description provided for @warrantyAutoLinkToPerson.
  ///
  /// In en, this message translates to:
  /// **'Auto Link to Person'**
  String get warrantyAutoLinkToPerson;

  /// No description provided for @warrantyEnableTrackingLink.
  ///
  /// In en, this message translates to:
  /// **'Enable Tracking Link'**
  String get warrantyEnableTrackingLink;

  /// No description provided for @warrantyTrackingLinkExpiresDays.
  ///
  /// In en, this message translates to:
  /// **'Tracking Link Expires (Days)'**
  String get warrantyTrackingLinkExpiresDays;

  /// No description provided for @warrantyEnableSmsNotification.
  ///
  /// In en, this message translates to:
  /// **'Send SMS on Activation'**
  String get warrantyEnableSmsNotification;

  /// No description provided for @warrantyEnableEmailNotification.
  ///
  /// In en, this message translates to:
  /// **'Send Email on Activation'**
  String get warrantyEnableEmailNotification;

  /// No description provided for @warrantyCodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'Warranty code not found'**
  String get warrantyCodeNotFound;

  /// No description provided for @warrantyInvalidSerial.
  ///
  /// In en, this message translates to:
  /// **'Invalid warranty serial'**
  String get warrantyInvalidSerial;

  /// No description provided for @warrantyAlreadyActivated.
  ///
  /// In en, this message translates to:
  /// **'This warranty has already been activated'**
  String get warrantyAlreadyActivated;

  /// No description provided for @warrantyActivationSuccess.
  ///
  /// In en, this message translates to:
  /// **'Warranty activated successfully'**
  String get warrantyActivationSuccess;

  /// No description provided for @warrantyActivationFailed.
  ///
  /// In en, this message translates to:
  /// **'Warranty activation failed'**
  String get warrantyActivationFailed;

  /// No description provided for @warrantyTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many activation attempts'**
  String get warrantyTooManyAttempts;

  /// No description provided for @warrantyProductSerialRequired.
  ///
  /// In en, this message translates to:
  /// **'Product serial is required'**
  String get warrantyProductSerialRequired;

  /// No description provided for @warrantyProductSerialNotFound.
  ///
  /// In en, this message translates to:
  /// **'Product serial not found'**
  String get warrantyProductSerialNotFound;

  /// No description provided for @warrantyLinkNotFound.
  ///
  /// In en, this message translates to:
  /// **'Tracking link not found'**
  String get warrantyLinkNotFound;

  /// No description provided for @warrantyLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'Tracking link has expired'**
  String get warrantyLinkExpired;

  /// No description provided for @warrantyLinkInactive.
  ///
  /// In en, this message translates to:
  /// **'Tracking link is inactive'**
  String get warrantyLinkInactive;

  /// No description provided for @warrantyPluginNotActive.
  ///
  /// In en, this message translates to:
  /// **'Warranty plugin is not active for this business'**
  String get warrantyPluginNotActive;

  /// No description provided for @warrantyGenerateCodes.
  ///
  /// In en, this message translates to:
  /// **'Generate Warranty Codes'**
  String get warrantyGenerateCodes;

  /// No description provided for @warrantyQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get warrantyQuantity;

  /// No description provided for @warrantyCustomSerials.
  ///
  /// In en, this message translates to:
  /// **'Custom Serials'**
  String get warrantyCustomSerials;

  /// No description provided for @warrantyCustomCodes.
  ///
  /// In en, this message translates to:
  /// **'Custom Codes'**
  String get warrantyCustomCodes;

  /// No description provided for @warrantyListCodes.
  ///
  /// In en, this message translates to:
  /// **'List Warranty Codes'**
  String get warrantyListCodes;

  /// No description provided for @warrantyFilterByStatus.
  ///
  /// In en, this message translates to:
  /// **'Filter by Status'**
  String get warrantyFilterByStatus;

  /// No description provided for @warrantyFilterByProduct.
  ///
  /// In en, this message translates to:
  /// **'Filter by Product'**
  String get warrantyFilterByProduct;

  /// No description provided for @warrantyEvents.
  ///
  /// In en, this message translates to:
  /// **'Warranty Events'**
  String get warrantyEvents;

  /// No description provided for @warrantyEventActivation.
  ///
  /// In en, this message translates to:
  /// **'Activation'**
  String get warrantyEventActivation;

  /// No description provided for @warrantyEventRepairRequest.
  ///
  /// In en, this message translates to:
  /// **'Repair Request'**
  String get warrantyEventRepairRequest;

  /// No description provided for @warrantyEventRepairCompleted.
  ///
  /// In en, this message translates to:
  /// **'Repair Completed'**
  String get warrantyEventRepairCompleted;

  /// No description provided for @warrantyEventReplacement.
  ///
  /// In en, this message translates to:
  /// **'Replacement'**
  String get warrantyEventReplacement;

  /// No description provided for @warrantyEventExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get warrantyEventExpired;

  /// No description provided for @warrantyEventRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get warrantyEventRevoked;

  /// No description provided for @warrantyManage.
  ///
  /// In en, this message translates to:
  /// **'Manage Warranty'**
  String get warrantyManage;

  /// No description provided for @customerClubTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Club'**
  String get customerClubTitle;

  /// No description provided for @customerClubMenu.
  ///
  /// In en, this message translates to:
  /// **'Customer Club'**
  String get customerClubMenu;

  /// No description provided for @customerClubTabLedger.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get customerClubTabLedger;

  /// No description provided for @customerClubTabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get customerClubTabSettings;

  /// No description provided for @customerClubTabAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust Points'**
  String get customerClubTabAdjust;

  /// No description provided for @customerClubLedgerTotal.
  ///
  /// In en, this message translates to:
  /// **'Transactions count'**
  String get customerClubLedgerTotal;

  /// No description provided for @customerClubLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get customerClubLoadMore;

  /// No description provided for @customerClubBalanceAfter.
  ///
  /// In en, this message translates to:
  /// **'Balance after'**
  String get customerClubBalanceAfter;

  /// No description provided for @customerClubPerson.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get customerClubPerson;

  /// No description provided for @customerClubEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable loyalty program'**
  String get customerClubEnabled;

  /// No description provided for @customerClubEarnMode.
  ///
  /// In en, this message translates to:
  /// **'Earning rule'**
  String get customerClubEarnMode;

  /// No description provided for @customerClubEarnPercent.
  ///
  /// In en, this message translates to:
  /// **'Percentage of basis amount'**
  String get customerClubEarnPercent;

  /// No description provided for @customerClubEarnPerCurrency.
  ///
  /// In en, this message translates to:
  /// **'Points per currency bracket'**
  String get customerClubEarnPerCurrency;

  /// No description provided for @customerClubAmountBasis.
  ///
  /// In en, this message translates to:
  /// **'Invoice amount basis'**
  String get customerClubAmountBasis;

  /// No description provided for @customerClubBasisNet.
  ///
  /// In en, this message translates to:
  /// **'Net excluding tax'**
  String get customerClubBasisNet;

  /// No description provided for @customerClubBasisTotal.
  ///
  /// In en, this message translates to:
  /// **'Total including tax'**
  String get customerClubBasisTotal;

  /// No description provided for @customerClubPercentOfBasis.
  ///
  /// In en, this message translates to:
  /// **'Percent of basis'**
  String get customerClubPercentOfBasis;

  /// No description provided for @customerClubPercentHint.
  ///
  /// In en, this message translates to:
  /// **'Example: 1 means 1% of basis amount'**
  String get customerClubPercentHint;

  /// No description provided for @customerClubStepAmount.
  ///
  /// In en, this message translates to:
  /// **'Bracket amount (currency)'**
  String get customerClubStepAmount;

  /// No description provided for @customerClubPointsPerStep.
  ///
  /// In en, this message translates to:
  /// **'Points per bracket'**
  String get customerClubPointsPerStep;

  /// No description provided for @customerClubRounding.
  ///
  /// In en, this message translates to:
  /// **'Rounding mode'**
  String get customerClubRounding;

  /// No description provided for @customerClubMaxPointsInvoice.
  ///
  /// In en, this message translates to:
  /// **'Max points per invoice (optional)'**
  String get customerClubMaxPointsInvoice;

  /// No description provided for @customerClubMinBasis.
  ///
  /// In en, this message translates to:
  /// **'Minimum basis amount to earn points'**
  String get customerClubMinBasis;

  /// No description provided for @customerClubRedemptionSection.
  ///
  /// In en, this message translates to:
  /// **'Redemption & expiry'**
  String get customerClubRedemptionSection;

  /// No description provided for @customerClubCurrencyValuePerPoint.
  ///
  /// In en, this message translates to:
  /// **'Discount amount per loyalty point (invoice currency)'**
  String get customerClubCurrencyValuePerPoint;

  /// No description provided for @customerClubCurrencyValuePerPointHint.
  ///
  /// In en, this message translates to:
  /// **'How much invoice discount one point buys, in invoice currency.'**
  String get customerClubCurrencyValuePerPointHint;

  /// No description provided for @customerClubMaxRedeemPerInvoice.
  ///
  /// In en, this message translates to:
  /// **'Maximum points redeemable per sales invoice (optional)'**
  String get customerClubMaxRedeemPerInvoice;

  /// No description provided for @customerClubPointsExpireAfterDays.
  ///
  /// In en, this message translates to:
  /// **'Points validity from grant date (days)'**
  String get customerClubPointsExpireAfterDays;

  /// No description provided for @customerClubPointsExpireAfterDaysHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty so points never expire.'**
  String get customerClubPointsExpireAfterDaysHint;

  /// No description provided for @customerClubRequireCustomerType.
  ///
  /// In en, this message translates to:
  /// **'Only contacts marked as Customer'**
  String get customerClubRequireCustomerType;

  /// No description provided for @customerClubSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Club settings saved.'**
  String get customerClubSettingsSaved;

  /// No description provided for @customerClubInvalidPersonId.
  ///
  /// In en, this message translates to:
  /// **'Invalid person id.'**
  String get customerClubInvalidPersonId;

  /// No description provided for @customerClubInvalidDelta.
  ///
  /// In en, this message translates to:
  /// **'Invalid delta points.'**
  String get customerClubInvalidDelta;

  /// No description provided for @customerClubDescriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Description is required.'**
  String get customerClubDescriptionRequired;

  /// No description provided for @customerClubAdjustmentSaved.
  ///
  /// In en, this message translates to:
  /// **'Adjustment recorded.'**
  String get customerClubAdjustmentSaved;

  /// No description provided for @customerClubNoAdjustPermission.
  ///
  /// In en, this message translates to:
  /// **'You cannot perform manual adjustments.'**
  String get customerClubNoAdjustPermission;

  /// No description provided for @customerClubAdjustIntro.
  ///
  /// In en, this message translates to:
  /// **'Increase or decrease points manually. Delta may be negative.'**
  String get customerClubAdjustIntro;

  /// No description provided for @customerClubPersonId.
  ///
  /// In en, this message translates to:
  /// **'Person ID'**
  String get customerClubPersonId;

  /// No description provided for @customerClubDeltaPoints.
  ///
  /// In en, this message translates to:
  /// **'Delta points (+/-)'**
  String get customerClubDeltaPoints;

  /// No description provided for @customerClubSubmitAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Submit adjustment'**
  String get customerClubSubmitAdjustment;

  /// No description provided for @customerClubSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Points rules, transactions and manual balances'**
  String get customerClubSettingsSubtitle;

  /// No description provided for @customerClubRoundingFloor.
  ///
  /// In en, this message translates to:
  /// **'Round down (floor)'**
  String get customerClubRoundingFloor;

  /// No description provided for @customerClubRoundingCeil.
  ///
  /// In en, this message translates to:
  /// **'Round up (ceil)'**
  String get customerClubRoundingCeil;

  /// No description provided for @customerClubRoundingRound.
  ///
  /// In en, this message translates to:
  /// **'Round to nearest'**
  String get customerClubRoundingRound;

  /// No description provided for @customerClubReferenceDocument.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get customerClubReferenceDocument;

  /// No description provided for @customerClubPointsShort.
  ///
  /// In en, this message translates to:
  /// **'pts'**
  String get customerClubPointsShort;

  /// No description provided for @customerClubTxnAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Manual adjustment'**
  String get customerClubTxnAdjustment;

  /// No description provided for @customerClubTxnRedeem.
  ///
  /// In en, this message translates to:
  /// **'Points redemption'**
  String get customerClubTxnRedeem;

  /// No description provided for @customerClubTxnRedeemVoid.
  ///
  /// In en, this message translates to:
  /// **'Redemption reversal'**
  String get customerClubTxnRedeemVoid;

  /// No description provided for @customerClubTxnInvoiceSync.
  ///
  /// In en, this message translates to:
  /// **'Invoice points sync'**
  String get customerClubTxnInvoiceSync;

  /// No description provided for @customerClubTxnInvoiceDeleteReversal.
  ///
  /// In en, this message translates to:
  /// **'Invoice deleted — points reversal'**
  String get customerClubTxnInvoiceDeleteReversal;

  /// No description provided for @customerClubTxnInvoiceDeleteReversalRedeem.
  ///
  /// In en, this message translates to:
  /// **'Invoice deleted — redemption reversal'**
  String get customerClubTxnInvoiceDeleteReversalRedeem;

  /// No description provided for @customerClubPermissionManageSettings.
  ///
  /// In en, this message translates to:
  /// **'Manage club settings ({title})'**
  String customerClubPermissionManageSettings(String title);

  /// No description provided for @customerClubPermissionAdjustManual.
  ///
  /// In en, this message translates to:
  /// **'Manual points adjustment ({title})'**
  String customerClubPermissionAdjustManual(String title);

  /// No description provided for @customerClubPermissionRedeemInvoice.
  ///
  /// In en, this message translates to:
  /// **'Redeem points on sales invoice ({title})'**
  String customerClubPermissionRedeemInvoice(String title);

  /// No description provided for @customerClubActionAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get customerClubActionAdjust;

  /// No description provided for @customerClubActionRedeem.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get customerClubActionRedeem;

  /// No description provided for @customerClubLedgerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No loyalty transactions yet.'**
  String get customerClubLedgerEmpty;

  /// No description provided for @customerClubLedgerShowingCount.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total}'**
  String customerClubLedgerShowingCount(int shown, int total);

  /// No description provided for @customerClubSettingsSectionActivation.
  ///
  /// In en, this message translates to:
  /// **'Activation'**
  String get customerClubSettingsSectionActivation;

  /// No description provided for @customerClubSettingsSectionEarning.
  ///
  /// In en, this message translates to:
  /// **'Earning rules'**
  String get customerClubSettingsSectionEarning;

  /// No description provided for @customerClubSettingsSectionAccess.
  ///
  /// In en, this message translates to:
  /// **'Person role restriction'**
  String get customerClubSettingsSectionAccess;

  /// No description provided for @customerClubSettingsSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved rules summary'**
  String get customerClubSettingsSummaryTitle;

  /// No description provided for @customerClubLedgerFilterPerson.
  ///
  /// In en, this message translates to:
  /// **'Filter transactions by person'**
  String get customerClubLedgerFilterPerson;

  /// No description provided for @customerClubCurrentPointsBalance.
  ///
  /// In en, this message translates to:
  /// **'Current points balance for this person'**
  String get customerClubCurrentPointsBalance;

  /// No description provided for @customerClubViewLedgerAction.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get customerClubViewLedgerAction;

  /// No description provided for @customerClubAdjustmentLargeDeltaTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm large adjustment'**
  String get customerClubAdjustmentLargeDeltaTitle;

  /// No description provided for @customerClubAdjustmentLargeDeltaBody.
  ///
  /// In en, this message translates to:
  /// **'Delta is {delta} points. Continue?'**
  String customerClubAdjustmentLargeDeltaBody(String delta);

  /// No description provided for @customerClubSummaryInactive.
  ///
  /// In en, this message translates to:
  /// **'Customer club is disabled for this business.'**
  String get customerClubSummaryInactive;

  /// No description provided for @customerClubTabAnalytics.
  ///
  /// In en, this message translates to:
  /// **'RFM / CLV analytics'**
  String get customerClubTabAnalytics;

  /// No description provided for @customerClubAnalyticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer analytics & segments'**
  String get customerClubAnalyticsTitle;

  /// No description provided for @customerClubAnalyticsRecalculate.
  ///
  /// In en, this message translates to:
  /// **'Recalculate'**
  String get customerClubAnalyticsRecalculate;

  /// No description provided for @customerClubAnalyticsRecalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get customerClubAnalyticsRecalculating;

  /// No description provided for @customerClubAnalyticsNoData.
  ///
  /// In en, this message translates to:
  /// **'No data yet. Enable RFM or CLV in settings, then tap Recalculate.'**
  String get customerClubAnalyticsNoData;

  /// No description provided for @customerClubAnalyticsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Enable “RFM analytics” and/or “CLV” in customer club settings to use this tab.'**
  String get customerClubAnalyticsDisabled;

  /// No description provided for @customerClubAnalyticsWindow.
  ///
  /// In en, this message translates to:
  /// **'Window: {start} to {end} ({months} mo)'**
  String customerClubAnalyticsWindow(String start, String end, int months);

  /// No description provided for @customerClubAnalyticsTotalPersons.
  ///
  /// In en, this message translates to:
  /// **'Customers in report'**
  String get customerClubAnalyticsTotalPersons;

  /// No description provided for @customerClubAnalyticsLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last computed'**
  String get customerClubAnalyticsLastRun;

  /// No description provided for @customerClubAnalyticsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search name, company or code'**
  String get customerClubAnalyticsSearch;

  /// No description provided for @customerClubAnalyticsFilterSegment.
  ///
  /// In en, this message translates to:
  /// **'Segment'**
  String get customerClubAnalyticsFilterSegment;

  /// No description provided for @customerClubAnalyticsAllSegments.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get customerClubAnalyticsAllSegments;

  /// No description provided for @customerClubAnalyticsR.
  ///
  /// In en, this message translates to:
  /// **'R (recency)'**
  String get customerClubAnalyticsR;

  /// No description provided for @customerClubAnalyticsF.
  ///
  /// In en, this message translates to:
  /// **'F (frequency)'**
  String get customerClubAnalyticsF;

  /// No description provided for @customerClubAnalyticsM.
  ///
  /// In en, this message translates to:
  /// **'M (monetary)'**
  String get customerClubAnalyticsM;

  /// No description provided for @customerClubAnalyticsCell.
  ///
  /// In en, this message translates to:
  /// **'RFM cell'**
  String get customerClubAnalyticsCell;

  /// No description provided for @customerClubAnalyticsCLV.
  ///
  /// In en, this message translates to:
  /// **'CLV'**
  String get customerClubAnalyticsCLV;

  /// No description provided for @customerClubAnalyticsMonetary.
  ///
  /// In en, this message translates to:
  /// **'Amount (window)'**
  String get customerClubAnalyticsMonetary;

  /// No description provided for @customerClubAnalyticsRecency.
  ///
  /// In en, this message translates to:
  /// **'Days since last purchase'**
  String get customerClubAnalyticsRecency;

  /// No description provided for @customerClubAnalyticsFrequency.
  ///
  /// In en, this message translates to:
  /// **'Purchase count'**
  String get customerClubAnalyticsFrequency;

  /// No description provided for @customerClubAnalyticsSegment.
  ///
  /// In en, this message translates to:
  /// **'Segment'**
  String get customerClubAnalyticsSegment;

  /// No description provided for @customerClubAnalyticsLoyaltyBalance.
  ///
  /// In en, this message translates to:
  /// **'Points balance'**
  String get customerClubAnalyticsLoyaltyBalance;

  /// No description provided for @customerClubCompositeScore.
  ///
  /// In en, this message translates to:
  /// **'Composite score'**
  String get customerClubCompositeScore;

  /// No description provided for @customerClubAnalyticsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get customerClubAnalyticsRefresh;

  /// No description provided for @customerClubAnalyticsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get customerClubAnalyticsLoadMore;

  /// No description provided for @customerClubAnalyticsSortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get customerClubAnalyticsSortLabel;

  /// No description provided for @customerClubAnalyticsSortMonetary.
  ///
  /// In en, this message translates to:
  /// **'Monetary'**
  String get customerClubAnalyticsSortMonetary;

  /// No description provided for @customerClubAnalyticsSortRecency.
  ///
  /// In en, this message translates to:
  /// **'Recency'**
  String get customerClubAnalyticsSortRecency;

  /// No description provided for @customerClubAnalyticsSortFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get customerClubAnalyticsSortFrequency;

  /// No description provided for @customerClubAnalyticsSortClv.
  ///
  /// In en, this message translates to:
  /// **'CLV'**
  String get customerClubAnalyticsSortClv;

  /// No description provided for @customerClubAnalyticsSortSegment.
  ///
  /// In en, this message translates to:
  /// **'Segment'**
  String get customerClubAnalyticsSortSegment;

  /// No description provided for @customerClubAnalyticsSortComposite.
  ///
  /// In en, this message translates to:
  /// **'Composite'**
  String get customerClubAnalyticsSortComposite;

  /// No description provided for @customerClubAnalyticsRecalculateDone.
  ///
  /// In en, this message translates to:
  /// **'Recalculation completed.'**
  String get customerClubAnalyticsRecalculateDone;

  /// No description provided for @customerClubSettingsSectionAnalytics.
  ///
  /// In en, this message translates to:
  /// **'RFM & customer lifetime value (CLV)'**
  String get customerClubSettingsSectionAnalytics;

  /// No description provided for @customerClubRfmEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable RFM analytics (recency, frequency, monetary)'**
  String get customerClubRfmEnabled;

  /// No description provided for @customerClubClvEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable customer lifetime value (CLV) estimate'**
  String get customerClubClvEnabled;

  /// No description provided for @customerClubRfmWindowMonths.
  ///
  /// In en, this message translates to:
  /// **'Analysis window length (months)'**
  String get customerClubRfmWindowMonths;

  /// No description provided for @customerClubRfmMonetaryBasisLabel.
  ///
  /// In en, this message translates to:
  /// **'Monetary basis for M'**
  String get customerClubRfmMonetaryBasisLabel;

  /// No description provided for @customerClubRfmScoringLabel.
  ///
  /// In en, this message translates to:
  /// **'Scoring method'**
  String get customerClubRfmScoringLabel;

  /// No description provided for @customerClubRfmScoringQuintiles.
  ///
  /// In en, this message translates to:
  /// **'Quintiles (classic)'**
  String get customerClubRfmScoringQuintiles;

  /// No description provided for @customerClubRfmScoringWeighted.
  ///
  /// In en, this message translates to:
  /// **'Weighted composite'**
  String get customerClubRfmScoringWeighted;

  /// No description provided for @customerClubRfmWeightR.
  ///
  /// In en, this message translates to:
  /// **'Weight — recency (R)'**
  String get customerClubRfmWeightR;

  /// No description provided for @customerClubRfmWeightF.
  ///
  /// In en, this message translates to:
  /// **'Weight — frequency (F)'**
  String get customerClubRfmWeightF;

  /// No description provided for @customerClubRfmWeightM.
  ///
  /// In en, this message translates to:
  /// **'Weight — monetary (M)'**
  String get customerClubRfmWeightM;

  /// No description provided for @customerClubClvFormulaLabel.
  ///
  /// In en, this message translates to:
  /// **'CLV formula'**
  String get customerClubClvFormulaLabel;

  /// No description provided for @customerClubClvFormulaHistorical.
  ///
  /// In en, this message translates to:
  /// **'Sum of purchases in window'**
  String get customerClubClvFormulaHistorical;

  /// No description provided for @customerClubClvFormulaProjection.
  ///
  /// In en, this message translates to:
  /// **'Avg order × annual frequency × lifespan'**
  String get customerClubClvFormulaProjection;

  /// No description provided for @customerClubClvLifespanYears.
  ///
  /// In en, this message translates to:
  /// **'Estimated customer lifespan (years) — for projection'**
  String get customerClubClvLifespanYears;

  /// No description provided for @customerClubAnalyticsHint.
  ///
  /// In en, this message translates to:
  /// **'After changing settings, run Recalculate from the analytics tab.'**
  String get customerClubAnalyticsHint;

  /// No description provided for @customerClubSettingsSectionLoyaltyRfm.
  ///
  /// In en, this message translates to:
  /// **'Loyalty points vs RFM'**
  String get customerClubSettingsSectionLoyaltyRfm;

  /// No description provided for @customerClubLoyaltyRfmMode.
  ///
  /// In en, this message translates to:
  /// **'Integration mode'**
  String get customerClubLoyaltyRfmMode;

  /// No description provided for @customerClubLoyaltyRfmDecoupled.
  ///
  /// In en, this message translates to:
  /// **'Separate: points from invoices; tiers use point balance'**
  String get customerClubLoyaltyRfmDecoupled;

  /// No description provided for @customerClubLoyaltyRfmTiers.
  ///
  /// In en, this message translates to:
  /// **'Tier multipliers follow RFM score (requires RFM analytics on)'**
  String get customerClubLoyaltyRfmTiers;

  /// No description provided for @customerClubLoyaltyRfmHint.
  ///
  /// In en, this message translates to:
  /// **'In RFM tier mode, set each tier’s min RFM score (0–1) via the tiers API field min_rfm_normalized, or rely on min_balance_points÷10000 as a fallback. Redemption still uses invoice-earned balance.'**
  String get customerClubLoyaltyRfmHint;

  /// No description provided for @customerClubAnalyticsSegmentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Segments'**
  String get customerClubAnalyticsSegmentsTitle;

  /// No description provided for @customerClubAnalyticsCampaignExport.
  ///
  /// In en, this message translates to:
  /// **'Campaign export'**
  String get customerClubAnalyticsCampaignExport;

  /// No description provided for @customerClubAnalyticsCampaignTitle.
  ///
  /// In en, this message translates to:
  /// **'Audience list for campaigns'**
  String get customerClubAnalyticsCampaignTitle;

  /// No description provided for @customerClubAnalyticsCampaignBody.
  ///
  /// In en, this message translates to:
  /// **'Person IDs for the current filters (segment + search). Paste into your SMS/email tool.'**
  String get customerClubAnalyticsCampaignBody;

  /// No description provided for @customerClubAnalyticsCampaignCopyIds.
  ///
  /// In en, this message translates to:
  /// **'Copy IDs'**
  String get customerClubAnalyticsCampaignCopyIds;

  /// No description provided for @customerClubAnalyticsCampaignTruncated.
  ///
  /// In en, this message translates to:
  /// **'Only {n} IDs returned; increase the API limit to fetch more.'**
  String customerClubAnalyticsCampaignTruncated(int n);

  /// No description provided for @customerClubAnalyticsRfmNormalized.
  ///
  /// In en, this message translates to:
  /// **'RFM normalized score (0–1)'**
  String get customerClubAnalyticsRfmNormalized;

  /// No description provided for @customerClubSortAsc.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get customerClubSortAsc;

  /// No description provided for @customerClubSortDesc.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get customerClubSortDesc;

  /// No description provided for @identityInquiryTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity Inquiry'**
  String get identityInquiryTitle;

  /// No description provided for @identityInquirySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Please enter national ID and birth date'**
  String get identityInquirySubtitle;

  /// No description provided for @nationalIdHint.
  ///
  /// In en, this message translates to:
  /// **'10-digit national ID'**
  String get nationalIdHint;

  /// No description provided for @nationalIdRequired.
  ///
  /// In en, this message translates to:
  /// **'National ID is required'**
  String get nationalIdRequired;

  /// No description provided for @nationalIdInvalidLength.
  ///
  /// In en, this message translates to:
  /// **'National ID must be 10 digits'**
  String get nationalIdInvalidLength;

  /// No description provided for @nationalIdInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid national ID'**
  String get nationalIdInvalid;

  /// No description provided for @birthDate.
  ///
  /// In en, this message translates to:
  /// **'Birth Date'**
  String get birthDate;

  /// No description provided for @birthDateHint.
  ///
  /// In en, this message translates to:
  /// **'Jalali date (YYYY-MM-DD or YYYY/MM/DD)'**
  String get birthDateHint;

  /// No description provided for @birthDateRequired.
  ///
  /// In en, this message translates to:
  /// **'Birth date is required'**
  String get birthDateRequired;

  /// No description provided for @birthDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid date format'**
  String get birthDateInvalid;

  /// No description provided for @selectBirthDate.
  ///
  /// In en, this message translates to:
  /// **'Select Date'**
  String get selectBirthDate;

  /// No description provided for @inquire.
  ///
  /// In en, this message translates to:
  /// **'Inquire'**
  String get inquire;

  /// No description provided for @inquiring.
  ///
  /// In en, this message translates to:
  /// **'Inquiring...'**
  String get inquiring;

  /// No description provided for @inquiryError.
  ///
  /// In en, this message translates to:
  /// **'Inquiry Error'**
  String get inquiryError;

  /// No description provided for @inquiryErrorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Inquiry error:'**
  String get inquiryErrorPrefix;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @noMatch.
  ///
  /// In en, this message translates to:
  /// **'No Match'**
  String get noMatch;

  /// No description provided for @noMatchDescription.
  ///
  /// In en, this message translates to:
  /// **'National ID and birth date do not match'**
  String get noMatchDescription;

  /// No description provided for @personalInformation.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get personalInformation;

  /// No description provided for @fatherName.
  ///
  /// In en, this message translates to:
  /// **'Father Name'**
  String get fatherName;

  /// No description provided for @alive.
  ///
  /// In en, this message translates to:
  /// **'Alive'**
  String get alive;

  /// No description provided for @deceased.
  ///
  /// In en, this message translates to:
  /// **'Deceased'**
  String get deceased;

  /// No description provided for @newInquiry.
  ///
  /// In en, this message translates to:
  /// **'New Inquiry'**
  String get newInquiry;

  /// No description provided for @identityInquiryDescription.
  ///
  /// In en, this message translates to:
  /// **'You can inquiry personal identity information by entering national ID and birth date'**
  String get identityInquiryDescription;

  /// No description provided for @noResultAvailable.
  ///
  /// In en, this message translates to:
  /// **'Error: No result available'**
  String get noResultAvailable;

  /// No description provided for @accountSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Account Settings'**
  String get accountSettingsTitle;

  /// No description provided for @accountSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage and configure all aspects of your account'**
  String get accountSettingsSubtitle;

  /// No description provided for @accountSettingsMarketingDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage referral links and marketing reports'**
  String get accountSettingsMarketingDescription;

  /// No description provided for @accountSettingsNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get accountSettingsNotificationsTitle;

  /// No description provided for @accountSettingsNotificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Notification channel settings and configuration'**
  String get accountSettingsNotificationsDescription;

  /// No description provided for @accountSettingsSignatureTitle.
  ///
  /// In en, this message translates to:
  /// **'Signature & Profile Picture'**
  String get accountSettingsSignatureTitle;

  /// No description provided for @accountSettingsSignatureDescription.
  ///
  /// In en, this message translates to:
  /// **'Upload and manage personal signature and profile picture'**
  String get accountSettingsSignatureDescription;

  /// No description provided for @accountSettingsApiKeysTitle.
  ///
  /// In en, this message translates to:
  /// **'API Keys'**
  String get accountSettingsApiKeysTitle;

  /// No description provided for @accountSettingsApiKeysDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage API keys for system access'**
  String get accountSettingsApiKeysDescription;

  /// No description provided for @accountSettingsLoginSessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Login Sessions'**
  String get accountSettingsLoginSessionsTitle;

  /// No description provided for @accountSettingsLoginSessionsDescription.
  ///
  /// In en, this message translates to:
  /// **'View and manage connected devices to your account'**
  String get accountSettingsLoginSessionsDescription;

  /// No description provided for @accountSettingsChangePasswordDescription.
  ///
  /// In en, this message translates to:
  /// **'Change account password'**
  String get accountSettingsChangePasswordDescription;

  /// No description provided for @accountSettingsVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Mobile & Email Verification'**
  String get accountSettingsVerificationTitle;

  /// No description provided for @accountSettingsVerificationDescription.
  ///
  /// In en, this message translates to:
  /// **'Verify mobile number and email for enhanced security'**
  String get accountSettingsVerificationDescription;

  /// No description provided for @accountSettingsNotificationHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification History'**
  String get accountSettingsNotificationHistoryTitle;

  /// No description provided for @accountSettingsNotificationHistoryDescription.
  ///
  /// In en, this message translates to:
  /// **'View all sent notifications (OTP, password reset, tickets, etc.)'**
  String get accountSettingsNotificationHistoryDescription;

  /// No description provided for @notificationCenterLevelInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get notificationCenterLevelInfo;

  /// No description provided for @notificationCenterLevelWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get notificationCenterLevelWarning;

  /// No description provided for @notificationCenterLevelCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get notificationCenterLevelCritical;

  /// No description provided for @notificationCenterLevelUnknown.
  ///
  /// In en, this message translates to:
  /// **'{level}'**
  String notificationCenterLevelUnknown(String level);

  /// No description provided for @notificationCenterClearAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear in-app notifications from your inbox'**
  String get notificationCenterClearAllTooltip;

  /// No description provided for @notificationCenterClearAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear notifications?'**
  String get notificationCenterClearAllTitle;

  /// No description provided for @notificationCenterClearAllMessage.
  ///
  /// In en, this message translates to:
  /// **'All visible announcements will be hidden. Live-only messages (not stored on the server) will also be removed from this list.'**
  String get notificationCenterClearAllMessage;

  /// No description provided for @notificationCenterClearAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get notificationCenterClearAllConfirm;

  /// No description provided for @notificationCenterClearAllCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get notificationCenterClearAllCancel;

  /// No description provided for @notificationCenterCleared.
  ///
  /// In en, this message translates to:
  /// **'Notifications cleared'**
  String get notificationCenterCleared;

  /// No description provided for @notificationsInappRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'In-app announcement retention'**
  String get notificationsInappRetentionTitle;

  /// No description provided for @notificationsInappRetentionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'System announcements you have read will be automatically removed or hidden after the number of days you set.'**
  String get notificationsInappRetentionSubtitle;

  /// No description provided for @notificationsInappRetentionEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable automatic cleanup of read items'**
  String get notificationsInappRetentionEnabled;

  /// No description provided for @notificationsInappRetentionDays.
  ///
  /// In en, this message translates to:
  /// **'Days after read before cleanup'**
  String get notificationsInappRetentionDays;

  /// No description provided for @apiKeysPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage API Keys'**
  String get apiKeysPageTitle;

  /// No description provided for @apiKeyErrorLoadingKeys.
  ///
  /// In en, this message translates to:
  /// **'Error loading keys'**
  String get apiKeyErrorLoadingKeys;

  /// No description provided for @apiKeyErrorCreatingKey.
  ///
  /// In en, this message translates to:
  /// **'Error creating key'**
  String get apiKeyErrorCreatingKey;

  /// No description provided for @apiKeyCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'API Key created'**
  String get apiKeyCreatedSuccessfully;

  /// No description provided for @apiKeySaveWarning.
  ///
  /// In en, this message translates to:
  /// **'Please save this key. This is the only time it will be displayed.'**
  String get apiKeySaveWarning;

  /// No description provided for @apiKeyClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get apiKeyClose;

  /// No description provided for @apiKeyCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get apiKeyCopy;

  /// No description provided for @apiKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Key copied'**
  String get apiKeyCopied;

  /// No description provided for @apiKeyUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Key updated successfully'**
  String get apiKeyUpdatedSuccessfully;

  /// No description provided for @apiKeyErrorUpdating.
  ///
  /// In en, this message translates to:
  /// **'Error updating key'**
  String get apiKeyErrorUpdating;

  /// No description provided for @apiKeyDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete API Key'**
  String get apiKeyDeleteTitle;

  /// No description provided for @apiKeyDeleteConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the key \"{name}\"?\nThis action is irreversible.'**
  String apiKeyDeleteConfirmation(String name);

  /// No description provided for @apiKeyDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Key deleted successfully'**
  String get apiKeyDeletedSuccessfully;

  /// No description provided for @apiKeyErrorDeleting.
  ///
  /// In en, this message translates to:
  /// **'Error deleting key'**
  String get apiKeyErrorDeleting;

  /// No description provided for @apiKeyFilterActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get apiKeyFilterActive;

  /// No description provided for @apiKeyFilterRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get apiKeyFilterRevoked;

  /// No description provided for @apiKeyFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get apiKeyFilterAll;

  /// No description provided for @apiKeyNoActiveKeys.
  ///
  /// In en, this message translates to:
  /// **'No active keys'**
  String get apiKeyNoActiveKeys;

  /// No description provided for @apiKeyNoRevokedKeys.
  ///
  /// In en, this message translates to:
  /// **'No revoked keys'**
  String get apiKeyNoRevokedKeys;

  /// No description provided for @apiKeyNoKeysCreated.
  ///
  /// In en, this message translates to:
  /// **'No API keys created'**
  String get apiKeyNoKeysCreated;

  /// No description provided for @apiKeyCreateNewButton.
  ///
  /// In en, this message translates to:
  /// **'Create New Key'**
  String get apiKeyCreateNewButton;

  /// No description provided for @apiKeyCreateHint.
  ///
  /// In en, this message translates to:
  /// **'Click the create button to create a new key'**
  String get apiKeyCreateHint;

  /// No description provided for @apiKeyNoRevokedHint.
  ///
  /// In en, this message translates to:
  /// **'No revoked keys to display'**
  String get apiKeyNoRevokedHint;

  /// No description provided for @apiKeyUsageHint.
  ///
  /// In en, this message translates to:
  /// **'Create a key to use the API in other applications'**
  String get apiKeyUsageHint;

  /// No description provided for @apiKeyEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get apiKeyEdit;

  /// No description provided for @apiKeyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get apiKeyDelete;

  /// No description provided for @apiKeyCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get apiKeyCreatedAt;

  /// No description provided for @apiKeyLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last Used'**
  String get apiKeyLastUsed;

  /// No description provided for @apiKeyExpiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get apiKeyExpiresAt;

  /// No description provided for @apiKeyRevokedAt.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get apiKeyRevokedAt;

  /// No description provided for @apiKeyAllowedIPs.
  ///
  /// In en, this message translates to:
  /// **'Allowed IPs'**
  String get apiKeyAllowedIPs;

  /// No description provided for @apiKeyCreateNewTitle.
  ///
  /// In en, this message translates to:
  /// **'Create New API Key'**
  String get apiKeyCreateNewTitle;

  /// No description provided for @apiKeyNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Key Name'**
  String get apiKeyNameLabel;

  /// No description provided for @apiKeyNameHint.
  ///
  /// In en, this message translates to:
  /// **'Example: Production API Key'**
  String get apiKeyNameHint;

  /// No description provided for @apiKeyScopeLabel.
  ///
  /// In en, this message translates to:
  /// **'Access Scope (JSON)'**
  String get apiKeyScopeLabel;

  /// No description provided for @apiKeyScopeHint.
  ///
  /// In en, this message translates to:
  /// **'Optional - Example: \'{\'\"read\": true, \"write\": false\'}\''**
  String get apiKeyScopeHint;

  /// No description provided for @apiKeyIPsLabel.
  ///
  /// In en, this message translates to:
  /// **'Allowed IP List'**
  String get apiKeyIPsLabel;

  /// No description provided for @apiKeyIPsHint.
  ///
  /// In en, this message translates to:
  /// **'Comma separated - Example: 192.168.1.1, 10.0.0.1'**
  String get apiKeyIPsHint;

  /// No description provided for @apiKeyExpiryLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiry Date and Time (Optional)'**
  String get apiKeyExpiryLabel;

  /// No description provided for @apiKeyExpiryHint.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get apiKeyExpiryHint;

  /// No description provided for @apiKeyNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get apiKeyNoExpiry;

  /// No description provided for @apiKeyEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit API Key'**
  String get apiKeyEditTitle;

  /// No description provided for @apiKeyWithoutName.
  ///
  /// In en, this message translates to:
  /// **'Unnamed'**
  String get apiKeyWithoutName;

  /// No description provided for @datePickerSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select Date'**
  String get datePickerSelectDate;

  /// No description provided for @dateInputInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date in YYYY/MM/DD format'**
  String get dateInputInvalidFormat;

  /// No description provided for @dateInputOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Date is outside the allowed range'**
  String get dateInputOutOfRange;

  /// No description provided for @dateInputOpenCalendar.
  ///
  /// In en, this message translates to:
  /// **'Open calendar'**
  String get dateInputOpenCalendar;

  /// No description provided for @timePickerSelectTime.
  ///
  /// In en, this message translates to:
  /// **'Select Time'**
  String get timePickerSelectTime;

  /// No description provided for @dateTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Date and Time'**
  String get dateTimeLabel;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @timeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeLabel;

  /// No description provided for @clearButton.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearButton;

  /// No description provided for @sessionsPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Login Sessions'**
  String get sessionsPageTitle;

  /// No description provided for @sessionsErrorLoading.
  ///
  /// In en, this message translates to:
  /// **'Error loading sessions'**
  String get sessionsErrorLoading;

  /// No description provided for @sessionsCannotDeleteCurrent.
  ///
  /// In en, this message translates to:
  /// **'Cannot delete current session'**
  String get sessionsCannotDeleteCurrent;

  /// No description provided for @sessionsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Session'**
  String get sessionsDeleteTitle;

  /// No description provided for @sessionsDeleteConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete session \"{device}\"?\nThis action is irreversible.'**
  String sessionsDeleteConfirmation(String device);

  /// No description provided for @sessionsDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Session deleted successfully'**
  String get sessionsDeletedSuccessfully;

  /// No description provided for @sessionsErrorDeleting.
  ///
  /// In en, this message translates to:
  /// **'Error deleting session'**
  String get sessionsErrorDeleting;

  /// No description provided for @sessionsNoOtherSessions.
  ///
  /// In en, this message translates to:
  /// **'No other sessions'**
  String get sessionsNoOtherSessions;

  /// No description provided for @sessionsRevokeAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Logout from all devices'**
  String get sessionsRevokeAllTitle;

  /// No description provided for @sessionsRevokeAllConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {count} other sessions?\nThis will logout all other devices.\nYour current session will be preserved.'**
  String sessionsRevokeAllConfirmation(int count);

  /// No description provided for @sessionsDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete All'**
  String get sessionsDeleteAll;

  /// No description provided for @sessionsDeleted.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions deleted'**
  String sessionsDeleted(int count);

  /// No description provided for @sessionsNoActive.
  ///
  /// In en, this message translates to:
  /// **'No active sessions'**
  String get sessionsNoActive;

  /// No description provided for @sessionsThisDevice.
  ///
  /// In en, this message translates to:
  /// **'This Device'**
  String get sessionsThisDevice;

  /// No description provided for @sessionsLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last Used'**
  String get sessionsLastUsed;

  /// No description provided for @sessionsCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get sessionsCreatedAt;

  /// No description provided for @sessionsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get sessionsToday;

  /// No description provided for @sessionsYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get sessionsYesterday;

  /// No description provided for @sessionsDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String sessionsDaysAgo(int days);

  /// No description provided for @sessionsWeeksAgo.
  ///
  /// In en, this message translates to:
  /// **'{weeks} weeks ago'**
  String sessionsWeeksAgo(int weeks);

  /// No description provided for @sessionsMonthsAgo.
  ///
  /// In en, this message translates to:
  /// **'{months} months ago'**
  String sessionsMonthsAgo(int months);

  /// No description provided for @invoiceWarehouseReleaseNone.
  ///
  /// In en, this message translates to:
  /// **'No warehouse document'**
  String get invoiceWarehouseReleaseNone;

  /// No description provided for @invoiceWarehouseReleaseDraft.
  ///
  /// In en, this message translates to:
  /// **'Warehouse draft'**
  String get invoiceWarehouseReleaseDraft;

  /// No description provided for @invoiceWarehouseReleasePosted.
  ///
  /// In en, this message translates to:
  /// **'Post warehouse immediately'**
  String get invoiceWarehouseReleasePosted;

  /// No description provided for @invoiceWarehouseReleaseSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Warehouse document after save'**
  String get invoiceWarehouseReleaseSectionTitle;

  /// No description provided for @invoiceWarehouseReleaseSectionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Uses your business default; changes are saved per invoice type in this browser.'**
  String get invoiceWarehouseReleaseSectionSubtitle;

  /// No description provided for @invoiceWarehouseReleaseBusinessTitle.
  ///
  /// In en, this message translates to:
  /// **'Warehouse document after invoice save'**
  String get invoiceWarehouseReleaseBusinessTitle;

  /// No description provided for @invoiceWarehouseReleaseBusinessSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When post_inventory / auto_post_warehouse are omitted (or null) in the API, this mode applies.'**
  String get invoiceWarehouseReleaseBusinessSubtitle;

  /// No description provided for @invoiceWarehouseReleaseStockHint.
  ///
  /// In en, this message translates to:
  /// **'With “post immediately”, the warehouse document is posted when the invoice is saved and the same shortage / negative-stock rules from the section below apply. Draft keeps it until you post manually.'**
  String get invoiceWarehouseReleaseStockHint;

  /// No description provided for @ftpBackupSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'FTP backup destination'**
  String get ftpBackupSettingsTitle;

  /// No description provided for @ftpBackupSettingsDescription.
  ///
  /// In en, this message translates to:
  /// **'Store connection details for optional backup upload to your FTP server.'**
  String get ftpBackupSettingsDescription;

  /// No description provided for @ftpPasswordLeaveEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep the current password'**
  String get ftpPasswordLeaveEmptyHint;

  /// No description provided for @ftpRemotePath.
  ///
  /// In en, this message translates to:
  /// **'Remote folder'**
  String get ftpRemotePath;

  /// No description provided for @ftpPassiveMode.
  ///
  /// In en, this message translates to:
  /// **'Passive mode (PASV)'**
  String get ftpPassiveMode;

  /// No description provided for @ftpUseFtps.
  ///
  /// In en, this message translates to:
  /// **'Use FTPS (FTP over TLS)'**
  String get ftpUseFtps;

  /// No description provided for @ftpSaveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get ftpSaveSettings;

  /// No description provided for @ftpDeleteSettings.
  ///
  /// In en, this message translates to:
  /// **'Remove FTP settings'**
  String get ftpDeleteSettings;

  /// No description provided for @ftpTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get ftpTestConnection;

  /// No description provided for @ftpScanUsage.
  ///
  /// In en, this message translates to:
  /// **'Scan folder usage'**
  String get ftpScanUsage;

  /// No description provided for @ftpUsageTotal.
  ///
  /// In en, this message translates to:
  /// **'Total size (this folder)'**
  String get ftpUsageTotal;

  /// No description provided for @ftpUsageFiles.
  ///
  /// In en, this message translates to:
  /// **'Files counted'**
  String get ftpUsageFiles;

  /// No description provided for @ftpUsageTruncated.
  ///
  /// In en, this message translates to:
  /// **'Scan stopped early (too many files)'**
  String get ftpUsageTruncated;

  /// No description provided for @ftpLastScan.
  ///
  /// In en, this message translates to:
  /// **'Last scan'**
  String get ftpLastScan;

  /// No description provided for @ftpSettingsUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Settings last saved'**
  String get ftpSettingsUpdatedAt;

  /// No description provided for @ftpNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get ftpNotConfigured;

  /// No description provided for @ftpUseSftp.
  ///
  /// In en, this message translates to:
  /// **'Use SFTP (SSH)'**
  String get ftpUseSftp;

  /// No description provided for @ftpInsecureWarning.
  ///
  /// In en, this message translates to:
  /// **'Without FTPS or SFTP, credentials and data can be read on the network. Enable FTPS or SFTP when possible.'**
  String get ftpInsecureWarning;

  /// No description provided for @ftpDeleteSettingsConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove backup destination'**
  String get ftpDeleteSettingsConfirmTitle;

  /// No description provided for @ftpDeleteSettingsConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove FTP/SFTP settings for this business? Automatic upload after backup will stop.'**
  String get ftpDeleteSettingsConfirmMessage;

  /// No description provided for @ftpTestResultSampleCount.
  ///
  /// In en, this message translates to:
  /// **'Directory listing sample: about {count} entries'**
  String ftpTestResultSampleCount(int count);

  /// No description provided for @backupFtpUploaded.
  ///
  /// In en, this message translates to:
  /// **'Copy on your server'**
  String get backupFtpUploaded;

  /// No description provided for @backupFtpNotUploaded.
  ///
  /// In en, this message translates to:
  /// **'Not sent to FTP'**
  String get backupFtpNotUploaded;

  /// No description provided for @backupOpenFtpSettings.
  ///
  /// In en, this message translates to:
  /// **'FTP settings'**
  String get backupOpenFtpSettings;

  /// No description provided for @backupFtpNotConfiguredError.
  ///
  /// In en, this message translates to:
  /// **'Save an FTP/SFTP destination in settings first.'**
  String get backupFtpNotConfiguredError;

  /// No description provided for @ftpSendAfterBackup.
  ///
  /// In en, this message translates to:
  /// **'Also upload to FTP after backup'**
  String get ftpSendAfterBackup;

  /// No description provided for @ftpSendAfterBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Requires saved FTP settings and permission'**
  String get ftpSendAfterBackupSubtitle;

  /// No description provided for @jobUploadingToFtp.
  ///
  /// In en, this message translates to:
  /// **'Uploading to FTP'**
  String get jobUploadingToFtp;

  /// No description provided for @jobFtpTestStarting.
  ///
  /// In en, this message translates to:
  /// **'FTP test starting'**
  String get jobFtpTestStarting;

  /// No description provided for @jobFtpTestRunning.
  ///
  /// In en, this message translates to:
  /// **'Running FTP checks'**
  String get jobFtpTestRunning;

  /// No description provided for @jobFtpTestCompleted.
  ///
  /// In en, this message translates to:
  /// **'FTP test completed'**
  String get jobFtpTestCompleted;

  /// No description provided for @jobFtpTestFailed.
  ///
  /// In en, this message translates to:
  /// **'FTP test failed'**
  String get jobFtpTestFailed;

  /// No description provided for @jobFtpUsageStarting.
  ///
  /// In en, this message translates to:
  /// **'Scanning FTP usage'**
  String get jobFtpUsageStarting;

  /// No description provided for @jobFtpUsageConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to FTP'**
  String get jobFtpUsageConnecting;

  /// No description provided for @jobFtpUsageScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning remote folders'**
  String get jobFtpUsageScanning;

  /// No description provided for @jobFtpUsageCompleted.
  ///
  /// In en, this message translates to:
  /// **'FTP usage scan completed'**
  String get jobFtpUsageCompleted;

  /// No description provided for @jobFtpUsageFailed.
  ///
  /// In en, this message translates to:
  /// **'FTP usage scan failed'**
  String get jobFtpUsageFailed;

  /// No description provided for @ftpTestResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection test'**
  String get ftpTestResultTitle;

  /// No description provided for @ftpClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get ftpClose;

  /// No description provided for @settingsPermissionManageFtp.
  ///
  /// In en, this message translates to:
  /// **'FTP backup connection'**
  String get settingsPermissionManageFtp;

  /// No description provided for @crmMenuNotesCalendar.
  ///
  /// In en, this message translates to:
  /// **'Notes & calendar'**
  String get crmMenuNotesCalendar;

  /// No description provided for @crmNotesCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'CRM notes & calendar'**
  String get crmNotesCalendarTitle;

  /// No description provided for @crmNotesRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get crmNotesRefresh;

  /// No description provided for @crmNotesAdd.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get crmNotesAdd;

  /// No description provided for @crmNotesMonthPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get crmNotesMonthPrev;

  /// No description provided for @crmNotesMonthNext.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get crmNotesMonthNext;

  /// No description provided for @crmNotesToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get crmNotesToday;

  /// No description provided for @crmNotesViewWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get crmNotesViewWeek;

  /// No description provided for @crmNotesViewMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get crmNotesViewMonth;

  /// No description provided for @crmNotesWeekPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get crmNotesWeekPrev;

  /// No description provided for @crmNotesWeekNext.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get crmNotesWeekNext;

  /// No description provided for @crmNotesMonthCalendarExpandTitle.
  ///
  /// In en, this message translates to:
  /// **'Full month calendar'**
  String get crmNotesMonthCalendarExpandTitle;

  /// No description provided for @crmNotesPickDayTooltip.
  ///
  /// In en, this message translates to:
  /// **'Choose day'**
  String get crmNotesPickDayTooltip;

  /// No description provided for @crmNotesDayNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes for this day'**
  String get crmNotesDayNotes;

  /// No description provided for @crmNotesNoNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes'**
  String get crmNotesNoNotes;

  /// No description provided for @crmNotesEmptyDayHint.
  ///
  /// In en, this message translates to:
  /// **'No notes for this day yet. Add one to keep your CRM timeline up to date.'**
  String get crmNotesEmptyDayHint;

  /// No description provided for @crmNotesRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get crmNotesRetry;

  /// No description provided for @crmNotesEditorMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get crmNotesEditorMoreOptions;

  /// No description provided for @crmNotesVisibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Who can see this note'**
  String get crmNotesVisibilityLabel;

  /// No description provided for @crmNotesVisibilityPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private (only me)'**
  String get crmNotesVisibilityPrivate;

  /// No description provided for @crmNotesVisibilityBusiness.
  ///
  /// In en, this message translates to:
  /// **'Everyone in this business'**
  String get crmNotesVisibilityBusiness;

  /// No description provided for @crmNotesVisibilityShared.
  ///
  /// In en, this message translates to:
  /// **'Selected people'**
  String get crmNotesVisibilityShared;

  /// No description provided for @crmNotesType.
  ///
  /// In en, this message translates to:
  /// **'Note type'**
  String get crmNotesType;

  /// No description provided for @crmNotesTitleOptional.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get crmNotesTitleOptional;

  /// No description provided for @crmNotesBody.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get crmNotesBody;

  /// No description provided for @crmNotesLeadOptional.
  ///
  /// In en, this message translates to:
  /// **'Lead (optional)'**
  String get crmNotesLeadOptional;

  /// No description provided for @crmNotesClearLead.
  ///
  /// In en, this message translates to:
  /// **'Clear lead'**
  String get crmNotesClearLead;

  /// No description provided for @crmNotesSharedUsers.
  ///
  /// In en, this message translates to:
  /// **'People who can see this note'**
  String get crmNotesSharedUsers;

  /// No description provided for @crmNotesMeetingStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get crmNotesMeetingStart;

  /// No description provided for @crmNotesMeetingEnd.
  ///
  /// In en, this message translates to:
  /// **'End (optional)'**
  String get crmNotesMeetingEnd;

  /// No description provided for @crmNotesSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get crmNotesSave;

  /// No description provided for @crmNotesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get crmNotesDelete;

  /// No description provided for @crmNotesComments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get crmNotesComments;

  /// No description provided for @crmNotesNoComments.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get crmNotesNoComments;

  /// No description provided for @crmNotesCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Write a comment…'**
  String get crmNotesCommentHint;

  /// No description provided for @crmNotesSendComment.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get crmNotesSendComment;

  /// No description provided for @crmNotesAudit.
  ///
  /// In en, this message translates to:
  /// **'Change history'**
  String get crmNotesAudit;

  /// No description provided for @crmNotesAuditEmpty.
  ///
  /// In en, this message translates to:
  /// **'No history entries yet.'**
  String get crmNotesAuditEmpty;

  /// No description provided for @crmNotesClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get crmNotesClose;

  /// No description provided for @crmNotesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get crmNotesEdit;

  /// No description provided for @crmNotesSearchLeads.
  ///
  /// In en, this message translates to:
  /// **'Search leads'**
  String get crmNotesSearchLeads;

  /// No description provided for @crmNotesApplySearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get crmNotesApplySearch;

  /// No description provided for @crmNotesErrorLoading.
  ///
  /// In en, this message translates to:
  /// **'Failed to load'**
  String get crmNotesErrorLoading;

  /// No description provided for @crmNotesErrorSaving.
  ///
  /// In en, this message translates to:
  /// **'Failed to save'**
  String get crmNotesErrorSaving;

  /// No description provided for @crmNotesAddNoteType.
  ///
  /// In en, this message translates to:
  /// **'New note type'**
  String get crmNotesAddNoteType;

  /// No description provided for @crmNotesNoteTypeCode.
  ///
  /// In en, this message translates to:
  /// **'Code (Latin, e.g. follow_up)'**
  String get crmNotesNoteTypeCode;

  /// No description provided for @crmNotesNoteTypeTitleFa.
  ///
  /// In en, this message translates to:
  /// **'Title (Persian)'**
  String get crmNotesNoteTypeTitleFa;

  /// No description provided for @crmNotesNoteTypeTitleEn.
  ///
  /// In en, this message translates to:
  /// **'Title (English)'**
  String get crmNotesNoteTypeTitleEn;

  /// No description provided for @crmNotesNoteTypeScheduling.
  ///
  /// In en, this message translates to:
  /// **'Scheduling'**
  String get crmNotesNoteTypeScheduling;

  /// No description provided for @crmNotesNoteTypeDayOnly.
  ///
  /// In en, this message translates to:
  /// **'Date only'**
  String get crmNotesNoteTypeDayOnly;

  /// No description provided for @crmNotesNoteTypeMeeting.
  ///
  /// In en, this message translates to:
  /// **'Meeting (date & time)'**
  String get crmNotesNoteTypeMeeting;

  /// No description provided for @crmNotesNoteTypeAllowComments.
  ///
  /// In en, this message translates to:
  /// **'Allow comments (for public notes)'**
  String get crmNotesNoteTypeAllowComments;

  /// No description provided for @crmNotesNoteTypeAllowCommentsHint.
  ///
  /// In en, this message translates to:
  /// **'Only affects notes that are visible to the business (public notes).'**
  String get crmNotesNoteTypeAllowCommentsHint;

  /// No description provided for @crmNotesNoteTypeCreated.
  ///
  /// In en, this message translates to:
  /// **'Note type created'**
  String get crmNotesNoteTypeCreated;

  /// No description provided for @crmNotesPickDateTime.
  ///
  /// In en, this message translates to:
  /// **'Pick date & time'**
  String get crmNotesPickDateTime;

  /// No description provided for @crmNotesDeleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This note will be removed. Continue?'**
  String get crmNotesDeleteConfirmMessage;

  /// No description provided for @crmNotesDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete note'**
  String get crmNotesDeleteConfirmTitle;

  /// No description provided for @crmNotesDeleteWarnComments.
  ///
  /// In en, this message translates to:
  /// **'Existing comments will also be removed.'**
  String get crmNotesDeleteWarnComments;

  /// No description provided for @crmNoteTabDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get crmNoteTabDetails;

  /// No description provided for @crmNoteTabComments.
  ///
  /// In en, this message translates to:
  /// **'Discussion'**
  String get crmNoteTabComments;

  /// No description provided for @crmNoteTabAudit.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get crmNoteTabAudit;

  /// No description provided for @crmNotesVisibilityShortPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get crmNotesVisibilityShortPrivate;

  /// No description provided for @crmNotesVisibilityShortBusiness.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get crmNotesVisibilityShortBusiness;

  /// No description provided for @crmNotesVisibilityShortShared.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get crmNotesVisibilityShortShared;

  /// No description provided for @crmNotesVisibilityHintPrivate.
  ///
  /// In en, this message translates to:
  /// **'Only you can see this note.'**
  String get crmNotesVisibilityHintPrivate;

  /// No description provided for @crmNotesVisibilityHintBusiness.
  ///
  /// In en, this message translates to:
  /// **'All members of this business who can access CRM.'**
  String get crmNotesVisibilityHintBusiness;

  /// No description provided for @crmNotesVisibilityHintShared.
  ///
  /// In en, this message translates to:
  /// **'Only you and the people you select.'**
  String get crmNotesVisibilityHintShared;

  /// No description provided for @crmNotesSharedPickHint.
  ///
  /// In en, this message translates to:
  /// **'Select at least one teammate (you are always included).'**
  String get crmNotesSharedPickHint;

  /// No description provided for @crmNotesEventDateButton.
  ///
  /// In en, this message translates to:
  /// **'Choose date'**
  String get crmNotesEventDateButton;

  /// No description provided for @crmNotesNoLeadsFound.
  ///
  /// In en, this message translates to:
  /// **'No leads match your search.'**
  String get crmNotesNoLeadsFound;

  /// No description provided for @crmNotesLeadSearchInDialogHint.
  ///
  /// In en, this message translates to:
  /// **'Type name, code, phone, or email…'**
  String get crmNotesLeadSearchInDialogHint;

  /// No description provided for @crmNotesCommentsDisabledTab.
  ///
  /// In en, this message translates to:
  /// **'Comments are disabled for this note type or visibility.'**
  String get crmNotesCommentsDisabledTab;

  /// No description provided for @crmNotesNoteTypeCodeHelper.
  ///
  /// In en, this message translates to:
  /// **'Latin letters, numbers, and underscore only. Used internally.'**
  String get crmNotesNoteTypeCodeHelper;

  /// No description provided for @crmNotesNoteTypePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview in current language'**
  String get crmNotesNoteTypePreview;

  /// No description provided for @crmNotesNoteTypeSectionIdentity.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get crmNotesNoteTypeSectionIdentity;

  /// No description provided for @crmNotesNoteTypeSectionTitles.
  ///
  /// In en, this message translates to:
  /// **'Titles'**
  String get crmNotesNoteTypeSectionTitles;

  /// No description provided for @crmNotesNoteTypeSectionBehavior.
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get crmNotesNoteTypeSectionBehavior;

  /// No description provided for @crmNotesCommentInputLabel.
  ///
  /// In en, this message translates to:
  /// **'New comment'**
  String get crmNotesCommentInputLabel;

  /// No description provided for @crmNotesAuditRecentLimit.
  ///
  /// In en, this message translates to:
  /// **'Showing the latest {count} entries'**
  String crmNotesAuditRecentLimit(int count);

  /// No description provided for @crmNoteAuditCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get crmNoteAuditCreated;

  /// No description provided for @crmNoteAuditUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get crmNoteAuditUpdated;

  /// No description provided for @crmNoteAuditVisibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility changed'**
  String get crmNoteAuditVisibility;

  /// No description provided for @crmNoteAuditAcl.
  ///
  /// In en, this message translates to:
  /// **'Sharing list changed'**
  String get crmNoteAuditAcl;

  /// No description provided for @crmNoteAuditSoftDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get crmNoteAuditSoftDeleted;

  /// No description provided for @crmNoteAuditCommentCreated.
  ///
  /// In en, this message translates to:
  /// **'Comment added'**
  String get crmNoteAuditCommentCreated;

  /// No description provided for @crmNoteAuditCommentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Comment removed'**
  String get crmNoteAuditCommentDeleted;

  /// No description provided for @crmNoteAuditOther.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get crmNoteAuditOther;

  /// No description provided for @crmDeleteIrreversible.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get crmDeleteIrreversible;

  /// No description provided for @crmDeleteLeadTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete lead'**
  String get crmDeleteLeadTitle;

  /// No description provided for @crmDeleteLeadMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete lead «{name}»?'**
  String crmDeleteLeadMessage(Object name);

  /// No description provided for @crmDeleteActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete activity'**
  String get crmDeleteActivityTitle;

  /// No description provided for @crmDeleteActivityMessageNamed.
  ///
  /// In en, this message translates to:
  /// **'Delete activity «{subject}»?'**
  String crmDeleteActivityMessageNamed(Object subject);

  /// No description provided for @crmDeleteActivityMessageUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Delete this activity?'**
  String get crmDeleteActivityMessageUnnamed;

  /// No description provided for @crmDeleteDealTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete deal'**
  String get crmDeleteDealTitle;

  /// No description provided for @crmDeleteDealMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete deal «{title}»?'**
  String crmDeleteDealMessage(Object title);

  /// No description provided for @crmDeleteProcessTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete process'**
  String get crmDeleteProcessTitle;

  /// No description provided for @crmDeleteProcessMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete process «{name}»?'**
  String crmDeleteProcessMessage(Object name);

  /// No description provided for @crmDeleteStageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete stage'**
  String get crmDeleteStageTitle;

  /// No description provided for @crmDeleteStageMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete stage «{name}»?'**
  String crmDeleteStageMessage(Object name);

  /// No description provided for @crmLeadFormSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Contact details, funnel stage, and follow-up.'**
  String get crmLeadFormSubtitle;

  /// No description provided for @crmActivityFormSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Link to a customer or a lead, then describe the interaction.'**
  String get crmActivityFormSubtitle;

  /// No description provided for @crmDealFormSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customer, pipeline stage, and financial details.'**
  String get crmDealFormSubtitle;

  /// No description provided for @crmConvertLeadTitle.
  ///
  /// In en, this message translates to:
  /// **'Convert to customer'**
  String get crmConvertLeadTitle;

  /// No description provided for @crmConvertLeadSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Creates a new person in contacts.'**
  String get crmConvertLeadSubtitle;

  /// No description provided for @crmConvertLeadIntro.
  ///
  /// In en, this message translates to:
  /// **'The lead will be converted and a new person record will be created in contacts.'**
  String get crmConvertLeadIntro;

  /// No description provided for @crmConvertWithDealLabel.
  ///
  /// In en, this message translates to:
  /// **'Also create a sales deal'**
  String get crmConvertWithDealLabel;

  /// No description provided for @crmConvertNoPipeline.
  ///
  /// In en, this message translates to:
  /// **'No active sales pipeline is available.'**
  String get crmConvertNoPipeline;

  /// No description provided for @crmConvertPipelineLabel.
  ///
  /// In en, this message translates to:
  /// **'Sales pipeline'**
  String get crmConvertPipelineLabel;

  /// No description provided for @crmConvertStageLabel.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get crmConvertStageLabel;

  /// No description provided for @crmConvertDealTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Deal title'**
  String get crmConvertDealTitleLabel;

  /// No description provided for @crmConvertAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get crmConvertAmountLabel;

  /// No description provided for @crmConvertSubmit.
  ///
  /// In en, this message translates to:
  /// **'Convert'**
  String get crmConvertSubmit;

  /// No description provided for @crmSectionIdentityContact.
  ///
  /// In en, this message translates to:
  /// **'Identity & contact'**
  String get crmSectionIdentityContact;

  /// No description provided for @crmSectionFunnel.
  ///
  /// In en, this message translates to:
  /// **'Funnel & stage'**
  String get crmSectionFunnel;

  /// No description provided for @crmSectionAssignmentFollowup.
  ///
  /// In en, this message translates to:
  /// **'Assignment & reminder'**
  String get crmSectionAssignmentFollowup;

  /// No description provided for @crmSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get crmSectionDescription;

  /// No description provided for @crmSectionActivityLink.
  ///
  /// In en, this message translates to:
  /// **'Customer or lead'**
  String get crmSectionActivityLink;

  /// No description provided for @crmSectionActivityScheduling.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get crmSectionActivityScheduling;

  /// No description provided for @crmSectionActivityDetails.
  ///
  /// In en, this message translates to:
  /// **'Subject & details'**
  String get crmSectionActivityDetails;

  /// No description provided for @crmSectionDealPipeline.
  ///
  /// In en, this message translates to:
  /// **'Pipeline & identity'**
  String get crmSectionDealPipeline;

  /// No description provided for @crmSectionDealCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer & documents'**
  String get crmSectionDealCustomer;

  /// No description provided for @crmSectionDealMoney.
  ///
  /// In en, this message translates to:
  /// **'Amount, currency & dates'**
  String get crmSectionDealMoney;

  /// No description provided for @crmActivityPickLead.
  ///
  /// In en, this message translates to:
  /// **'Search & select lead'**
  String get crmActivityPickLead;

  /// No description provided for @crmActivityClearLead.
  ///
  /// In en, this message translates to:
  /// **'Clear lead'**
  String get crmActivityClearLead;

  /// No description provided for @crmActivityTypeCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get crmActivityTypeCall;

  /// No description provided for @crmActivityTypeEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get crmActivityTypeEmail;

  /// No description provided for @crmActivityTypeMeeting.
  ///
  /// In en, this message translates to:
  /// **'Meeting'**
  String get crmActivityTypeMeeting;

  /// No description provided for @crmActivityTypeNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get crmActivityTypeNote;

  /// No description provided for @crmProcessFormSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Code, display name, and default flags for this workflow.'**
  String get crmProcessFormSubtitle;

  /// No description provided for @crmProcessSectionMain.
  ///
  /// In en, this message translates to:
  /// **'Definition'**
  String get crmProcessSectionMain;

  /// No description provided for @crmProcessSectionStages.
  ///
  /// In en, this message translates to:
  /// **'Initial stages (new only)'**
  String get crmProcessSectionStages;

  /// No description provided for @inventoryNegativePolicySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Warehouse posting: stock shortage rules'**
  String get inventoryNegativePolicySectionTitle;

  /// No description provided for @inventoryNegativePolicyIntro.
  ///
  /// In en, this message translates to:
  /// **'This is not the same as “inventory control” on each product—that toggle decides whether the item is tracked in stock at all. Here you decide whether posting an outgoing warehouse move can proceed when quantity on hand is insufficient (negative stock). By default posting is blocked; use the switches below for bulk vs unique items. Transfer documents can stay fully strict separately.'**
  String get inventoryNegativePolicyIntro;

  /// No description provided for @inventoryNegativePolicyBulkTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow negative stock for bulk items'**
  String get inventoryNegativePolicyBulkTitle;

  /// No description provided for @inventoryNegativePolicyBulkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Products in bulk inventory mode with inventory tracking enabled.'**
  String get inventoryNegativePolicyBulkSubtitle;

  /// No description provided for @inventoryNegativePolicyUniqueTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow negative stock for unique items'**
  String get inventoryNegativePolicyUniqueTitle;

  /// No description provided for @inventoryNegativePolicyUniqueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Serialized / unique inventory mode; higher risk of mismatches with physical stock.'**
  String get inventoryNegativePolicyUniqueSubtitle;

  /// No description provided for @inventoryNegativePolicyTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfers always require sufficient stock'**
  String get inventoryNegativePolicyTransferTitle;

  /// No description provided for @inventoryNegativePolicyTransferSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When enabled, transfer documents always run full shortage checks, regardless of the two options above.'**
  String get inventoryNegativePolicyTransferSubtitle;

  /// No description provided for @workflowMarketplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Workflow repository'**
  String get workflowMarketplaceTitle;

  /// No description provided for @workflowMarketplaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse workflows published by others and add them to your business.'**
  String get workflowMarketplaceSubtitle;

  /// No description provided for @workflowMarketplaceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search title and short description…'**
  String get workflowMarketplaceSearchHint;

  /// No description provided for @workflowMarketplaceTagFilterHint.
  ///
  /// In en, this message translates to:
  /// **'Tag filter (optional)'**
  String get workflowMarketplaceTagFilterHint;

  /// No description provided for @workflowMarketplaceEmpty.
  ///
  /// In en, this message translates to:
  /// **'No items in the repository yet.'**
  String get workflowMarketplaceEmpty;

  /// No description provided for @workflowMarketplaceInstallCount.
  ///
  /// In en, this message translates to:
  /// **'Installs'**
  String get workflowMarketplaceInstallCount;

  /// No description provided for @workflowMarketplacePublisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get workflowMarketplacePublisher;

  /// No description provided for @workflowMarketplacePublishedAt.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get workflowMarketplacePublishedAt;

  /// No description provided for @workflowMarketplaceVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get workflowMarketplaceVersion;

  /// No description provided for @workflowMarketplaceInstall.
  ///
  /// In en, this message translates to:
  /// **'Add to this business'**
  String get workflowMarketplaceInstall;

  /// No description provided for @workflowMarketplaceDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Package details'**
  String get workflowMarketplaceDetailTitle;

  /// No description provided for @workflowMarketplaceLongDescription.
  ///
  /// In en, this message translates to:
  /// **'Full description'**
  String get workflowMarketplaceLongDescription;

  /// No description provided for @workflowMarketplaceChangelog.
  ///
  /// In en, this message translates to:
  /// **'Changes in this version'**
  String get workflowMarketplaceChangelog;

  /// No description provided for @workflowMarketplaceBrowseTab.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get workflowMarketplaceBrowseTab;

  /// No description provided for @workflowMarketplaceOpen.
  ///
  /// In en, this message translates to:
  /// **'Workflow repository'**
  String get workflowMarketplaceOpen;

  /// No description provided for @workflowMarketplaceMyPublished.
  ///
  /// In en, this message translates to:
  /// **'My published'**
  String get workflowMarketplaceMyPublished;

  /// No description provided for @workflowMarketplacePublish.
  ///
  /// In en, this message translates to:
  /// **'Publish to repository'**
  String get workflowMarketplacePublish;

  /// No description provided for @workflowMarketplacePublishTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Repository title'**
  String get workflowMarketplacePublishTitleLabel;

  /// No description provided for @workflowMarketplaceShortDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Summary (list card)'**
  String get workflowMarketplaceShortDescriptionLabel;

  /// No description provided for @workflowMarketplaceLongDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Full description for repository'**
  String get workflowMarketplaceLongDescriptionLabel;

  /// No description provided for @workflowMarketplaceTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma-separated)'**
  String get workflowMarketplaceTagsLabel;

  /// No description provided for @workflowMarketplaceVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get workflowMarketplaceVersionLabel;

  /// No description provided for @workflowMarketplacePublishSubmit.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get workflowMarketplacePublishSubmit;

  /// No description provided for @workflowMarketplacePublishSaved.
  ///
  /// In en, this message translates to:
  /// **'Workflow published to the repository.'**
  String get workflowMarketplacePublishSaved;

  /// No description provided for @workflowMarketplaceInstalled.
  ///
  /// In en, this message translates to:
  /// **'Workflow added as draft.'**
  String get workflowMarketplaceInstalled;

  /// No description provided for @workflowMarketplaceNameAfterInstall.
  ///
  /// In en, this message translates to:
  /// **'Workflow name after install (optional)'**
  String get workflowMarketplaceNameAfterInstall;

  /// No description provided for @workflowMarketplaceError.
  ///
  /// In en, this message translates to:
  /// **'Repository error'**
  String get workflowMarketplaceError;

  /// No description provided for @workflowMarketplaceStatusLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get workflowMarketplaceStatusLive;

  /// No description provided for @workflowMarketplaceStatusPrivate.
  ///
  /// In en, this message translates to:
  /// **'Unpublished'**
  String get workflowMarketplaceStatusPrivate;

  /// No description provided for @workflowMarketplaceMyEmpty.
  ///
  /// In en, this message translates to:
  /// **'You have not published anything to the repository yet.'**
  String get workflowMarketplaceMyEmpty;

  /// No description provided for @workflowMarketplaceUnpublish.
  ///
  /// In en, this message translates to:
  /// **'Remove from repository'**
  String get workflowMarketplaceUnpublish;

  /// No description provided for @workflowMarketplaceUnpublishConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove from public list?'**
  String get workflowMarketplaceUnpublishConfirmTitle;

  /// No description provided for @workflowMarketplaceUnpublishConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Others will no longer see this workflow. It will stay in your list and you can publish it again later.'**
  String get workflowMarketplaceUnpublishConfirmBody;

  /// No description provided for @workflowMarketplaceRepublish.
  ///
  /// In en, this message translates to:
  /// **'Publish again'**
  String get workflowMarketplaceRepublish;

  /// No description provided for @workflowMarketplaceRemovedFromRepo.
  ///
  /// In en, this message translates to:
  /// **'Removed from the public repository.'**
  String get workflowMarketplaceRemovedFromRepo;

  /// No description provided for @workflowMarketplaceRepublishedToast.
  ///
  /// In en, this message translates to:
  /// **'Published to the repository again.'**
  String get workflowMarketplaceRepublishedToast;

  /// No description provided for @distributionMenu.
  ///
  /// In en, this message translates to:
  /// **'Field distribution'**
  String get distributionMenu;

  /// No description provided for @distributionTabDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get distributionTabDashboard;

  /// No description provided for @distributionTabToday.
  ///
  /// In en, this message translates to:
  /// **'Daily plan'**
  String get distributionTabToday;

  /// No description provided for @distributionTabRoutes.
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get distributionTabRoutes;

  /// No description provided for @distributionTabVisits.
  ///
  /// In en, this message translates to:
  /// **'Visits'**
  String get distributionTabVisits;

  /// No description provided for @distributionTabReturns.
  ///
  /// In en, this message translates to:
  /// **'Returns'**
  String get distributionTabReturns;

  /// No description provided for @distributionPermissionOperate.
  ///
  /// In en, this message translates to:
  /// **'Field work (start/end visit, returns)'**
  String get distributionPermissionOperate;

  /// No description provided for @distributionPermissionManage.
  ///
  /// In en, this message translates to:
  /// **'Routes, stops, assignments, approve returns'**
  String get distributionPermissionManage;

  /// No description provided for @distributionPermissionReportsTeam.
  ///
  /// In en, this message translates to:
  /// **'Team reports and plans for other users'**
  String get distributionPermissionReportsTeam;

  /// No description provided for @distributionSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get distributionSelectDate;

  /// No description provided for @distributionVisitsToday.
  ///
  /// In en, this message translates to:
  /// **'Visits today'**
  String get distributionVisitsToday;

  /// No description provided for @distributionCompletedToday.
  ///
  /// In en, this message translates to:
  /// **'Completed today'**
  String get distributionCompletedToday;

  /// No description provided for @distributionPendingReturns.
  ///
  /// In en, this message translates to:
  /// **'Pending returns'**
  String get distributionPendingReturns;

  /// No description provided for @distributionActiveRoutes.
  ///
  /// In en, this message translates to:
  /// **'Active routes'**
  String get distributionActiveRoutes;

  /// No description provided for @distributionNoPlan.
  ///
  /// In en, this message translates to:
  /// **'No route plan for this date.'**
  String get distributionNoPlan;

  /// No description provided for @distributionStartVisit.
  ///
  /// In en, this message translates to:
  /// **'Start visit'**
  String get distributionStartVisit;

  /// No description provided for @distributionCompleteVisit.
  ///
  /// In en, this message translates to:
  /// **'Complete visit'**
  String get distributionCompleteVisit;

  /// No description provided for @distributionOutcomeOrder.
  ///
  /// In en, this message translates to:
  /// **'Order / invoice'**
  String get distributionOutcomeOrder;

  /// No description provided for @distributionOutcomeNoOrder.
  ///
  /// In en, this message translates to:
  /// **'No order'**
  String get distributionOutcomeNoOrder;

  /// No description provided for @distributionOutcomeCancelled.
  ///
  /// In en, this message translates to:
  /// **'Visit cancelled'**
  String get distributionOutcomeCancelled;

  /// No description provided for @distributionDocumentIdHint.
  ///
  /// In en, this message translates to:
  /// **'Document ID (proforma/invoice), optional'**
  String get distributionDocumentIdHint;

  /// No description provided for @distributionDealIdHint.
  ///
  /// In en, this message translates to:
  /// **'CRM deal ID, optional'**
  String get distributionDealIdHint;

  /// No description provided for @distributionNoOrderReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for no order'**
  String get distributionNoOrderReason;

  /// No description provided for @distributionLinesJson.
  ///
  /// In en, this message translates to:
  /// **'Return lines (product id, qty, reason)'**
  String get distributionLinesJson;

  /// No description provided for @distributionReturnCreate.
  ///
  /// In en, this message translates to:
  /// **'Submit return request'**
  String get distributionReturnCreate;

  /// No description provided for @distributionRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get distributionRefresh;

  /// No description provided for @distributionPluginInactive.
  ///
  /// In en, this message translates to:
  /// **'Field distribution add-on is not active. Enable it from the marketplace.'**
  String get distributionPluginInactive;

  /// No description provided for @distributionSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Routes, daily plan, field visits and returns'**
  String get distributionSettingsSubtitle;

  /// No description provided for @distributionSharedRoutingCatalog.
  ///
  /// In en, this message translates to:
  /// **'Shared route catalog for all visitors'**
  String get distributionSharedRoutingCatalog;

  /// No description provided for @distributionSharedRoutingCatalogHint.
  ///
  /// In en, this message translates to:
  /// **'When off, each visitor only sees routes assigned to them.'**
  String get distributionSharedRoutingCatalogHint;

  /// No description provided for @distributionRequireVisitInDailyPlan.
  ///
  /// In en, this message translates to:
  /// **'Start visit only from daily plan'**
  String get distributionRequireVisitInDailyPlan;

  /// No description provided for @distributionRequireVisitInDailyPlanHint.
  ///
  /// In en, this message translates to:
  /// **'The person must be on that visitor daily plan.'**
  String get distributionRequireVisitInDailyPlanHint;

  /// No description provided for @distributionSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved.'**
  String get distributionSettingsSaved;

  /// No description provided for @distributionNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get distributionNotesLabel;

  /// No description provided for @reportsDistributionSection.
  ///
  /// In en, this message translates to:
  /// **'Distribution & field visits'**
  String get reportsDistributionSection;

  /// No description provided for @reportsDistributionDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Visit & returns summary'**
  String get reportsDistributionDashboardTitle;

  /// No description provided for @reportsDistributionDashboardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Visit and return statistics for a date range'**
  String get reportsDistributionDashboardSubtitle;

  /// No description provided for @invoiceGlobalDiscountSection.
  ///
  /// In en, this message translates to:
  /// **'Invoice-level discount'**
  String get invoiceGlobalDiscountSection;

  /// No description provided for @invoiceGlobalDiscountTypePercent.
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get invoiceGlobalDiscountTypePercent;

  /// No description provided for @invoiceGlobalDiscountTypeAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get invoiceGlobalDiscountTypeAmount;

  /// No description provided for @invoiceGlobalDiscountValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Invoice discount value'**
  String get invoiceGlobalDiscountValueLabel;

  /// No description provided for @invoiceGlobalDiscountLineDiscountHint.
  ///
  /// In en, this message translates to:
  /// **'Line discounts subtotal: {amount}'**
  String invoiceGlobalDiscountLineDiscountHint(String amount);

  /// No description provided for @invoiceGlobalDiscountAmountComputedHint.
  ///
  /// In en, this message translates to:
  /// **'Applied invoice discount: {amount}'**
  String invoiceGlobalDiscountAmountComputedHint(String amount);

  /// No description provided for @invoiceSummarySubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get invoiceSummarySubtotal;

  /// No description provided for @invoiceSummaryDiscount.
  ///
  /// In en, this message translates to:
  /// **'Total discount'**
  String get invoiceSummaryDiscount;

  /// No description provided for @invoiceSummaryTax.
  ///
  /// In en, this message translates to:
  /// **'Total tax'**
  String get invoiceSummaryTax;

  /// No description provided for @invoiceSummaryTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand total'**
  String get invoiceSummaryTotal;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoice-level discount (calculation)'**
  String get businessSettingsInvoiceGlobalDiscountTitle;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountBasisLabel.
  ///
  /// In en, this message translates to:
  /// **'Percent discount basis'**
  String get businessSettingsInvoiceGlobalDiscountBasisLabel;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountBasisSubtotalAfterLines.
  ///
  /// In en, this message translates to:
  /// **'Net after line discounts (pre-tax)'**
  String get businessSettingsInvoiceGlobalDiscountBasisSubtotalAfterLines;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountBasisGrossBeforeLines.
  ///
  /// In en, this message translates to:
  /// **'Gross before line discounts'**
  String get businessSettingsInvoiceGlobalDiscountBasisGrossBeforeLines;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountBasisTotalWithTax.
  ///
  /// In en, this message translates to:
  /// **'Sum of line totals including tax'**
  String get businessSettingsInvoiceGlobalDiscountBasisTotalWithTax;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountTaxModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Effect on tax'**
  String get businessSettingsInvoiceGlobalDiscountTaxModeLabel;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountTaxModeRecalculate.
  ///
  /// In en, this message translates to:
  /// **'Recalculate tax proportionally'**
  String get businessSettingsInvoiceGlobalDiscountTaxModeRecalculate;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountTaxModeKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep per-line tax amounts'**
  String get businessSettingsInvoiceGlobalDiscountTaxModeKeep;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountMaxPercent.
  ///
  /// In en, this message translates to:
  /// **'Max percent (optional)'**
  String get businessSettingsInvoiceGlobalDiscountMaxPercent;

  /// No description provided for @businessSettingsInvoiceGlobalDiscountMaxAmount.
  ///
  /// In en, this message translates to:
  /// **'Max amount (optional)'**
  String get businessSettingsInvoiceGlobalDiscountMaxAmount;

  /// No description provided for @editInvoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit invoice'**
  String get editInvoiceTitle;

  /// No description provided for @saveChangesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChangesTooltip;

  /// No description provided for @invoiceProductsTab.
  ///
  /// In en, this message translates to:
  /// **'Products & services'**
  String get invoiceProductsTab;

  /// No description provided for @invoiceTransactionsTab.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get invoiceTransactionsTab;

  /// No description provided for @invoiceInstallmentsTab.
  ///
  /// In en, this message translates to:
  /// **'Installments'**
  String get invoiceInstallmentsTab;

  /// No description provided for @invoiceSettingsTab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get invoiceSettingsTab;

  /// No description provided for @invoiceGlobalDiscountPercentInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invoice discount percent must be between 0 and 100'**
  String get invoiceGlobalDiscountPercentInvalid;

  /// No description provided for @invoiceGlobalDiscountAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invoice discount amount cannot be negative'**
  String get invoiceGlobalDiscountAmountInvalid;

  /// No description provided for @invoiceGlobalDiscountValueInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invoice discount value is invalid'**
  String get invoiceGlobalDiscountValueInvalid;

  /// No description provided for @fiscalYearRollbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Revert current fiscal year'**
  String get fiscalYearRollbackTitle;

  /// No description provided for @fiscalYearRollbackRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get fiscalYearRollbackRetry;

  /// No description provided for @fiscalYearRollbackTokenMissing.
  ///
  /// In en, this message translates to:
  /// **'No confirmation code or it has expired. Tap “Refresh preview” and try again.'**
  String get fiscalYearRollbackTokenMissing;

  /// No description provided for @fiscalYearRollbackConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Final confirmation'**
  String get fiscalYearRollbackConfirmTitle;

  /// No description provided for @fiscalYearRollbackConfirmWithBackupBody.
  ///
  /// In en, this message translates to:
  /// **'A full business backup will be saved in the system first, then the current fiscal year and all its documents will be removed. Closing documents on the previous year (if any) will also be removed. This cannot be undone in the app.'**
  String get fiscalYearRollbackConfirmWithBackupBody;

  /// No description provided for @fiscalYearRollbackConfirmWithoutBackupBody.
  ///
  /// In en, this message translates to:
  /// **'The current fiscal year and all its documents will be removed. Closing documents on the previous year (if any) will also be removed. This cannot be undone in the app.'**
  String get fiscalYearRollbackConfirmWithoutBackupBody;

  /// No description provided for @fiscalYearRollbackCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get fiscalYearRollbackCancel;

  /// No description provided for @fiscalYearRollbackConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Remove current year'**
  String get fiscalYearRollbackConfirmDelete;

  /// No description provided for @fiscalYearRollbackPhaseBackupStarting.
  ///
  /// In en, this message translates to:
  /// **'Creating full system backup…'**
  String get fiscalYearRollbackPhaseBackupStarting;

  /// No description provided for @fiscalYearRollbackBackupStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start backup.'**
  String get fiscalYearRollbackBackupStartFailed;

  /// No description provided for @fiscalYearRollbackBackupJobIdMissing.
  ///
  /// In en, this message translates to:
  /// **'Backup job id was not returned by the server.'**
  String get fiscalYearRollbackBackupJobIdMissing;

  /// No description provided for @fiscalYearRollbackPhasePreviewRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refreshing preview (new confirmation code)…'**
  String get fiscalYearRollbackPhasePreviewRefresh;

  /// No description provided for @fiscalYearRollbackAfterBackupBlocked.
  ///
  /// In en, this message translates to:
  /// **'After the backup, fiscal rollback is no longer allowed. The business state may have changed. Review the preview and try again.'**
  String get fiscalYearRollbackAfterBackupBlocked;

  /// No description provided for @fiscalYearRollbackTokenAfterBackupMissing.
  ///
  /// In en, this message translates to:
  /// **'No confirmation code after backup. Tap “Refresh preview”.'**
  String get fiscalYearRollbackTokenAfterBackupMissing;

  /// No description provided for @fiscalYearRollbackTokenMissingGeneric.
  ///
  /// In en, this message translates to:
  /// **'Confirmation code is not available.'**
  String get fiscalYearRollbackTokenMissingGeneric;

  /// No description provided for @fiscalYearRollbackPhaseDeleting.
  ///
  /// In en, this message translates to:
  /// **'Removing current fiscal year…'**
  String get fiscalYearRollbackPhaseDeleting;

  /// No description provided for @fiscalYearRollbackSuccessFallback.
  ///
  /// In en, this message translates to:
  /// **'Completed successfully'**
  String get fiscalYearRollbackSuccessFallback;

  /// No description provided for @fiscalYearRollbackWarningCard.
  ///
  /// In en, this message translates to:
  /// **'This removes all documents in the current fiscal year and makes the previous year current.'**
  String get fiscalYearRollbackWarningCard;

  /// No description provided for @fiscalYearRollbackCurrentYearLabel.
  ///
  /// In en, this message translates to:
  /// **'Current year (will be removed)'**
  String get fiscalYearRollbackCurrentYearLabel;

  /// No description provided for @fiscalYearRollbackYearIdSuffix.
  ///
  /// In en, this message translates to:
  /// **'ID {id}'**
  String fiscalYearRollbackYearIdSuffix(String id);

  /// No description provided for @fiscalYearRollbackNextCurrentLabel.
  ///
  /// In en, this message translates to:
  /// **'Will become current'**
  String get fiscalYearRollbackNextCurrentLabel;

  /// No description provided for @fiscalYearRollbackDocCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Documents in current year: {count}'**
  String fiscalYearRollbackDocCountLabel(String count);

  /// No description provided for @fiscalYearRollbackClosingDocsToDelete.
  ///
  /// In en, this message translates to:
  /// **'Closing documents on the previous year to be removed: {count}'**
  String fiscalYearRollbackClosingDocsToDelete(String count);

  /// No description provided for @fiscalYearRollbackBackupCheckboxTitle.
  ///
  /// In en, this message translates to:
  /// **'Take a full backup before removing the year'**
  String get fiscalYearRollbackBackupCheckboxTitle;

  /// No description provided for @fiscalYearRollbackBackupCheckboxSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Same system backup (.hbx) as in settings, for restore if needed.'**
  String get fiscalYearRollbackBackupCheckboxSubtitle;

  /// No description provided for @fiscalYearRollbackOpenBackupPage.
  ///
  /// In en, this message translates to:
  /// **'Open backup page'**
  String get fiscalYearRollbackOpenBackupPage;

  /// No description provided for @fiscalYearRollbackExecuteButton.
  ///
  /// In en, this message translates to:
  /// **'Remove current fiscal year'**
  String get fiscalYearRollbackExecuteButton;

  /// No description provided for @fiscalYearRollbackBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'This action is not allowed right now — reasons:'**
  String get fiscalYearRollbackBlockedTitle;

  /// No description provided for @fiscalYearRollbackBlockedHint.
  ///
  /// In en, this message translates to:
  /// **'After fixing the items below, tap “Refresh preview”.'**
  String get fiscalYearRollbackBlockedHint;

  /// No description provided for @fiscalYearRollbackRefreshPreview.
  ///
  /// In en, this message translates to:
  /// **'Refresh preview'**
  String get fiscalYearRollbackRefreshPreview;

  /// No description provided for @fiscalYearRollbackBackupProgressPrefix.
  ///
  /// In en, this message translates to:
  /// **'Backup: {detail}'**
  String fiscalYearRollbackBackupProgressPrefix(String detail);

  /// No description provided for @fiscalYearRollbackPreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Fiscal rollback preview failed.'**
  String get fiscalYearRollbackPreviewFailed;

  /// No description provided for @fiscalYearRollbackNetworkUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your connection and sign-in.'**
  String get fiscalYearRollbackNetworkUnreachable;

  /// No description provided for @fiscalYearRollbackExecuteFailed.
  ///
  /// In en, this message translates to:
  /// **'Fiscal rollback failed.'**
  String get fiscalYearRollbackExecuteFailed;

  /// No description provided for @fiscalYearRollbackExecuteFailedSupport.
  ///
  /// In en, this message translates to:
  /// **'The operation failed. If it keeps happening, contact support.'**
  String get fiscalYearRollbackExecuteFailedSupport;

  /// No description provided for @backupJobWaitTimeout.
  ///
  /// In en, this message translates to:
  /// **'Backup did not finish within the wait time. Check status under Settings → Backup.'**
  String get backupJobWaitTimeout;

  /// No description provided for @backupJobStorageLimitFallback.
  ///
  /// In en, this message translates to:
  /// **'Backup could not be saved due to storage limits. Activate a plan or free space.'**
  String get backupJobStorageLimitFallback;

  /// No description provided for @settingsSideCurrenciesTitle.
  ///
  /// In en, this message translates to:
  /// **'Secondary currencies'**
  String get settingsSideCurrenciesTitle;

  /// No description provided for @settingsSideCurrenciesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add and remove currencies available for this business'**
  String get settingsSideCurrenciesSubtitle;

  /// No description provided for @settingsInvoiceFxPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoice FX revaluation policy'**
  String get settingsInvoiceFxPolicyTitle;

  /// No description provided for @settingsInvoiceFxPolicySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reference time for the rate and behavior when no rate exists (base vs. foreign currency)'**
  String get settingsInvoiceFxPolicySubtitle;

  /// No description provided for @fxRevaluationSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoice revaluation (policy)'**
  String get fxRevaluationSettingsTitle;

  /// No description provided for @fxRevaluationSettingsIntro.
  ///
  /// In en, this message translates to:
  /// **'These options define the reference time for the revaluation rate (against the base currency) for invoices in foreign currency, and what happens if no rate exists.'**
  String get fxRevaluationSettingsIntro;

  /// No description provided for @fxRevaluationAsOfSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Reference time for the rate (as_of)'**
  String get fxRevaluationAsOfSourceLabel;

  /// No description provided for @fxRevaluationAsOfSourceDocumentDate.
  ///
  /// In en, this message translates to:
  /// **'Document date (time from the option below)'**
  String get fxRevaluationAsOfSourceDocumentDate;

  /// No description provided for @fxRevaluationAsOfSourceRegisteredAt.
  ///
  /// In en, this message translates to:
  /// **'When the document is registered in the system'**
  String get fxRevaluationAsOfSourceRegisteredAt;

  /// No description provided for @fxRevaluationDateEffectiveLabel.
  ///
  /// In en, this message translates to:
  /// **'Effective time on that day (UTC)'**
  String get fxRevaluationDateEffectiveLabel;

  /// No description provided for @fxRevaluationTimeStartOfDay.
  ///
  /// In en, this message translates to:
  /// **'Start of day 00:00'**
  String get fxRevaluationTimeStartOfDay;

  /// No description provided for @fxRevaluationTimeNoon.
  ///
  /// In en, this message translates to:
  /// **'Midday 12:00'**
  String get fxRevaluationTimeNoon;

  /// No description provided for @fxRevaluationTimeEndOfDay.
  ///
  /// In en, this message translates to:
  /// **'End of day 23:59:59 (multiple rates per day)'**
  String get fxRevaluationTimeEndOfDay;

  /// No description provided for @fxRevaluationWhenNoRateLabel.
  ///
  /// In en, this message translates to:
  /// **'If no revaluation rate exists for the reference time'**
  String get fxRevaluationWhenNoRateLabel;

  /// No description provided for @fxRevaluationWhenNoRateBlock.
  ///
  /// In en, this message translates to:
  /// **'Block saving the invoice'**
  String get fxRevaluationWhenNoRateBlock;

  /// No description provided for @fxRevaluationWhenNoRateAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow saving without a rate (incomplete FX on the document)'**
  String get fxRevaluationWhenNoRateAllow;

  /// No description provided for @fxRevaluationSettingsFooterNote.
  ///
  /// In en, this message translates to:
  /// **'Users without “Currency revaluation” permission cannot pick a specific rate row; the system uses the latest effective rate up to the reference time.'**
  String get fxRevaluationSettingsFooterNote;

  /// No description provided for @fxRevaluationSettingsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String fxRevaluationSettingsLoadError(String error);

  /// No description provided for @fxRevaluationSettingsSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String fxRevaluationSettingsSaveError(String error);

  /// No description provided for @invoiceFxRateFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Revaluation rate (optional)'**
  String get invoiceFxRateFieldLabel;

  /// No description provided for @invoiceFxRateAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic (business policy settings)'**
  String get invoiceFxRateAuto;

  /// No description provided for @invoiceFxRateHelper.
  ///
  /// In en, this message translates to:
  /// **'For non-base currency; “Automatic” uses the latest valid rate up to the document reference time.'**
  String get invoiceFxRateHelper;

  /// No description provided for @invoiceFxRateStoredOnDocument.
  ///
  /// In en, this message translates to:
  /// **'Rate stored on this document'**
  String get invoiceFxRateStoredOnDocument;

  /// No description provided for @invoiceFxRateRow.
  ///
  /// In en, this message translates to:
  /// **'{rate} — {effective}{idPart}'**
  String invoiceFxRateRow(String rate, String effective, String idPart);

  /// No description provided for @crmWebChatError.
  ///
  /// In en, this message translates to:
  /// **'Error: {detail}'**
  String crmWebChatError(String detail);

  /// No description provided for @crmWebChatErrorLoadingMessages.
  ///
  /// In en, this message translates to:
  /// **'Error loading messages: {detail}'**
  String crmWebChatErrorLoadingMessages(String detail);

  /// No description provided for @crmWebChatStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get crmWebChatStatusOpen;

  /// No description provided for @crmWebChatStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get crmWebChatStatusPending;

  /// No description provided for @crmWebChatStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get crmWebChatStatusResolved;

  /// No description provided for @crmWebChatFileSaved.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get crmWebChatFileSaved;

  /// No description provided for @crmWebChatErrorDownload.
  ///
  /// In en, this message translates to:
  /// **'Download error: {detail}'**
  String crmWebChatErrorDownload(String detail);

  /// No description provided for @crmWebChatFileUploadDisabledCrm.
  ///
  /// In en, this message translates to:
  /// **'File uploads are disabled in CRM settings.'**
  String get crmWebChatFileUploadDisabledCrm;

  /// No description provided for @crmWebChatFileReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the file (size or browser limit). Try a smaller file.'**
  String get crmWebChatFileReadFailed;

  /// No description provided for @crmWebChatFileIdMissing.
  ///
  /// In en, this message translates to:
  /// **'File id was not returned from the server.'**
  String get crmWebChatFileIdMissing;

  /// No description provided for @crmWebChatFileSent.
  ///
  /// In en, this message translates to:
  /// **'File sent'**
  String get crmWebChatFileSent;

  /// No description provided for @crmWebChatNoCrmWritePermission.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to change CRM data.'**
  String get crmWebChatNoCrmWritePermission;

  /// No description provided for @crmWebChatMessageSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get crmWebChatMessageSent;

  /// No description provided for @crmWebChatSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get crmWebChatSaved;

  /// No description provided for @crmWebChatWidgetCreated.
  ///
  /// In en, this message translates to:
  /// **'Chat widget created'**
  String get crmWebChatWidgetCreated;

  /// No description provided for @crmWebChatWidgetUpdated.
  ///
  /// In en, this message translates to:
  /// **'Chat widget updated'**
  String get crmWebChatWidgetUpdated;

  /// No description provided for @crmWebChatEditConversationTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit conversation'**
  String get crmWebChatEditConversationTitle;

  /// No description provided for @crmWebChatFieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get crmWebChatFieldStatus;

  /// No description provided for @crmWebChatAssignTo.
  ///
  /// In en, this message translates to:
  /// **'Assign to'**
  String get crmWebChatAssignTo;

  /// No description provided for @crmWebChatOptionalLeadId.
  ///
  /// In en, this message translates to:
  /// **'Lead id (optional)'**
  String get crmWebChatOptionalLeadId;

  /// No description provided for @crmWebChatOptionalPersonId.
  ///
  /// In en, this message translates to:
  /// **'Person id (optional)'**
  String get crmWebChatOptionalPersonId;

  /// No description provided for @crmWebChatUnassigned.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get crmWebChatUnassigned;

  /// No description provided for @crmWebChatEmbedSnippet.
  ///
  /// In en, this message translates to:
  /// **'// API base: {base}\n// Step 1: POST /api/v1/public/crm-chat/conversations/start\n// JSON body must include public_key \"{publicKey}\" and first_name, last_name, email, phone, page_url.\n// Step 2: with visitor_token and conversation_id, POST to /api/v1/public/crm-chat/messages.\n// See CRM_WEB_CHAT in the Hesabix repository for details.'**
  String crmWebChatEmbedSnippet(String base, String publicKey);

  /// No description provided for @crmWebChatDefaultWidgetName.
  ///
  /// In en, this message translates to:
  /// **'Widget'**
  String get crmWebChatDefaultWidgetName;

  /// No description provided for @crmWebChatAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'You do not have access to view CRM.'**
  String get crmWebChatAccessDenied;

  /// No description provided for @crmWebChatPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Web chat'**
  String get crmWebChatPageTitle;

  /// No description provided for @crmWebChatSearchConversationsHint.
  ///
  /// In en, this message translates to:
  /// **'Search conversations, ID, email…'**
  String get crmWebChatSearchConversationsHint;

  /// No description provided for @crmWebChatMessageDeleted.
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get crmWebChatMessageDeleted;

  /// No description provided for @crmWebChatLoadOlder.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get crmWebChatLoadOlder;

  /// No description provided for @crmWebChatDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get crmWebChatDeleteMessage;

  /// No description provided for @crmWebChatDeleteMessageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Deleting this message cannot be undone. Continue?'**
  String get crmWebChatDeleteMessageConfirm;

  /// No description provided for @crmWebChatDeleteConversation.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation'**
  String get crmWebChatDeleteConversation;

  /// No description provided for @crmWebChatDeleteConversationConfirm.
  ///
  /// In en, this message translates to:
  /// **'This conversation and all its messages will be permanently deleted. Continue?'**
  String get crmWebChatDeleteConversationConfirm;

  /// No description provided for @crmWebChatConversationDeleted.
  ///
  /// In en, this message translates to:
  /// **'Conversation deleted'**
  String get crmWebChatConversationDeleted;

  /// No description provided for @crmWebChatEditMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get crmWebChatEditMessageTitle;

  /// No description provided for @crmWebChatEditMessageHint.
  ///
  /// In en, this message translates to:
  /// **'New text…'**
  String get crmWebChatEditMessageHint;

  /// No description provided for @crmWebChatEditMessageSaved.
  ///
  /// In en, this message translates to:
  /// **'Message updated'**
  String get crmWebChatEditMessageSaved;

  /// No description provided for @crmWebChatMessageEditedBadge.
  ///
  /// In en, this message translates to:
  /// **'(edited)'**
  String get crmWebChatMessageEditedBadge;

  /// No description provided for @crmWebChatRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get crmWebChatRefreshTooltip;

  /// No description provided for @crmWebChatFilterStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status filter'**
  String get crmWebChatFilterStatusLabel;

  /// No description provided for @crmWebChatFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get crmWebChatFilterAll;

  /// No description provided for @crmWebChatFilterLongPressHint.
  ///
  /// In en, this message translates to:
  /// **'To delete conversations in bulk, press and hold the status filter title.'**
  String get crmWebChatFilterLongPressHint;

  /// No description provided for @crmWebChatCrmSettingsWidgetsIntro.
  ///
  /// In en, this message translates to:
  /// **'Manage the public key, allowed domains, and visitor file upload for each widget.'**
  String get crmWebChatCrmSettingsWidgetsIntro;

  /// No description provided for @crmWebChatCrmSettingsNoWidgets.
  ///
  /// In en, this message translates to:
  /// **'No widgets yet. Create one with the button below.'**
  String get crmWebChatCrmSettingsNoWidgets;

  /// No description provided for @crmWebChatAddWidgetButton.
  ///
  /// In en, this message translates to:
  /// **'New widget'**
  String get crmWebChatAddWidgetButton;

  /// No description provided for @crmWebChatBulkDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete conversations in bulk'**
  String get crmWebChatBulkDeleteTitle;

  /// No description provided for @crmWebChatBulkDeleteConfirmAll.
  ///
  /// In en, this message translates to:
  /// **'All conversations and messages for this business will be permanently deleted. This cannot be undone. Continue?'**
  String get crmWebChatBulkDeleteConfirmAll;

  /// No description provided for @crmWebChatBulkDeleteConfirmStatus.
  ///
  /// In en, this message translates to:
  /// **'All conversations with status «{statusLabel}» and their messages will be permanently deleted. This cannot be undone. Continue?'**
  String crmWebChatBulkDeleteConfirmStatus(String statusLabel);

  /// No description provided for @crmWebChatBulkDeleteDone.
  ///
  /// In en, this message translates to:
  /// **'{count} conversation(s) deleted'**
  String crmWebChatBulkDeleteDone(int count);

  /// No description provided for @crmWebChatWidgetsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat widgets'**
  String get crmWebChatWidgetsSectionTitle;

  /// No description provided for @crmWebChatWidgetsSectionHint.
  ///
  /// In en, this message translates to:
  /// **'Use edit for the public key and to disable file upload per site.'**
  String get crmWebChatWidgetsSectionHint;

  /// No description provided for @crmWebChatVisitorAttachmentCrmOff.
  ///
  /// In en, this message translates to:
  /// **'Visitor attachments: off (enable in CRM settings first).'**
  String get crmWebChatVisitorAttachmentCrmOff;

  /// No description provided for @crmWebChatVisitorAttachmentAllowed.
  ///
  /// In en, this message translates to:
  /// **'Visitor attachments: allowed — business storage.'**
  String get crmWebChatVisitorAttachmentAllowed;

  /// No description provided for @crmWebChatVisitorAttachmentWidgetOff.
  ///
  /// In en, this message translates to:
  /// **'Visitor attachments: off for this widget.'**
  String get crmWebChatVisitorAttachmentWidgetOff;

  /// No description provided for @crmWebChatWidgetStateActive.
  ///
  /// In en, this message translates to:
  /// **'State: active — embedded on the site'**
  String get crmWebChatWidgetStateActive;

  /// No description provided for @crmWebChatWidgetStateInactive.
  ///
  /// In en, this message translates to:
  /// **'State: inactive — new conversations cannot start with this key'**
  String get crmWebChatWidgetStateInactive;

  /// No description provided for @crmWebChatPublicKeyCopied.
  ///
  /// In en, this message translates to:
  /// **'Public key copied'**
  String get crmWebChatPublicKeyCopied;

  /// No description provided for @crmWebChatEmbedGuideCopied.
  ///
  /// In en, this message translates to:
  /// **'Connection guide copied'**
  String get crmWebChatEmbedGuideCopied;

  /// No description provided for @crmWebChatMenuCopyPublicKey.
  ///
  /// In en, this message translates to:
  /// **'Copy public key'**
  String get crmWebChatMenuCopyPublicKey;

  /// No description provided for @crmWebChatMenuCopyApiGuide.
  ///
  /// In en, this message translates to:
  /// **'Copy API guide'**
  String get crmWebChatMenuCopyApiGuide;

  /// No description provided for @crmWebChatMenuEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit…'**
  String get crmWebChatMenuEdit;

  /// No description provided for @crmWebChatNoWidgetsYet.
  ///
  /// In en, this message translates to:
  /// **'No widgets yet — use + to add one.'**
  String get crmWebChatNoWidgetsYet;

  /// No description provided for @crmWebChatNoConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations — try changing the filter'**
  String get crmWebChatNoConversations;

  /// No description provided for @crmWebChatConversationNumber.
  ///
  /// In en, this message translates to:
  /// **'Conversation {id}'**
  String crmWebChatConversationNumber(int id);

  /// No description provided for @crmWebChatSelectConversation.
  ///
  /// In en, this message translates to:
  /// **'Select a conversation'**
  String get crmWebChatSelectConversation;

  /// No description provided for @crmWebChatConversationNotFoundRefresh.
  ///
  /// In en, this message translates to:
  /// **'Conversation not found — try refreshing'**
  String get crmWebChatConversationNotFoundRefresh;

  /// No description provided for @crmWebChatVisitorStartPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page where chat started (visitor)'**
  String get crmWebChatVisitorStartPageLabel;

  /// No description provided for @crmWebChatVisitorCurrentPageLabel.
  ///
  /// In en, this message translates to:
  /// **'Visitor\'\'s current page'**
  String get crmWebChatVisitorCurrentPageLabel;

  /// No description provided for @crmWebChatVisitorIpLine.
  ///
  /// In en, this message translates to:
  /// **'IP: {ip}'**
  String crmWebChatVisitorIpLine(String ip);

  /// No description provided for @crmWebChatVisitorDeviceMobile.
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get crmWebChatVisitorDeviceMobile;

  /// No description provided for @crmWebChatVisitorDeviceTablet.
  ///
  /// In en, this message translates to:
  /// **'Tablet'**
  String get crmWebChatVisitorDeviceTablet;

  /// No description provided for @crmWebChatVisitorDeviceDesktop.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get crmWebChatVisitorDeviceDesktop;

  /// No description provided for @crmWebChatVisitorDeviceUnknown.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get crmWebChatVisitorDeviceUnknown;

  /// No description provided for @crmWebChatWidgetLine.
  ///
  /// In en, this message translates to:
  /// **'Widget: {name}'**
  String crmWebChatWidgetLine(String name);

  /// No description provided for @crmWebChatAssigneeLine.
  ///
  /// In en, this message translates to:
  /// **'Owner: {name}'**
  String crmWebChatAssigneeLine(String name);

  /// No description provided for @crmWebChatEditConversationButton.
  ///
  /// In en, this message translates to:
  /// **'Edit conversation'**
  String get crmWebChatEditConversationButton;

  /// No description provided for @crmWebChatLeads.
  ///
  /// In en, this message translates to:
  /// **'Leads'**
  String get crmWebChatLeads;

  /// No description provided for @crmWebChatRoleAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get crmWebChatRoleAgent;

  /// No description provided for @crmWebChatRoleVisitor.
  ///
  /// In en, this message translates to:
  /// **'Visitor'**
  String get crmWebChatRoleVisitor;

  /// No description provided for @crmWebChatFileLabel.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get crmWebChatFileLabel;

  /// No description provided for @crmWebChatAttachFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Attach file (business storage, context crm_web_chat)'**
  String get crmWebChatAttachFileTooltip;

  /// No description provided for @crmWebChatReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Reply… (Ctrl+Enter to send)'**
  String get crmWebChatReplyHint;

  /// No description provided for @crmWebChatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get crmWebChatSend;

  /// No description provided for @crmWebChatWidgetDialogTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit chat widget'**
  String get crmWebChatWidgetDialogTitleEdit;

  /// No description provided for @crmWebChatWidgetDialogTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New chat widget'**
  String get crmWebChatWidgetDialogTitleNew;

  /// No description provided for @crmWebChatWidgetDialogIntro.
  ///
  /// In en, this message translates to:
  /// **'After creation, copy the public key and API connection guide from the widget’s ⋯ menu. Allowed domains only affect browser security (CORS).'**
  String get crmWebChatWidgetDialogIntro;

  /// No description provided for @crmWebChatWidgetNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Widget name (internal)'**
  String get crmWebChatWidgetNameLabel;

  /// No description provided for @crmWebChatWidgetNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. My shop'**
  String get crmWebChatWidgetNameHint;

  /// No description provided for @crmWebChatWidgetNameHelper.
  ///
  /// In en, this message translates to:
  /// **'Only visible in your panel to tell widgets apart.'**
  String get crmWebChatWidgetNameHelper;

  /// No description provided for @crmWebChatWidgetOriginsLabel.
  ///
  /// In en, this message translates to:
  /// **'Allowed request domains'**
  String get crmWebChatWidgetOriginsLabel;

  /// No description provided for @crmWebChatWidgetOriginsHint.
  ///
  /// In en, this message translates to:
  /// **'shop.example.com, blog.shop.example.com'**
  String get crmWebChatWidgetOriginsHint;

  /// No description provided for @crmWebChatWidgetOriginsHelper.
  ///
  /// In en, this message translates to:
  /// **'Optional. Host names only (no https://), separated by a comma. If empty, domain rules follow the API docs. For a specific site, add that host here.'**
  String get crmWebChatWidgetOriginsHelper;

  /// No description provided for @crmWebChatVisitorFileSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'Let site visitors send files'**
  String get crmWebChatVisitorFileSwitchTitle;

  /// No description provided for @crmWebChatVisitorFileSwitchOn.
  ///
  /// In en, this message translates to:
  /// **'Subject to your storage plan. You can turn this off for this widget only; if left on, it matches other widgets.'**
  String get crmWebChatVisitorFileSwitchOn;

  /// No description provided for @crmWebChatVisitorFileSwitchOff.
  ///
  /// In en, this message translates to:
  /// **'Disabled at business level. In CRM settings (e.g. Communications → CRM settings), turn on web chat file upload, then return and set this switch.'**
  String get crmWebChatVisitorFileSwitchOff;

  /// No description provided for @crmWebChatWidgetActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Widget active'**
  String get crmWebChatWidgetActiveTitle;

  /// No description provided for @crmWebChatWidgetActiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If off, new conversations cannot start with this public key (existing threads stay in the panel).'**
  String get crmWebChatWidgetActiveSubtitle;

  /// No description provided for @crmWebChatNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a widget name (e.g. site or section).'**
  String get crmWebChatNameRequired;

  /// No description provided for @crmWebChatCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get crmWebChatCreate;

  /// No description provided for @crmWebChatSocketLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get crmWebChatSocketLive;

  /// No description provided for @crmWebChatSocketPolling.
  ///
  /// In en, this message translates to:
  /// **'Polling'**
  String get crmWebChatSocketPolling;

  /// No description provided for @crmWebChatSocketOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get crmWebChatSocketOffline;

  /// No description provided for @crmWebChatSocketNoKey.
  ///
  /// In en, this message translates to:
  /// **'No key'**
  String get crmWebChatSocketNoKey;

  /// No description provided for @crmWebChatPeerTyping.
  ///
  /// In en, this message translates to:
  /// **'Visitor is typing…'**
  String get crmWebChatPeerTyping;

  /// No description provided for @crmWebChatTooltipMessageSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get crmWebChatTooltipMessageSent;

  /// No description provided for @crmWebChatTooltipMessageRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get crmWebChatTooltipMessageRead;

  /// No description provided for @crmSettingsWebChatVoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice messages in web chat'**
  String get crmSettingsWebChatVoiceTitle;

  /// No description provided for @crmSettingsWebChatVoiceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Voice clips count toward your storage plan like other uploads.'**
  String get crmSettingsWebChatVoiceSubtitle;

  /// No description provided for @crmWebChatVisitorVoiceSwitchTitle.
  ///
  /// In en, this message translates to:
  /// **'Let visitors send voice messages'**
  String get crmWebChatVisitorVoiceSwitchTitle;

  /// No description provided for @crmWebChatVisitorVoiceSwitchOn.
  ///
  /// In en, this message translates to:
  /// **'Follow CRM and storage limits. Per-widget toggle off if needed.'**
  String get crmWebChatVisitorVoiceSwitchOn;

  /// No description provided for @crmWebChatVisitorVoiceSwitchOff.
  ///
  /// In en, this message translates to:
  /// **'Voice upload is disabled in CRM settings or limited for this widget.'**
  String get crmWebChatVisitorVoiceSwitchOff;

  /// No description provided for @crmWebChatVoiceDisabledCrm.
  ///
  /// In en, this message translates to:
  /// **'Voice messages are disabled in CRM settings for this business'**
  String get crmWebChatVoiceDisabledCrm;

  /// No description provided for @crmWebChatComposerDropTarget.
  ///
  /// In en, this message translates to:
  /// **'Drop to send'**
  String get crmWebChatComposerDropTarget;

  /// No description provided for @crmWebChatMicRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get crmWebChatMicRecording;

  /// No description provided for @crmWebChatMicStopSend.
  ///
  /// In en, this message translates to:
  /// **'Stop & send'**
  String get crmWebChatMicStopSend;

  /// No description provided for @crmWebChatMicUnavailableWeb.
  ///
  /// In en, this message translates to:
  /// **'Voice capture is unavailable in this browser build; attach a file instead'**
  String get crmWebChatMicUnavailableWeb;

  /// No description provided for @crmWebChatVisitorVoiceOffWidget.
  ///
  /// In en, this message translates to:
  /// **'Guest voice disabled'**
  String get crmWebChatVisitorVoiceOffWidget;

  /// No description provided for @accountSettingsAppearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get accountSettingsAppearanceTitle;

  /// No description provided for @accountSettingsAppearanceDescription.
  ///
  /// In en, this message translates to:
  /// **'Business panel layout on desktop (single page vs tabs)'**
  String get accountSettingsAppearanceDescription;

  /// No description provided for @appearanceSettingsPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance settings'**
  String get appearanceSettingsPageTitle;

  /// No description provided for @appearanceBusinessPanelSection.
  ///
  /// In en, this message translates to:
  /// **'Business panel (desktop)'**
  String get appearanceBusinessPanelSection;

  /// No description provided for @appearanceNavigationSingleLabel.
  ///
  /// In en, this message translates to:
  /// **'Single page'**
  String get appearanceNavigationSingleLabel;

  /// No description provided for @appearanceNavigationSingleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only one page open at a time (classic navigation)'**
  String get appearanceNavigationSingleSubtitle;

  /// No description provided for @appearanceNavigationTabsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tabs in top bar'**
  String get appearanceNavigationTabsLabel;

  /// No description provided for @appearanceNavigationTabsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keep multiple pages open and switch via tabs on the dark strip (desktop only). Background tabs stay mounted; stable page keys improve reuse when you return.'**
  String get appearanceNavigationTabsSubtitle;

  /// No description provided for @appearanceDesktopOnlyNote.
  ///
  /// In en, this message translates to:
  /// **'Tabbed layout applies only on wide screens; on mobile, navigation stays single-page.'**
  String get appearanceDesktopOnlyNote;

  /// No description provided for @appearanceSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get appearanceSaved;

  /// No description provided for @appearanceSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save settings'**
  String get appearanceSaveError;

  /// No description provided for @appearanceSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get appearanceSaveButton;

  /// No description provided for @businessPanelTabCloseThisTab.
  ///
  /// In en, this message translates to:
  /// **'Close this tab'**
  String get businessPanelTabCloseThisTab;

  /// No description provided for @businessPanelTabCloseTabsToTheRight.
  ///
  /// In en, this message translates to:
  /// **'Close tabs to the right'**
  String get businessPanelTabCloseTabsToTheRight;

  /// No description provided for @businessPanelTabCloseTabsToTheLeft.
  ///
  /// In en, this message translates to:
  /// **'Close tabs to the left'**
  String get businessPanelTabCloseTabsToTheLeft;

  /// No description provided for @businessPanelTabAllTabsTitle.
  ///
  /// In en, this message translates to:
  /// **'All tabs'**
  String get businessPanelTabAllTabsTitle;

  /// No description provided for @businessPanelTabCloseAllTabs.
  ///
  /// In en, this message translates to:
  /// **'Close all tabs'**
  String get businessPanelTabCloseAllTabs;

  /// No description provided for @businessPanelTabListTooltip.
  ///
  /// In en, this message translates to:
  /// **'List all tabs'**
  String get businessPanelTabListTooltip;

  /// No description provided for @businessPanelTabRouteProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get businessPanelTabRouteProjects;

  /// No description provided for @businessPanelTabRoutePriceListItems.
  ///
  /// In en, this message translates to:
  /// **'Price list items'**
  String get businessPanelTabRoutePriceListItems;

  /// No description provided for @businessPanelTabRouteRepairTechnicians.
  ///
  /// In en, this message translates to:
  /// **'Repair technicians'**
  String get businessPanelTabRouteRepairTechnicians;

  /// No description provided for @businessPanelTabRouteRepairShopSettings.
  ///
  /// In en, this message translates to:
  /// **'Repair shop settings'**
  String get businessPanelTabRouteRepairShopSettings;

  /// No description provided for @appearanceSidebarTabBehaviorSection.
  ///
  /// In en, this message translates to:
  /// **'Sidebar navigation (when tabs are on)'**
  String get appearanceSidebarTabBehaviorSection;

  /// No description provided for @appearanceSidebarTabBehaviorReuseTitle.
  ///
  /// In en, this message translates to:
  /// **'Reuse open tab or open a new one'**
  String get appearanceSidebarTabBehaviorReuseTitle;

  /// No description provided for @appearanceSidebarTabBehaviorReuseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If that page is already open in a tab, switch to it; otherwise add a new tab. This matches the previous default behavior.'**
  String get appearanceSidebarTabBehaviorReuseSubtitle;

  /// No description provided for @appearanceSidebarTabBehaviorLongPressTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace the active tab; long press for the default behavior'**
  String get appearanceSidebarTabBehaviorLongPressTitle;

  /// No description provided for @appearanceSidebarTabBehaviorLongPressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A normal click loads the destination in the current tab only. Long press on a sidebar item reuses an open tab or opens a new tab, like the option above.'**
  String get appearanceSidebarTabBehaviorLongPressSubtitle;

  /// No description provided for @mobileLauncherTitle.
  ///
  /// In en, this message translates to:
  /// **'Mobile launcher'**
  String get mobileLauncherTitle;

  /// No description provided for @mobileLauncherAppearanceTile.
  ///
  /// In en, this message translates to:
  /// **'Launcher look'**
  String get mobileLauncherAppearanceTile;

  /// No description provided for @mobileLauncherAppearancePageTitle.
  ///
  /// In en, this message translates to:
  /// **'Launcher appearance'**
  String get mobileLauncherAppearancePageTitle;

  /// No description provided for @mobileLauncherBackgroundColorSection.
  ///
  /// In en, this message translates to:
  /// **'Background color'**
  String get mobileLauncherBackgroundColorSection;

  /// No description provided for @mobileLauncherSaveColors.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get mobileLauncherSaveColors;

  /// No description provided for @mobileLauncherColorsSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get mobileLauncherColorsSaved;

  /// No description provided for @mobileLauncherBackToAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get mobileLauncherBackToAccount;

  /// No description provided for @mobileLauncherOpenFullPanel.
  ///
  /// In en, this message translates to:
  /// **'Full panel'**
  String get mobileLauncherOpenFullPanel;

  /// No description provided for @mobileLauncherChooseModeTitle.
  ///
  /// In en, this message translates to:
  /// **'How do you want to open this business?'**
  String get mobileLauncherChooseModeTitle;

  /// No description provided for @mobileLauncherModeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard panel'**
  String get mobileLauncherModeStandard;

  /// No description provided for @mobileLauncherModeLauncher.
  ///
  /// In en, this message translates to:
  /// **'Mobile launcher'**
  String get mobileLauncherModeLauncher;

  /// No description provided for @mobileLauncherInvalidBusiness.
  ///
  /// In en, this message translates to:
  /// **'Invalid business id'**
  String get mobileLauncherInvalidBusiness;

  /// No description provided for @mobileLauncherDisableHomeLauncherMenu.
  ///
  /// In en, this message translates to:
  /// **'Open app to profile home'**
  String get mobileLauncherDisableHomeLauncherMenu;

  /// No description provided for @mobileLauncherDisableHomeLauncherDone.
  ///
  /// In en, this message translates to:
  /// **'The app will open to your profile until you choose launcher again.'**
  String get mobileLauncherDisableHomeLauncherDone;

  /// No description provided for @mobileLauncherBusinessNoAccess.
  ///
  /// In en, this message translates to:
  /// **'You no longer have access to this business.'**
  String get mobileLauncherBusinessNoAccess;

  /// No description provided for @mobileLauncherExitAppHint.
  ///
  /// In en, this message translates to:
  /// **'Press back again to exit'**
  String get mobileLauncherExitAppHint;

  /// No description provided for @mobileLauncherBrandName.
  ///
  /// In en, this message translates to:
  /// **'Hesabix'**
  String get mobileLauncherBrandName;

  /// No description provided for @mobileLauncherBusinessFallback.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get mobileLauncherBusinessFallback;

  /// No description provided for @mobileLauncherGridLayoutSection.
  ///
  /// In en, this message translates to:
  /// **'Grid layout'**
  String get mobileLauncherGridLayoutSection;

  /// No description provided for @mobileLauncherGridColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get mobileLauncherGridColumns;

  /// No description provided for @mobileLauncherGridRows.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get mobileLauncherGridRows;

  /// No description provided for @mobileLauncherGridPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get mobileLauncherGridPreview;

  /// No description provided for @mobileLauncherQuickSalesTile.
  ///
  /// In en, this message translates to:
  /// **'Quick sales'**
  String get mobileLauncherQuickSalesTile;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
