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
  /// **'FTP Host'**
  String get ftpHost;

  /// No description provided for @ftpPort.
  ///
  /// In en, this message translates to:
  /// **'FTP Port'**
  String get ftpPort;

  /// No description provided for @ftpUsername.
  ///
  /// In en, this message translates to:
  /// **'FTP Username'**
  String get ftpUsername;

  /// No description provided for @ftpPassword.
  ///
  /// In en, this message translates to:
  /// **'FTP Password'**
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
  /// **'Configure file storage systems and manage files'**
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

  /// No description provided for @shipments.
  ///
  /// In en, this message translates to:
  /// **'Shipments'**
  String get shipments;

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
  /// **'Version 1.0.0'**
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

  /// No description provided for @selectBackupFile.
  ///
  /// In en, this message translates to:
  /// **'Select backup file (.hbx)'**
  String get selectBackupFile;

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

  /// No description provided for @personsList.
  ///
  /// In en, this message translates to:
  /// **'Persons List'**
  String get personsList;

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

  /// No description provided for @inventoryControl.
  ///
  /// In en, this message translates to:
  /// **'Inventory control'**
  String get inventoryControl;

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

  /// No description provided for @notificationsOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Ensure messages reach your team'**
  String get notificationsOverviewTitle;

  /// No description provided for @notificationsOverviewDescription.
  ///
  /// In en, this message translates to:
  /// **'Decide which channels deliver operational alerts so administrators know how messages are sent.'**
  String get notificationsOverviewDescription;

  /// No description provided for @notificationsGuidanceItemChannels.
  ///
  /// In en, this message translates to:
  /// **'Enable or disable channels based on availability and team requirements.'**
  String get notificationsGuidanceItemChannels;

  /// No description provided for @notificationsGuidanceItemTemplates.
  ///
  /// In en, this message translates to:
  /// **'Publish an active template for each channel and language.'**
  String get notificationsGuidanceItemTemplates;

  /// No description provided for @notificationsGuidanceItemTesting.
  ///
  /// In en, this message translates to:
  /// **'After changes, verify delivery paths with the test buttons.'**
  String get notificationsGuidanceItemTesting;

  /// No description provided for @notificationsLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Read the guide'**
  String get notificationsLearnMore;

  /// No description provided for @notificationsDocumentationUrl.
  ///
  /// In en, this message translates to:
  /// **'https://docs.hesabix.com/notifications'**
  String get notificationsDocumentationUrl;

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
  /// **'Custom credit limit (toman)'**
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

  /// No description provided for @taxSendSelectedErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to send selected invoices: {error}'**
  String taxSendSelectedErrorWithMessage(String error);

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

  /// No description provided for @taxRemoveSelectedErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove selected invoices: {error}'**
  String taxRemoveSelectedErrorWithMessage(String error);
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
