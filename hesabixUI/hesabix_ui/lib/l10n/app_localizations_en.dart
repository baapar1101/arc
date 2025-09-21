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
  String get mobile => 'Mobile';

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
  String get thisMonth => 'This Month';

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

  @override
  String get businessBasicInfo => 'Basic Business Information';

  @override
  String get businessContactInfo => 'Contact Information';

  @override
  String get businessLegalInfo => 'Legal Information';

  @override
  String get businessGeographicInfo => 'Geographic Information';

  @override
  String get businessConfirmation => 'Confirmation';

  @override
  String get businessName => 'Business Name';

  @override
  String get businessType => 'Business Type';

  @override
  String get businessField => 'Business Field';

  @override
  String get address => 'Address';

  @override
  String get phone => 'Phone';

  @override
  String get postalCode => 'Postal Code';

  @override
  String get nationalId => 'National ID';

  @override
  String get registrationNumber => 'Registration Number';

  @override
  String get economicId => 'Economic ID';

  @override
  String get country => 'Country';

  @override
  String get province => 'Province';

  @override
  String get city => 'City';

  @override
  String get step => 'Step';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get createBusiness => 'Create Business';

  @override
  String get confirmInfo => 'Confirm Information';

  @override
  String get confirmInfoMessage =>
      'Are you sure about the entered information?';

  @override
  String get businessCreatedSuccessfully => 'Business created successfully';

  @override
  String get businessCreationFailed => 'Failed to create business';

  @override
  String get pleaseFillRequiredFields => 'Please fill all required fields';

  @override
  String get required => 'required';

  @override
  String get example => 'Example';

  @override
  String get phoneExample => '02112345678';

  @override
  String get mobileExample => '09123456789';

  @override
  String get nationalIdExample => '1234567890';

  @override
  String get company => 'Company';

  @override
  String get shop => 'Shop';

  @override
  String get store => 'Store';

  @override
  String get union => 'Union';

  @override
  String get club => 'Club';

  @override
  String get institute => 'Institute';

  @override
  String get individual => 'Individual';

  @override
  String get manufacturing => 'Manufacturing';

  @override
  String get trading => 'Trading';

  @override
  String get service => 'Service';

  @override
  String get other => 'Other';

  @override
  String get newTicket => 'New Ticket';

  @override
  String get ticketTitle => 'Ticket Title';

  @override
  String get ticketDescription => 'Problem Description';

  @override
  String get category => 'Category';

  @override
  String get priority => 'Priority';

  @override
  String get status => 'Status';

  @override
  String get messages => 'Messages';

  @override
  String get sendMessage => 'Send Message';

  @override
  String get messageHint => 'Type your message...';

  @override
  String get createTicket => 'Create Ticket';

  @override
  String get ticketCreated => 'Ticket created successfully';

  @override
  String get messageSent => 'Message sent';

  @override
  String get loadingTickets => 'Loading tickets...';

  @override
  String get noTickets => 'No tickets found';

  @override
  String get ticketDetails => 'Ticket Details';

  @override
  String get supportTickets => 'Support Tickets';

  @override
  String get ticketCreatedAt => 'Created At';

  @override
  String get ticketUpdatedAt => 'Last Updated';

  @override
  String get ticketLoadingError => 'Error loading ticket';

  @override
  String get ticketId => 'Ticket ID';

  @override
  String get createdAt => 'Created At';

  @override
  String get updatedAt => 'Updated At';

  @override
  String get assignedTo => 'Assigned to';

  @override
  String get low => 'Low';

  @override
  String get medium => 'Medium';

  @override
  String get high => 'High';

  @override
  String get urgent => 'Urgent';

  @override
  String get open => 'Open';

  @override
  String get inProgress => 'In Progress';

  @override
  String get waitingForUser => 'Waiting for User';

  @override
  String get closed => 'Closed';

  @override
  String get resolved => 'Resolved';

  @override
  String get technicalIssue => 'Technical Issue';

  @override
  String get featureRequest => 'Feature Request';

  @override
  String get question => 'Question';

  @override
  String get complaint => 'Complaint';

  @override
  String get operatorPanel => 'Operator Panel';

  @override
  String get allTickets => 'All Tickets';

  @override
  String get assignTicket => 'Assign Ticket';

  @override
  String get createNewTicket => 'Create New Ticket';

  @override
  String get createSupportTicket => 'Create Support Ticket';

  @override
  String get ticketTitleLabel => 'Ticket Title';

  @override
  String get ticketTitleHint => 'Enter a short and clear title for your issue';

  @override
  String get categoryLabel => 'Category';

  @override
  String get priorityLabel => 'Priority';

  @override
  String get descriptionLabel => 'Problem Description';

  @override
  String get descriptionHint =>
      'Please describe your problem or question in detail...';

  @override
  String get submitTicket => 'Submit Ticket';

  @override
  String get submittingTicket => 'Submitting...';

  @override
  String get ticketTitleRequired => 'Ticket title is required';

  @override
  String get ticketTitleMinLength => 'Title must be at least 5 characters';

  @override
  String get categoryRequired => 'Please select a category';

  @override
  String get priorityRequired => 'Please select a priority';

  @override
  String get descriptionRequired => 'Problem description is required';

  @override
  String get descriptionMinLength =>
      'Description must be at least 10 characters';

  @override
  String get loadingData => 'Loading...';

  @override
  String get retry => 'Retry';

  @override
  String get ticketCreatedSuccessfully => 'Ticket created successfully';

  @override
  String get pleaseSelectCategoryAndPriority =>
      'Please select category and priority';

  @override
  String get changeStatus => 'Change Status';

  @override
  String get multiSelectFilter => 'Multi-Select Filter';

  @override
  String get selectFilterOptions => 'Select Filter Options';

  @override
  String get noFilterOptionsAvailable => 'No filter options available';

  @override
  String get marketingDescription => 'Manage referrals and marketing codes';

  @override
  String get referralCode => 'Referral Code';

  @override
  String get internalMessage => 'Internal Message';

  @override
  String get operator => 'Operator';

  @override
  String ticketNumber(Object number) {
    return 'Ticket #$number';
  }

  @override
  String get ticketNotFound => 'Ticket not found';

  @override
  String get noMessagesFound => 'No messages found';

  @override
  String get writeYourMessage => 'Write your message...';

  @override
  String get writeYourResponse => 'Write your response...';

  @override
  String get sendingMessage => 'Sending message...';

  @override
  String get messageSentSuccessfully => 'Message sent successfully';

  @override
  String get errorSendingMessage => 'Error sending message';

  @override
  String get statusUpdatedSuccessfully => 'Status updated successfully';

  @override
  String get errorUpdatingStatus => 'Error updating status';

  @override
  String get ticketClosed => 'Ticket is closed';

  @override
  String get ticketResolved => 'Ticket is resolved';

  @override
  String daysAgo(Object count) {
    return '$count days ago';
  }

  @override
  String hoursAgo(Object count) {
    return '$count hours ago';
  }

  @override
  String minutesAgo(Object count) {
    return '$count minutes ago';
  }

  @override
  String get justNow => 'Just now';

  @override
  String get conversation => 'Conversation';

  @override
  String get ticketInfo => 'Ticket Information';

  @override
  String get createdBy => 'Created by';

  @override
  String get lastUpdated => 'Last updated';

  @override
  String messageCount(Object count) {
    return '$count messages';
  }

  @override
  String get replyAsOperator => 'Reply as Operator';

  @override
  String get replyAsUser => 'Reply as User';

  @override
  String get internalNote => 'Internal Note';

  @override
  String get publicMessage => 'Public Message';

  @override
  String get markAsInternal => 'Mark as Internal';

  @override
  String get markAsPublic => 'Mark as Public';

  @override
  String get ticketDetailsDialog => 'Ticket Details';

  @override
  String get close => 'Close';

  @override
  String get fileStorage => 'File Management';

  @override
  String get fileStorageSettings => 'File Settings';

  @override
  String get storageConfigurations => 'Storage Configurations';

  @override
  String get addStorageConfig => 'Add Storage Configuration';

  @override
  String get editStorageConfig => 'Edit Storage Configuration';

  @override
  String get storageName => 'Configuration Name';

  @override
  String get storageType => 'Storage Type';

  @override
  String get localStorage => 'Local Storage';

  @override
  String get ftpStorage => 'FTP Storage';

  @override
  String get isDefault => 'Default';

  @override
  String get isActive => 'Active';

  @override
  String get configData => 'Configuration Data';

  @override
  String get basePath => 'Base Path';

  @override
  String get ftpHost => 'FTP Host';

  @override
  String get ftpPort => 'FTP Port';

  @override
  String get ftpUsername => 'FTP Username';

  @override
  String get ftpPassword => 'FTP Password';

  @override
  String get ftpDirectory => 'FTP Directory';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get connectionSuccessful => 'Connection Successful';

  @override
  String get connectionFailed => 'Connection Failed';

  @override
  String get setAsDefault => 'Set as Default';

  @override
  String get fileStatistics => 'File Statistics';

  @override
  String get totalFiles => 'Total Files';

  @override
  String get totalSize => 'Total Size';

  @override
  String get temporaryFiles => 'Temporary Files';

  @override
  String get unverifiedFiles => 'Unverified Files';

  @override
  String get cleanupTemporaryFiles => 'Cleanup Temporary Files';

  @override
  String get cleanupCompleted => 'Cleanup Completed';

  @override
  String filesCleaned(Object count) {
    return '$count files cleaned';
  }

  @override
  String get fileManagement => 'File Management';

  @override
  String get allFiles => 'All Files';

  @override
  String get unverifiedFilesList => 'Unverified Files';

  @override
  String get fileName => 'File Name';

  @override
  String get fileSize => 'File Size';

  @override
  String get mimeType => 'MIME Type';

  @override
  String get moduleContext => 'Module Context';

  @override
  String get expiresAt => 'Expires At';

  @override
  String get isTemporary => 'Temporary';

  @override
  String get isVerified => 'Verified';

  @override
  String get forceDelete => 'Force Delete';

  @override
  String get restoreFile => 'Restore File';

  @override
  String get deleteConfirm => 'Confirm Delete';

  @override
  String get deleteConfirmMessage =>
      'Are you sure you want to delete this file?';

  @override
  String get restoreConfirm => 'Confirm Restore';

  @override
  String get restoreConfirmMessage =>
      'Are you sure you want to restore this file?';

  @override
  String get fileDeleted => 'File deleted';

  @override
  String get fileRestored => 'File restored';

  @override
  String get errorDeletingFile => 'Error deleting file';

  @override
  String get errorRestoringFile => 'Error restoring file';

  @override
  String get noFilesFound => 'No files found';

  @override
  String get loadingFiles => 'Loading files...';

  @override
  String get errorLoadingFiles => 'Error loading files';

  @override
  String get refreshFiles => 'Refresh Files';

  @override
  String get fileDetails => 'File Details';

  @override
  String get originalName => 'Original Name';

  @override
  String get storedName => 'Stored Name';

  @override
  String get filePath => 'File Path';

  @override
  String get checksum => 'Checksum';

  @override
  String get uploadedBy => 'Uploaded by';

  @override
  String get lastVerified => 'Last Verified';

  @override
  String get developerData => 'Developer Data';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get actions => 'Actions';

  @override
  String get search => 'Search';

  @override
  String get filter => 'Filter';

  @override
  String get apply => 'Apply';

  @override
  String get reset => 'Reset';

  @override
  String get of => 'of';

  @override
  String get itemsPerPage => 'Items per page';

  @override
  String get first => 'First';

  @override
  String get last => 'Last';
}
