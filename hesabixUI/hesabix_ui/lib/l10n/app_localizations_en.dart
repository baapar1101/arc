// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Hesabix';

  @override
  String get login => 'Login';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get submit => 'Submit';

  @override
  String get loginFailed => 'Login failed. Please try again.';

  @override
  String get homeWelcome => 'Signed in successfully!';

  @override
  String get language => 'Language';

  @override
  String get requiredField => 'is required';

  @override
  String get register => 'Register';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String get firstName => 'First Name';

  @override
  String get lastName => 'Last Name';

  @override
  String get email => 'Email';

  @override
  String get mobile => 'Mobile number';

  @override
  String get registerSuccess => 'Registration successful.';

  @override
  String get forgotSent => 'Reset link sent to your email.';

  @override
  String get identifier => 'Email or mobile';

  @override
  String get theme => 'Theme';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get welcomeTitle => 'Hesabix Cloud Accounting';

  @override
  String get welcomeSubtitle =>
      'Smart, secure, and always available accounting for your business.';

  @override
  String get brandTagline =>
      'Manage your finances anywhere, anytime with confidence.';

  @override
  String get captcha => 'Captcha';

  @override
  String get refresh => 'Refresh';

  @override
  String get captchaRequired => 'Captcha is required.';

  @override
  String get sendReset => 'Send reset code';

  @override
  String get registerFailed => 'Registration failed. Please try again.';

  @override
  String get resetFailed => 'Request failed. Please try again.';

  @override
  String get fixFormErrors => 'Please fix the form errors.';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get profile => 'Profile';

  @override
  String get settings => 'Settings';

  @override
  String get logout => 'Logout';

  @override
  String get logoutDone => 'Signed out.';

  @override
  String get logoutConfirmTitle => 'Sign out';

  @override
  String get logoutConfirmMessage => 'Are you sure you want to sign out?';

  @override
  String get menu => 'Menu';

  @override
  String get systemSettings => 'System Settings';

  @override
  String get adminTools => 'Admin Tools';

  @override
  String get ok => 'OK';

  @override
  String get cancel => 'Cancel';

  @override
  String get columnSettings => 'Column Settings';

  @override
  String get columnSettingsDescription =>
      'Manage column visibility and order for this table';

  @override
  String get columnName => 'Column Name';

  @override
  String get visibility => 'Visibility';

  @override
  String get order => 'Order';

  @override
  String get visible => 'Visible';

  @override
  String get hidden => 'Hidden';

  @override
  String get resetToDefaults => 'Reset to Defaults';

  @override
  String get save => 'Save';

  @override
  String get error => 'Error';

  @override
  String get newBusiness => 'New business';

  @override
  String get businesses => 'Businesses';

  @override
  String get support => 'Support';

  @override
  String get changePassword => 'Change password';

  @override
  String get marketing => 'Marketing';

  @override
  String get marketingReport => 'Marketing report';

  @override
  String get today => 'Today';

  @override
  String get thisMonth => 'This month';

  @override
  String get total => 'Total';

  @override
  String get dateFrom => 'From date';

  @override
  String get dateTo => 'To date';

  @override
  String get applyFilter => 'Apply filter';

  @override
  String get copied => 'Copied';

  @override
  String get copyLink => 'Copy link';

  @override
  String get loading => 'Loading...';

  @override
  String get currentPassword => 'Current password';

  @override
  String get newPassword => 'New password';

  @override
  String get confirmPassword => 'Confirm new password';

  @override
  String get changePasswordSuccess => 'Password changed successfully';

  @override
  String get changePasswordFailed =>
      'Failed to change password. Please try again.';

  @override
  String get passwordsDoNotMatch =>
      'New password and confirm password do not match';

  @override
  String get samePassword =>
      'New password must be different from current password';

  @override
  String get invalidCurrentPassword => 'Current password is incorrect';

  @override
  String get passwordChanged => 'Password changed successfully';

  @override
  String get changePasswordDescription =>
      'Enter your current password and choose a new secure password';

  @override
  String get changePasswordButton => 'Change Password';

  @override
  String get passwordMinLength => 'Password must be at least 8 characters';

  @override
  String get calendar => 'Calendar';

  @override
  String get gregorian => 'Gregorian';

  @override
  String get jalali => 'Jalali';

  @override
  String get calendarType => 'Calendar Type';

  @override
  String get dataLoadingError => 'Error loading data';

  @override
  String get yourReferralLink => 'Your referral link';

  @override
  String get filtersAndSearch => 'Filters and search';

  @override
  String get hideFilters => 'Hide filters';

  @override
  String get showFilters => 'Show filters';

  @override
  String get clear => 'Clear';

  @override
  String get searchInNameEmail => 'Search in name, last name and email...';

  @override
  String get recordsPerPage => 'Records per page';

  @override
  String get records => 'records';

  @override
  String get test => 'Test';

  @override
  String get user => 'User';

  @override
  String showingRecords(Object end, Object start, Object total) {
    return 'Showing $start to $end of $total records';
  }

  @override
  String get previousPage => 'Previous page';

  @override
  String get nextPage => 'Next page';

  @override
  String pageOf(Object current, Object total) {
    return '$current of $total';
  }

  @override
  String get referralList => 'Referral List';

  @override
  String get dateRangeFilter => 'Date Range Filter';

  @override
  String get columnSearch => 'Column Search';

  @override
  String searchInColumn(Object column) {
    return 'Search in $column';
  }

  @override
  String get searchType => 'Search Type';

  @override
  String get contains => 'contains';

  @override
  String get startsWith => 'Starts With';

  @override
  String get endsWith => 'Ends With';

  @override
  String get exactMatch => 'Exact Match';

  @override
  String get searchValue => 'Search Value';

  @override
  String get applyColumnFilter => 'Apply Column Filter';

  @override
  String get clearColumnFilter => 'Clear Column Filter';

  @override
  String get activeFilters => 'Active Filters';

  @override
  String get selectDate => 'Select Date';

  @override
  String get noDataFound => 'No data found';

  @override
  String get marketingReportSubtitle => 'Manage and analyze user referrals';

  @override
  String get showing => 'Showing';

  @override
  String get to => 'to';

  @override
  String get ofText => 'of';

  @override
  String get results => 'results';

  @override
  String get firstPage => 'First page';

  @override
  String get lastPage => 'Last page';

  @override
  String get exportToExcel => 'Export to Excel';

  @override
  String get exportToPdf => 'Export to PDF';

  @override
  String get exportSelected => 'Export Selected';

  @override
  String get exportAll => 'Export All';

  @override
  String get exporting => 'Exporting...';

  @override
  String get exportSuccess => 'Export completed successfully';

  @override
  String get exportError => 'Export error';

  @override
  String get export => 'Export';

  @override
  String get rowNumber => 'Row';

  @override
  String get registrationDate => 'Registration Date';

  @override
  String get selectedRange => 'Selected Range';

  @override
  String get page => 'Page';

  @override
  String get equals => 'equals';

  @override
  String get greater_than => 'greater than';

  @override
  String get greater_equal => 'greater or equal';

  @override
  String get less_than => 'less than';

  @override
  String get less_equal => 'less or equal';

  @override
  String get not_equals => 'not equals';

  @override
  String get starts_with => 'starts with';

  @override
  String get ends_with => 'ends with';

  @override
  String get in_list => 'in list';
}
