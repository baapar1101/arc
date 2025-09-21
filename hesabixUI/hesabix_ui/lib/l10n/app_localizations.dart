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

  /// No description provided for @isActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get isActive;

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

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get testConnection;

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
  /// **'Confirm Delete'**
  String get deleteConfirm;

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

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

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
