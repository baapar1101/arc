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
  /// **'Mobile number'**
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
  /// **'This month'**
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
