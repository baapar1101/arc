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
  String get acceptTermsPrefix => 'I accept ';

  @override
  String get acceptTermsSuffix => '';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get and => 'and';

  @override
  String get acceptTermsRequired =>
      'You must accept the Privacy Policy and Terms of Service to register.';

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
  String get emailSettings => 'Email Settings';

  @override
  String get emailSettingsDescription =>
      'Configure SMTP settings for email sending';

  @override
  String get emailConfigurations => 'Email Configurations';

  @override
  String get noEmailConfigurations => 'No email configurations found';

  @override
  String get addEmailConfiguration => 'Add Email Configuration';

  @override
  String get configurationName => 'Configuration Name';

  @override
  String get smtpHost => 'SMTP Host';

  @override
  String get smtpPort => 'SMTP Port';

  @override
  String get smtpUsername => 'SMTP Username';

  @override
  String get smtpPassword => 'SMTP Password';

  @override
  String get fromEmail => 'From Email';

  @override
  String get fromName => 'From Name';

  @override
  String get useTls => 'Use TLS';

  @override
  String get useSsl => 'Use SSL';

  @override
  String get isActive => 'Active';

  @override
  String get active => 'Active';

  @override
  String get testConnection => 'Test Connection';

  @override
  String get sendTestEmail => 'Send Test Email';

  @override
  String get saveConfiguration => 'Save Configuration';

  @override
  String get deleteConfiguration => 'Delete Configuration';

  @override
  String get deleteConfigurationConfirm =>
      'Are you sure you want to delete this configuration?';

  @override
  String get delete => 'Delete';

  @override
  String get invalidPort => 'Invalid port';

  @override
  String get invalidEmail => 'Invalid email';

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
  String get bulkDefaultWarehouseTitle => 'Bulk default warehouse';

  @override
  String get bulkDefaultWarehouseAction => 'Change default warehouse';

  @override
  String get bulkDefaultWarehouseNewWarehouseLabel => 'New warehouse';

  @override
  String get bulkDefaultWarehouseClearOption =>
      'Clear default warehouse (empty)';

  @override
  String get bulkDefaultWarehouseScopeLabel => 'Apply scope (Policy):';

  @override
  String get bulkDefaultWarehouseScopeAll => 'All selected';

  @override
  String get bulkDefaultWarehouseScopeTrackInventoryTrue =>
      'Only inventory-tracked items (track_inventory=true)';

  @override
  String get bulkDefaultWarehouseScopeTrackInventoryFalse =>
      'Only non-inventory items (track_inventory=false)';

  @override
  String get bulkDefaultWarehouseConfirmTitle => 'Apply changes';

  @override
  String get bulkDefaultWarehouseConfirmMessage =>
      'Are you sure you want to apply this default warehouse change to the selected items?';

  @override
  String bulkDefaultWarehouseApplySuccess(String count) {
    return 'Done. Updated: $count';
  }

  @override
  String bulkDefaultWarehouseSelectedCount(int count) {
    return 'Selected items: $count';
  }

  @override
  String bulkDefaultWarehousePreviewSummary(
    String total,
    String found,
    String willUpdate,
  ) {
    return 'Requested: $total | Found: $found | Will update: $willUpdate';
  }

  @override
  String bulkDefaultWarehouseSkippedCount(int count) {
    return 'Skipped: $count';
  }

  @override
  String get bulkDefaultWarehouseNotesLabel => 'Notes:';

  @override
  String bulkDefaultWarehouseForcedServiceNull(int count) {
    return 'Service items forced to null default warehouse: $count';
  }

  @override
  String bulkDefaultWarehouseApplySummary(
    String total,
    String found,
    String updated,
    String skipped,
  ) {
    return 'Requested: $total | Found: $found | Updated: $updated | Skipped: $skipped';
  }

  @override
  String get bulkDefaultWarehouseReasonAlreadySet => 'Already set';

  @override
  String get bulkDefaultWarehouseReasonScopeMismatch => 'Out of selected scope';

  @override
  String get bulkDefaultWarehouseReasonNotFound => 'Not found';

  @override
  String get bulkDefaultWarehouseReasonServiceAlreadyNull =>
      'Service item must have no default warehouse';

  @override
  String get bulkDefaultWarehouseReasonUnknown => 'Unknown';

  @override
  String get newBusiness => 'New business';

  @override
  String get businesses => 'Businesses';

  @override
  String get deleteBusiness => 'Delete Business';

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
  String get passwordMaxLength =>
      'Password must not exceed 72 bytes (about 72 ASCII characters)';

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
  String get installmentsReportTitle => 'Installments report';

  @override
  String get installmentsFiltersFiscalYear => 'Fiscal year';

  @override
  String get installmentsFiltersStatus => 'Status';

  @override
  String get installmentsFiltersDueFrom => 'Due date from';

  @override
  String get installmentsFiltersDueTo => 'Due date to';

  @override
  String get installmentsFiltersPerson => 'Person';

  @override
  String get installmentsFiltersPersonHint => 'Search and select a person';

  @override
  String get installmentsFiltersInvoice => 'Invoice';

  @override
  String get installmentsFiltersInvoiceHint => 'Selected invoice number';

  @override
  String get installmentsFiltersInvoiceButton => 'Select invoice';

  @override
  String get installmentsStatusAll => 'All statuses';

  @override
  String get installmentsStatusPending => 'Pending';

  @override
  String get installmentsStatusPartial => 'Partially paid';

  @override
  String get installmentsStatusPaid => 'Paid';

  @override
  String get installmentsStatusOverdue => 'Overdue';

  @override
  String get installmentsSummaryPrincipal => 'Principal total';

  @override
  String get installmentsSummaryInterest => 'Interest total';

  @override
  String get installmentsSummaryTotal => 'Grand total';

  @override
  String get installmentsSummaryPaid => 'Paid total';

  @override
  String get installmentsSummaryRemaining => 'Remaining total';

  @override
  String get installmentsSummaryLateFee => 'Late fee total';

  @override
  String get installmentsFetchError => 'Failed to load installments';

  @override
  String get installmentsExportError => 'Export failed';

  @override
  String get installmentsExportWebOnly =>
      'File download is only available on the web version';

  @override
  String get installmentsInvoicePickerTitle => 'Select installment invoice';

  @override
  String get installmentsInvoicePickerSearchLabel =>
      'Search by code, description...';

  @override
  String get installmentInvoicesLoadMore => 'Load more';

  @override
  String installmentInvoicesCount(Object count) {
    return '$count installment invoice(s)';
  }

  @override
  String get installmentsTableInvoice => 'Invoice';

  @override
  String get installmentsTableInstallment => 'Installment';

  @override
  String get installmentsTablePerson => 'Person';

  @override
  String get installmentsTableDueDate => 'Due date';

  @override
  String get installmentsTableStatus => 'Status';

  @override
  String get installmentsTablePrincipal => 'Principal';

  @override
  String get installmentsTableInterest => 'Interest';

  @override
  String get installmentsTableTotal => 'Total';

  @override
  String get installmentsTablePaid => 'Paid';

  @override
  String get installmentsTableRemaining => 'Remaining';

  @override
  String get installmentsTableLateFee => 'Late fee';

  @override
  String get installmentsTableOverdueDays => 'Overdue days';

  @override
  String get installmentsRowsPerPage => 'Rows per page';

  @override
  String get installmentsViewPortfolios => 'Installment files';

  @override
  String get installmentsViewFlat => 'All installments';

  @override
  String get installmentsFiltersBucket => 'Quick filter';

  @override
  String get installmentsBucketAll => 'All';

  @override
  String get installmentsBucketUnpaid => 'Unpaid (open)';

  @override
  String get installmentsBucketUpcoming => 'Upcoming due dates';

  @override
  String get installmentsBucketOverdueOnly => 'Overdue only';

  @override
  String get installmentsMinOverdueDaysLabel => 'Min. overdue days';

  @override
  String get installmentsTableMobile => 'Mobile';

  @override
  String get installmentsGroupedNextDue => 'Next due';

  @override
  String get installmentsGroupedWorstStatus => 'Worst status';

  @override
  String get installmentsGroupedInstallments => 'Installments (matched)';

  @override
  String get installmentsGroupedPaidCount => 'Paid';

  @override
  String get installmentsGroupedOverdueCount => 'Overdue';

  @override
  String get installmentsGroupedRemainingSum => 'Remaining (sum)';

  @override
  String get installmentsDetailTitle => 'Installment plan';

  @override
  String get installmentsPaymentsColumn => 'Receipts';

  @override
  String get installmentsNoPaymentsYet => 'No receipt allocations yet';

  @override
  String get installmentsPaymentsDetailMissing =>
      'Payment is recorded on this installment, but linked receipt rows could not be listed. Try reopening the dialog after saving receipts with installment allocation.';

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
  String get importFromExcel => 'Import from Excel';

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
  String get includeSampleDataLabel => 'Add sample data for a quick start';

  @override
  String get includeSampleDataSubtitle =>
      'Creates sample customers, product, warehouse, and cash/bank accounts (not used when restoring from a .hbx backup).';

  @override
  String get sampleDataSeedWarning =>
      'Business created but sample data could not be completed';

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
  String get owner => 'Owner';

  @override
  String get member => 'Member';

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
  String get configData => 'Configuration Data';

  @override
  String get basePath => 'Base Path';

  @override
  String get ftpHost => 'Host';

  @override
  String get ftpPort => 'Port';

  @override
  String get ftpUsername => 'Username';

  @override
  String get ftpPassword => 'Password';

  @override
  String get ftpDirectory => 'FTP Directory';

  @override
  String get connectionSuccessful => 'Connection Successful';

  @override
  String get connectionFailed => 'Connection Failed';

  @override
  String get setAsDefault => 'Set as Default';

  @override
  String get defaultConfiguration => 'Default Configuration';

  @override
  String get setDefaultConfirm =>
      'Are you sure you want to set this configuration as default?';

  @override
  String get defaultSetSuccessfully => 'Default configuration set successfully';

  @override
  String get defaultSetFailed => 'Failed to set default configuration';

  @override
  String get cannotDeleteDefault => 'Cannot delete default configuration';

  @override
  String get defaultConfigurationNote =>
      'Default configuration is used for sending emails and cannot be deleted';

  @override
  String get setAsDefaultEmail => 'Set as Default Email';

  @override
  String get defaultEmailServer => 'Default Email Server';

  @override
  String get changeDefaultEmail => 'Change Default Email';

  @override
  String get currentDefault => 'Current Default';

  @override
  String get makeDefault => 'Make Default';

  @override
  String get defaultEmailNote => 'Emails are sent from the default server';

  @override
  String get noDefaultSet => 'No default email server is set';

  @override
  String get selectDefaultServer => 'Select Default Server';

  @override
  String get defaultServerChanged => 'Default server changed';

  @override
  String get defaultServerChangeFailed => 'Failed to change default server';

  @override
  String get emailConfigSavedSuccessfully =>
      'Email configuration saved successfully';

  @override
  String get emailConfigUpdatedSuccessfully =>
      'Email configuration updated successfully';

  @override
  String get editEmailConfiguration => 'Edit Email Configuration';

  @override
  String get updateConfiguration => 'Update Configuration';

  @override
  String get testEmailSubject => 'Test Email';

  @override
  String get testEmailBody => 'This is a test email.';

  @override
  String get testEmailSentSuccessfully => 'Test email sent successfully';

  @override
  String get emailConfigDeletedSuccessfully =>
      'Configuration deleted successfully';

  @override
  String get confirm => 'Confirm';

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
  String deleteConfirm(Object name) {
    return 'Are you sure to delete \"$name\"?';
  }

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
  String get itemsPerPage => 'Items per page';

  @override
  String get first => 'First';

  @override
  String get last => 'Last';

  @override
  String get systemSettingsWelcome => 'System Settings';

  @override
  String get systemSettingsDescription =>
      'Manage system configuration and administration';

  @override
  String get storageManagement => 'Storage Management';

  @override
  String get storageManagementDescription =>
      'Configure file storage, public app URL for share links (file sharing), and manage files';

  @override
  String get systemConfiguration => 'System Configuration';

  @override
  String get systemConfigurationDescription =>
      'General system settings and preferences';

  @override
  String get userManagement => 'User Management';

  @override
  String get userManagementDescription => 'Manage users, roles and permissions';

  @override
  String get systemLogs => 'System Logs';

  @override
  String get systemLogsDescription =>
      'View system reports and user activity logs';

  @override
  String get backToSettings => 'Back to Settings';

  @override
  String get settingsOverview => 'Settings Overview';

  @override
  String get availableSettings => 'Available Settings';

  @override
  String get systemAdministration => 'System Administration';

  @override
  String get generalSettings => 'General Settings';

  @override
  String get securitySettings => 'Security Settings';

  @override
  String get maintenanceSettings => 'Maintenance Settings';

  @override
  String get smsDestinationRateSettings =>
      'SMS rate limit (per destination number)';

  @override
  String get smsDestinationRateEnabled =>
      'Enforce per-number send cap within a time window';

  @override
  String get smsDestinationRateMaxSends => 'Max sends per number in the window';

  @override
  String get smsDestinationRateWindowMinutes => 'Window length (minutes)';

  @override
  String get smsDestinationRateMaxSendsHelper =>
      '0 means no cap (this per-number limit is off)';

  @override
  String get initializing => 'Initializing...';

  @override
  String get loadingLanguageSettings => 'Loading language settings...';

  @override
  String get loadingCalendarSettings => 'Loading calendar settings...';

  @override
  String get loadingThemeSettings => 'Loading theme settings...';

  @override
  String get loadingAuthentication => 'Loading authentication...';

  @override
  String get businessManagementPlatform => 'Business Management Platform';

  @override
  String get businessDashboard => 'Business Dashboard';

  @override
  String get businessStatistics => 'Business Statistics';

  @override
  String get recentActivities => 'Recent Activities';

  @override
  String get sales => 'Sales';

  @override
  String get accounting => 'Accounting';

  @override
  String get inventory => 'Inventory';

  @override
  String get reports => 'Reports';

  @override
  String get members => 'Members';

  @override
  String get backToProfile => 'Back to Profile';

  @override
  String get noBusinessesFound => 'No businesses found';

  @override
  String get createFirstBusiness => 'Create your first business';

  @override
  String get accessDenied => 'Access denied';

  @override
  String get basicTools => 'Basic Tools';

  @override
  String get businessSettings => 'Business Settings';

  @override
  String get printDocuments => 'Print Documents';

  @override
  String get people => 'People';

  @override
  String get peopleList => 'People List';

  @override
  String get personCode => 'Person Code';

  @override
  String get receipts => 'Receipts';

  @override
  String get payments => 'Payments';

  @override
  String get receiptsAndPayments => 'Receipts and Payments';

  @override
  String get productsAndServices => 'Products/Services';

  @override
  String get products => 'Products and Services';

  @override
  String get product => 'Product';

  @override
  String get services => 'Services';

  @override
  String get priceLists => 'Price Lists';

  @override
  String get categories => 'Categories';

  @override
  String get productAttributes => 'Product Attributes';

  @override
  String get addAttribute => 'Add Attribute';

  @override
  String get viewAttributes => 'View Attributes';

  @override
  String get editAttributes => 'Edit Attributes';

  @override
  String get deleteAttributes => 'Delete Attributes';

  @override
  String get title => 'Title';

  @override
  String get description => 'Description';

  @override
  String get add => 'Add';

  @override
  String get banking => 'Banking';

  @override
  String get accounts => 'Accounts';

  @override
  String get pettyCash => 'Petty Cash';

  @override
  String get cashBox => 'Cash Box';

  @override
  String get wallet => 'Wallet';

  @override
  String get checks => 'Checks';

  @override
  String get transfers => 'Transfers';

  @override
  String get invoice => 'Invoice';

  @override
  String get expenseAndIncome => 'Expense and Income';

  @override
  String get accountingMenu => 'Accounting';

  @override
  String get documents => 'Documents';

  @override
  String get chartOfAccounts => 'Chart of Accounts';

  @override
  String get openingBalance => 'Opening Balance';

  @override
  String get yearEndClosing => 'Year End Closing';

  @override
  String get currencyRevaluation => 'FX rates & revaluation';

  @override
  String get accountingSettings => 'Settings';

  @override
  String get servicesAndPlugins => 'Services and Plugins';

  @override
  String get warehouseManagement => 'Warehouse Management';

  @override
  String get warehouses => 'Warehouse Management';

  @override
  String get inquiries => 'Inquiries';

  @override
  String get storageSpace => 'Storage Space';

  @override
  String get taxpayers => 'Taxpayers';

  @override
  String get others => 'Others';

  @override
  String get pluginMarketplace => 'Plugin Marketplace';

  @override
  String get practicalTools => 'Practical Tools';

  @override
  String get usersAndPermissions => 'Users and Permissions';

  @override
  String get businessUsers => 'Business Users';

  @override
  String get addNewUser => 'Add New User';

  @override
  String get userEmailOrPhone => 'Email or Phone';

  @override
  String get userEmailOrPhoneHint => 'Enter user email or phone number';

  @override
  String get addUser => 'Add User';

  @override
  String get userAddedSuccessfully => 'User added successfully';

  @override
  String get userAddFailed => 'Failed to add user';

  @override
  String get userRemovedSuccessfully => 'User removed successfully';

  @override
  String get userRemoveFailed => 'Failed to remove user';

  @override
  String get permissionsUpdatedSuccessfully =>
      'Permissions updated successfully';

  @override
  String get permissionsUpdateFailed => 'Failed to update permissions';

  @override
  String get userNotFound => 'User not found';

  @override
  String get invalidEmailOrPhone => 'Invalid email or phone number';

  @override
  String get userAlreadyExists => 'User already exists';

  @override
  String get removeUser => 'Remove User';

  @override
  String get removeUserConfirm => 'Are you sure you want to remove this user?';

  @override
  String get userPermissions => 'User Permissions';

  @override
  String get permissions => 'Permissions';

  @override
  String get permission => 'Permission';

  @override
  String get hasPermission => 'Has Permission';

  @override
  String get noPermission => 'No Permission';

  @override
  String get viewUsers => 'View Users';

  @override
  String get managePermissions => 'Manage Permissions';

  @override
  String get totalUsers => 'Total Users';

  @override
  String get activeUsers => 'Active Users';

  @override
  String get pendingUsers => 'Pending Users';

  @override
  String get userName => 'User Name';

  @override
  String get userEmail => 'Email';

  @override
  String get userPhone => 'Phone';

  @override
  String get userStatus => 'Status';

  @override
  String get userRole => 'Role';

  @override
  String get userAddedAt => 'Added At';

  @override
  String get lastActive => 'Last Active';

  @override
  String get inactive => 'Inactive';

  @override
  String get pending => 'Pending';

  @override
  String get admin => 'Admin';

  @override
  String get viewer => 'Viewer';

  @override
  String get editPermissions => 'Edit Permissions';

  @override
  String get savePermissions => 'Save Permissions';

  @override
  String get noUsersFound => 'No users found';

  @override
  String get searchUsers => 'Search users...';

  @override
  String get filterByStatus => 'Filter by Status';

  @override
  String get filterByRole => 'Filter by Role';

  @override
  String get allStatuses => 'All Statuses';

  @override
  String get allRoles => 'All Roles';

  @override
  String get permissionDashboard => 'Dashboard Access';

  @override
  String get permissionPeople => 'People Access';

  @override
  String get permissionReceipts => 'Receipts Access';

  @override
  String get permissionPayments => 'Payments Access';

  @override
  String get permissionReports => 'Reports Access';

  @override
  String get permissionSettings => 'Settings Access';

  @override
  String get permissionUsers => 'Users Access';

  @override
  String get permissionPrint => 'Print Access';

  @override
  String get ownerWarning =>
      'Warning: Business owner does not need to be added and always has full access to all sections';

  @override
  String get ownerWarningTitle => 'Business Owner';

  @override
  String get alreadyAddedWarning =>
      'This user has already been added to the business';

  @override
  String get alreadyAddedWarningTitle => 'Existing User';

  @override
  String get version => 'Version 1.0.23';

  @override
  String get motto => 'The world becomes beautiful through cooperation';

  @override
  String get view => 'View';

  @override
  String get draft => 'Manage Drafts';

  @override
  String get addPerson => 'Add Person';

  @override
  String get viewPeople => 'View People List';

  @override
  String get editPeople => 'Edit People Information';

  @override
  String get deletePeople => 'Delete People';

  @override
  String get addReceipt => 'Add New Receipt';

  @override
  String get viewReceipts => 'View Receipts';

  @override
  String get editReceipts => 'Edit Receipts';

  @override
  String get deleteReceipts => 'Delete Receipts';

  @override
  String get manageReceiptDrafts => 'Manage Receipt Drafts';

  @override
  String get addPayment => 'Add New Payment';

  @override
  String get viewPayments => 'View Payments';

  @override
  String get editPayments => 'Edit Payments';

  @override
  String get deletePayments => 'Delete Payments';

  @override
  String get managePaymentDrafts => 'Manage Payment Drafts';

  @override
  String get addProduct => 'Add Product or Service';

  @override
  String get duplicateProduct => 'Copy Product / Service';

  @override
  String get productDuplicatedSuccessfully =>
      'Product copy was created successfully';

  @override
  String get viewProducts => 'View Products and Services';

  @override
  String get editProducts => 'Edit Products and Services';

  @override
  String get deleteProducts => 'Delete Products and Services';

  @override
  String get addPriceList => 'Add Price List';

  @override
  String get viewPriceLists => 'View Price Lists';

  @override
  String get editPriceLists => 'Edit Price Lists';

  @override
  String get deletePriceLists => 'Delete Price Lists';

  @override
  String get addCategory => 'Add Category';

  @override
  String get viewCategories => 'View Categories';

  @override
  String get editCategories => 'Edit Categories';

  @override
  String get deleteCategories => 'Delete Categories';

  @override
  String get addInventory => 'Add Inventory';

  @override
  String get viewInventory => 'View Inventory';

  @override
  String get editInventory => 'Edit Inventory';

  @override
  String get deleteInventory => 'Delete Inventory';

  @override
  String get viewReports => 'View Reports';

  @override
  String get generateReports => 'Generate Reports';

  @override
  String get exportReports => 'Export Reports';

  @override
  String get viewSettings => 'View Settings';

  @override
  String get editSettings => 'Edit Settings';

  @override
  String get users => 'Users';

  @override
  String get manageUsers => 'Manage Users';

  @override
  String get print => 'Print Documents';

  @override
  String get peopleReceipts => 'Receipts from People';

  @override
  String get peoplePayments => 'Payments to People';

  @override
  String get storageConfigUpdated => 'Storage configuration updated';

  @override
  String get storageConfigCreated => 'Storage configuration created';

  @override
  String get storageConfigDeleted => 'Storage configuration deleted';

  @override
  String get storageConfigHasFiles =>
      'This storage configuration has files and cannot be deleted';

  @override
  String get storageConfigNotFound => 'Storage configuration not found';

  @override
  String get storageConfigSetAsDefault => 'Configuration set as default';

  @override
  String get storageConfigSetDefaultFailed => 'Failed to set as default';

  @override
  String get adminStorageFtpPurposeSubtitle =>
      'Used as the default file storage backend for uploads (not the same as per-business backup FTP).';

  @override
  String get adminStorageFtpInsecureWarning =>
      'Without TLS, credentials and data can be read on the network. Enable TLS when the server supports it.';

  @override
  String get adminStorageFtpPasswordOptionalHint =>
      'Leave empty to keep the current password';

  @override
  String get adminStorageFtpPassive => 'Passive mode (PASV)';

  @override
  String get adminStorageFormSectionBasic => 'Basic information';

  @override
  String get adminStorageFormSectionDetails => 'Configuration details';

  @override
  String get adminStorageFormSectionOptions => 'Options';

  @override
  String get adminStorageNameHint => 'Enter a name for this storage profile';

  @override
  String get adminStorageFtpHostLabel => 'FTP host';

  @override
  String get adminStorageFtpHostHint => 'Hostname or IP of the FTP server';

  @override
  String get adminStorageFtpPortHintPlain => 'Default 21 without TLS';

  @override
  String get adminStorageFtpPortHintTls =>
      'Often 990 with implicit TLS, or 21 with explicit TLS';

  @override
  String get adminStorageFtpDirectoryLabel => 'Remote folder';

  @override
  String get adminStorageFtpDirectoryHint =>
      'Remote folder for stored files (e.g. /hesabix_files)';

  @override
  String get adminStorageLocalBasePath => 'Base path';

  @override
  String get adminStorageFtpUseTlsTitle => 'Use TLS';

  @override
  String get adminStorageFtpUseTlsSubtitle =>
      'FTP over TLS (FTPS) when supported';

  @override
  String get adminStorageDefaultTitle => 'Set as default';

  @override
  String get adminStorageDefaultSubtitle =>
      'Use this profile as the default storage';

  @override
  String get adminStorageActiveTitle => 'Active';

  @override
  String get adminStorageActiveSubtitle =>
      'Inactive profiles are not used for new uploads';

  @override
  String get adminStorageCreateTitle => 'Create storage profile';

  @override
  String get adminStorageEditTitle => 'Edit storage profile';

  @override
  String get adminStorageFtpServerTitle => 'FTP server';

  @override
  String get adminStorageTestConnection => 'Test connection';

  @override
  String get adminStorageTestingConnection => 'Testing connection…';

  @override
  String get adminStorageTestSuccess => 'Connection test succeeded';

  @override
  String get adminStorageTestFailed => 'Connection test failed';

  @override
  String get adminStorageSaveInProgress => 'Saving…';

  @override
  String get adminStorageCreateButton => 'Create';

  @override
  String get adminStorageUpdateButton => 'Update';

  @override
  String get passwordChangeError => 'Error changing password';

  @override
  String get bankAccounts => 'Bank Accounts';

  @override
  String get cash => 'Cash';

  @override
  String get invoices => 'Invoices';

  @override
  String get expensesIncome => 'Expenses & Income';

  @override
  String get accountingDocuments => 'Accounting Documents';

  @override
  String get warehouse => 'Warehouse';

  @override
  String get warehouseTransfers => 'Warehouse Transfers';

  @override
  String get permissionsWarehouseInventoryHint =>
      'Warehouse locations and warehouse documents use different permissions. Warehouse management is for defining warehouses. To use warehouse documents (lists, creating or posting documents, issuing from invoices, stock count adjustments, and related stock operations), enable the matching options under Warehouse transfers.';

  @override
  String get permissionsGroupHintChecks =>
      'Creating a new check posts an accounting document. Besides check permissions, enable at least one of add, edit, or draft under Accounting documents. Some check workflows (collection, endorsement, payment, etc.) may also record documents.';

  @override
  String get permissionsGroupHintAccountingDocuments =>
      'These permissions apply to manual journal entries and to automatic documents generated by the system from operations such as checks, receipts and payments, and invoices (where applicable).';

  @override
  String get checkFormNeedsChecksWritePermission =>
      'You do not have permission to add or edit checks.';

  @override
  String get checkFormNeedsAccountingDocumentsPermission =>
      'You do not have permission to post accounting documents. Saving a check records a journal entry; ask an admin to grant add, edit, or draft under Accounting documents.';

  @override
  String get addBankAccount => 'Add Bank Account';

  @override
  String get viewBankAccounts => 'View Bank Accounts';

  @override
  String get editBankAccounts => 'Edit Bank Accounts';

  @override
  String get deleteBankAccounts => 'Delete Bank Accounts';

  @override
  String get addCash => 'Add Cash';

  @override
  String get viewCash => 'View Cash';

  @override
  String get editCash => 'Edit Cash';

  @override
  String get deleteCash => 'Delete Cash';

  @override
  String get addPettyCash => 'Add Petty Cash';

  @override
  String get viewPettyCash => 'View Petty Cash';

  @override
  String get editPettyCash => 'Edit Petty Cash';

  @override
  String get deletePettyCash => 'Delete Petty Cash';

  @override
  String get addCheck => 'Add Check';

  @override
  String get viewChecks => 'View Checks';

  @override
  String get editChecks => 'Edit Checks';

  @override
  String get deleteChecks => 'Delete Checks';

  @override
  String get collectChecks => 'Collect Checks';

  @override
  String get transferChecks => 'Transfer Checks';

  @override
  String get returnChecks => 'Return Checks';

  @override
  String get viewWallet => 'View Wallet';

  @override
  String get chargeWallet => 'Charge Wallet';

  @override
  String get addTransfer => 'Add Transfer';

  @override
  String get viewTransfers => 'View Transfers';

  @override
  String get editTransfers => 'Edit Transfers';

  @override
  String get deleteTransfers => 'Delete Transfers';

  @override
  String get manageTransferDrafts => 'Manage Transfer Drafts';

  @override
  String get addInvoice => 'Add Invoice';

  @override
  String get invoiceCopyOpenNew => 'Copy to new invoice';

  @override
  String get invoiceCopyLoading =>
      'Preparing the new invoice form from the selected document…';

  @override
  String get viewInvoices => 'View Invoices';

  @override
  String get editInvoices => 'Edit Invoices';

  @override
  String get deleteInvoices => 'Delete Invoices';

  @override
  String get manageInvoiceDrafts => 'Manage Invoice Drafts';

  @override
  String get addExpenseIncome => 'Add Expense/Income';

  @override
  String get viewExpensesIncome => 'View Expenses & Income';

  @override
  String get editExpensesIncome => 'Edit Expenses & Income';

  @override
  String get deleteExpensesIncome => 'Delete Expenses & Income';

  @override
  String get manageExpenseIncomeDrafts => 'Manage Expense/Income Drafts';

  @override
  String get addAccountingDocument => 'Add Accounting Document';

  @override
  String get viewAccountingDocuments => 'View Accounting Documents';

  @override
  String get editAccountingDocuments => 'Edit Accounting Documents';

  @override
  String get deleteAccountingDocuments => 'Delete Accounting Documents';

  @override
  String get manageAccountingDocumentDrafts =>
      'Manage Accounting Document Drafts';

  @override
  String get addAccount => 'Add Account';

  @override
  String get viewChartOfAccounts => 'View Chart of Accounts';

  @override
  String get editChartOfAccounts => 'Edit Chart of Accounts';

  @override
  String get deleteAccounts => 'Delete Accounts';

  @override
  String get viewOpeningBalance => 'View Opening Balance';

  @override
  String get editOpeningBalance => 'Edit Opening Balance';

  @override
  String get addWarehouse => 'Add Warehouse';

  @override
  String get viewWarehouses => 'View Warehouses';

  @override
  String get editWarehouses => 'Edit Warehouses';

  @override
  String get deleteWarehouses => 'Delete Warehouses';

  @override
  String get addWarehouseTransfer => 'Add Warehouse Transfer';

  @override
  String get viewWarehouseTransfers => 'View Warehouse Transfers';

  @override
  String get editWarehouseTransfers => 'Edit Warehouse Transfers';

  @override
  String get deleteWarehouseTransfers => 'Delete Warehouse Transfers';

  @override
  String get manageWarehouseTransferDrafts =>
      'Manage Warehouse Transfer Drafts';

  @override
  String get printSettings => 'Print Settings';

  @override
  String get eventHistory => 'Event History';

  @override
  String get viewStorage => 'View Storage';

  @override
  String get deleteFiles => 'Files';

  @override
  String get smsPanel => 'SMS Panel';

  @override
  String get viewSmsHistory => 'View SMS History';

  @override
  String get manageSmsTemplates => 'Manage SMS Templates';

  @override
  String get marketplace => 'Marketplace';

  @override
  String get viewMarketplace => 'View Marketplace';

  @override
  String get buyPlugins => 'Buy Plugins';

  @override
  String get appearanceSettings => 'Appearance Settings';

  @override
  String get advancedSettings => 'Advanced Settings';

  @override
  String get businessSettingsDescription =>
      'Manage business information and main settings';

  @override
  String get usersAndPermissionsDescription =>
      'Manage users and set access levels';

  @override
  String get printDocumentsDescription =>
      'Configure print templates and formatting';

  @override
  String get languageDescription => 'Select user interface language';

  @override
  String get themeDescription => 'Choose light, dark or system theme';

  @override
  String get calendarDescription =>
      'Select calendar type (Jalali or Gregorian)';

  @override
  String get dataBackup => 'Data Backup';

  @override
  String get dataBackupDescription => 'Create backup of all business data';

  @override
  String get dataRestore => 'Data Restore';

  @override
  String get dataRestoreDescription => 'Restore data from previous backup';

  @override
  String get restoreModeNewBusiness => 'Create a new business';

  @override
  String get restoreModeReplace => 'Replace existing data';

  @override
  String get restoreWarningTitle => 'Security Warning';

  @override
  String get restoreWarningReplace =>
      '⚠️ Restoring with \"Complete replacement\" mode will DELETE all current business data and replace it with backup data. This action is IRREVERSIBLE!';

  @override
  String get restoreWarningNewBusiness =>
      'ℹ️ Restoring with \"Create new business\" mode will create a new business with backup data and will NOT affect your current data.';

  @override
  String get restoreSecurityNote => 'Security Notes:';

  @override
  String get restoreSecurityNote1 =>
      '• Create a backup of your current data before restoring';

  @override
  String get restoreSecurityNote2 =>
      '• Ensure the backup file is valid and belongs to your business';

  @override
  String get restoreSecurityNote3 =>
      '• Restore may take several minutes, please wait';

  @override
  String get restoreSecurityNote4 =>
      '• Contact support if you encounter any errors';

  @override
  String get restoreConfirmReplace => 'Confirm Complete Replacement';

  @override
  String get restoreConfirmReplaceMessage =>
      'Are you sure you want to DELETE all current data and replace it with backup data?\n\nThis action is IRREVERSIBLE!';

  @override
  String get restoreConfirmNewBusiness => 'Confirm New Business Creation';

  @override
  String get restoreConfirmNewBusinessMessage =>
      'Are you sure you want to create a new business with backup data?';

  @override
  String get restoreSourceTitle => 'Restore Source';

  @override
  String get restoreModeTitle => 'Restore Mode';

  @override
  String get selectBackupFile => 'Select backup file (.hbx)';

  @override
  String get defaultBackupFilename => 'backup.hbx';

  @override
  String get errorUnknown => 'Unknown error';

  @override
  String get errorConnectionTimeout =>
      'Connection timeout. Please check your internet connection.';

  @override
  String get errorReceiveTimeout => 'Receive timeout. Please try again.';

  @override
  String get errorConnectionError =>
      'Connection error. Please check your internet connection.';

  @override
  String get errorFileUploadFailed => 'File upload failed. Please try again.';

  @override
  String get errorDataSaveFailed =>
      'Could not save the data. Please try again.';

  @override
  String get errorSendTimeout => 'Send timeout.';

  @override
  String get errorUnknownServer => 'Unknown server error';

  @override
  String get errorRequestTimeout => 'Request timeout. Please try again.';

  @override
  String get errorExtractorSaveData => 'Could not save data.';

  @override
  String get errorExtractorFileUpload => 'File upload error.';

  @override
  String get errorInternetUnavailablePleaseRetry =>
      'No internet connection. Please try again.';

  @override
  String get errorInvalidInput =>
      'Invalid input data. Please check the information.';

  @override
  String get errorBackupNotFound => 'Backup not found.';

  @override
  String get errorBusinessMismatch =>
      'This backup belongs to a different business.';

  @override
  String get errorNotSupported => 'This operation is not currently supported.';

  @override
  String get errorRateLimit => 'Too many requests. Please wait a moment.';

  @override
  String get errorInvalidBackup => 'Backup file is invalid or corrupted.';

  @override
  String get errorBusinessCreationFailed =>
      'Failed to create new business. Please try again.';

  @override
  String get errorRestoreFailed => 'Restore failed';

  @override
  String get byteUnitB => 'B';

  @override
  String get byteUnitKB => 'KB';

  @override
  String get byteUnitMB => 'MB';

  @override
  String get byteUnitGB => 'GB';

  @override
  String get byteUnitTB => 'TB';

  @override
  String get backupCompleted => 'Backup completed';

  @override
  String get restoreCompleted => 'Restore completed';

  @override
  String get backupFailed => 'Backup failed';

  @override
  String get restoreFailed => 'Restore failed';

  @override
  String get jobStartingBackup => 'Starting backup';

  @override
  String get jobCollectingData => 'Collecting data';

  @override
  String get jobPackagingArchive => 'Packaging archive';

  @override
  String get jobSavingFile => 'Saving file';

  @override
  String get jobFinalizing => 'Finalizing';

  @override
  String get jobUploadingFile => 'Uploading file';

  @override
  String get jobStartingRestore => 'Starting restore';

  @override
  String get jobLoadingBackup => 'Loading backup';

  @override
  String get jobCreatingNewBusiness => 'Creating new business';

  @override
  String get jobNewBusinessCreated => 'New business created';

  @override
  String get jobCleaningCurrentData => 'Cleaning current data';

  @override
  String get jobPreparingToRestoreData => 'Preparing to restore data';

  @override
  String get jobUpdatingBusinessInfo => 'Updating business info';

  @override
  String get jobPreparingBusinessData => 'Preparing business data';

  @override
  String get jobRestoringData => 'Restoring data';

  @override
  String get manage => 'Manage';

  @override
  String get configure => 'Configure';

  @override
  String get set => 'Set';

  @override
  String get execute => 'Execute';

  @override
  String get backup => 'Backup';

  @override
  String get restore => 'Restore';

  @override
  String get businessSettingsDialogContent =>
      'In this section you can manage business information, address, contact numbers and other details.';

  @override
  String get usersAndPermissionsDialogContent =>
      'In this section you can add new users, set permissions and manage roles.';

  @override
  String get printDocumentsDialogContent =>
      'In this section you can configure print templates, letterheads and printer settings.';

  @override
  String get dataBackupDialogContent =>
      'In this section you can create a backup of all business data.';

  @override
  String get dataRestoreDialogContent =>
      'In this section you can restore data from a previous backup.';

  @override
  String get systemLogsDialogContent =>
      'In this section you can view system reports, errors and user activities.';

  @override
  String get accountManagement => 'Account Management';

  @override
  String get persons => 'Persons';

  @override
  String get person => 'Person';

  @override
  String get personsList => 'Persons List';

  @override
  String get personGroup => 'Person group';

  @override
  String get personGroupNone => 'No group';

  @override
  String get personGroupsManage => 'Manage person groups';

  @override
  String get personGroupColumn => 'Group';

  @override
  String get editPerson => 'Edit Person';

  @override
  String get personDetails => 'Person Details';

  @override
  String get deletePerson => 'Delete Person';

  @override
  String get personAliasName => 'Alias Name';

  @override
  String get personFirstName => 'First Name';

  @override
  String get personLastName => 'Last Name';

  @override
  String get personType => 'Person Type';

  @override
  String get personCompanyName => 'Company Name';

  @override
  String get personNamePrefix => 'Name prefix';

  @override
  String get personNamePrefixNone => 'None';

  @override
  String get personLegalEntityType => 'Legal entity type';

  @override
  String get personLegalEntityNatural => 'Natural person';

  @override
  String get personLegalEntityLegal => 'Legal entity';

  @override
  String get personPaymentId => 'Payment ID';

  @override
  String get personNationalId => 'National ID';

  @override
  String get personRegistrationNumber => 'Registration Number';

  @override
  String get personEconomicId => 'Economic ID';

  @override
  String get personCountry => 'Country';

  @override
  String get personProvince => 'Province';

  @override
  String get personCity => 'City';

  @override
  String get personAddress => 'Address';

  @override
  String get personPostalCode => 'Postal Code';

  @override
  String get personPhone => 'Phone';

  @override
  String get personMobile => 'Mobile';

  @override
  String get personFax => 'Fax';

  @override
  String get personEmail => 'Email';

  @override
  String get personWebsite => 'Website';

  @override
  String get personSocialNetworks => 'Messengers and social networks';

  @override
  String get personSocialPlatform => 'Platform';

  @override
  String get personSocialValue => 'Username, link or number';

  @override
  String get personSocialCustomName => 'Custom platform name (for Other)';

  @override
  String get addPersonSocialRow => 'Add contact';

  @override
  String get noPersonSocialRows => 'No messenger or social entry yet.';

  @override
  String get personBankAccounts => 'Bank Accounts';

  @override
  String get editBankAccount => 'Edit Bank Account';

  @override
  String get deleteBankAccount => 'Delete Bank Account';

  @override
  String get bankName => 'Bank Name';

  @override
  String get accountNumber => 'Account Number';

  @override
  String get cardNumber => 'Card Number';

  @override
  String get shebaNumber => 'Sheba Number';

  @override
  String get personTypeCustomer => 'Customer';

  @override
  String get personTypeMarketer => 'Marketer';

  @override
  String get personTypeEmployee => 'Employee';

  @override
  String get personTypeSupplier => 'Supplier';

  @override
  String get personTypePartner => 'Partner';

  @override
  String get personTypeSeller => 'Seller';

  @override
  String get personTypeShareholder => 'Shareholder';

  @override
  String get personCreatedSuccessfully => 'Person created successfully';

  @override
  String get personUpdatedSuccessfully => 'Person updated successfully';

  @override
  String get personDeletedSuccessfully => 'Person deleted successfully';

  @override
  String get personNotFound => 'Person not found';

  @override
  String get personAliasNameRequired => 'Alias name is required';

  @override
  String get personAliasPickFromNamesHint => 'Fill alias from name fields…';

  @override
  String get personTypeRequired => 'Person type is required';

  @override
  String get bankAccountAddedSuccessfully => 'Bank account added successfully';

  @override
  String get bankAccountUpdatedSuccessfully =>
      'Bank account updated successfully';

  @override
  String get bankAccountDeletedSuccessfully =>
      'Bank account deleted successfully';

  @override
  String get bankNameRequired => 'Bank name is required';

  @override
  String get personBasicInfo => 'Basic Information';

  @override
  String get personEconomicInfo => 'Economic Information';

  @override
  String get personContactInfo => 'Contact Information';

  @override
  String get personBankInfo => 'Bank Accounts';

  @override
  String get personSummary => 'Persons Summary';

  @override
  String get totalPersons => 'Total Persons';

  @override
  String get activePersons => 'Active Persons';

  @override
  String get inactivePersons => 'Inactive Persons';

  @override
  String get personsByType => 'Persons by Type';

  @override
  String get update => 'Update';

  @override
  String get collect => 'Collect';

  @override
  String get transfer => 'Transfer';

  @override
  String get charge => 'Charge';

  @override
  String get saving => 'Saving...';

  @override
  String get userPermissionsTitle => 'User Permissions';

  @override
  String get dialogClose => 'Close';

  @override
  String get buy => 'Buy';

  @override
  String get templates => 'Templates';

  @override
  String get history => 'History';

  @override
  String get business => 'Business';

  @override
  String get shareCount => 'Share Count';

  @override
  String get commissionSalePercentLabel => 'Commission Sale Percent';

  @override
  String get commissionSalesReturnPercentLabel =>
      'Commission Sales Return Percent';

  @override
  String get commissionSalesAmountLabel => 'Commission Sales Amount';

  @override
  String get commissionSalesReturnAmountLabel =>
      'Commission Sales Return Amount';

  @override
  String get importPersonsFromExcel => 'Import Persons from Excel';

  @override
  String get selectedFile => 'Selected file';

  @override
  String get noFileSelected => 'No file selected';

  @override
  String get chooseFile => 'Choose file';

  @override
  String get matchBy => 'Match by';

  @override
  String get code => 'Code';

  @override
  String get conflictPolicy => 'Conflict policy';

  @override
  String get policyInsertOnly => 'Insert-only';

  @override
  String get policyUpdateExisting => 'Update existing';

  @override
  String get policyUpsert => 'Upsert';

  @override
  String get dryRun => 'Dry run';

  @override
  String get dryRunValidateOnly => 'Dry run (validate only)';

  @override
  String get downloadTemplate => 'Download template';

  @override
  String get reviewDryRun => 'Review (Dry run)';

  @override
  String get import => 'Import';

  @override
  String get importReal => 'Import (real)';

  @override
  String get templateDownloaded => 'Template downloaded';

  @override
  String get pickFileError => 'Error picking file';

  @override
  String get templateDownloadError => 'Error downloading template';

  @override
  String get importError => 'Import error';

  @override
  String get result => 'Result';

  @override
  String get valid => 'Valid';

  @override
  String get invalid => 'Invalid';

  @override
  String get inserted => 'Inserted';

  @override
  String get updated => 'Updated';

  @override
  String get skipped => 'Skipped';

  @override
  String get importSkippedApply => 'Failed on save';

  @override
  String get importPreviewInsert => 'Would insert (preview)';

  @override
  String get importPreviewUpdate => 'Would update (preview)';

  @override
  String get importPreviewSkipConflict => 'Would skip existing (preview)';

  @override
  String get importWarningsTitle => 'Warnings';

  @override
  String get personImportSuccess => 'Import completed';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get row => 'Row';

  @override
  String get onlyForMarketerSeller =>
      'This section is shown only for marketer/seller';

  @override
  String get percentFromSales => 'Percent from sales';

  @override
  String get percentFromSalesReturn => 'Percent from sales return';

  @override
  String get salesAmount => 'Sales amount';

  @override
  String get salesReturnAmount => 'Sales return amount';

  @override
  String get mustBeBetweenZeroAndHundred => 'Must be between 0 and 100';

  @override
  String get mustBePositiveNumber => 'Must be a positive number';

  @override
  String get personCodeOptional => 'Person code (optional)';

  @override
  String get uniqueCodeNumeric => 'Unique code (numeric)';

  @override
  String get automatic => 'Automatic';

  @override
  String get manual => 'Manual';

  @override
  String get personCodeRequired => 'Person code is required';

  @override
  String get codeMustBeNumeric => 'Code must be numeric';

  @override
  String get integerNoDecimal => 'Integer number (no decimals)';

  @override
  String get shareholderShareCountRequired =>
      'For shareholder, share count is required';

  @override
  String get noBankAccountsAdded => 'No bank accounts added';

  @override
  String get commissionExcludeDiscounts => 'Exclude discounts from commission';

  @override
  String get commissionExcludeAdditionsDeductions =>
      'Exclude additions/deductions from commission';

  @override
  String get commissionPostInInvoiceDocument =>
      'Post commission in invoice accounting document';

  @override
  String get manageCategories => 'Manage Categories';

  @override
  String get categoriesDialogTitle => 'Manage Categories';

  @override
  String get addRootCategory => 'Add Root';

  @override
  String get addChildCategory => 'Add Child';

  @override
  String get renameCategory => 'Rename';

  @override
  String get deleteCategory => 'Delete Category';

  @override
  String get deleteCategoryConfirm =>
      'Are you sure you want to delete this category?';

  @override
  String get categoryNameFa => 'Name (Persian)';

  @override
  String get categoryNameEn => 'Name (English)';

  @override
  String get categoryName => 'Category Name';

  @override
  String get categoryNameRequired => 'Category name is required';

  @override
  String get categoryNameHint => 'Enter category name';

  @override
  String get categoryType => 'Type';

  @override
  String get productType => 'Product';

  @override
  String get serviceType => 'Service';

  @override
  String get loadingCategories => 'Loading categories...';

  @override
  String get createCategory => 'Create Category';

  @override
  String get updateCategory => 'Update Category';

  @override
  String get deleteCategorySuccess => 'Category deleted';

  @override
  String get operationFailed => 'Operation failed';

  @override
  String get productGeneralInfo => 'General Information';

  @override
  String get pricingAndInventory => 'Pricing & Inventory';

  @override
  String get tax => 'Tax';

  @override
  String get productStock => 'Stock';

  @override
  String get productStockInWarehouses => 'Product Stock in Warehouses';

  @override
  String get productCommercialPricing => 'Commercial & Pricing';

  @override
  String get productCommercialPricingNoAccessHint =>
      'To view this tab, invoice read permission is required. Ask your admin to grant invoices.view.';

  @override
  String get productCommercialInsightsNotEligibleTitle =>
      'This report is not active for this product';

  @override
  String get productCommercialInsightsNotEligibleBody =>
      'This summary is not available for this product or current business configuration.';

  @override
  String get productCommercialInsightsChecklistTitle => 'Checklist:';

  @override
  String get productCommercialInsightsChecklistInventoryTracked =>
      'Ensure inventory tracking is enabled for this product.';

  @override
  String get productCommercialInsightsChecklistConfirmedInvoice =>
      'Ensure at least one confirmed purchase/sales invoice exists for this product.';

  @override
  String get productCommercialInsightsChecklistPostedWarehouseDoc =>
      'Ensure related invoices have a posted warehouse document with source type invoice.';

  @override
  String get productCommercialInsightsReload => 'Reload';

  @override
  String get productCommercialInsightsResetTooltip => 'Reset';

  @override
  String get productCommercialInsightsNoData => 'No data';

  @override
  String get productCommercialInsightsDocumentDate => 'Document date';

  @override
  String get productCommercialInsightsParty => 'Party';

  @override
  String get productCommercialInsightsDocumentCode => 'Document code';

  @override
  String get productCommercialInsightsQuantity => 'Quantity';

  @override
  String get productCommercialInsightsUnitPriceBase =>
      'Unit price in base currency';

  @override
  String get productCommercialInsightsFxRateToBase =>
      'Document to base FX rate';

  @override
  String get productCommercialInsightsChartDataMissing =>
      'Chart data is not available.';

  @override
  String get productCommercialInsightsChartNoPoints =>
      'No chart points for the selected range.';

  @override
  String get productCommercialInsightsLanePurchase => 'Purchase';

  @override
  String get productCommercialInsightsLaneSale => 'Sale';

  @override
  String get productCommercialInsightsLegendPurchaseAvg =>
      'Weighted average purchase (base)';

  @override
  String get productCommercialInsightsLegendSaleAvg =>
      'Weighted average sale (base)';

  @override
  String get productCommercialInsightsAvgUnitBaseLabel =>
      'Average unit in base';

  @override
  String get productCommercialInsightsTotalQuantityLabel => 'Total quantity';

  @override
  String get productCommercialInsightsBucketDay => 'Day';

  @override
  String get productCommercialInsightsBucketWeek => 'Week';

  @override
  String get productCommercialInsightsBucketMonth => 'Month';

  @override
  String get productCommercialInsightsPreset30Days => '30 days';

  @override
  String get productCommercialInsightsPreset90Days => '90 days';

  @override
  String get productCommercialInsightsPreset6Months => '6 months';

  @override
  String get productCommercialInsightsPreset1Year => '1 year';

  @override
  String get productCommercialInsightsPresetCustom => 'Custom';

  @override
  String get productCommercialInsightsFromDate => 'From date';

  @override
  String get productCommercialInsightsToDate => 'To date';

  @override
  String get productCommercialInsightsLastPurchase => 'Last purchase';

  @override
  String get productCommercialInsightsLastSale => 'Last sale';

  @override
  String get productCommercialInsightsTotalsInRange => 'Totals in range';

  @override
  String get productCommercialInsightsPurchaseQuantity => 'Purchase quantity';

  @override
  String get productCommercialInsightsSaleQuantity => 'Sale quantity';

  @override
  String get productCommercialInsightsPurchaseLinesCount =>
      'Purchase lines count';

  @override
  String get productCommercialInsightsSaleLinesCount => 'Sale lines count';

  @override
  String get productCommercialInsightsTrendTitle =>
      'Weighted average unit price trend (base currency)';

  @override
  String get productCommercialInsightsTopSuppliers => 'Top suppliers in range';

  @override
  String get productCommercialInsightsTopBuyers => 'Top buyers in range';

  @override
  String get productCommercialInsightsRecentEventsTitle =>
      'Recent events (invoice lines)';

  @override
  String get productCommercialInsightsUnitShortLabel => 'unit';

  @override
  String get warehouseCode => 'Warehouse Code';

  @override
  String get warehouseName => 'Warehouse Name';

  @override
  String get stockQuantity => 'Quantity';

  @override
  String get totalStock => 'Total Stock';

  @override
  String get noStockRecorded => 'No stock recorded';

  @override
  String get inventoryNotTracked => 'This product does not track inventory';

  @override
  String get stockReportDate => 'Report Date';

  @override
  String get showZeroStock => 'Show Zero Stock';

  @override
  String get refreshStock => 'Refresh Stock';

  @override
  String get inventoryControl => 'Inventory control';

  @override
  String get inventoryControlHelpSubtitle =>
      'On: stock is tracked and this product is included on invoice-linked warehouse documents. Off: the product is skipped when warehouse drafts are generated from invoices.';

  @override
  String get inventoryControlHelpDetail =>
      'Turning this off does not mean “allow posting issues with negative stock.” To sometimes post outgoing warehouse documents despite insufficient stock, use the shortage / negative-stock policy in business settings—that is separate from this switch.';

  @override
  String get inventoryUniqueModeRequiresTrack =>
      'To use unique inventory mode, enable “inventory control” first';

  @override
  String get reorderPoint => 'Reorder point';

  @override
  String get reorderPointRepeat => 'Reorder point';

  @override
  String get minOrderQty => 'Minimum order quantity';

  @override
  String get leadTimeDays => 'Lead time (days)';

  @override
  String get pricing => 'Pricing';

  @override
  String get productName => 'Product name';

  @override
  String get barcode => 'Barcode';

  @override
  String get productGeneralBarcodes => 'General barcodes';

  @override
  String get productGeneralBarcodesHint =>
      'Enter multiple codes separated by commas (English or Persian comma). Used for quick product lookup on invoices and optional PDF labels.';

  @override
  String get printGeneralBarcodeLabels => 'Print general barcode labels (PDF)';

  @override
  String get generalBarcodeLabelsTitle => 'General barcode labels';

  @override
  String get generalBarcodeLabelsNoneSelected =>
      'No general barcodes found on selected products.';

  @override
  String get labelPdfDialogTitle => 'Print labels';

  @override
  String get labelPdfContentSection => 'Label content';

  @override
  String get labelPdfLinearBarcode => 'Linear barcode';

  @override
  String get labelPdfQrCode => 'QR code';

  @override
  String get labelPdfBarcodeAsText => 'Barcode value as text';

  @override
  String get labelPdfProductName => 'Product name';

  @override
  String get labelPdfSerialLine => 'Serial line';

  @override
  String get labelPdfPaperLayoutSection => 'Paper & layout';

  @override
  String get labelPdfPaperSize => 'Paper size';

  @override
  String get labelPdfLandscape => 'Landscape';

  @override
  String get labelPdfColumns => 'Columns';

  @override
  String get labelPdfPageMarginPts => 'Page margin (pt)';

  @override
  String get labelPdfPreview => 'Preview';

  @override
  String get labelPdfSave => 'Save PDF';

  @override
  String get labelPdfShare => 'Share';

  @override
  String get labelPdfClose => 'Close';

  @override
  String get labelPdfSaved => 'PDF file saved';

  @override
  String get labelPdfSaveFailed => 'Could not save PDF';

  @override
  String get labelPdfShareFailed => 'Share failed';

  @override
  String get labelPdfBuildError => 'Could not build PDF';

  @override
  String get labelPdfPreviewHintDesktop =>
      'Zoom and scroll using the preview toolbar';

  @override
  String get labelPdfPreviewHintWeb =>
      'On web: preview uses your browser PDF viewer (zoom via menu or Ctrl±)';

  @override
  String get labelPdfOrientationLandscape => 'Landscape';

  @override
  String get labelPdfOrientationPortrait => 'Portrait';

  @override
  String get generalInformation => 'General information';

  @override
  String get imageNotAvailable => 'Image not available';

  @override
  String get salesPrice => 'Sales price';

  @override
  String get salesPriceNote => 'Sales price note';

  @override
  String get purchasePrice => 'Purchase price';

  @override
  String get purchasePriceNote => 'Purchase price note';

  @override
  String get pricesInPriceLists => 'Prices in price lists';

  @override
  String get addPrice => 'Add price';

  @override
  String get price => 'Price';

  @override
  String get currency => 'Currency';

  @override
  String get noPriceListsTitle => 'No price list';

  @override
  String get noPriceListsMessage =>
      'To add a price, first create a price list.';

  @override
  String get noPriceListsHint =>
      'Use \"Manage price lists\" button in Products page to create one.';

  @override
  String get gotIt => 'Got it';

  @override
  String get unitsTitle => 'Units';

  @override
  String get mainUnit => 'Main unit';

  @override
  String get secondaryUnit => 'Secondary unit';

  @override
  String get unitConversionFactor => 'Unit conversion factor';

  @override
  String get itemType => 'Type';

  @override
  String get type => 'Type';

  @override
  String get productPhysicalDesc => 'Physical products';

  @override
  String get serviceDesc => 'Services';

  @override
  String get taxTitle => 'Tax';

  @override
  String get taxCode => 'Tax code';

  @override
  String get isSalesTaxable => 'Sales taxable';

  @override
  String get salesTaxRate => 'Sales tax rate (%)';

  @override
  String get isPurchaseTaxable => 'Purchase taxable';

  @override
  String get purchaseTaxRate => 'Purchase tax rate (%)';

  @override
  String get taxType => 'Tax type';

  @override
  String get taxTypeId => 'Tax type id';

  @override
  String get taxUnit => 'Tax unit';

  @override
  String get taxUnitId => 'Tax unit id';

  @override
  String get vatColumn => 'VAT';

  @override
  String taxVatPercent(Object value) {
    return '$value%';
  }

  @override
  String get taxVatUnknown => 'Not specified';

  @override
  String get bulkPriceUpdateTitle => 'Bulk price update';

  @override
  String get bulkPriceUpdateSubtitle =>
      'Increase or decrease prices with advanced filters';

  @override
  String get bulkPriceUpdateApplyScopeTitle => 'Apply to';

  @override
  String get bulkPriceUpdateScopeBase => 'Base prices only';

  @override
  String get bulkPriceUpdateScopePriceLists => 'Price lists only';

  @override
  String get bulkPriceUpdateScopeBoth => 'Base prices and price lists';

  @override
  String get bulkPriceUpdateStatsTitle => 'Summary stats';

  @override
  String get bulkPriceUpdateListOnlyTargetHint =>
      'Only sale prices inside price lists will change.';

  @override
  String get bulkPriceUpdatePriceListsHint =>
      'If none selected, all price lists (matching currency filter) apply.';

  @override
  String get bulkPriceUpdatePreviewListChanges => 'Price list';

  @override
  String bulkPriceUpdatePreviewListRowsCount(int count) {
    return '$count rows';
  }

  @override
  String get bulkPriceUpdateSummaryListRows => 'Price list rows';

  @override
  String get bulkPriceUpdateSummaryListDelta => 'Total price list delta';

  @override
  String get bulkProductPricesSheetTitle => 'Bulk price sheet';

  @override
  String get bulkProductPricesSheetSubtitle =>
      'Edit base prices in a table; each page is saved separately.';

  @override
  String get bulkProductPricesSheetSave => 'Save this page';

  @override
  String get bulkProductPricesSheetNext => 'Next page';

  @override
  String get bulkProductPricesSheetPrev => 'Previous page';

  @override
  String get bulkProductPricesSheetSearch => 'Search';

  @override
  String get bulkProductPricesSheetClearSearch => 'Clear';

  @override
  String get bulkProductPricesSheetNoChanges => 'Nothing to save';

  @override
  String get bulkProductPricesSheetCode => 'Code';

  @override
  String get bulkProductPricesSheetName => 'Name';

  @override
  String get bulkProductPricesSheetPriceListsForColumns => 'Price list columns';

  @override
  String get bulkProductPricesSheetSelectListsHint =>
      'Select one or more price lists to show and edit list prices, then load the page.';

  @override
  String get bulkProductPricesSheetExportExcel => 'Download Excel';

  @override
  String get bulkProductPricesSheetImportExcel => 'Upload Excel';

  @override
  String get bulkProductPricesSheetExcelHint =>
      'All products matching this search are exported. After editing prices, upload the file. Keep the worksheet name «BulkPrices»; pi_* columns are price-item IDs.';

  @override
  String get bulkProductPricesSheetGuideTitle => 'Guide & Excel';

  @override
  String get bulkProductPricesSheetSearchSection => 'Search & price lists';

  @override
  String get bulkProductPricesSheetTableSection => 'Price grid';

  @override
  String get bulkProductPricesSheetMoreActions => 'More actions';

  @override
  String get bulkProductPricesSheetNoRows => 'No products on this page';

  @override
  String get bulkProductPricesSheetNoRowsHint =>
      'Try another search or switch page.';

  @override
  String get bulkProductPricesSheetPageLabel => 'Page';

  @override
  String get bulkProductPricesSheetPriceListPrices => 'List prices';

  @override
  String get preview => 'Preview';

  @override
  String get applyChanges => 'Apply changes';

  @override
  String get changeTypeAndDirection => 'Change type & direction';

  @override
  String get changeTarget => 'Target';

  @override
  String get changeAmount => 'Change amount';

  @override
  String get filters => 'Filters';

  @override
  String get previewChanges => 'Preview changes';

  @override
  String get percentage => 'Percentage';

  @override
  String get amount => 'Amount';

  @override
  String get samplePercent => 'e.g. 10%';

  @override
  String get sampleAmount => 'e.g. 1,000,000';

  @override
  String get increase => 'Increase';

  @override
  String get decrease => 'Decrease';

  @override
  String get both => 'Both';

  @override
  String get allCurrencies => 'All currencies';

  @override
  String get priceList => 'Price list';

  @override
  String get allPriceLists => 'All lists';

  @override
  String get itemTypeLabel => 'Item type';

  @override
  String get allTypes => 'All types';

  @override
  String get productsWithInventoryOnly => 'Only products with inventory';

  @override
  String get productsWithInventoryOnlySubtitle =>
      'Only products with inventory control';

  @override
  String get productsWithBasePriceOnly => 'Only products with base price';

  @override
  String get productsWithBasePriceOnlySubtitle =>
      'Only products that have a base price';

  @override
  String get confirmChangesTitle => 'Confirm changes';

  @override
  String confirmApplyChangesForNProducts(Object count) {
    return 'Apply changes to $count products?';
  }

  @override
  String get irreversibleWarning => 'This action is irreversible.';

  @override
  String get summary => 'Summary';

  @override
  String get totalProducts => 'Total products';

  @override
  String get affectedProducts => 'Affected products';

  @override
  String get salesPriceChanges => 'Sales price changes';

  @override
  String get purchasePriceChanges => 'Purchase price changes';

  @override
  String get codeLabel => 'Code';

  @override
  String get salesLabel => 'Sales';

  @override
  String get purchaseLabel => 'Purchase';

  @override
  String get managePriceLists => 'Manage price lists';

  @override
  String get noProductsReadAccess =>
      'You do not have permission to view products & services';

  @override
  String get productId => 'Product ID';

  @override
  String get unit => 'Unit';

  @override
  String get minQty => 'Minimum quantity';

  @override
  String get addPriceTitle => 'Add price';

  @override
  String get editPriceTitle => 'Edit price';

  @override
  String get productDeletedSuccessfully =>
      'Product or service deleted successfully';

  @override
  String get productsDeletedSuccessfully =>
      'Selected items deleted successfully';

  @override
  String get noRowsSelectedError => 'No rows selected';

  @override
  String get deleteSelected => 'Delete Selected';

  @override
  String get deletedSuccessfully => 'Deleted successfully';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get pettyCashManagement => 'Petty Cash Management';

  @override
  String get pettyCashName => 'Petty Cash Name';

  @override
  String get pettyCashCode => 'Petty Cash Code';

  @override
  String get pettyCashDescription => 'Petty Cash Description';

  @override
  String get pettyCashCurrency => 'Currency';

  @override
  String get pettyCashIsActive => 'Active';

  @override
  String get pettyCashIsDefault => 'Default';

  @override
  String get pettyCashCreatedSuccessfully => 'Petty cash created successfully';

  @override
  String get pettyCashUpdatedSuccessfully => 'Petty cash updated successfully';

  @override
  String get pettyCashDeletedSuccessfully => 'Petty cash deleted successfully';

  @override
  String get pettyCashNotFound => 'Petty cash not found';

  @override
  String get pettyCashNameRequired => 'Petty cash name is required';

  @override
  String get duplicatePettyCashCode => 'Duplicate petty cash code';

  @override
  String get invalidPettyCashCode => 'Invalid petty cash code';

  @override
  String get pettyCashBulkDeleted => 'Petty cash items deleted successfully';

  @override
  String get pettyCashListFetched => 'Petty cash list fetched';

  @override
  String get pettyCashDetails => 'Petty cash details';

  @override
  String get pettyCashExportExcel => 'Export petty cash to Excel';

  @override
  String get pettyCashExportPdf => 'Export petty cash to PDF';

  @override
  String get pettyCashReport => 'Petty Cash Report';

  @override
  String get accountTypeBank => 'Bank';

  @override
  String get accountTypeCashRegister => 'Cash Register';

  @override
  String get accountTypePettyCash => 'Petty Cash';

  @override
  String get accountTypeCheck => 'Check';

  @override
  String get accountTypePerson => 'Person';

  @override
  String get accountTypeProduct => 'Product';

  @override
  String get accountTypeService => 'Service';

  @override
  String get accountTypeAccountingDocument => 'Accounting Document';

  @override
  String get printTemplatePublished => 'Print template (Published)';

  @override
  String get noCustomTemplate => '— No custom template —';

  @override
  String get reload => 'Reload';

  @override
  String get presetInvoicesList => 'Invoices/List';

  @override
  String get presetInvoicesDetail => 'Invoices/Detail';

  @override
  String get presetReceiptsPaymentsList => 'ReceiptsPayments/List';

  @override
  String get presetReceiptsPaymentsDetail => 'ReceiptsPayments/Detail';

  @override
  String get presetExpenseIncomeList => 'ExpenseIncome/List';

  @override
  String get presetDocumentsList => 'Documents/List';

  @override
  String get presetDocumentsDetail => 'Documents/Detail';

  @override
  String get presetTransfersList => 'Transfers/List';

  @override
  String get presetTransfersDetail => 'Transfers/Detail';

  @override
  String get presetWarehousePostalLabel => 'Warehouse / postal label';

  @override
  String get reportTemplatesScopeAll => 'All report types';

  @override
  String get reportTemplatesScopeCustom => 'Custom (technical keys)';

  @override
  String get reportTemplateNewVisual => 'New — visual builder';

  @override
  String get reportTemplateNewHtml => 'New — HTML (advanced)';

  @override
  String get reportTemplateMoreMenu => 'More tools';

  @override
  String get reportTemplateExportJson => 'Export JSON…';

  @override
  String get reportTemplateImportJson => 'Import JSON…';

  @override
  String get reportTemplatePickExport => 'Choose a template to export';

  @override
  String get reportTemplateImportDoneOpenHtml =>
      'Form filled. Use \"New — HTML\" to review and save.';

  @override
  String reportTemplatesLoadError(String error) {
    return 'Failed to load templates: $error';
  }

  @override
  String get reportTemplatePreviewTitle => 'Template preview';

  @override
  String get reportTemplatePreviewHtmlTab => 'HTML';

  @override
  String get reportTemplatePreviewPdfTab => 'PDF';

  @override
  String reportTemplatePreviewPdfBytes(String bytes) {
    return 'Generated PDF size: $bytes bytes';
  }

  @override
  String get reportTemplateCopyPlaceholder => 'Copy placeholder';

  @override
  String get reportTemplateCopied => 'Copied to clipboard';

  @override
  String get reportTemplateStatusPublished => 'Published';

  @override
  String get reportTemplateStatusDraft => 'Draft';

  @override
  String get reportTemplateDefaultBadge => 'Default';

  @override
  String get reportTemplateRowActions => 'Actions';

  @override
  String get reportTemplatePublish => 'Publish';

  @override
  String get reportTemplateUnpublish => 'Unpublish';

  @override
  String get reportTemplatePreview => 'Preview';

  @override
  String get reportTemplateEdit => 'Edit';

  @override
  String get reportTemplateSetDefault => 'Set as default';

  @override
  String get reportTemplateDelete => 'Delete';

  @override
  String get reportTemplateExportThis => 'Export JSON';

  @override
  String get reportTemplatesFilterScopeLabel => 'Report scope';

  @override
  String get reportTemplateStatusFilterHint => 'All statuses';

  @override
  String get reportTemplatePlaceholdersTitle => 'Available placeholders';

  @override
  String get reportTemplateVariablesHelpButton => 'Placeholder help';

  @override
  String reportTemplatesSchemaFetchError(String error) {
    return 'Failed to load placeholder schema: $error';
  }

  @override
  String get reportTemplatesEmptyList => 'No templates found';

  @override
  String get reportTemplateDeleteConfirmTitle => 'Delete template';

  @override
  String get reportTemplateDeleteConfirmMessage =>
      'Are you sure you want to delete this template? This cannot be undone.';

  @override
  String get reportTemplateSetDefaultTitle => 'Confirm';

  @override
  String get reportTemplateSetDefaultMessage =>
      'Use this template as the default for its module and subtype?';

  @override
  String reportTemplateEditSaveError(String error) {
    return 'Could not save template: $error';
  }

  @override
  String reportTemplatePreviewError(String error) {
    return 'Preview failed: $error';
  }

  @override
  String reportTemplateInvalidJsonError(String error) {
    return 'Invalid JSON: $error';
  }

  @override
  String get reportTemplatePdfDownloadStarted => 'PDF download started';

  @override
  String reportTemplatePdfSavedToPath(String path) {
    return 'Saved to: $path';
  }

  @override
  String get reportTemplatePdfSavedGeneric => 'File saved';

  @override
  String get reportTemplateDownload => 'Download';

  @override
  String get reportTemplateOpenInNewTab => 'Open in new tab';

  @override
  String get reportTemplatePdfInlineFailedHint =>
      'In-page PDF preview failed; use the HTML tab.';

  @override
  String get reportTemplateBuilderDesignEmpty =>
      'Visual builder design is empty.';

  @override
  String get reportTemplatePaperCustomLabel => 'Custom paper size (optional)';

  @override
  String get reportTemplatePaperCustomHelper =>
      'If set, this replaces the selected paper size (max 32 characters).';

  @override
  String get reportTemplateEditorTabCss => 'CSS';

  @override
  String get reportTemplateEditorTabHeader => 'Header';

  @override
  String get reportTemplateEditorTabFooter => 'Footer';

  @override
  String get reportTemplatePageSettingsSection => 'Page settings';

  @override
  String get reportTemplateFieldName => 'Template name';

  @override
  String get reportTemplateFieldDescription => 'Description';

  @override
  String get reportTemplateModuleKeyLabel => 'module_key';

  @override
  String get reportTemplateSubtypeLabel => 'subtype';

  @override
  String get reportTemplateModuleKeyTooltip => 'API report module identifier.';

  @override
  String get reportTemplateSubtypeTooltip =>
      'API report subtype (e.g. list or detail).';

  @override
  String get reportTemplateHintHtmlBody =>
      'HTML body (Jinja2 placeholders allowed)';

  @override
  String get reportTemplateHintCss => 'Optional CSS';

  @override
  String get reportTemplateHintHeaderHtml => 'Optional header HTML';

  @override
  String get reportTemplateHintFooterHtml => 'Optional footer HTML';

  @override
  String get printPdf => 'Print PDF';

  @override
  String get generating => 'Generating...';

  @override
  String get pdfSuccess => 'PDF generated successfully';

  @override
  String get pdfError => 'Error generating PDF';

  @override
  String get printTemplate => 'Print template';

  @override
  String get templateStandard => 'Standard template';

  @override
  String get templateCompact => 'Compact template';

  @override
  String get templateDetailed => 'Detailed template';

  @override
  String get templateCustom => 'Custom template';

  @override
  String get invoicesListManage => 'Manage invoices list';

  @override
  String get all => 'All';

  @override
  String get invoiceTypeSales => 'Sales';

  @override
  String get invoiceTypePurchase => 'Purchase';

  @override
  String get invoiceTypeSalesReturn => 'Sales return';

  @override
  String get invoiceTypePurchaseReturn => 'Purchase return';

  @override
  String get invoiceTypeProduction => 'Production';

  @override
  String get invoiceTypeDirectConsumption => 'Direct consumption';

  @override
  String get invoiceTypeWaste => 'Waste';

  @override
  String get documentDate => 'Document date';

  @override
  String get totalAmount => 'Total amount';

  @override
  String get invoicePaidAmount => 'Invoice paid amount';

  @override
  String get invoiceRemainingAmount => 'Invoice remaining amount';

  @override
  String get unknown => 'Unknown';

  @override
  String get noInvoicesFound => 'No invoices found';

  @override
  String get loadingInvoices => 'Loading invoices...';

  @override
  String get errorLoadingInvoices => 'Error loading invoices';

  @override
  String get proforma => 'Proforma';

  @override
  String get finalized => 'Finalized';

  @override
  String get clearDateFilter => 'Clear date filter';

  @override
  String get deleteConfirmTitle => 'Confirm delete';

  @override
  String deleteInvoiceConfirm(String code) {
    return 'Are you sure you want to delete invoice $code? This action is irreversible.';
  }

  @override
  String deletedInvoiceSuccess(String code) {
    return 'Invoice $code deleted successfully';
  }

  @override
  String get deleteInvoiceError => 'Failed to delete invoice';

  @override
  String deleteInvoiceErrorWithMessage(String error) {
    return 'Failed to delete invoice: $error';
  }

  @override
  String get deleteInvoiceTaxWorkspaceError =>
      'This invoice is in the tax workspace and cannot be deleted';

  @override
  String get deleteInvoiceReceiptPaymentsWarning =>
      'Related receipt/payment documents:';

  @override
  String get deleteInvoiceWarehouseWarning =>
      'Related finalized warehouse documents:';

  @override
  String deleteInvoiceInstallmentsWarning(String count) {
    return 'This invoice has $count installments that will be deleted';
  }

  @override
  String get saveInvoice => 'Save invoice';

  @override
  String get invoiceInfoTab => 'Invoice info';

  @override
  String get productsServicesTab => 'Products & services';

  @override
  String get transactionsTab => 'Transactions';

  @override
  String get settingsTab => 'Settings';

  @override
  String get invoiceCreatedSuccess => 'Invoice created successfully';

  @override
  String saveInvoiceErrorWithMessage(String error) {
    return 'Failed to save invoice: $error';
  }

  @override
  String get noRowsAdded => 'No rows added';

  @override
  String get quantityUnit => 'Quantity/Unit';

  @override
  String get unitPrice => 'Unit price';

  @override
  String get installmentsTitle => 'Installment sale';

  @override
  String get installmentsSubtitle =>
      'If enabled, an installment plan will be saved with the invoice';

  @override
  String get installmentsSettingsSubtitle =>
      'Manage installment plans and sales conditions';

  @override
  String get installmentsCount => 'Number of installments';

  @override
  String get downPayment => 'Down payment';

  @override
  String get interestRatePercent => 'Total period interest (%)';

  @override
  String get installmentsPeriod => 'Installment period';

  @override
  String get installmentsMonthly => 'Monthly (30 days)';

  @override
  String get installmentsDaysBased => 'By days';

  @override
  String get installmentDaysLength => 'Length of each installment (days)';

  @override
  String get firstInstallmentDueDate => 'First due date';

  @override
  String get invalidInstallmentsCount => 'Invalid number of installments';

  @override
  String get unitPricePickHint =>
      'Unit price (pick from list or enter manually)';

  @override
  String get lineTotalAmount => 'Line total amount';

  @override
  String get lineDescription => 'Line description';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get discountTypeAndValue => 'Discount (type and value)';

  @override
  String get taxPercentAndAmount => 'Tax (percent and amount)';

  @override
  String get selectUnitTitle => 'Select unit';

  @override
  String get mainUnitLabel => 'Main unit';

  @override
  String get secondaryUnitLabel => 'Secondary unit';

  @override
  String get noUnitsDefined => 'No units defined for this product';

  @override
  String get discountType => 'Discount type';

  @override
  String get percent => 'Percent';

  @override
  String get pricePickFromList => 'Pick from price list';

  @override
  String get noPricesFound => 'No prices to show';

  @override
  String get baseEstimatedPrice => 'Estimated base price';

  @override
  String get priceListLabel => 'Price list';

  @override
  String get kardexDocuments => 'Kardex documents';

  @override
  String get documentCode => 'Document code';

  @override
  String get documentType => 'Document type';

  @override
  String get movementDirection => 'Movement';

  @override
  String get movementIn => 'Incoming';

  @override
  String get movementOut => 'Outgoing';

  @override
  String get debit => 'Debit';

  @override
  String get credit => 'Credit';

  @override
  String get quantity => 'Quantity';

  @override
  String get runningAmount => 'Running amount';

  @override
  String get runningQuantity => 'Running quantity';

  @override
  String get viewDocument => 'View document';

  @override
  String get totalsDebit => 'Total debit';

  @override
  String get totalsCredit => 'Total credit';

  @override
  String get totalsQuantity => 'Total quantity';

  @override
  String get totalsRunningAmount => 'Running amount';

  @override
  String get totalsRunningQuantity => 'Running quantity';

  @override
  String get addFilter => 'Add filter';

  @override
  String get presetsTitle => 'Presets';

  @override
  String get applyPreset => 'Apply preset';

  @override
  String get deleteSelectedPreset => 'Delete selected preset';

  @override
  String get savePreset => 'Save preset';

  @override
  String get savePresetTitle => 'Save preset';

  @override
  String get presetNameHint => 'Enter preset name';

  @override
  String get presetSaved => 'Preset saved';

  @override
  String presetSaveError(String error) {
    return 'Error saving preset: $error';
  }

  @override
  String presetDeleteError(String error) {
    return 'Error deleting preset: $error';
  }

  @override
  String presetApplyError(String error) {
    return 'Error applying preset: $error';
  }

  @override
  String get fiscalYear => 'Fiscal year';

  @override
  String get fiscalYears => 'Fiscal years';

  @override
  String get addFilterPersons => 'Add filter: People';

  @override
  String get addFilterProduct => 'Add filter: Product/Service';

  @override
  String get addFilterBank => 'Add filter: Bank';

  @override
  String get addFilterCash => 'Add filter: Cash register';

  @override
  String get addFilterPetty => 'Add filter: Petty cash';

  @override
  String get addFilterAccount => 'Add filter: Ledger account';

  @override
  String get addFilterCheck => 'Add filter: Check';

  @override
  String get matchModeAny => 'Any';

  @override
  String get matchModeSameLine => 'Same line';

  @override
  String get matchModeDocumentAnd => 'Same document';

  @override
  String get resultScopeLinesMatching => 'Only matching lines';

  @override
  String get resultScopeLinesOfDocument => 'All lines of document';

  @override
  String get includeRunningBalance => 'Include running balance';

  @override
  String get applyManually => 'Apply manually';

  @override
  String get ledgerAccount => 'Account';

  @override
  String get reportsGeneralSection => 'General reports';

  @override
  String get reportsPeopleSection => 'People reports';

  @override
  String get reportsProductsSection => 'Products & services reports';

  @override
  String get reportsBankingSection => 'Banking & cash reports';

  @override
  String get reportsSalesSection => 'Sales reports';

  @override
  String get reportsPurchasesSection => 'Purchase reports';

  @override
  String get reportsProductionSection => 'Production reports';

  @override
  String get reportsBasicAccountingSection => 'Basic accounting';

  @override
  String get reportsProfitLossSection => 'Profit & loss';

  @override
  String get reportsKardexSubtitle =>
      'Detailed transactions by person/product/bank/account/check with date filters';

  @override
  String get reportsDebtorsTitle => 'Debtors list';

  @override
  String get reportsDebtorsSubtitle => 'People with debit balances';

  @override
  String get reportsCreditorsTitle => 'Creditors list';

  @override
  String get reportsCreditorsSubtitle => 'People with credit balances';

  @override
  String get reportsPeopleTransactionsTitle => 'People transactions';

  @override
  String get reportsPeopleTransactionsSubtitle =>
      'Detailed receipts and payments by person';

  @override
  String get reportsItemMovementsTitle => 'Item movements';

  @override
  String get reportsItemMovementsSubtitle =>
      'In, out and balance over a period';

  @override
  String get reportsInventoryKardexTitle => 'Inventory kardex';

  @override
  String get reportsInventoryKardexSubtitle =>
      'Per-item movement details (FIFO/LIFO/average)';

  @override
  String get reportsInventoryStockTitle => 'Inventory stock report';

  @override
  String get reportsInventoryStockSubtitle =>
      'Product inventory by warehouse and date';

  @override
  String get reportsSalesByProductTitle => 'Sales by product';

  @override
  String get reportsSalesByProductSubtitle =>
      'Performance of each product in time range';

  @override
  String get reportsBankAccountsTurnoverTitle => 'Bank accounts turnover';

  @override
  String get reportsBankAccountsTurnoverSubtitle =>
      'Withdrawals and deposits by account';

  @override
  String get reportsCashPettyTurnoverTitle => 'Cash and petty cash turnover';

  @override
  String get reportsCashPettyTurnoverSubtitle => 'Detailed cash in/out';

  @override
  String get reportsChecksTitle => 'Checks';

  @override
  String get reportsChecksSubtitle =>
      'Receivable, payable, due dates and statuses';

  @override
  String get reportsDailySalesTitle => 'Daily sales';

  @override
  String get reportsDailySalesSubtitle => 'Daily sales performance and trends';

  @override
  String get reportsMonthlySalesTitle => 'Monthly sales';

  @override
  String get reportsMonthlySalesSubtitle =>
      'Monthly comparison and sales growth';

  @override
  String get reportsTopCustomersTitle => 'Top customers';

  @override
  String get reportsTopCustomersSubtitle => 'Ranking by amount or count';

  @override
  String get reportsDailyPurchasesTitle => 'Daily purchases';

  @override
  String get reportsDailyPurchasesSubtitle =>
      'Daily purchase performance and trends';

  @override
  String get reportsTopSuppliersTitle => 'Top suppliers';

  @override
  String get reportsTopSuppliersSubtitle => 'Suppliers ranked by purchases';

  @override
  String get reportsMaterialsConsumptionTitle => 'Materials consumption';

  @override
  String get reportsMaterialsConsumptionSubtitle =>
      'Raw material consumption per product';

  @override
  String get reportsProductionTitle => 'Production report';

  @override
  String get reportsProductionSubtitle => 'Production volume and waste';

  @override
  String get reportsTrialBalanceTitle => 'Trial balance';

  @override
  String get reportsTrialBalanceSubtitle => '2/4/6/8-column balance';

  @override
  String get reportsGeneralLedgerTitle => 'General ledger';

  @override
  String get reportsGeneralLedgerSubtitle => 'Account movements over a period';

  @override
  String get reportsJournalLedgerTitle => 'Journal Ledger';

  @override
  String get reportsJournalLedgerSubtitle =>
      'All financial transactions in chronological order';

  @override
  String get debitAccount => 'Debit Account';

  @override
  String get creditAccount => 'Credit Account';

  @override
  String get reportsPnlPeriodTitle => 'Period profit and loss';

  @override
  String get reportsPnlPeriodSubtitle =>
      'Revenue, expenses, and net profit/loss';

  @override
  String get reportsPnlCumulativeTitle => 'Cumulative profit and loss';

  @override
  String get reportsAccountsReviewTitle => 'Accounts review report';

  @override
  String get reportsAccountsReviewSubtitle =>
      'Account tree structure with balances and transaction details';

  @override
  String get reportsPnlCumulativeSubtitle =>
      'Periodical comparison and cumulative view';

  @override
  String get reportsComingSoonMessage => 'This report will be available soon.';

  @override
  String get reportsSearchHint => 'Search reports…';

  @override
  String reportsSearchResults(Object count) {
    return 'Results ($count)';
  }

  @override
  String get reportsSearchNoResults => 'No reports matched your search.';

  @override
  String get reportsFavoritesTitle => 'Favorites';

  @override
  String get reportsFavoritesEmptyMessage =>
      'For quick access, tap the star next to a report.';

  @override
  String get reportsRecentTitle => 'Recently used';

  @override
  String get reportsRecentEmptyMessage => 'Reports you open will show up here.';

  @override
  String get reportsWarehouseSection => 'Warehouse reports';

  @override
  String get reportsSystemSection => 'System reports';

  @override
  String get reportsActivityLogsTitle => 'User activity logs';

  @override
  String get reportsActivityLogsSubtitle =>
      'View the history of user activity in the system';

  @override
  String reportsSectionCount(Object count) {
    return '$count reports';
  }

  @override
  String get reportsAddToFavorites => 'Add to favorites';

  @override
  String get reportsRemoveFromFavorites => 'Remove from favorites';

  @override
  String get reportsInstallmentsSubtitle =>
      'Installment status, due dates, and remaining balance';

  @override
  String get reportsStockCountTitle => 'Stock count report';

  @override
  String get reportsStockCountSubtitle =>
      'Stock count history and adjustment documents';

  @override
  String get reportsWarehouseDocumentsSummaryTitle =>
      'Warehouse documents summary';

  @override
  String get reportsWarehouseDocumentsSummarySubtitle =>
      'Summary by document type with inbound/outbound stats';

  @override
  String get reportsSlowMovingItemsTitle => 'Slow-moving items';

  @override
  String get reportsSlowMovingItemsSubtitle =>
      'Items with no movement during the selected time range';

  @override
  String get reportsCriticalStockTitle => 'Critical stock items';

  @override
  String get reportsCriticalStockSubtitle =>
      'Items with stock below the defined threshold';

  @override
  String get reportsInterWarehouseTransfersTitle => 'Inter-warehouse transfers';

  @override
  String get reportsInterWarehouseTransfersSubtitle =>
      'Details of transfers between warehouses';

  @override
  String get reportsAdjustmentDocumentsTitle => 'Adjustment documents';

  @override
  String get reportsAdjustmentDocumentsSubtitle =>
      'Analysis of adjustment documents and inventory differences';

  @override
  String get reportsWarehousePerformanceTitle => 'Warehouse performance';

  @override
  String get reportsWarehousePerformanceSubtitle =>
      'Compare warehouse performance';

  @override
  String get reportsProductMovementHistoryTitle => 'Product movement history';

  @override
  String get reportsProductMovementHistorySubtitle =>
      'Full movement history of a product across all warehouses';

  @override
  String get reportsInventoryValuationTitle => 'Inventory valuation';

  @override
  String get reportsInventoryValuationSubtitle =>
      'Monetary valuation of warehouse inventories';

  @override
  String get reportsPendingDocumentsTitle => 'Pending documents';

  @override
  String get reportsPendingDocumentsSubtitle =>
      'Draft or pending-approval documents';

  @override
  String get reportsInventoryTurnoverTitle => 'Inventory turnover';

  @override
  String get reportsInventoryTurnoverSubtitle =>
      'Inventory turnover rate for products';

  @override
  String get reportsSortTooltip => 'Sort';

  @override
  String get reportsSortDefault => 'Default';

  @override
  String get reportsSortAlphabetical => 'Alphabetical';

  @override
  String get operationSuccessful => 'Operation successful';

  @override
  String get notificationsSettingsTitle => 'Notification Settings';

  @override
  String get notificationsSettingsSubtitle =>
      'Enable delivery channels, send test messages, and manage service credentials.';

  @override
  String get notificationsChannelsSectionTitle => 'Delivery channels';

  @override
  String get notificationsChannelsSectionSubtitle =>
      'Any enabled channel may be used for system notifications and operational alerts.';

  @override
  String get notificationsChannelTelegram => 'Telegram';

  @override
  String get notificationsChannelTelegramDescription =>
      'Send messages through a connected Telegram bot for operators.';

  @override
  String get notificationsChannelBale => 'Bale';

  @override
  String get notificationsChannelBaleDescription =>
      'Send messages through Bale messenger (connected bot).';

  @override
  String get notificationsBaleAdvancedTitle => 'Bale advanced settings';

  @override
  String get notificationsBaleAdvancedSubtitle =>
      'Configure Bale bot for notifications';

  @override
  String get notificationsFieldBaleToken => 'Bale bot token';

  @override
  String get notificationsFieldBaleTokenHint =>
      'Bot token from @BotFather in Bale';

  @override
  String get notificationsFieldBaleUsername => 'Bale bot username';

  @override
  String get notificationsFieldBaleWebhookSecret => 'Bale webhook secret';

  @override
  String get notificationsBaleConnected => 'Connected';

  @override
  String get notificationsBaleNotConnected => 'Not connected';

  @override
  String get notificationsBaleConnectButton => 'Connect Bale';

  @override
  String get notificationsBaleDisconnectButton => 'Disconnect Bale';

  @override
  String get notificationsBaleConnecting => 'Connecting...';

  @override
  String get notificationsBaleConnectionWarning =>
      'To enable Bale notifications, please connect first.';

  @override
  String notificationsBaleLinkInstructions(String token) {
    return 'Click the link below or open the bot in Bale and send /start $token.';
  }

  @override
  String get notificationsBaleLinkExpired =>
      'Connection link expired. Please create a new link.';

  @override
  String notificationsBaleConnectedSince(String date) {
    return 'Connected since $date';
  }

  @override
  String get notificationsBaleConnectionSuccess =>
      'Bale connected successfully.';

  @override
  String get notificationsBaleConnectionError => 'Error connecting Bale.';

  @override
  String get notificationsBaleDisconnectSuccess => 'Bale disconnected.';

  @override
  String get notificationsBaleDisconnectError => 'Error disconnecting Bale.';

  @override
  String get notificationsChannelEmail => 'Email';

  @override
  String get notificationsChannelEmailDescription =>
      'Send emails using the server configured in system settings.';

  @override
  String get notificationsChannelSms => 'SMS';

  @override
  String get notificationsChannelSmsDescription =>
      'Send SMS via your configured provider for sensitive events.';

  @override
  String get notificationsChannelInApp => 'In-app';

  @override
  String get notificationsChannelInAppDescription =>
      'Display notifications inside Hesabix web and mobile in real time.';

  @override
  String get notificationsSaveSuccess => 'Notification settings saved.';

  @override
  String get notificationsSaveError => 'Failed to save notification settings.';

  @override
  String get notificationsTestSectionTitle => 'Send test message';

  @override
  String get notificationsTestSectionSubtitle =>
      'After any change, use the selected channel to send a test.';

  @override
  String notificationsTestButton(String channel) {
    return 'Test $channel';
  }

  @override
  String notificationsTestSuccess(String channel) {
    return 'Test message sent via $channel.';
  }

  @override
  String notificationsTestError(String channel) {
    return 'Failed to send test message via $channel.';
  }

  @override
  String get notificationsWebsocketInfoTitle => 'Realtime in-app notifications';

  @override
  String notificationsWebsocketInfoDescription(String endpoint) {
    return 'Users connect with a valid API key to the websocket endpoint $endpoint. Web and mobile apps establish this connection automatically.';
  }

  @override
  String get notificationsAdvancedSectionTitle =>
      'Advanced configuration (admin)';

  @override
  String get notificationsAdvancedSectionSubtitle =>
      'Manage Telegram and SMS validation here. Requires system_settings access.';

  @override
  String get notificationsAdvancedTelegramHeader => 'Telegram bot setup';

  @override
  String get notificationsFieldTelegramToken => 'Bot token';

  @override
  String get notificationsFieldTelegramUsername => 'Bot username';

  @override
  String get notificationsFieldTelegramWebhookSecret => 'Webhook secret';

  @override
  String get notificationsFieldTelegramSecretHeader => 'Secret header name';

  @override
  String get notificationsFieldTelegramTokenHint =>
      'Issued by BotFather (format: 123456789:ABC...).';

  @override
  String get notificationsFieldTelegramWebhookSecretHint =>
      'Optional; used to validate incoming requests.';

  @override
  String get notificationsAdvancedSmsHeader => 'SMS gateway';

  @override
  String get notificationsFieldSmsProvider => 'Provider name';

  @override
  String get notificationsFieldSmsApiKey => 'API key';

  @override
  String get notificationsFieldSmsApiKeyHint =>
      'Provided by your SMS vendor; rotate periodically.';

  @override
  String get notificationsFieldSmsSender => 'Sender/Number';

  @override
  String get notificationsFieldSmsSenderHint =>
      'Exactly as registered in your vendor panel.';

  @override
  String get notificationsProxySectionTitle => 'Telegram proxy';

  @override
  String get notificationsProxySectionSubtitle =>
      'When servers are hosted inside Iran, enable the proxy to route Telegram traffic through an external relay.';

  @override
  String get notificationsProxyEnableLabel => 'Enable Telegram proxy';

  @override
  String get notificationsFieldTelegramProxyBaseUrl => 'Proxy base URL';

  @override
  String get notificationsFieldTelegramProxyApiKey => 'Proxy access key';

  @override
  String get notificationsAdvancedRestartHint =>
      'After changes, restart the notification service during low traffic if needed.';

  @override
  String get notificationsAdvancedSave => 'Save advanced settings';

  @override
  String get notificationsAdvancedSaveSuccess =>
      'Advanced notification settings saved.';

  @override
  String get notificationsAdvancedSaveError =>
      'Failed to save advanced notification settings.';

  @override
  String get notificationsTelegramConnectionStatus => 'Connection status';

  @override
  String get notificationsTelegramConnected => 'Connected';

  @override
  String get notificationsTelegramNotConnected => 'Not connected';

  @override
  String get notificationsTelegramConnectButton => 'Connect Telegram';

  @override
  String get notificationsTelegramDisconnectButton => 'Disconnect';

  @override
  String get notificationsTelegramConnecting => 'Connecting...';

  @override
  String get notificationsTelegramConnectionWarning =>
      'To enable Telegram notifications, please connect first.';

  @override
  String get notificationsTelegramConnectionSuccess =>
      'Telegram connection established successfully.';

  @override
  String get notificationsTelegramConnectionError =>
      'Failed to connect Telegram.';

  @override
  String get notificationsTelegramDisconnectSuccess =>
      'Telegram connection disconnected.';

  @override
  String get notificationsTelegramDisconnectError =>
      'Failed to disconnect Telegram.';

  @override
  String get notificationsTelegramLinkExpired =>
      'Connection link expired. Please create a new link.';

  @override
  String notificationsTelegramLinkInstructions(String token) {
    return 'Click the link below or open the bot in Telegram and send /start $token.';
  }

  @override
  String notificationsTelegramLinkExpiresIn(int minutes) {
    final intl.NumberFormat minutesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String minutesString = minutesNumberFormat.format(minutes);

    return 'This link expires in $minutesString minutes.';
  }

  @override
  String notificationsTelegramConnectedSince(String date) {
    return 'Connected since $date';
  }

  @override
  String get templateBuilderNew => 'Visual Builder (New)';

  @override
  String get templateBuilderEdit => 'Visual Builder (Edit)';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get header => 'Header';

  @override
  String get body => 'Body';

  @override
  String get footer => 'Footer';

  @override
  String get globalCssOptional => 'Global CSS (optional)';

  @override
  String get previewPdf => 'Preview PDF';

  @override
  String get previewHtmlOutput => 'Preview HTML (render output)';

  @override
  String get empty => '(empty)';

  @override
  String get createTemplateBuilder => 'Create template (Builder)';

  @override
  String get saveChanges => 'Save changes';

  @override
  String createdWithId(int id) {
    return 'Created (ID: $id)';
  }

  @override
  String previewError(String error) {
    return 'Preview error: $error';
  }

  @override
  String createError(String error) {
    return 'Create error: $error';
  }

  @override
  String templateCreatedWithId(int id) {
    return 'Template created (ID: $id)';
  }

  @override
  String get addText => 'Add text';

  @override
  String get divider => 'Divider';

  @override
  String get spacer => 'Spacer';

  @override
  String get addImage => 'Add image';

  @override
  String get addQr => 'Add QR';

  @override
  String get partyInfo => 'Party info';

  @override
  String get addTotals => 'Add totals';

  @override
  String get stampSignature => 'Stamp/Signature';

  @override
  String get watermark => 'Watermark';

  @override
  String get addTable => 'Add table';

  @override
  String get textWithVariable => 'Text (variable)';

  @override
  String get alignment => 'Alignment';

  @override
  String get left => 'Left';

  @override
  String get center => 'Center';

  @override
  String get right => 'Right';

  @override
  String get showIfCondition => 'Show if (condition)';

  @override
  String blockType(String type) {
    return 'Block $type';
  }

  @override
  String get pageSize => 'Page size';

  @override
  String get orientation => 'Orientation';

  @override
  String get portrait => 'Portrait';

  @override
  String get landscape => 'Landscape';

  @override
  String get marginTop => 'Top margin (mm)';

  @override
  String get marginRight => 'Right (mm)';

  @override
  String get marginBottom => 'Bottom (mm)';

  @override
  String get marginLeft => 'Left (mm)';

  @override
  String get create => 'Create';

  @override
  String get walletBusinessTitle => 'Business wallet';

  @override
  String get walletAvailableBalance => 'Available balance';

  @override
  String get walletPendingBalance => 'Pending balance';

  @override
  String get walletRequestPayout => 'Request payout';

  @override
  String get walletTopUp => 'Top up';

  @override
  String get walletLast30Days => 'Last 30 days report';

  @override
  String get walletGrossIn => 'Gross in';

  @override
  String get walletFeesIn => 'Fees in';

  @override
  String get walletNetIn => 'Net in';

  @override
  String get walletGrossOut => 'Gross out';

  @override
  String get walletFeesOut => 'Fees out';

  @override
  String get walletNetOut => 'Net out';

  @override
  String get walletRecentTransactions => 'Recent transactions';

  @override
  String get walletTransactions => 'Transactions';

  @override
  String get moneyAmount => 'Amount';

  @override
  String get feeAmount => 'Fee';

  @override
  String get document => 'Document';

  @override
  String get walletTypeTopUp => 'Top up';

  @override
  String get walletTypeCustomerPayment => 'Customer payment';

  @override
  String get walletTypePayoutRequest => 'Payout request';

  @override
  String get walletTypePayoutSettlement => 'Payout settlement';

  @override
  String get walletTypeRefund => 'Refund';

  @override
  String get walletTypeFee => 'Fee';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusProcessing => 'Processing';

  @override
  String get statusSucceeded => 'Succeeded';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusCanceled => 'Canceled';

  @override
  String get walletPayoutRequestTitle => 'Payout request';

  @override
  String get walletSelectBankAccountHint => 'Select bank account';

  @override
  String get walletPaymentGateway => 'Payment gateway';

  @override
  String get walletPayoutRequested => 'Payout request submitted';

  @override
  String get settingsWalletPayoutsAdmin => 'Wallet payout management';

  @override
  String get settingsWalletPayoutsAdminDescription =>
      'Review wallet payout requests and record bank settlement details';

  @override
  String get walletPayoutsAdminTitle => 'Wallet payout requests';

  @override
  String get walletPayoutsAdminSubtitle =>
      'Monitor pending payout requests, review bank account details, and register settlement information after transfers are completed.';

  @override
  String get walletPayoutsAdminEmpty => 'No payout requests to show.';

  @override
  String get walletPayoutsAdminSettleDialogTitle =>
      'Record settlement information';

  @override
  String get walletPayoutsAdminSettleAction => 'Record & settle';

  @override
  String get walletPayoutsAdminSuccess =>
      'Settlement information saved successfully.';

  @override
  String get walletPayoutsAdminFormRequired => 'This field is required';

  @override
  String get walletPayoutsAdminSettlementDate => 'Settlement date';

  @override
  String get walletPayoutsAdminFeeHint =>
      'If the bank charged a fee, enter the amount here';

  @override
  String get bankTrackingCode => 'Bank tracking code';

  @override
  String get walletTopUpTitle => 'Top up';

  @override
  String get walletTopUpInitializing =>
      'Submitting request and preparing payment gateway...';

  @override
  String get walletRedirectingToGateway => 'Redirecting to payment gateway...';

  @override
  String get walletTopUpNoPaymentLink =>
      'Top-up request submitted, but no payment link received. Please try again later or check gateway settings.';

  @override
  String get walletGatewayInitFailed =>
      'Error connecting to gateway. Please check settings or try again later.';

  @override
  String get walletInvalidGatewayConfig =>
      'Gateway configuration is incomplete. Please check merchant ID and callback URL.';

  @override
  String get walletGatewayDisabled => 'This gateway is disabled.';

  @override
  String get walletGatewayNotFound => 'Payment gateway not found.';

  @override
  String get walletGatewayServerError =>
      'Server error connecting to gateway. Please try again later.';

  @override
  String get walletOpenGatewayDialogTitle => 'Redirect to payment gateway';

  @override
  String get walletOpenGatewayDialogInstructions =>
      'To continue, open the link below:';

  @override
  String get walletPaymentResultTitle => 'Wallet payment result';

  @override
  String get walletPaymentSuccess => 'Payment completed successfully';

  @override
  String get walletPaymentFailed => 'Payment failed';

  @override
  String get transactionId => 'Transaction ID';

  @override
  String get paymentReference => 'Payment reference';

  @override
  String get walletStatusCheckErrorPrefix => 'Error checking status:';

  @override
  String get walletBackToWallet => 'Back to wallet';

  @override
  String get walletSettingsTitle => 'Wallet settings';

  @override
  String get walletBaseCurrency => 'Wallet base currency';

  @override
  String get walletCurrencyRequired => 'Currency selection is required';

  @override
  String get saved => 'Saved';

  @override
  String get savedSuccessfully => 'Saved successfully';

  @override
  String get currencyToman => 'Toman';

  @override
  String get creditSettingsTitle => 'Customer credit';

  @override
  String get creditSettingsSubtitle =>
      'Configure credit limits and delay policies';

  @override
  String get creditEnableTitle => 'Enable credit';

  @override
  String get creditEnableSubtitle => 'Check customer credit limit during sales';

  @override
  String get creditDefaultLimit => 'Default credit limit';

  @override
  String get creditGraceDays => 'Grace period (days)';

  @override
  String get creditLateFeeRatePercent => 'Late fee (%)';

  @override
  String get creditAutoBlockAfterDays => 'Auto block after (days)';

  @override
  String get creditStrategy => 'Strategy';

  @override
  String get creditStrategySingleDefault => 'Single default limit';

  @override
  String get creditStrategyByGroup => 'By group/role';

  @override
  String get creditStrategyPerUser => 'Per-user limit';

  @override
  String get installmentPlansTitle => 'Installment plans';

  @override
  String get newInstallmentPlan => 'New plan';

  @override
  String get editPlan => 'Edit';

  @override
  String get deletePlan => 'Delete';

  @override
  String deletePlanConfirm(String name) {
    return 'Delete plan \"$name\"?';
  }

  @override
  String get installmentPlanCreateTitle => 'New installment plan';

  @override
  String get installmentPlanEditTitle => 'Edit installment plan';

  @override
  String get planName => 'Plan name';

  @override
  String get planMethod => 'Calculation method';

  @override
  String get planMethodFlat => 'Flat';

  @override
  String get planMethodAmortized => 'Amortized';

  @override
  String get planNumInstallments => 'Number of installments';

  @override
  String get planPeriodDays => 'Interval (days)';

  @override
  String get planDownPaymentPercent => 'Down payment (%)';

  @override
  String get planInterestRate => 'Total interest (%)';

  @override
  String get planLateFeeRate => 'Late fee (%)';

  @override
  String get planIssueFee => 'Issue fee (toman)';

  @override
  String get planIsActive => 'Active';

  @override
  String get creditTabTitle => 'Credit';

  @override
  String get creditPersonPolicyTitle => 'Person credit policy';

  @override
  String get creditCheckModeLabel => 'Credit check mode';

  @override
  String get creditCheckModeInherit => 'Inherit from business settings';

  @override
  String get creditCheckModeEnabled => 'Credit check enabled';

  @override
  String get creditCheckModeDisabled => 'Credit check disabled';

  @override
  String get creditLimitLabel => 'Custom credit limit';

  @override
  String get creditLimitHint => 'Leave empty to use business default';

  @override
  String get creditTipText =>
      'Leaving empty or choosing inherit uses the business default credit settings.';

  @override
  String get selectInstallmentPlan => 'Select installment plan';

  @override
  String get applyPlan => 'Apply plan';

  @override
  String get taxWorkspaceMenu => 'Tax workspace';

  @override
  String get taxWorkspaceTitle => 'Tax workspace';

  @override
  String get taxWorkspaceSubtitle =>
      'Review invoices before sending them to the tax system.';

  @override
  String get taxIntegrationTitle => 'Tax system integration';

  @override
  String get taxIntegrationSubtitle =>
      'Manage credentials and keys required to connect to the national tax platform.';

  @override
  String get taxSettingsTabConnection => 'Connection & basics';

  @override
  String get taxSettingsTabKeys => 'Keys & certificates';

  @override
  String get taxSettingsTabDataQuality => 'Data quality';

  @override
  String get taxSettingsTabGuide => 'Guide';

  @override
  String get taxGuideIntroTitle => 'How to complete the Tax System setup?';

  @override
  String get taxGuideIntroDescription =>
      'This guide walks through the entire integration flow with the Iranian Taxpayers System in the new Hesabix version—from key generation to data quality checks and invoice submission.';

  @override
  String get taxGuidePrereqTitle => 'Prerequisites before you begin';

  @override
  String get taxGuidePrereqItem1 =>
      'Access to the “Tax System” menu as a business admin';

  @override
  String get taxGuidePrereqItem2 =>
      'Accurate registration data (national ID, economic code, corporate email)';

  @override
  String get taxGuidePrereqItem3 =>
      'Active access to your taxpayer workspace on my.tax.gov.ir';

  @override
  String get taxGuideStep1Title => '1) Generate keys inside Hesabix';

  @override
  String get taxGuideStep1Description =>
      'Use the “Generate new keys” card to create the private/public key pair and CSR.';

  @override
  String get taxGuideStep1Bullet1 =>
      'Open the Keys & Certificates tab and tap the generate button.';

  @override
  String get taxGuideStep1Bullet2 =>
      'Provide the exact taxpayer type and national ID.';

  @override
  String get taxGuideStep1Bullet3 =>
      'Persian/English names and email must match the tax records.';

  @override
  String get taxGuideStep2Title => '2) Download and store securely';

  @override
  String get taxGuideStep2Description =>
      'Keys are shown only once; store them safely.';

  @override
  String get taxGuideStep2Bullet1 =>
      'Download the key files and keep them in offline, encrypted storage.';

  @override
  String get taxGuideStep2Bullet2 =>
      'Never share the private key outside the tax integration team.';

  @override
  String get taxGuideStep2Bullet3 =>
      'If the private key is lost you must regenerate the entire pair.';

  @override
  String get taxGuideStep3Title =>
      '3) Register the public key on my.tax.gov.ir';

  @override
  String get taxGuideStep3Description =>
      'You must upload the Public Key to obtain the tax memory ID.';

  @override
  String get taxGuideStep3Bullet1 =>
      'Log into my.tax.gov.ir and navigate to Case Access > Enrollment > Tax Memory ID.';

  @override
  String get taxGuideStep3Bullet2 =>
      'Select “By taxpayer” and upload the generated Public Key file.';

  @override
  String get taxGuideStep3Bullet3 =>
      'Copy the issued memory ID and paste it back into Hesabix.';

  @override
  String get taxGuideStep4Title => '4) Complete the connection form in Hesabix';

  @override
  String get taxGuideStep4Description =>
      'Tax memory ID, economic code and private key are mandatory under the Connection tab.';

  @override
  String get taxGuideStep4Bullet1 =>
      'Enter the ID and economic code without extra spaces.';

  @override
  String get taxGuideStep4Bullet2 =>
      'Paste the PEM private key and optionally store the Public Key and CSR.';

  @override
  String get taxGuideStep4Bullet3 =>
      'Enable sandbox mode only for staging/testing environments.';

  @override
  String get taxGuideStep5Title =>
      '5) Request the intermediate certificate via CSR';

  @override
  String get taxGuideStep5Description =>
      'Legal entities must submit the CSR to the national certificate authority.';

  @override
  String get taxGuideStep5Bullet1 =>
      'Visit gica.ir and choose the CSR-based request option.';

  @override
  String get taxGuideStep5Bullet2 =>
      'Fill in the company details and pay the issuance fee.';

  @override
  String get taxGuideStep5Bullet3 =>
      'After in-person verification upload the issued certificate into Hesabix.';

  @override
  String get taxGuideStep6Title => '6) Assign product/service tax codes';

  @override
  String get taxGuideStep6Description =>
      'Invoices will be rejected if items lack tax code and unit.';

  @override
  String get taxGuideStep6Bullet1 =>
      'Edit each item under Products & Services and add the 13-digit tax code.';

  @override
  String get taxGuideStep6Bullet2 =>
      'Use the public code list from stuffid.tax.gov.ir or request dedicated codes.';

  @override
  String get taxGuideStep6Bullet3 =>
      'Service codes can be obtained from portal.gs1-ir.org.';

  @override
  String get taxGuideStep7Title =>
      '7) Run data quality checks before submission';

  @override
  String get taxGuideStep7Description =>
      'Review the Data Quality tab and the tax workspace before sending invoices.';

  @override
  String get taxGuideStep7Bullet1 =>
      'The Data Quality tab highlights missing fields for products, customers and invoices.';

  @override
  String get taxGuideStep7Bullet2 =>
      'Add invoices to the tax workspace first and fix validation errors inline.';

  @override
  String get taxGuideStep7Bullet3 =>
      'Send single or bulk invoices only after the checklist is green.';

  @override
  String get taxGuideResourcesTitle => 'Shortcuts and resources';

  @override
  String get taxGuideResourcesWorkspace =>
      'Tax workspace: available under Sales > Tax Workspace.';

  @override
  String get taxGuideResourcesProducts =>
      'Products & Services: update tax codes via the same menu or Excel import.';

  @override
  String get taxGuideResourcesSupport =>
      'For integration issues review the Tax Settings logs or open a support ticket.';

  @override
  String get taxMemoryIdLabel => 'Tax memory ID';

  @override
  String get taxEconomicCodeLabel => 'Economic code';

  @override
  String get taxSandboxModeLabel => 'Sandbox mode';

  @override
  String get taxSandboxModeSubtitle =>
      'When enabled, requests are sent to the sandbox environment.';

  @override
  String get taxPrivateKeyLabel => 'Private key (PEM)';

  @override
  String get taxPublicKeyLabel => 'Public key (optional)';

  @override
  String get taxCertificateLabel => 'Digital certificate (optional)';

  @override
  String get taxCertificateRequestLabel => 'Certificate request (CSR)';

  @override
  String get taxGenerateKeys => 'Generate new keys';

  @override
  String get taxMemoryIdRequired => 'Tax memory ID is required';

  @override
  String get taxEconomicCodeRequired => 'Economic code is required';

  @override
  String get taxPrivateKeyRequired => 'Private key is required';

  @override
  String get taxKeysGenerated => 'Keys generated successfully';

  @override
  String get taxSettingsSaved => 'Tax integration settings saved';

  @override
  String taxLastUpdated(String date) {
    return 'Last updated: $date';
  }

  @override
  String get taxPersonTypeLabel => 'Taxpayer type';

  @override
  String get taxPersonTypeNatural => 'Individual';

  @override
  String get taxPersonTypeLegal => 'Legal entity';

  @override
  String get taxNationalIdLabel => 'Taxpayer national ID';

  @override
  String get taxLegalNameFaLabel => 'Persian company name';

  @override
  String get taxLegalNameEnLabel => 'English company name';

  @override
  String get taxLegalEmailLabel => 'Corporate email';

  @override
  String get taxDataQualityTitle => 'Data quality check';

  @override
  String get taxDataQualitySubtitle =>
      'Review missing tax data before submitting invoices.';

  @override
  String get taxDataQualityReload => 'Refresh report';

  @override
  String get taxDataQualityProductsHeader => 'Products & services';

  @override
  String get taxDataQualityPersonsHeader => 'Persons & customers';

  @override
  String get taxDataQualityMissingTaxCode => 'Items missing tax code';

  @override
  String get taxDataQualityMissingTaxUnit => 'Items missing tax unit';

  @override
  String get taxDataQualityMissingNationalId => 'Persons missing national ID';

  @override
  String get taxDataQualityMissingEconomicId => 'Persons missing economic ID';

  @override
  String get taxDataQualitySamples => 'Samples';

  @override
  String get taxDataQualityNoSamples => 'No samples available.';

  @override
  String get taxDataQualityNoIssues => 'All good! No pending data issues.';

  @override
  String get taxDataQualityNoData => 'No report to display.';

  @override
  String taxDataQualityFetchError(String error) {
    return 'Failed to fetch quality report: $error';
  }

  @override
  String get taxDataQualityTaxCodeLabel => 'Tax code';

  @override
  String get taxDataQualityTaxUnitLabel => 'Tax unit';

  @override
  String get taxDataQualityNationalIdLabel => 'National ID';

  @override
  String get taxDataQualityEconomicIdLabel => 'Economic ID';

  @override
  String get taxValidationIssuesTitle => 'Tax validation issues';

  @override
  String get taxValidationIssuesDescription =>
      'Resolve the following items before sending invoices to the tax platform.';

  @override
  String get taxValidationIssuesEmpty => 'No issue details provided.';

  @override
  String get taxValidationIssuesCategoryPerson => 'Person Issues';

  @override
  String get taxValidationIssuesCategoryProduct => 'Product/Service Issues';

  @override
  String get taxValidationIssuesCategoryOther => 'Other Issues';

  @override
  String get taxValidationIssuesEditInvoice => 'Edit Invoice';

  @override
  String get taxValidationIssuesLineNumber => 'Line';

  @override
  String get taxAddToWorkspaceSingle => 'Add to tax workspace';

  @override
  String get taxRemoveFromWorkspaceSingle => 'Remove from tax workspace';

  @override
  String get taxStatus => 'Tax status';

  @override
  String get taxInWorkspace => 'In tax workspace';

  @override
  String get taxNotInWorkspace => 'Not in tax workspace';

  @override
  String get taxStatusPending => 'Pending';

  @override
  String get taxStatusSent => 'Sent';

  @override
  String get taxStatusFinalized => 'Finalized';

  @override
  String get taxStatusFailed => 'Failed';

  @override
  String get installmentColumn => 'Installment';

  @override
  String get documentDetailsInstallmentsTab => 'Installments';

  @override
  String get documentDetailsInstallmentsEmptySchedule =>
      'No installment rows were found for this invoice.';

  @override
  String documentDetailsInstallmentsAmountsNote(String currency) {
    return 'All amounts are in $currency.';
  }

  @override
  String get documentDetailsInstallmentReceive => 'Record receipt';

  @override
  String get documentDetailsInstallmentReceiptTypeOnly =>
      'Installment allocation is only available with a receipt for this invoice type.';

  @override
  String get documentDetailsInstallmentDocCodeColumn => 'Document';

  @override
  String get documentDetailsInstallmentPaymentDateColumn => 'Document date';

  @override
  String get taxStatusNotSent => 'Not sent';

  @override
  String get taxAddToWorkspaceNotAllowed =>
      'This invoice cannot be added to the tax workspace.';

  @override
  String get taxAddToWorkspaceDialogTitle => 'Add to tax workspace';

  @override
  String taxAddToWorkspaceDialogMessage(String code) {
    return 'Add invoice $code to tax workspace?';
  }

  @override
  String taxAddToWorkspaceSuccess(String code) {
    return 'Invoice $code added to tax workspace.';
  }

  @override
  String get taxAddToWorkspaceError => 'Failed to add to tax workspace.';

  @override
  String taxAddToWorkspaceErrorWithMessage(String error) {
    return 'Failed to add to tax workspace: $error';
  }

  @override
  String get taxRemoveFromWorkspaceDialogTitle => 'Remove from tax workspace';

  @override
  String taxRemoveFromWorkspaceDialogMessage(String code) {
    return 'Remove invoice $code from tax workspace?';
  }

  @override
  String get taxRemoveFromWorkspaceSuccess =>
      'Invoice removed from tax workspace.';

  @override
  String get taxRemoveFromWorkspaceError =>
      'Failed to remove from tax workspace.';

  @override
  String taxRemoveFromWorkspaceErrorWithMessage(String error) {
    return 'Failed to remove from tax workspace: $error';
  }

  @override
  String get taxWorkspaceEmpty => 'No invoices in tax workspace.';

  @override
  String get taxWorkspaceLoading => 'Loading tax workspace...';

  @override
  String get taxWorkspaceError => 'Error loading tax workspace.';

  @override
  String get taxSendSingle => 'Send to tax system';

  @override
  String get taxTrackingCode => 'Tracking code';

  @override
  String get taxLastSendAt => 'Last sent at';

  @override
  String get taxSendSingleDialogTitle => 'Send to tax system';

  @override
  String taxSendSingleDialogMessage(String code) {
    return 'Send invoice $code to tax system?';
  }

  @override
  String get taxSendSuccess => 'Sent to tax system.';

  @override
  String taxSendErrorWithMessage(String error) {
    return 'Failed to send to tax system: $error';
  }

  @override
  String get taxSendSelectedTooltip => 'Send selected invoices to tax system';

  @override
  String taxSendSelectedButton(int count) {
    return 'Send selected ($count)';
  }

  @override
  String get taxRemoveSelectedTooltip =>
      'Remove selected invoices from tax workspace';

  @override
  String taxRemoveSelectedButton(int count) {
    return 'Remove selected ($count)';
  }

  @override
  String get taxSendSelectedDialogTitle => 'Send selected to tax system';

  @override
  String taxSendSelectedDialogMessage(int count) {
    return 'Send $count selected invoices to tax system?';
  }

  @override
  String get taxSendSelectedSuccess => 'Selected invoices sent to tax system.';

  @override
  String get taxSendSelectedAllAlreadySent =>
      'All selected invoices have already been sent.';

  @override
  String taxSendSelectedSomeAlreadySent(int skipped, int count) {
    return '$skipped invoice(s) have already been sent. Send $count remaining invoice(s)?';
  }

  @override
  String taxSendSelectedErrorWithMessage(String error) {
    return 'Failed to send selected invoices: $error';
  }

  @override
  String taxSendSelectedPartialTitle(int success, int failed) {
    return '$success sent, $failed failed';
  }

  @override
  String taxBatchFailedRow(String id) {
    return 'Invoice $id';
  }

  @override
  String get taxInquireSelectedTooltip =>
      'Inquire status for selected invoices';

  @override
  String taxInquireSelectedButton(int count) {
    return 'Inquire status ($count)';
  }

  @override
  String get taxInquireSelectedDialogTitle => 'Inquire status';

  @override
  String taxInquireSelectedDialogMessage(int count) {
    return 'Inquire status for $count selected invoices?';
  }

  @override
  String taxInquireSelectedErrorWithMessage(String error) {
    return 'Failed to inquire status: $error';
  }

  @override
  String get taxInquiryResultTitle => 'Status inquiry result';

  @override
  String get taxInquiryResultEmpty => 'No results to display.';

  @override
  String get taxInquiryStatusUnknown => 'Unknown status';

  @override
  String get taxRemoveSelectedDialogTitle =>
      'Remove selected from tax workspace';

  @override
  String taxRemoveSelectedDialogMessage(int count) {
    return 'Remove $count selected invoices from tax workspace?';
  }

  @override
  String get taxRemoveSelectedSuccess =>
      'Selected invoices removed from tax workspace.';

  @override
  String get taxRemoveSelectedAllAlreadySent =>
      'All selected invoices have already been sent and cannot be removed from workspace.';

  @override
  String taxRemoveSelectedSomeAlreadySent(int skipped, int count) {
    return '$skipped invoice(s) have already been sent. Remove $count remaining invoice(s) from workspace?';
  }

  @override
  String taxRemoveSelectedErrorWithMessage(String error) {
    return 'Failed to remove selected invoices: $error';
  }

  @override
  String get taxQuickActionSendAllPending => 'Send all pending';

  @override
  String get taxQuickActionInquireAllSent => 'Inquire all sent';

  @override
  String get taxQuickActionRetryAllFailed => 'Retry all failed';

  @override
  String get taxHelpTooltip => 'Help';

  @override
  String get taxHelpTitle => 'Tax workspace guide';

  @override
  String get taxHelpSectionStatuses => 'Invoice statuses';

  @override
  String get taxHelpStatusNotSent => 'Not sent: Invoice has not been sent yet';

  @override
  String get taxHelpStatusPending => 'Pending: Currently being sent';

  @override
  String get taxHelpStatusSent => 'Sent: Sent and awaiting confirmation';

  @override
  String get taxHelpStatusFinalized => 'Finalized: Finalized by the tax system';

  @override
  String get taxHelpStatusFailed => 'Failed: Sending failed';

  @override
  String get taxHelpSectionQuickActions => 'Quick actions';

  @override
  String get taxHelpQuickActionSendPending =>
      'Send all pending: Send all pending invoices';

  @override
  String get taxHelpQuickActionInquireSent =>
      'Inquire all sent: Check status of sent invoices';

  @override
  String get taxHelpQuickActionRetryFailed =>
      'Retry all failed: Retry failed invoices';

  @override
  String get taxHelpSectionImportantNotes => 'Important notes';

  @override
  String get taxHelpNoteValidateBeforeSend =>
      'Validate invoices before sending';

  @override
  String get taxHelpNoteFailedInDLQ =>
      'Failed invoices are stored in the error queue';

  @override
  String get taxHelpNoteTimeline =>
      'You can view the change history of each invoice';

  @override
  String get taxHelpNoteExport => 'You can export sending reports';

  @override
  String get taxOperationSuccess => 'Operation completed successfully';

  @override
  String taxOperationError(String error) {
    return 'Error performing operation: $error';
  }

  @override
  String get taxSendingInvoices => 'Sending invoices...';

  @override
  String get taxSendingWithError => 'Sending encountered an error';

  @override
  String taxSentCountFailedCount(int sentCount, int failedCount) {
    return 'Sent: $sentCount | Failed: $failedCount';
  }

  @override
  String get taxProcessing => 'Processing...';

  @override
  String get taxUnknownError => 'Unknown error';

  @override
  String taxFailedInvoicesCount(int count) {
    return '$count invoices encountered errors';
  }

  @override
  String get taxRetryFailed => 'Retry';

  @override
  String get taxErrorCategoryValidation => 'Validation errors';

  @override
  String get taxErrorCategoryNetwork => 'Network errors';

  @override
  String get taxErrorCategoryAccess => 'Access errors';

  @override
  String get taxErrorCategoryStatus => 'Status errors';

  @override
  String get taxErrorCategoryOther => 'Other errors';

  @override
  String taxErrorItemsCount(int count) {
    return '$count items';
  }

  @override
  String taxInvoiceNumber(int invoiceId) {
    return 'Invoice #$invoiceId';
  }

  @override
  String get taxCurrencyRial => 'Rial';

  @override
  String get documentMonetizationTitle => 'Packages and Tariffs';

  @override
  String get documentMonetizationSubtitle =>
      'Packages, per-document fees and volume settlement';

  @override
  String get subscriptionPackages => 'Subscription Packages';

  @override
  String get noActivePackage =>
      'No active package has been registered for this business.';

  @override
  String get noPackageAvailable =>
      'Currently no package is available for purchase.';

  @override
  String get activePackage => 'Active Package';

  @override
  String get autoRenewActive => 'Auto-renewal is active';

  @override
  String get periodAmount => 'Period Amount';

  @override
  String get expiryDate => 'Expiry Date';

  @override
  String get duration => 'Duration';

  @override
  String get month => 'month';

  @override
  String get free => 'Free';

  @override
  String get activate => 'Activate';

  @override
  String get activating => 'Activating...';

  @override
  String activatePackage(String name) {
    return 'Activate $name';
  }

  @override
  String get packageDuration => 'Package Duration';

  @override
  String get packagePrice => 'Price';

  @override
  String get autoRenewAtEnd => 'Auto-renewal at end of period';

  @override
  String get confirmAndActivate => 'Confirm and Activate';

  @override
  String get invalidPackageId => 'Invalid package ID';

  @override
  String get packageActivatedSuccess => 'Package activated successfully';

  @override
  String get packageActivationError => 'Package activation failed';

  @override
  String get activePolicies => 'Active Policies';

  @override
  String get noPolicyDefined => 'No policy has been defined';

  @override
  String get noInvoice => 'No invoice exists';

  @override
  String get chargeType => 'Type';

  @override
  String get pay => 'Pay';

  @override
  String get paymentSuccess => 'Payment completed';

  @override
  String get paymentError => 'Payment failed';

  @override
  String get finalizeVolume => 'Finalize Volume Period';

  @override
  String get volumeFinalized => 'Volume calculations finalized';

  @override
  String get volumeFinalizeError => 'Volume period calculation failed';

  @override
  String get statusActive => 'Active';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusExpired => 'Expired';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusAwaitingPayment => 'Awaiting Payment';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusInvoiced => 'Invoiced';

  @override
  String get chargeTypePerDocument => 'Per Document';

  @override
  String get chargeTypeVolumeCycle => 'Volume Cycle';

  @override
  String get chargeTypeSubscriptionFee => 'Subscription Fee';

  @override
  String get policyTypeFree => 'Free';

  @override
  String get policyTypeSubscription => 'Unlimited Package';

  @override
  String get policyTypeVolume => 'Volume';

  @override
  String get policyTypePerDocument => 'Per Document';

  @override
  String get policyTypeHybrid => 'Hybrid';

  @override
  String get warehouseDocuments => 'Warehouse Documents';

  @override
  String get relatedWarehouseDocuments => 'Related warehouse documents';

  @override
  String get warehouseDocumentPostSuccess => 'Warehouse document posted.';

  @override
  String warehouseDocumentPostFailed(String error) {
    return 'Could not post warehouse document: $error';
  }

  @override
  String get warehouseDocument => 'Warehouse Document';

  @override
  String get warehouseDocumentCode => 'Document Code';

  @override
  String get warehouseDocumentType => 'Document Type';

  @override
  String get warehouseDocumentStatus => 'Status';

  @override
  String get warehouseDocumentDate => 'Document Date';

  @override
  String get warehouseDocumentFrom => 'From Warehouse';

  @override
  String get warehouseDocumentTo => 'To Warehouse';

  @override
  String get warehouseDocumentTotalQuantity => 'Total Quantity';

  @override
  String get warehouseDocumentTotalAmount => 'Total Amount';

  @override
  String get docTypeReceipt => 'Receipt';

  @override
  String get docTypeIssue => 'Issue';

  @override
  String get docTypeTransfer => 'Transfer';

  @override
  String get docTypeAdjustment => 'Adjustment';

  @override
  String get docTypeProductionIn => 'Production In';

  @override
  String get docTypeProductionOut => 'Production Out';

  @override
  String get statusDraft => 'Draft';

  @override
  String get statusPosted => 'Posted';

  @override
  String get createWarehouseDocument => 'Create Manual Document';

  @override
  String get postWarehouseDocument => 'Post Document';

  @override
  String get cancelWarehouseDocument => 'Cancel Document';

  @override
  String get deleteWarehouseDocument => 'Delete Document';

  @override
  String get viewWarehouseDocument => 'View Details';

  @override
  String get printWarehouseDocument => 'Print PDF';

  @override
  String get warehousePostalLabelTooltip => 'Postal consignment label (PDF)';

  @override
  String get warehousePostalLabelDialogTitle => 'Postal consignment label';

  @override
  String get warehousePostalLabelPaperSize => 'Paper size';

  @override
  String get warehousePostalLabelOrientation => 'Orientation';

  @override
  String get warehousePostalLabelPortrait => 'Portrait';

  @override
  String get warehousePostalLabelLandscape => 'Landscape';

  @override
  String get warehousePostalLabelCustomPaperHint =>
      'Custom size (max 32 chars, e.g. 120mm 80mm)';

  @override
  String get warehousePostalLabelTemplate => 'Print template';

  @override
  String get warehousePostalLabelNoTemplate => '— System default —';

  @override
  String get warehousePostalLabelFieldsSection => 'Fields on label';

  @override
  String get warehousePostalLabelShowSender => 'Sender';

  @override
  String get warehousePostalLabelShowReceiver => 'Recipient';

  @override
  String get warehousePostalLabelShowWarehouse => 'Warehouse names';

  @override
  String get warehousePostalLabelShowLines => 'Items summary';

  @override
  String get warehousePostalLabelShowDelivery => 'Shipping / notes';

  @override
  String get warehousePostalLabelShowTracking => 'Tracking number';

  @override
  String get warehousePostalLabelShowSource => 'Source document code';

  @override
  String get warehousePostalLabelDownload => 'Download PDF';

  @override
  String get applicationName => 'Application Name';

  @override
  String get applicationVersion => 'Application Version';

  @override
  String get defaultLanguage => 'Default Language';

  @override
  String get defaultTheme => 'Default Theme';

  @override
  String get enableUserRegistration => 'Enable User Registration';

  @override
  String get enableEmailVerification => 'Enable Email Verification';

  @override
  String get sessionTimeout => 'Session Timeout';

  @override
  String get sessionTimeoutMinutes => 'Session Timeout (minutes)';

  @override
  String get maxFileSize => 'Max File Size';

  @override
  String get maxFileSizeMB => 'Max File Size (MB)';

  @override
  String get maxUsers => 'Max Users';

  @override
  String get maintenanceMode => 'Maintenance Mode';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get errorLoadingSettings => 'Error loading settings';

  @override
  String get errorSavingSettings => 'Error saving settings';

  @override
  String get settingsSavedSuccessfully => 'Settings saved successfully';

  @override
  String get persian => 'Persian';

  @override
  String get english => 'English';

  @override
  String get zeroMeansUnlimited => '0 = Unlimited';

  @override
  String get otpLogin => 'OTP Login';

  @override
  String get otpLoginTitle => 'Login with OTP';

  @override
  String get otpLoginSubtitle =>
      'Login code will be sent to your email, mobile number or Telegram';

  @override
  String get otpLoginIdentifierHint => 'Enter your email or mobile number';

  @override
  String get otpLoginIdentifierRequired => 'Email or mobile number is required';

  @override
  String get otpCodeSent => 'Code sent';

  @override
  String get otpChannelSelectionTitle => 'Receive code via:';

  @override
  String get otpChannelSms => 'SMS';

  @override
  String get otpChannelEmail => 'Email';

  @override
  String get otpChannelTelegram => 'Telegram';

  @override
  String get otpSendCodeButton => 'Send login code';

  @override
  String get otpChangeChannelTitle => 'Change delivery method:';

  @override
  String get otpChangeIdentifier => 'Change identifier';

  @override
  String get otpSelectChannelError => 'Please select a delivery channel';

  @override
  String get otpCaptchaError => 'Error loading captcha';

  @override
  String otpCodeSentMessage(String channel) {
    return 'Login code sent to your $channel';
  }

  @override
  String get otpCodeResentMessage => 'Login code resent';

  @override
  String get otpSendError => 'Error sending login code';

  @override
  String get otpEnterCaptchaError => 'Please enter captcha code';

  @override
  String get workflows => 'Automations';

  @override
  String get workflow => 'Automation';

  @override
  String get newWorkflow => 'New Workflow';

  @override
  String get editWorkflow => 'Edit Workflow';

  @override
  String get workflowSaved => 'Workflow saved';

  @override
  String get workflowDeleted => 'Workflow deleted';

  @override
  String get workflowDuplicated => 'Workflow duplicated';

  @override
  String get workflowCopy => 'Copy';

  @override
  String get workflowUndo => 'Undo';

  @override
  String get workflowSave => 'Save';

  @override
  String get workflowCancel => 'Cancel';

  @override
  String get workflowClose => 'Close';

  @override
  String get workflowValidationError => 'Validation Error';

  @override
  String get workflowErrorLoading => 'Error loading data';

  @override
  String get workflowErrorSaving => 'Error saving';

  @override
  String get workflowStatusUpdated => 'Workflow status updated';

  @override
  String get workflowExecuted => 'Workflow executed';

  @override
  String get workflowErrorExecuting => 'Error executing workflow';

  @override
  String get workflowNoAccess => 'You do not have access to workflows.';

  @override
  String get workflowNoAccessEditor =>
      'You do not have access to workflow editor.';

  @override
  String get workflowNoWorkflows => 'No workflows yet.';

  @override
  String get workflowCreateFirst =>
      'Use the button below to create your first automation.';

  @override
  String get workflowCreate => 'Create Workflow';

  @override
  String get workflowRefresh => 'Refresh';

  @override
  String get workflowRunNow => 'Run now';

  @override
  String get workflowTestRun => 'Test run (live status)';

  @override
  String get workflowFixValidationBeforeTestRun =>
      'Fix validation errors on the canvas before running a test.';

  @override
  String get workflowExecutionHistory => 'Execution history';

  @override
  String get workflowHistoryClearCanvasHighlight => 'Clear highlight on canvas';

  @override
  String get workflowEdit => 'Edit';

  @override
  String get workflowLastUpdate => 'Last update';

  @override
  String get workflowAvailableTriggers => 'Available triggers';

  @override
  String get workflowAvailableActions => 'Available actions';

  @override
  String get workflowFilters => 'Filters';

  @override
  String get workflowStatus => 'Status';

  @override
  String get workflowSearch => 'Search';

  @override
  String get workflowAllStatuses => 'All statuses';

  @override
  String get workflowOnlyActive => 'Only active';

  @override
  String get workflowInactive => 'Inactive';

  @override
  String get workflowDraft => 'Draft';

  @override
  String get workflowActive => 'Active';

  @override
  String get workflowNodeDeleted => 'Node deleted';

  @override
  String get workflowNodeDuplicated => 'Node duplicated';

  @override
  String get workflowNodeSettings => 'Settings';

  @override
  String get workflowNodeNoSettings =>
      'This node does not require any special settings.';

  @override
  String get workflowNodeFieldRequired => 'This field is required';

  @override
  String get workflowNodeArrayType => 'Array';

  @override
  String get workflowNodeObjectType => 'Object';

  @override
  String get workflowConfigUsePreviousNode => 'Use previous node';

  @override
  String get workflowConfigSelectFromNodes => 'Select from previous nodes';

  @override
  String get workflowConfigValueUsesNode => 'This value uses a previous node';

  @override
  String get workflowConfigSelectDate => 'Select date';

  @override
  String get workflowConfigToday => 'Today';

  @override
  String get workflowConfigDateHelper => 'Select date (ISO: YYYY-MM-DD)';

  @override
  String get workflowConfigNoNodesToSelect => 'No nodes available to select';

  @override
  String get workflowConfigNoTelegramUsers =>
      'No users connected to Telegram bot. Please connect users first.';

  @override
  String get workflowConfigNoBaleUsers =>
      'No users connected to Bale bot. Please connect users first.';

  @override
  String get workflowConfigOwner => 'Owner';

  @override
  String get workflowConfigSearchSelectPerson => 'Search and select person';

  @override
  String get workflowConfigPersonIdLabel => 'Person ID';

  @override
  String get workflowConfigPersonIdHelper =>
      'Enter ID or use previous node: \$node_id.person_id';

  @override
  String get workflowConfigSearchSelectProduct =>
      'Search and select product/service';

  @override
  String get workflowConfigProductIdLabel => 'Product ID';

  @override
  String get workflowConfigProductIdHelper => 'Product/service ID';

  @override
  String get workflowConfigType => 'Type';

  @override
  String get workflowConfigPercent => 'Percent';

  @override
  String get workflowConfigFixedAmount => 'Fixed amount';

  @override
  String get workflowConfigDiscountPercent => 'Discount %';

  @override
  String get workflowConfigDiscountAmount => 'Discount amount';

  @override
  String workflowConfigItemN(int n) {
    return 'Item $n';
  }

  @override
  String get workflowConfigAddItem => 'Add item';

  @override
  String get workflowConfigAddLineItem => 'Add line item';

  @override
  String get workflowConfigProduct => 'Product';

  @override
  String get workflowConfigQuantity => 'Quantity';

  @override
  String get workflowConfigUnitPrice => 'Unit price';

  @override
  String get workflowConfigTaxPercent => 'Tax %';

  @override
  String get workflowConfigDescription => 'Description';

  @override
  String get workflowConfigPaymentMethod => 'Payment method';

  @override
  String get workflowConfigAmount => 'Amount';

  @override
  String get workflowConfigAccountSelect => 'Bank account / Cash register';

  @override
  String get workflowConfigAddPayment => 'Add payment';

  @override
  String get workflowConfigNoPaymentsYet =>
      'No payments added yet. Use the button below to add.';

  @override
  String workflowConfigPaymentN(int n) {
    return 'Payment $n';
  }

  @override
  String get workflowConfigNotSelected => 'Not selected';

  @override
  String get workflowConfigSelectWarehouse => 'Select warehouse';

  @override
  String get workflowConfigSelectAccount => 'Select account';

  @override
  String get workflowConfigSelectFiscalYear => 'Select fiscal year';

  @override
  String get workflowConfigInvalidJson => 'Invalid JSON';

  @override
  String get workflowConfigJsonHint => '{\"key\": \"value\"}';

  @override
  String get workflowConfigCash => 'Cash';

  @override
  String get workflowConfigBank => 'Bank';

  @override
  String get workflowConfigCheck => 'Check';

  @override
  String get workflowConfigCard => 'Card';

  @override
  String get workflowConfigSelectTelegramUser =>
      'Select user connected to Telegram bot';

  @override
  String get workflowConfigSelectBaleUser =>
      'Select user connected to Bale bot';

  @override
  String get workflowConfigSelectAtLeastOne => 'Select at least one item';

  @override
  String get workflowConfigReferenceTitle => 'Select from previous nodes';

  @override
  String get workflowConfigNoNodesAvailable => 'No nodes available to select';

  @override
  String get workflowConfigStep1Node => 'Step 1: Select node';

  @override
  String get workflowConfigStep2Data => 'Step 2: Select data';

  @override
  String workflowConfigSelectDataFrom(String label) {
    return 'Select data from \"$label\"';
  }

  @override
  String get workflowConfigOrSelectField => 'Or select a specific field:';

  @override
  String get workflowConfigUseFullNodeOutput => 'Use full node output';

  @override
  String get workflowConfigFullNodeOutputDesc =>
      'All output data from the node';

  @override
  String get workflowConfigBack => 'Back';

  @override
  String get workflowConfigCancel => 'Cancel';

  @override
  String get workflowConfigGroupFilters => 'Filters';

  @override
  String get workflowConfigGroupScheduling => 'Scheduling';

  @override
  String get workflowConfigGroupErrorManagement => 'Error management';

  @override
  String get workflowConfigGroupMainSettings => 'Main settings';

  @override
  String get workflowConfigGroupAdvanced => 'Advanced settings';

  @override
  String get workflowConfigUserDefault => 'User';

  @override
  String get workflowConfigFiscalYearDefault => 'Fiscal year';

  @override
  String get workflowConfigJsonLabel => 'JSON';

  @override
  String get workflowPaletteSearch => 'Search...';

  @override
  String get workflowPaletteAll => 'All';

  @override
  String get workflowPaletteTriggers => 'Triggers';

  @override
  String get workflowPaletteActions => 'Actions';

  @override
  String get workflowPaletteLoops => 'Loops';

  @override
  String get workflowPaletteConditions => 'Conditions';

  @override
  String get workflowNodeUnknown => 'Unknown node';

  @override
  String get workflowConfigEnumRequiredForMultiSelect =>
      'Error: enum values required for multi-select';

  @override
  String get workflowConfigFieldEnabled => 'Enabled';

  @override
  String get workflowConfigFieldTo => 'To';

  @override
  String get workflowConfigFieldSubject => 'Subject';

  @override
  String get workflowConfigFieldBody => 'Body';

  @override
  String get workflowConfigFieldMessage => 'Message';

  @override
  String get workflowConfigFieldMinAmount => 'Minimum amount';

  @override
  String get workflowConfigFieldMaxAmount => 'Maximum amount';

  @override
  String get workflowConfigFieldStatusFilter => 'Status filter';

  @override
  String get workflowConfigFieldPersonType => 'Person type';

  @override
  String get workflowConfigFieldCurrency => 'Currency';

  @override
  String get workflowConfigFieldPersonId => 'Person ID';

  @override
  String get workflowConfigFieldProductId => 'Product ID';

  @override
  String get workflowConfigFieldWarehouseId => 'Warehouse ID';

  @override
  String get workflowConfigFieldAccountId => 'Account ID';

  @override
  String get workflowConfigFieldRetryCount => 'Retry count';

  @override
  String get workflowConfigFieldRetryDelay => 'Retry delay';

  @override
  String get workflowConfigFieldOnError => 'On error';

  @override
  String get workflowConfigFieldBreakOnError => 'Break on error';

  @override
  String get workflowConfigFieldContinueOnError => 'Continue on error';

  @override
  String get workflowConfigFieldTriggerType => 'Trigger type';

  @override
  String get workflowConfigFieldActionType => 'Action type';

  @override
  String get workflowConfigFieldLoopType => 'Loop type';

  @override
  String get workflowConfigFieldItemsSource => 'Items source';

  @override
  String get workflowConfigFieldItemVariable => 'Item variable';

  @override
  String get workflowConfigFieldIndexVariable => 'Index variable';

  @override
  String get workflowConfigFieldMaxIterations => 'Max iterations';

  @override
  String get workflowConfigFieldStart => 'Start';

  @override
  String get workflowConfigFieldEnd => 'End';

  @override
  String get workflowConfigFieldStep => 'Step';

  @override
  String get workflowConfigFieldConditionLeft => 'Left value';

  @override
  String get workflowConfigFieldConditionOperator => 'Comparison operator';

  @override
  String get workflowConfigFieldConditionRight => 'Right value';

  @override
  String get workflowConfigFieldTimeout => 'Timeout';

  @override
  String get workflowConfigFieldCooldown => 'Cooldown';

  @override
  String get workflowConfigFieldSchedule => 'Schedule';

  @override
  String get workflowConfigFieldDelay => 'Delay';

  @override
  String get workflowConfigFieldDocumentType => 'Document type';

  @override
  String get workflowConfigFieldFiscalYearFilter => 'Fiscal year filter';

  @override
  String get workflowConfigFieldFiscalYearId => 'Fiscal year';

  @override
  String get workflowConfigFieldUserIdFilter => 'User filter';

  @override
  String get workflowConfigFieldDescriptionContains => 'Description contains';

  @override
  String get workflowConfigFieldCooldownSeconds => 'Cooldown (seconds)';

  @override
  String get workflowConfigFieldTimeoutSeconds => 'Timeout (seconds)';

  @override
  String get workflowConfigFieldInvoiceType => 'Invoice type';

  @override
  String get workflowConfigFieldPersonTypeFilter => 'Person type filter';

  @override
  String get workflowConfigFieldCurrencyId => 'Currency';

  @override
  String get workflowConfigFieldIncludeTaxDetails => 'Include tax details';

  @override
  String get workflowConfigFieldIncludePaymentStatus =>
      'Include payment status';

  @override
  String get workflowConfigFieldAccountIdFilter => 'Account filter';

  @override
  String get workflowConfigFieldPaymentMethodFilter => 'Payment method filter';

  @override
  String get workflowConfigFieldIncludeBalance => 'Include balance';

  @override
  String get workflowConfigFieldCheckDuplicate => 'Check duplicate';

  @override
  String get workflowConfigFieldTypeFilter => 'Type filter';

  @override
  String get workflowConfigFieldCheckType => 'Check type';

  @override
  String get workflowConfigFieldDaysBefore => 'Days before due';

  @override
  String get workflowConfigFieldReferenceCode => 'Reference code';

  @override
  String get workflowConfigFieldExtraInfo => 'Extra info';

  @override
  String get workflowConfigFieldIsProforma => 'Proforma invoice';

  @override
  String get workflowConnectionHelpTitle => 'How to Connect Nodes';

  @override
  String get workflowConnectionHelpMethod1 =>
      'Method 1: Drag & Drop (Recommended)';

  @override
  String get workflowConnectionHelpMethod1Step1 =>
      '1. Click and hold on the output point of a node';

  @override
  String get workflowConnectionHelpMethod1Step2 =>
      '2. Drag your mouse - a temporary line will appear';

  @override
  String get workflowConnectionHelpMethod1Step3 =>
      '3. Release on the input point of another node';

  @override
  String get workflowConnectionHelpMethod2 => 'Method 2: Click & Click';

  @override
  String get workflowConnectionHelpMethod2Step1 =>
      '1. Click on the output point of a node';

  @override
  String get workflowConnectionHelpMethod2Step2 =>
      '2. Click on the input point of another node';

  @override
  String get workflowConnectionHelpTips => 'Tips';

  @override
  String get workflowConnectionHelpTipsText =>
      '• Trigger nodes only have output points\n• Action nodes have both input and output points\n• To delete connection: click on it and press Delete';

  @override
  String get workflowConnectionHelpGotIt => 'Got it';

  @override
  String get workflowEditNameDescription => 'Edit name and description';

  @override
  String get workflowNameRequired => 'Workflow name *';

  @override
  String get workflowNameHint => 'e.g. Invoice approval process';

  @override
  String get workflowDescription => 'Description';

  @override
  String get workflowDescriptionHint =>
      'Optional description for this workflow...';

  @override
  String get workflowSaveWorkflow => 'Save workflow';

  @override
  String get workflowEnterName => 'Please enter workflow name';

  @override
  String get workflowInfoUpdated =>
      'Info updated. For permanent save, click the Save button.';

  @override
  String get workflowNoteComment => 'Note / Comment';

  @override
  String get workflowNoteHint => 'Note or comment for this node...';

  @override
  String get workflowNoteDeleted => 'Note deleted';

  @override
  String get workflowNoteCleared => 'Note cleared';

  @override
  String get workflowNoteSaved => 'Note saved';

  @override
  String get workflowSaveAsTemplate => 'Save as template';

  @override
  String get workflowTemplateName => 'Template name';

  @override
  String get workflowTemplateNameHint => 'e.g. Invoice process';

  @override
  String workflowTemplateSaved(String name) {
    return 'Template \"$name\" saved';
  }

  @override
  String workflowTemplateLoaded(String name) {
    return 'Template \"$name\" loaded';
  }

  @override
  String get workflowSelectTemplate => 'Select template';

  @override
  String get workflowBuiltinTemplates => 'Built-in templates';

  @override
  String get workflowSavedTemplates => 'Saved templates';

  @override
  String get workflowNoSavedTemplates => 'No saved templates';

  @override
  String get workflowTemplateDefault => 'Template';

  @override
  String workflowTemplateN(int n) {
    return 'Template $n';
  }

  @override
  String workflowCreatedAt(String date) {
    return 'Created: $date';
  }

  @override
  String get workflowErrorAddNode => 'Error adding node';

  @override
  String get workflowErrorSaveTemplate => 'Error saving template';

  @override
  String get workflowErrorLoadTemplate => 'Error loading template';

  @override
  String get workflowTimelineTitle => 'Execution timeline';

  @override
  String get workflowTimelineRefresh => 'Refresh';

  @override
  String get workflowAnalyticsTitle => 'Analytics';

  @override
  String get workflowPerformance => 'Performance';

  @override
  String get workflowNoData => 'No data available';

  @override
  String get workflowErrorLoadTimeline => 'Error loading timeline';

  @override
  String get workflowAllLogs => 'All logs';

  @override
  String get workflowAllNodes => 'All nodes';

  @override
  String get workflowErrors => 'Errors';

  @override
  String get workflowNodeStats => 'Node stats';

  @override
  String get workflowColumnNode => 'Node';

  @override
  String get workflowColumnType => 'Type';

  @override
  String get workflowColumnExecutions => 'Executions';

  @override
  String get workflowColumnAvgTime => 'Avg. time';

  @override
  String get workflowErrorLoadAnalytics => 'Error loading analytics';

  @override
  String get workflowErrorLoadErrorStats => 'Error loading error stats';

  @override
  String get workflowTotalExecutions => 'Total executions';

  @override
  String get workflowSuccessful => 'Successful';

  @override
  String get workflowFailed => 'Failed';

  @override
  String get workflowAvgTime => 'Avg. time';

  @override
  String get workflowSuccessRate => 'Success rate';

  @override
  String get workflowNoErrorsRecorded => 'No errors recorded!';

  @override
  String get workflowTotalErrors => 'Total errors';

  @override
  String get workflowErrorTypes => 'Error types';

  @override
  String get workflowErrorLoadHistory => 'Error loading history';

  @override
  String get workflowErrorLoadLogs => 'Error loading logs';

  @override
  String get workflowDeleteWorkflow => 'Delete workflow';

  @override
  String workflowDeleteConfirm(String name) {
    return 'Are you sure you want to delete workflow \"$name\"?';
  }

  @override
  String get workflowDeletedSuccess => 'Workflow deleted successfully';

  @override
  String get workflowErrorDelete => 'Error deleting workflow';

  @override
  String get workflowStatusActive => 'Active';

  @override
  String get workflowStatusInactive => 'Inactive';

  @override
  String get workflowStatusDraft => 'Draft';

  @override
  String get workflowNoNodesDefined => 'No nodes defined';

  @override
  String get workflowEmpty => 'This workflow is empty';

  @override
  String get workflowErrorDisplay => 'Error displaying workflow';

  @override
  String get workflowExecutionLogs => 'Execution logs';

  @override
  String get workflowExecutionLogCopyOne => 'Copy this log';

  @override
  String get workflowExecutionLogsCopyAll => 'Copy all logs';

  @override
  String get workflowNoLogs => 'No logs found';

  @override
  String get workflowNoExecutions => 'No executions yet';

  @override
  String get workflowStarted => 'Started';

  @override
  String get workflowCompleted => 'Completed';

  @override
  String get workflowLogs => 'Logs';

  @override
  String get workflowErrorLoadingLogs => 'Error loading logs';

  @override
  String get workflowErrorUpdatingStatus => 'Error updating status';

  @override
  String get workflowHierarchicalLayoutApplied => 'Hierarchical layout applied';

  @override
  String get workflowForceDirectedLayoutApplied =>
      'Force-directed layout applied';

  @override
  String get workflowValidationSuccess => 'Validation successful';

  @override
  String get workflowAllNodesValid => 'All nodes are valid!';

  @override
  String workflowNodesWithErrors(int count) {
    return '$count nodes have errors';
  }

  @override
  String get workflowToolbarOpenPalette => 'Open node palette';

  @override
  String get workflowToolbarZoomOut => 'Zoom out';

  @override
  String get workflowToolbarZoomIn => 'Zoom in';

  @override
  String get workflowToolbarResetZoom => 'Reset zoom';

  @override
  String get workflowToolbarConnectionHelp => 'Connection help';

  @override
  String get workflowToolbarHideGrid => 'Hide Grid';

  @override
  String get workflowToolbarShowGrid => 'Show Grid';

  @override
  String get workflowToolbarDisableSnapToGrid => 'Disable Snap to Grid';

  @override
  String get workflowToolbarEnableSnapToGrid => 'Enable Snap to Grid';

  @override
  String get workflowToolbarAlignmentTools => 'Alignment tools';

  @override
  String get workflowToolbarAlignLeft => 'Align left';

  @override
  String get workflowToolbarAlignRight => 'Align right';

  @override
  String get workflowToolbarAlignTop => 'Align top';

  @override
  String get workflowToolbarAlignBottom => 'Align bottom';

  @override
  String get workflowToolbarDistributeHorizontally => 'Distribute horizontally';

  @override
  String get workflowToolbarDistributeVertically => 'Distribute vertically';

  @override
  String get workflowToolbarAlignToGrid => 'Align to grid';

  @override
  String get workflowToolbarClearAll => 'Clear all';

  @override
  String get workflowToolbarAutoLayout => 'Auto layout';

  @override
  String get workflowToolbarTemplates => 'Templates';

  @override
  String get workflowToolbarLoadTemplate => 'Load template';

  @override
  String get workflowToolbarSelectLayoutType => 'Select layout type';

  @override
  String get workflowToolbarHierarchical => 'Hierarchical';

  @override
  String get workflowToolbarForceDirected => 'Force-directed';

  @override
  String get workflowToolbarShowValidationErrors => 'Show validation errors';

  @override
  String get workflowToolbarUndo => 'Undo';

  @override
  String get workflowToolbarRedo => 'Redo';

  @override
  String get workflowToolbarNodes => 'Nodes';

  @override
  String get workflowToolbarConnections => 'Connections';

  @override
  String get workflowNoSuggestedFields => 'No suggested fields for this node';

  @override
  String workflowTypeFieldManually(String nodeId) {
    return 'You can type the field manually: $nodeId.field_name';
  }

  @override
  String get workflowFieldInvoiceId => 'Invoice ID';

  @override
  String get workflowFieldDescInvoiceId => 'Numeric invoice ID';

  @override
  String get workflowFieldInvoiceCode => 'Invoice code';

  @override
  String get workflowFieldDescInvoiceCode => 'Unique invoice code';

  @override
  String get workflowFieldInvoiceNumber => 'Invoice number';

  @override
  String get workflowFieldDescInvoiceNumber => 'Invoice number';

  @override
  String get workflowFieldInvoiceDate => 'Invoice date';

  @override
  String get workflowFieldDescInvoiceDate => 'Invoice issue date';

  @override
  String get workflowFieldTotalAmount => 'Total amount';

  @override
  String get workflowFieldDescTotalAmount => 'Total amount';

  @override
  String get workflowFieldDiscountAmount => 'Discount amount';

  @override
  String get workflowFieldDescDiscountAmount => 'Total discounts';

  @override
  String get workflowFieldTaxAmount => 'Tax amount';

  @override
  String get workflowFieldDescTaxAmount => 'Total tax';

  @override
  String get workflowFieldFinalAmount => 'Final amount';

  @override
  String get workflowFieldDescFinalAmount => 'Payable amount';

  @override
  String get workflowFieldCustomerName => 'Customer name';

  @override
  String get workflowFieldDescCustomerName => 'Counterparty name';

  @override
  String get workflowFieldCustomerId => 'Customer ID';

  @override
  String get workflowFieldDescCustomerId => 'Counterparty ID';

  @override
  String get workflowFieldDescription => 'Description';

  @override
  String get workflowFieldDescDescription => 'Description';

  @override
  String get workflowFieldInvoiceDescription => 'Invoice description';

  @override
  String get workflowFieldStatus => 'Status';

  @override
  String get workflowFieldDescStatus => 'Status';

  @override
  String get workflowFieldInvoiceStatus => 'Invoice status';

  @override
  String get workflowFieldPaymentId => 'Payment ID';

  @override
  String get workflowFieldDescPaymentId => 'Numeric payment ID';

  @override
  String get workflowFieldAmount => 'Amount';

  @override
  String get workflowFieldDescAmount => 'Amount';

  @override
  String get workflowFieldPaymentAmount => 'Payment amount';

  @override
  String get workflowFieldPaymentDate => 'Payment date';

  @override
  String get workflowFieldDescPaymentDate => 'Payment date';

  @override
  String get workflowFieldPaymentMethod => 'Payment method';

  @override
  String get workflowFieldDescPaymentMethod => 'Payment method type';

  @override
  String get workflowFieldPaymentStatus => 'Payment status';

  @override
  String get workflowFieldReferenceCode => 'Reference code';

  @override
  String get workflowFieldDescReferenceCode => 'Transaction reference code';

  @override
  String get workflowFieldDocumentId => 'Document ID';

  @override
  String get workflowFieldDescDocumentId => 'Numeric document ID';

  @override
  String get workflowFieldDocumentType => 'Document type';

  @override
  String get workflowFieldDescDocumentType => 'Accounting document type';

  @override
  String get workflowFieldDocTotalAmount => 'Document total';

  @override
  String get workflowFieldDescDocTotalAmount => 'Document total amount';

  @override
  String get workflowFieldDocDescription => 'Document description';

  @override
  String get workflowFieldDescDocDescription => 'Document description';

  @override
  String get workflowFieldReceiptPaymentId => 'Receipt/Payment ID';

  @override
  String get workflowFieldDescReceiptPaymentId => 'Numeric ID';

  @override
  String get workflowFieldType => 'Type';

  @override
  String get workflowFieldDescType => 'Receipt or payment';

  @override
  String get workflowFieldPersonId => 'ID';

  @override
  String get workflowFieldDescPersonId => 'Counterparty ID';

  @override
  String get workflowFieldPersonName => 'Name';

  @override
  String get workflowFieldDescPersonName => 'Counterparty name';

  @override
  String get workflowFieldEmail => 'Email';

  @override
  String get workflowFieldDescEmail => 'Email address';

  @override
  String get workflowFieldPhone => 'Phone';

  @override
  String get workflowFieldDescPhone => 'Phone number';

  @override
  String get workflowFieldMobile => 'Mobile';

  @override
  String get workflowFieldDescMobile => 'Mobile number';

  @override
  String get workflowFieldPersonType => 'Type';

  @override
  String get workflowFieldDescPersonType => 'Counterparty type';

  @override
  String get workflowFieldProductId => 'Product ID';

  @override
  String get workflowFieldDescProductId => 'Numeric product ID';

  @override
  String get workflowFieldProductName => 'Product name';

  @override
  String get workflowFieldDescProductName => 'Product name';

  @override
  String get workflowFieldProductCode => 'Product code';

  @override
  String get workflowFieldDescProductCode => 'Product code';

  @override
  String get workflowFieldPrice => 'Price';

  @override
  String get workflowFieldDescPrice => 'Sale price';

  @override
  String get workflowFieldQuantity => 'Quantity';

  @override
  String get workflowFieldDescQuantity => 'Stock quantity';

  @override
  String get workflowFieldId => 'ID';

  @override
  String get workflowFieldDescId => 'Record ID';

  @override
  String get workflowFieldName => 'Name';

  @override
  String get workflowFieldDescName => 'Name';

  @override
  String get workflowFieldTitle => 'Title';

  @override
  String get workflowFieldDescTitle => 'Title';

  @override
  String get workflowFieldGenDescription => 'Description';

  @override
  String get workflowFieldDescGenDescription => 'Description';

  @override
  String get workflowFieldGenStatus => 'Status';

  @override
  String get workflowFieldDescGenStatus => 'Status';

  @override
  String get workflowFieldCreatedAt => 'Created date';

  @override
  String get workflowFieldDescCreatedAt => 'Creation date and time';

  @override
  String get workflowFieldInvoiceType => 'Invoice type';

  @override
  String get workflowFieldDescInvoiceType =>
      'Invoice document type (e.g. sales/purchase)';

  @override
  String get workflowFieldLeadId => 'Lead ID';

  @override
  String get workflowFieldDescLeadId => 'CRM lead record ID';

  @override
  String get workflowFieldDealId => 'Deal ID';

  @override
  String get workflowFieldDescDealId => 'CRM deal/opportunity record ID';

  @override
  String get workflowFieldProcessDefinitionId => 'Process definition ID';

  @override
  String get workflowFieldDescProcessDefinitionId => 'Sales process definition';

  @override
  String get workflowFieldStageId => 'Stage ID';

  @override
  String get workflowFieldDescStageId => 'Current stage in the process';

  @override
  String get workflowFieldOldStageId => 'Previous stage ID';

  @override
  String get workflowFieldDescOldStageId => 'Stage before the change';

  @override
  String get workflowFieldNewStageId => 'New stage ID';

  @override
  String get workflowFieldDescNewStageId => 'Stage after the change';

  @override
  String get workflowFieldIsWin => 'Won deal';

  @override
  String get workflowFieldDescIsWin => 'Whether the deal was closed as won';

  @override
  String get workflowFieldPersonTypesList => 'Person types';

  @override
  String get workflowFieldDescPersonTypesList =>
      'Assigned person types list (on create)';

  @override
  String get workflowFieldSuccess => 'Success';

  @override
  String get workflowFieldDescSuccess => 'Whether the action succeeded';

  @override
  String get workflowFieldWorkflowUserId => 'User ID';

  @override
  String get workflowFieldDescWorkflowUserId => 'User ID in action output';

  @override
  String get workflowFieldSentMessage => 'Sent message';

  @override
  String get workflowFieldDescSentMessage =>
      'Message text after send (e.g. Telegram/Bale)';

  @override
  String get workflowFieldTelegramChatId => 'Telegram chat ID';

  @override
  String get workflowFieldDescTelegramChatId => 'Recipient Telegram chat ID';

  @override
  String get workflowFieldBaleChatId => 'Bale chat ID';

  @override
  String get workflowFieldDescBaleChatId => 'Recipient Bale chat ID';

  @override
  String get workflowFieldFileStorageId => 'File ID (storage)';

  @override
  String get workflowFieldDescFileStorageId =>
      'UUID of the file on the file server; use in Bale attachment_file_id as \$node_id.file_id';

  @override
  String get workflowFieldAttachmentFileId => 'Attachment file ID';

  @override
  String get workflowFieldDescAttachmentFileId =>
      'Same as file_id on backup success; alias for referencing in Bale';

  @override
  String get workflowFieldStoredFilename => 'Stored filename';

  @override
  String get workflowFieldDescStoredFilename =>
      'Original filename of the backup or attachment on the file server';

  @override
  String get workflowFieldSendFileAttachment => 'Send file attachment';

  @override
  String get workflowFieldDescSendFileAttachment =>
      'Whether the Bale action sent a document from file storage';

  @override
  String get workflowFieldCrmChatConversationId => 'Chat conversation ID';

  @override
  String get workflowFieldDescCrmChatConversationId =>
      'CRM web chat conversation record ID in trigger_data';

  @override
  String get workflowFieldCrmChatWidgetId => 'Chat widget ID';

  @override
  String get workflowFieldDescCrmChatWidgetId =>
      'Web chat widget linked to this conversation';

  @override
  String get workflowFieldCrmChatMessageId => 'Chat message ID';

  @override
  String get workflowFieldDescCrmChatMessageId =>
      'Recorded web chat message ID';

  @override
  String get workflowFieldCrmChatBody => 'Message body';

  @override
  String get workflowFieldDescCrmChatBody =>
      'Visitor or agent message text in web chat';

  @override
  String get workflowFieldCrmChatSenderRole => 'Sender role';

  @override
  String get workflowFieldDescCrmChatSenderRole =>
      'visitor or agent depending on the message';

  @override
  String get workflowFieldCrmChatVisitorFirstName => 'Visitor first name';

  @override
  String get workflowFieldDescCrmChatVisitorFirstName =>
      'First name from the chat widget form';

  @override
  String get workflowFieldCrmChatVisitorLastName => 'Visitor last name';

  @override
  String get workflowFieldDescCrmChatVisitorLastName =>
      'Last name from the chat widget form';

  @override
  String get workflowFieldCrmChatPageUrl => 'Page URL';

  @override
  String get workflowFieldDescCrmChatPageUrl =>
      'Site page URL when the event occurred (if present)';

  @override
  String get workflowFieldCrmChatConversationStatus => 'Conversation status';

  @override
  String get workflowFieldDescCrmChatConversationStatus =>
      'e.g. open or resolved';

  @override
  String get workflowFieldCrmChatAssignedToUserId => 'Assigned user ID';

  @override
  String get workflowFieldDescCrmChatAssignedToUserId =>
      'Responsible agent user when assigned';

  @override
  String get workflowFieldCrmChatAgentUserId => 'Agent user ID';

  @override
  String get workflowFieldDescCrmChatAgentUserId =>
      'Sending user for agent-role messages (agent reply trigger)';

  @override
  String get workflowFieldAutomationSource => 'Automation source';

  @override
  String get workflowFieldDescAutomationSource =>
      'e.g. workflow when the message was sent by automation';

  @override
  String get workflowFieldOperatorRelay => 'Operator relay';

  @override
  String get workflowFieldDescOperatorRelay =>
      'When sent via operator bridge (Telegram/Bale)';

  @override
  String get workflowFieldCrmChatOldAssignedUserId => 'Previous assignee ID';

  @override
  String get workflowFieldDescCrmChatOldAssignedUserId =>
      'Before assignment changed';

  @override
  String get workflowFieldCrmChatNewAssignedUserId => 'New assignee ID';

  @override
  String get workflowFieldDescCrmChatNewAssignedUserId =>
      'After assignment changed';

  @override
  String get workflowFieldCrmChatOldStatus => 'Previous conversation status';

  @override
  String get workflowFieldDescCrmChatOldStatus => 'Before status update';

  @override
  String get workflowFieldCrmChatNewStatus => 'New conversation status';

  @override
  String get workflowFieldDescCrmChatNewStatus => 'After status update';

  @override
  String get workflowFieldEmailTo => 'To';

  @override
  String get workflowFieldDescEmailTo =>
      'Recipient email address (resolved after send)';

  @override
  String get workflowFieldEmailSubject => 'Subject';

  @override
  String get workflowFieldDescEmailSubject =>
      'Email subject line (resolved after send)';

  @override
  String get workflowFieldHttpStatusCode => 'HTTP status code';

  @override
  String get workflowFieldDescHttpStatusCode =>
      'Response status code (e.g. 200)';

  @override
  String get workflowFieldHttpResponse => 'HTTP response';

  @override
  String get workflowFieldDescHttpResponse => 'Response body or payload';

  @override
  String get workflowFieldVariableName => 'Variable name';

  @override
  String get workflowFieldDescVariableName =>
      'Name of variable stored in context';

  @override
  String get workflowFieldVariableValue => 'Variable value';

  @override
  String get workflowFieldDescVariableValue => 'Stored value for the variable';

  @override
  String get workflowFieldWebhookPayload => 'Webhook payload';

  @override
  String get workflowFieldDescWebhookPayload => 'Parsed webhook payload data';

  @override
  String get workflowFieldWebhookBody => 'Request body';

  @override
  String get workflowFieldDescWebhookBody => 'Raw HTTP request body';

  @override
  String get workflowFieldScheduledAt => 'Scheduled run time';

  @override
  String get workflowFieldDescScheduledAt => 'When the scheduled trigger ran';

  @override
  String get workflowFieldWarehouseId => 'Warehouse ID';

  @override
  String get workflowFieldDescWarehouseId =>
      'Warehouse related to inventory event';

  @override
  String get workflowFieldCurrentQuantity => 'Current quantity';

  @override
  String get workflowFieldDescCurrentQuantity => 'Current stock quantity';

  @override
  String get workflowFieldMinQuantity => 'Minimum quantity';

  @override
  String get workflowFieldDescMinQuantity => 'Low-stock threshold';

  @override
  String get workflowFieldCheckId => 'Check ID';

  @override
  String get workflowFieldDescCheckId => 'Check record ID';

  @override
  String get workflowFieldCheckNumber => 'Check number';

  @override
  String get workflowFieldDescCheckNumber => 'Printed check number';

  @override
  String get workflowFieldDueDate => 'Due date';

  @override
  String get workflowFieldDescDueDate => 'Maturity/due date';

  @override
  String get workflowFieldLogLevel => 'Log level';

  @override
  String get workflowFieldDescLogLevel => 'Level recorded in workflow log';

  @override
  String get workflowTemplateInvoiceSalesName => 'Invoice sales notification';

  @override
  String get workflowTemplateInvoiceSalesDesc =>
      'After creating sales invoice, email and Telegram are sent';

  @override
  String get workflowCategoryInvoice => 'Invoice';

  @override
  String get workflowTemplateInventoryLowName => 'Low inventory alert';

  @override
  String get workflowTemplateInventoryLowDesc =>
      'When product stock is low, notification is sent';

  @override
  String get workflowCategoryInventory => 'Inventory';

  @override
  String get workflowTemplateReceiptPaymentName => 'Receipt/Payment log';

  @override
  String get workflowTemplateReceiptPaymentDesc =>
      'After recording receipt/payment, log is created';

  @override
  String get workflowCategoryFinancial => 'Financial';

  @override
  String get workflowTemplatePersonWelcomeName => 'New person welcome';

  @override
  String get workflowTemplatePersonWelcomeDesc =>
      'After creating new person, welcome message is sent';

  @override
  String get workflowCategoryPersons => 'Persons';

  @override
  String get workflowCategoryCrm => 'CRM';

  @override
  String get workflowTemplateCrmNewLeadNotifyName =>
      'New lead in-app notification';

  @override
  String get workflowTemplateCrmNewLeadNotifyDesc =>
      'When a lead is created, an in-app notification is recorded';

  @override
  String get workflowTemplateCrmDealWonLogName => 'Log won deal closure';

  @override
  String get workflowTemplateCrmDealWonLogDesc =>
      'Only won deals; writes an info log entry';

  @override
  String get workflowTemplateReceiptUpdatedNotifyName =>
      'Notify on receipt/payment edit';

  @override
  String get workflowTemplateReceiptUpdatedNotifyDesc =>
      'After a receipt or payment is edited, an in-app notification is created';

  @override
  String get workflowTemplateInvoiceAmountBranchName =>
      'Sales invoice: high vs low amount';

  @override
  String get workflowTemplateInvoiceAmountBranchDesc =>
      'If amount is at least 10M, high-priority in-app notice; otherwise only a log (simple If example)';

  @override
  String get workflowTestRunCompletedDry =>
      'Dry run succeeded (no real sends or writes).';

  @override
  String get settingsCategoriesCount => 'Categories';

  @override
  String get settingsCount => 'Settings';

  @override
  String get expandAllCategories => 'Expand All';

  @override
  String get collapseAllCategories => 'Collapse All';

  @override
  String get categoryTreeShowProductsInCategory =>
      'Show products in this category';

  @override
  String get categoryTreeActionsMenuTooltip => 'Actions';

  @override
  String get categoryTreeMoreActionsTooltip => 'More';

  @override
  String categoryLoadProductsError(String error) {
    return 'Error loading products: $error';
  }

  @override
  String get categoryTreeNoProductsInCategory => 'No products in this category';

  @override
  String get categoryDescriptionHint => 'Optional category description';

  @override
  String get categorySortOrderLabel => 'Display order';

  @override
  String get categorySortOrderHint => 'Sort number (lower appears first)';

  @override
  String get categorySortOrderRequired => 'Display order is required';

  @override
  String get categorySortOrderInvalidNumber => 'Please enter a valid number';

  @override
  String get categoryParentFieldLabel => 'Parent category';

  @override
  String get productCategoryFilterBrowseAll => 'All categories';

  @override
  String get productCategorySubcategoriesLabel => 'Subcategories';

  @override
  String get categoryPickerSearchEmpty => 'No categories found';

  @override
  String get categoryTreeAllCategoriesOption => 'All categories';

  @override
  String get noSettingsFound => 'No settings found';

  @override
  String get searchResults => 'Search Results';

  @override
  String searchResultCount(int count) {
    return '$count result';
  }

  @override
  String noSearchResults(String query) {
    return 'No results found for \"$query\"';
  }

  @override
  String get searchSettingsPlaceholder => 'Search settings...';

  @override
  String get noSettingsInCategory => 'No settings found in this category';

  @override
  String get settingsCategoryCoreConfiguration => 'Core & Configuration';

  @override
  String get settingsCategoryCoreConfigurationDescription =>
      'Basic system settings and configuration';

  @override
  String get settingsCategoryStorageFiles => 'Storage & Files';

  @override
  String get settingsCategoryStorageFilesDescription =>
      'File storage and storage plan management';

  @override
  String get settingsCategoryFinancialPayment => 'Financial & Payment';

  @override
  String get settingsCategoryFinancialPaymentDescription =>
      'Wallet and payment gateway settings';

  @override
  String get settingsCategoryUsersBusinesses => 'Users & Businesses';

  @override
  String get settingsCategoryUsersBusinessesDescription =>
      'User and business management';

  @override
  String get settingsCategoryCommunications => 'Communications';

  @override
  String get settingsCategoryCommunicationsDescription =>
      'Email, notifications and announcements';

  @override
  String get settingsCategoryAI => 'Artificial Intelligence';

  @override
  String get settingsCategoryAIDescription => 'AI settings, plans and prompts';

  @override
  String get settingsCategoryExternalServices => 'External Services';

  @override
  String get settingsCategoryExternalServicesDescription =>
      'External service integrations';

  @override
  String get settingsCategoryMonitoringLogs => 'Monitoring & Logs';

  @override
  String get settingsCategoryMonitoringLogsDescription =>
      'System monitoring and logging';

  @override
  String get settingsShareLinks => 'Share Links';

  @override
  String get settingsShareLinksDescription =>
      'Configure public share link destinations';

  @override
  String get personShareLinkActive => 'Active link';

  @override
  String get personShareCopyAndSendLink => 'Copy and share link';

  @override
  String get personShareRevokeLink => 'Revoke link';

  @override
  String get personShareRevoking => 'Revoking...';

  @override
  String get personShareRefreshStatus => 'Refresh status';

  @override
  String get personShareLinkHint =>
      'This short link is ready to share via SMS or social networks.';

  @override
  String get personShareStatus => 'Status';

  @override
  String get personShareExpiry => 'Expiry';

  @override
  String get personShareViews => 'Views';

  @override
  String get personShareLastView => 'Last view';

  @override
  String get personShareCreateNew => 'Create new link';

  @override
  String get personShareCreateWarning =>
      'Creating a new link will deactivate the previous one (if any).';

  @override
  String get personShareExpiryLabel => 'Link validity';

  @override
  String get personShareExpiry7Days => '7 days (default)';

  @override
  String get personShareExpiry14Days => '14 days';

  @override
  String get personShareExpiry30Days => '30 days';

  @override
  String get personShareExpiryNone => 'No expiry';

  @override
  String get personShareMaxViewsLabel => 'Max views allowed';

  @override
  String get personShareMaxViewsHint => '1–1000 or empty (unlimited). e.g. 5';

  @override
  String get personShareDocumentsLimit => 'Account card row count';

  @override
  String get personShareIncludeLedger => 'Show account card';

  @override
  String get personShareIncludeLedgerSubtitle =>
      'List of person account transactions';

  @override
  String get personShareIncludeInvoices => 'Show invoice list';

  @override
  String get personShareIncludeInvoicesSubtitle =>
      'Latest invoices for this person';

  @override
  String get personShareCreateButton => 'Create link';

  @override
  String get personShareCreateButtonNew => 'Create new link';

  @override
  String get personShareCreating => 'Creating...';

  @override
  String get personShareRefresh => 'Refresh';

  @override
  String get personShareValidationAtLeastOne =>
      'At least one of “Show account card” or “Show invoice list” must be enabled.';

  @override
  String get personSharePermissionHint =>
      'You need edit permission on people to create or revoke links.';

  @override
  String get personShareLinkCopied => 'Link copied to clipboard';

  @override
  String get personShareLinkCopiedAndShare =>
      'Link copied; you can share it via SMS or social networks.';

  @override
  String get personShareRetry => 'Retry';

  @override
  String get personShareNoExpiry => 'No expiry';

  @override
  String get personShareNotSet => 'Not set';

  @override
  String get personShareLinkCreated => 'Share link created successfully';

  @override
  String get personShareLinkRevoked => 'Share link revoked';

  @override
  String get personShareLinkCreateError => 'Failed to create link';

  @override
  String get personShareLinkRevokeError => 'Failed to revoke link';

  @override
  String get personShareSendLinkBySms => 'Send link via SMS';

  @override
  String get personShareSendingSms => 'Sending...';

  @override
  String get personShareNoMobileHint =>
      'Mobile number is not set for this customer.';

  @override
  String get personShareNoTemplateHint =>
      'No approved template found for account card link. Create and approve a template for the “Send account card link” event in Notification Templates.';

  @override
  String get personShareSmsSent => 'SMS sent successfully.';

  @override
  String get personShareCreateLinkFirst => 'Create a link first.';

  @override
  String get personShareSendToNumberLabel =>
      'Send to another number (optional)';

  @override
  String get personShareSendToNumberHint =>
      'Leave empty to use the number saved for this customer';

  @override
  String get settingsRedisCache => 'Redis Cache';

  @override
  String get settingsRedisCacheDescription =>
      'Configure Redis cache for improved performance';

  @override
  String get settingsFirewall => 'Application firewall';

  @override
  String get settingsFirewallDescription =>
      'IP allow/deny, per-path rate limits (database), temporary bans, logs and reports';

  @override
  String get firewallTabRules => 'Rules';

  @override
  String get firewallTabRatePolicies => 'Path rate limits';

  @override
  String get firewallTabBlockLogs => 'Blocked requests';

  @override
  String get firewallTabAudit => 'Audit log';

  @override
  String get firewallTabReports => 'Reports';

  @override
  String get firewallAddRatePolicy => 'Add rate policy';

  @override
  String get firewallEditRatePolicy => 'Edit rate policy';

  @override
  String get firewallRatePolicyPathRequired =>
      'Path prefix (e.g. /api/v1/public/crm-chat)';

  @override
  String get firewallRateMaxRequests => 'Max requests per window';

  @override
  String get firewallRateWindowSeconds => 'Window size (seconds)';

  @override
  String get firewallNoRatePolicies =>
      'No rate policies. Use this for per-IP limits on public API paths (e.g. web chat).';

  @override
  String get firewallDeleteRatePolicyTitle => 'Delete rate policy?';

  @override
  String get firewallDeleteRatePolicyBody =>
      'The rate limit for this path will be removed.';

  @override
  String get firewallEnabled => 'Enabled';

  @override
  String get firewallAddRule => 'Add rule';

  @override
  String get firewallEditRule => 'Edit rule';

  @override
  String get firewallActionLabel => 'Action';

  @override
  String get firewallActionAllow => 'Allow';

  @override
  String get firewallActionDeny => 'Deny';

  @override
  String get firewallIpCidr => 'IP or CIDR';

  @override
  String get firewallPathPrefixOptional => 'Path prefix (optional)';

  @override
  String get firewallHttpMethodsOptional =>
      'HTTP methods e.g. GET,POST (optional)';

  @override
  String get firewallPriority => 'Priority (lower = evaluated first)';

  @override
  String get firewallNoteOptional => 'Note (optional)';

  @override
  String get firewallSaved => 'Saved';

  @override
  String get firewallBanIp => 'Ban IP';

  @override
  String get firewallDurationMinutesHint =>
      'Duration in minutes (empty = permanent until removed)';

  @override
  String get firewallBanDone => 'Ban applied';

  @override
  String get firewallActiveOnlyFilter => 'Active rules only';

  @override
  String get firewallRefresh => 'Refresh';

  @override
  String get firewallNoRules => 'No rules';

  @override
  String get firewallDeleteConfirmTitle => 'Delete rule?';

  @override
  String get firewallDeleteConfirmBody => 'This cannot be undone.';

  @override
  String get firewallNoExpiry => 'No expiry';

  @override
  String get firewallFilterByIp => 'Filter by IP';

  @override
  String get firewallReportsPeriod => 'Period';

  @override
  String get firewallReportsDays => 'days';

  @override
  String get firewallReportsTotalBlocks => 'Blocked requests (period)';

  @override
  String get firewallReportsActiveDenyRules => 'Active deny rules';

  @override
  String get firewallReportsTopIps => 'Top blocked IPs';

  @override
  String get firewallReportsByDay => 'Blocks by day';

  @override
  String get settingsStoragePlans => 'Storage Plans';

  @override
  String get settingsStoragePlansDescription =>
      'Manage storage plans and pricing';

  @override
  String get settingsDocumentMonetization => 'Document Monetization';

  @override
  String get settingsDocumentMonetizationDescription =>
      'Manage document revenue scenarios and packages';

  @override
  String get settingsMarketplacePlugins => 'Marketplace Plugins Management';

  @override
  String get settingsMarketplacePluginsDescription =>
      'Manage plugins and plans for the marketplace';

  @override
  String get settingsWalletSettings => 'Wallet Settings';

  @override
  String get settingsWalletSettingsDescription =>
      'Set base currency and policies';

  @override
  String get settingsCurrenciesAdmin => 'Currency management';

  @override
  String get settingsCurrenciesAdminDescription =>
      'Decimal places, rounding, add or remove currencies';

  @override
  String get settingsPaymentGateways => 'Payment Gateways';

  @override
  String get settingsPaymentGatewaysDescription =>
      'Manage and configure payment gateways';

  @override
  String get settingsBusinessesManagement => 'Businesses Management';

  @override
  String get settingsBusinessesManagementDescription =>
      'View and manage all system businesses';

  @override
  String get settingsAnnouncements => 'Announcements';

  @override
  String get settingsAnnouncementsDescription =>
      'Create/edit/publish system announcements';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsNotificationsDescription =>
      'Enable/disable channels and send test messages';

  @override
  String get settingsNotificationTemplates => 'Notification Templates';

  @override
  String get settingsNotificationTemplatesDescription =>
      'Manage templates for channels and languages';

  @override
  String get settingsSupportOperators => 'Support operators';

  @override
  String get settingsSupportOperatorsDescription =>
      'Grant or revoke support operator access for users';

  @override
  String get settingsNotificationModeration =>
      'Notification template moderation';

  @override
  String get settingsNotificationModerationDescription =>
      'Approve or reject notification templates submitted by businesses';

  @override
  String get settingsNotificationSmsPricing => 'Notification SMS pricing';

  @override
  String get settingsNotificationSmsPricingDescription =>
      'Set the price per SMS for business notifications';

  @override
  String get settingsSystemScripts => 'System scripts';

  @override
  String get settingsSystemScriptsDescription =>
      'Run global corrective operations for all businesses';

  @override
  String get supportOperatorsPageTitle => 'Support operators';

  @override
  String get supportOperatorsRemoveOperatorTitle => 'Remove operator';

  @override
  String supportOperatorsRemoveOperatorConfirm(String email) {
    return 'Are you sure you want to revoke operator access for $email?';
  }

  @override
  String get supportOperatorsAccessRevokedSuccess =>
      'Operator access revoked successfully';

  @override
  String get supportOperatorsEmpty => 'No support operators found';

  @override
  String get supportOperatorsEmptyHint =>
      'To add an operator, use the User Management page.';

  @override
  String get supportOperatorsTelegramConnected => 'Telegram linked';

  @override
  String get supportOperatorsTelegramNotConnected => 'Not linked';

  @override
  String get supportOperatorsStatusInactive => 'Inactive';

  @override
  String get settingsAISettings => 'AI Settings';

  @override
  String get settingsAISettingsDescription =>
      'Configure Provider, model and API Key';

  @override
  String get settingsAIPlans => 'AI Plans';

  @override
  String get settingsAIPlansDescription => 'Manage AI usage plans and pricing';

  @override
  String get settingsAIPrompts => 'AI Prompts';

  @override
  String get settingsAIPromptsDescription =>
      'Manage default prompts for different roles';

  @override
  String get settingsZohalServices => 'Zohal Services';

  @override
  String get settingsZohalServicesDescription =>
      'Manage Zohal inquiry services and API settings';

  @override
  String get settingsZohalSettings => 'Zohal Settings';

  @override
  String get settingsZohalSettingsDescription =>
      'Set API Key and configure Zohal service';

  @override
  String get settingsTaxProductCodes => 'Tax Product Codes';

  @override
  String get settingsTaxProductCodesDescription =>
      'Search and import new list from XML file';

  @override
  String get settingsSystemMonitoring => 'System Monitoring';

  @override
  String get settingsSystemMonitoringDescription =>
      'Check system status, hardware resources and services';

  @override
  String get settingsServiceLogs => 'Service Logs';

  @override
  String get settingsServiceLogsDescription =>
      'View logs for hesabix-api, hesabix-rq-worker, and hesabix-notification-moderation and manage services';

  @override
  String get settingsBusinessActivityLogs => 'Business Activity Logs';

  @override
  String get settingsBusinessActivityLogsDescription =>
      'View activity logs across all businesses with filters by date, business, user, and action type';

  @override
  String get serviceLogsPauseAutoRefreshTooltip => 'Pause auto-refresh';

  @override
  String get serviceLogsResumeAutoRefreshTooltip => 'Resume auto-refresh';

  @override
  String get serviceLogsRefreshTooltip => 'Refresh';

  @override
  String get serviceLogsFollowTailOnTooltip =>
      'Follow latest log line is on; turn off to read older entries';

  @override
  String get serviceLogsFollowTailOffTooltip => 'Follow latest log line is off';

  @override
  String get serviceLogsLinesLabel => 'Line count';

  @override
  String get serviceLogsSearchHint => 'Search log text…';

  @override
  String get serviceLogsFilterAll => 'All';

  @override
  String get serviceLogsFilterErrors => 'Errors';

  @override
  String get serviceLogsFilterWarnings => 'Warn+';

  @override
  String get serviceLogsActive => 'Active';

  @override
  String get serviceLogsInactive => 'Inactive';

  @override
  String get serviceLogsEnabled => 'Enabled at boot';

  @override
  String get serviceLogsDisabled => 'Disabled at boot';

  @override
  String get serviceLogsRestart => 'Restart';

  @override
  String get serviceLogsRestartConfirmTitle => 'Confirm restart';

  @override
  String serviceLogsRestartConfirmBody(String serviceName) {
    return 'Service «$serviceName» may be briefly unavailable. Type the exact service name to continue.';
  }

  @override
  String get serviceLogsRestartTypeHint => 'Service name';

  @override
  String get serviceLogsStatusDetails => 'systemctl status details';

  @override
  String get serviceLogsNoStatusOutput => 'No status output available.';

  @override
  String get serviceLogsErrorTitle => 'Failed to load logs';

  @override
  String get serviceLogsRetry => 'Retry';

  @override
  String get serviceLogsEmpty => 'No log entries';

  @override
  String serviceLogsLogCount(int count) {
    return 'Log lines: $count';
  }

  @override
  String serviceLogsFilteredCount(int shown, int total) {
    return 'Showing $shown of $total';
  }

  @override
  String get serviceLogsLegendError => 'Error';

  @override
  String get serviceLogsLegendWarn => 'Warning';

  @override
  String get serviceLogsLegendInfo => 'Info';

  @override
  String serviceLogsFetchError(String error) {
    return 'Failed to fetch logs: $error';
  }

  @override
  String serviceLogsRestartError(String error) {
    return 'Restart failed: $error';
  }

  @override
  String get serviceLogsRestartSuccessDefault =>
      'Service restarted successfully';

  @override
  String get serviceLogsFollowTailChip => 'Follow tail';

  @override
  String get serviceLogsEmptyAllowedList =>
      'The server returned an empty allowed-service list.';

  @override
  String get serviceLogsNoFilterMatches =>
      'No lines match the current filters or search';

  @override
  String serviceLogsAllowedServicesFetchFailed(String error) {
    return 'Could not refresh the service list from the server; using defaults. $error';
  }

  @override
  String serviceLogsStatusLoadFailed(String error) {
    return 'Could not load service status: $error';
  }

  @override
  String get settingsDatabaseBackup => 'Database Backup';

  @override
  String get settingsDatabaseBackupDescription =>
      'Create full database backup and send to email, FTP or download directly';

  @override
  String get warranty => 'Warranty';

  @override
  String get warrantyManagement => 'Warranty Management';

  @override
  String get warrantySettings => 'Warranty Settings';

  @override
  String get warrantyCodes => 'Warranty Codes';

  @override
  String get warrantyCode => 'Warranty Code';

  @override
  String get warrantySerial => 'Warranty Serial';

  @override
  String get generateWarrantyCodes => 'Generate Warranty Codes';

  @override
  String get warrantyActivation => 'Warranty Activation';

  @override
  String get warrantyTracking => 'Warranty Tracking';

  @override
  String get warrantyStatus => 'Warranty Status';

  @override
  String get warrantyGenerated => 'Generated';

  @override
  String get warrantyActivated => 'Activated';

  @override
  String get warrantyExpired => 'This warranty has expired';

  @override
  String get warrantyUsed => 'Used';

  @override
  String get warrantyRevoked => 'This warranty has been revoked';

  @override
  String get warrantyDuration => 'Warranty Duration';

  @override
  String get warrantyDurationDays => 'Warranty Duration (Days)';

  @override
  String get warrantyExpiresAt => 'Expires At';

  @override
  String get warrantyGeneratedAt => 'Generated At';

  @override
  String get warrantyActivatedAt => 'Activated At';

  @override
  String get warrantyProduct => 'Warranty Product';

  @override
  String get warrantyCustomer => 'Customer';

  @override
  String get warrantyCustomerName => 'Customer Name';

  @override
  String get warrantyCustomerPhone => 'Customer Phone';

  @override
  String get warrantyCustomerEmail => 'Customer Email';

  @override
  String get warrantyProductSerial => 'Product Serial';

  @override
  String get activateWarranty => 'Activate Warranty';

  @override
  String get trackWarranty => 'Track Warranty';

  @override
  String get warrantyTrackingLink => 'Warranty Tracking Link';

  @override
  String get warrantyCodeFormat => 'Code Format';

  @override
  String get warrantyCodePrefix => 'Code Prefix';

  @override
  String get warrantySerialFormat => 'Serial Format';

  @override
  String get warrantySerialLength => 'Serial Length';

  @override
  String get warrantyRandom => 'Random';

  @override
  String get warrantySequential => 'Sequential';

  @override
  String get warrantyCustom => 'Custom';

  @override
  String get warrantySecuritySettings => 'Security Settings';

  @override
  String get warrantyRequireSerialVerification =>
      'Require Product Serial Verification';

  @override
  String get warrantyRequireProductInstanceMatch =>
      'Require Product Instance Match';

  @override
  String get warrantyMaxActivationAttempts => 'Max Activation Attempts';

  @override
  String get warrantyActivationLockoutDuration => 'Lockout Duration (Minutes)';

  @override
  String get warrantyAutoLinkToPerson => 'Auto Link to Person';

  @override
  String get warrantyEnableTrackingLink => 'Enable Tracking Link';

  @override
  String get warrantyTrackingLinkExpiresDays => 'Tracking Link Expires (Days)';

  @override
  String get warrantyEnableSmsNotification => 'Send SMS on Activation';

  @override
  String get warrantyEnableEmailNotification => 'Send Email on Activation';

  @override
  String get warrantyCodeNotFound => 'Warranty code not found';

  @override
  String get warrantyInvalidSerial => 'Invalid warranty serial';

  @override
  String get warrantyAlreadyActivated =>
      'This warranty has already been activated';

  @override
  String get warrantyActivationSuccess => 'Warranty activated successfully';

  @override
  String get warrantyActivationFailed => 'Warranty activation failed';

  @override
  String get warrantyTooManyAttempts => 'Too many activation attempts';

  @override
  String get warrantyProductSerialRequired => 'Product serial is required';

  @override
  String get warrantyProductSerialNotFound => 'Product serial not found';

  @override
  String get warrantyLinkNotFound => 'Tracking link not found';

  @override
  String get warrantyLinkExpired => 'Tracking link has expired';

  @override
  String get warrantyLinkInactive => 'Tracking link is inactive';

  @override
  String get warrantyPluginNotActive =>
      'Warranty plugin is not active for this business';

  @override
  String get warrantyGenerateCodes => 'Generate Warranty Codes';

  @override
  String get warrantyQuantity => 'Quantity';

  @override
  String get warrantyCustomSerials => 'Custom Serials';

  @override
  String get warrantyCustomCodes => 'Custom Codes';

  @override
  String get warrantyListCodes => 'List Warranty Codes';

  @override
  String get warrantyFilterByStatus => 'Filter by Status';

  @override
  String get warrantyFilterByProduct => 'Filter by Product';

  @override
  String get warrantyEvents => 'Warranty Events';

  @override
  String get warrantyEventActivation => 'Activation';

  @override
  String get warrantyEventRepairRequest => 'Repair Request';

  @override
  String get warrantyEventRepairCompleted => 'Repair Completed';

  @override
  String get warrantyEventReplacement => 'Replacement';

  @override
  String get warrantyEventExpired => 'Expired';

  @override
  String get warrantyEventRevoked => 'Revoked';

  @override
  String get warrantyManage => 'Manage Warranty';

  @override
  String get customerClubTitle => 'Customer Club';

  @override
  String get customerClubMenu => 'Customer Club';

  @override
  String get customerClubTabLedger => 'Transactions';

  @override
  String get customerClubTabSettings => 'Settings';

  @override
  String get customerClubTabAdjust => 'Adjust Points';

  @override
  String get customerClubLedgerTotal => 'Transactions count';

  @override
  String get customerClubLoadMore => 'Load more';

  @override
  String get customerClubBalanceAfter => 'Balance after';

  @override
  String get customerClubPerson => 'Person';

  @override
  String get customerClubEnabled => 'Enable loyalty program';

  @override
  String get customerClubEarnMode => 'Earning rule';

  @override
  String get customerClubEarnPercent => 'Percentage of basis amount';

  @override
  String get customerClubEarnPerCurrency => 'Points per currency bracket';

  @override
  String get customerClubAmountBasis => 'Invoice amount basis';

  @override
  String get customerClubBasisNet => 'Net excluding tax';

  @override
  String get customerClubBasisTotal => 'Total including tax';

  @override
  String get customerClubPercentOfBasis => 'Percent of basis';

  @override
  String get customerClubPercentHint => 'Example: 1 means 1% of basis amount';

  @override
  String get customerClubStepAmount => 'Bracket amount (currency)';

  @override
  String get customerClubPointsPerStep => 'Points per bracket';

  @override
  String get customerClubRounding => 'Rounding mode';

  @override
  String get customerClubMaxPointsInvoice =>
      'Max points per invoice (optional)';

  @override
  String get customerClubMinBasis => 'Minimum basis amount to earn points';

  @override
  String get customerClubRedemptionSection => 'Redemption & expiry';

  @override
  String get customerClubCurrencyValuePerPoint =>
      'Discount amount per loyalty point (invoice currency)';

  @override
  String get customerClubCurrencyValuePerPointHint =>
      'How much invoice discount one point buys, in invoice currency.';

  @override
  String get customerClubMaxRedeemPerInvoice =>
      'Maximum points redeemable per sales invoice (optional)';

  @override
  String get customerClubPointsExpireAfterDays =>
      'Points validity from grant date (days)';

  @override
  String get customerClubPointsExpireAfterDaysHint =>
      'Leave empty so points never expire.';

  @override
  String get customerClubRequireCustomerType =>
      'Only contacts marked as Customer';

  @override
  String get customerClubSettingsSaved => 'Club settings saved.';

  @override
  String get customerClubInvalidPersonId => 'Invalid person id.';

  @override
  String get customerClubInvalidDelta => 'Invalid delta points.';

  @override
  String get customerClubDescriptionRequired => 'Description is required.';

  @override
  String get customerClubAdjustmentSaved => 'Adjustment recorded.';

  @override
  String get customerClubNoAdjustPermission =>
      'You cannot perform manual adjustments.';

  @override
  String get customerClubAdjustIntro =>
      'Increase or decrease points manually. Delta may be negative.';

  @override
  String get customerClubPersonId => 'Person ID';

  @override
  String get customerClubDeltaPoints => 'Delta points (+/-)';

  @override
  String get customerClubSubmitAdjustment => 'Submit adjustment';

  @override
  String get customerClubSettingsSubtitle =>
      'Points rules, transactions and manual balances';

  @override
  String get customerClubRoundingFloor => 'Round down (floor)';

  @override
  String get customerClubRoundingCeil => 'Round up (ceil)';

  @override
  String get customerClubRoundingRound => 'Round to nearest';

  @override
  String get customerClubReferenceDocument => 'Document';

  @override
  String get customerClubPointsShort => 'pts';

  @override
  String get customerClubTxnAdjustment => 'Manual adjustment';

  @override
  String get customerClubTxnRedeem => 'Points redemption';

  @override
  String get customerClubTxnRedeemVoid => 'Redemption reversal';

  @override
  String get customerClubTxnInvoiceSync => 'Invoice points sync';

  @override
  String get customerClubTxnInvoiceDeleteReversal =>
      'Invoice deleted — points reversal';

  @override
  String get customerClubTxnInvoiceDeleteReversalRedeem =>
      'Invoice deleted — redemption reversal';

  @override
  String customerClubPermissionManageSettings(String title) {
    return 'Manage club settings ($title)';
  }

  @override
  String customerClubPermissionAdjustManual(String title) {
    return 'Manual points adjustment ($title)';
  }

  @override
  String customerClubPermissionRedeemInvoice(String title) {
    return 'Redeem points on sales invoice ($title)';
  }

  @override
  String get customerClubActionAdjust => 'Adjust';

  @override
  String get customerClubActionRedeem => 'Redeem';

  @override
  String get customerClubLedgerEmpty => 'No loyalty transactions yet.';

  @override
  String customerClubLedgerShowingCount(int shown, int total) {
    return 'Showing $shown of $total';
  }

  @override
  String get customerClubSettingsSectionActivation => 'Activation';

  @override
  String get customerClubSettingsSectionEarning => 'Earning rules';

  @override
  String get customerClubSettingsSectionAccess => 'Person role restriction';

  @override
  String get customerClubSettingsSummaryTitle => 'Saved rules summary';

  @override
  String get customerClubLedgerFilterPerson => 'Filter transactions by person';

  @override
  String get customerClubCurrentPointsBalance =>
      'Current points balance for this person';

  @override
  String get customerClubViewLedgerAction => 'Transactions';

  @override
  String get customerClubAdjustmentLargeDeltaTitle =>
      'Confirm large adjustment';

  @override
  String customerClubAdjustmentLargeDeltaBody(String delta) {
    return 'Delta is $delta points. Continue?';
  }

  @override
  String get customerClubSummaryInactive =>
      'Customer club is disabled for this business.';

  @override
  String get customerClubTabAnalytics => 'RFM / CLV analytics';

  @override
  String get customerClubAnalyticsTitle => 'Customer analytics & segments';

  @override
  String get customerClubAnalyticsRecalculate => 'Recalculate';

  @override
  String get customerClubAnalyticsRecalculating => 'Calculating…';

  @override
  String get customerClubAnalyticsNoData =>
      'No data yet. Enable RFM or CLV in settings, then tap Recalculate.';

  @override
  String get customerClubAnalyticsDisabled =>
      'Enable “RFM analytics” and/or “CLV” in customer club settings to use this tab.';

  @override
  String customerClubAnalyticsWindow(String start, String end, int months) {
    return 'Window: $start to $end ($months mo)';
  }

  @override
  String get customerClubAnalyticsTotalPersons => 'Customers in report';

  @override
  String get customerClubAnalyticsLastRun => 'Last computed';

  @override
  String get customerClubAnalyticsSearch => 'Search name, company or code';

  @override
  String get customerClubAnalyticsFilterSegment => 'Segment';

  @override
  String get customerClubAnalyticsAllSegments => 'All';

  @override
  String get customerClubAnalyticsR => 'R (recency)';

  @override
  String get customerClubAnalyticsF => 'F (frequency)';

  @override
  String get customerClubAnalyticsM => 'M (monetary)';

  @override
  String get customerClubAnalyticsCell => 'RFM cell';

  @override
  String get customerClubAnalyticsCLV => 'CLV';

  @override
  String get customerClubAnalyticsMonetary => 'Amount (window)';

  @override
  String get customerClubAnalyticsRecency => 'Days since last purchase';

  @override
  String get customerClubAnalyticsFrequency => 'Purchase count';

  @override
  String get customerClubAnalyticsSegment => 'Segment';

  @override
  String get customerClubAnalyticsLoyaltyBalance => 'Points balance';

  @override
  String get customerClubCompositeScore => 'Composite score';

  @override
  String get customerClubAnalyticsRefresh => 'Refresh';

  @override
  String get customerClubAnalyticsLoadMore => 'Load more';

  @override
  String get customerClubAnalyticsSortLabel => 'Sort by';

  @override
  String get customerClubAnalyticsSortMonetary => 'Monetary';

  @override
  String get customerClubAnalyticsSortRecency => 'Recency';

  @override
  String get customerClubAnalyticsSortFrequency => 'Frequency';

  @override
  String get customerClubAnalyticsSortClv => 'CLV';

  @override
  String get customerClubAnalyticsSortSegment => 'Segment';

  @override
  String get customerClubAnalyticsSortComposite => 'Composite';

  @override
  String get customerClubAnalyticsRecalculateDone => 'Recalculation completed.';

  @override
  String get customerClubSettingsSectionAnalytics =>
      'RFM & customer lifetime value (CLV)';

  @override
  String get customerClubRfmEnabled =>
      'Enable RFM analytics (recency, frequency, monetary)';

  @override
  String get customerClubClvEnabled =>
      'Enable customer lifetime value (CLV) estimate';

  @override
  String get customerClubRfmWindowMonths => 'Analysis window length (months)';

  @override
  String get customerClubRfmMonetaryBasisLabel => 'Monetary basis for M';

  @override
  String get customerClubRfmScoringLabel => 'Scoring method';

  @override
  String get customerClubRfmScoringQuintiles => 'Quintiles (classic)';

  @override
  String get customerClubRfmScoringWeighted => 'Weighted composite';

  @override
  String get customerClubRfmWeightR => 'Weight — recency (R)';

  @override
  String get customerClubRfmWeightF => 'Weight — frequency (F)';

  @override
  String get customerClubRfmWeightM => 'Weight — monetary (M)';

  @override
  String get customerClubClvFormulaLabel => 'CLV formula';

  @override
  String get customerClubClvFormulaHistorical => 'Sum of purchases in window';

  @override
  String get customerClubClvFormulaProjection =>
      'Avg order × annual frequency × lifespan';

  @override
  String get customerClubClvLifespanYears =>
      'Estimated customer lifespan (years) — for projection';

  @override
  String get customerClubAnalyticsHint =>
      'After changing settings, run Recalculate from the analytics tab.';

  @override
  String get customerClubSettingsSectionLoyaltyRfm => 'Loyalty points vs RFM';

  @override
  String get customerClubLoyaltyRfmMode => 'Integration mode';

  @override
  String get customerClubLoyaltyRfmDecoupled =>
      'Separate: points from invoices; tiers use point balance';

  @override
  String get customerClubLoyaltyRfmTiers =>
      'Tier multipliers follow RFM score (requires RFM analytics on)';

  @override
  String get customerClubLoyaltyRfmHint =>
      'In RFM tier mode, set each tier’s min RFM score (0–1) via the tiers API field min_rfm_normalized, or rely on min_balance_points÷10000 as a fallback. Redemption still uses invoice-earned balance.';

  @override
  String get customerClubAnalyticsSegmentsTitle => 'Segments';

  @override
  String get customerClubAnalyticsCampaignExport => 'Campaign export';

  @override
  String get customerClubAnalyticsCampaignTitle =>
      'Audience list for campaigns';

  @override
  String get customerClubAnalyticsCampaignBody =>
      'Person IDs for the current filters (segment + search). Paste into your SMS/email tool.';

  @override
  String get customerClubAnalyticsCampaignCopyIds => 'Copy IDs';

  @override
  String customerClubAnalyticsCampaignTruncated(int n) {
    return 'Only $n IDs returned; increase the API limit to fetch more.';
  }

  @override
  String get customerClubAnalyticsRfmNormalized => 'RFM normalized score (0–1)';

  @override
  String get customerClubSortAsc => 'Ascending';

  @override
  String get customerClubSortDesc => 'Descending';

  @override
  String get identityInquiryTitle => 'Identity Inquiry';

  @override
  String get identityInquirySubtitle =>
      'Please enter national ID and birth date';

  @override
  String get nationalIdHint => '10-digit national ID';

  @override
  String get nationalIdRequired => 'National ID is required';

  @override
  String get nationalIdInvalidLength => 'National ID must be 10 digits';

  @override
  String get nationalIdInvalid => 'Invalid national ID';

  @override
  String get birthDate => 'Birth Date';

  @override
  String get birthDateHint => 'Jalali date (YYYY-MM-DD or YYYY/MM/DD)';

  @override
  String get birthDateRequired => 'Birth date is required';

  @override
  String get birthDateInvalid => 'Invalid date format';

  @override
  String get selectBirthDate => 'Select Date';

  @override
  String get inquire => 'Inquire';

  @override
  String get inquiring => 'Inquiring...';

  @override
  String get inquiryError => 'Inquiry Error';

  @override
  String get inquiryErrorPrefix => 'Inquiry error:';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get noMatch => 'No Match';

  @override
  String get noMatchDescription => 'National ID and birth date do not match';

  @override
  String get personalInformation => 'Personal Information';

  @override
  String get fatherName => 'Father Name';

  @override
  String get alive => 'Alive';

  @override
  String get deceased => 'Deceased';

  @override
  String get newInquiry => 'New Inquiry';

  @override
  String get identityInquiryDescription =>
      'You can inquiry personal identity information by entering national ID and birth date';

  @override
  String get noResultAvailable => 'Error: No result available';

  @override
  String get accountSettingsTitle => 'Account Settings';

  @override
  String get accountSettingsSubtitle =>
      'Manage and configure all aspects of your account';

  @override
  String get accountSettingsMarketingDescription =>
      'Manage referral links and marketing reports';

  @override
  String get accountSettingsNotificationsTitle => 'Notifications';

  @override
  String get accountSettingsNotificationsDescription =>
      'Notification channel settings and configuration';

  @override
  String get accountSettingsSignatureTitle => 'Signature & Profile Picture';

  @override
  String get accountSettingsSignatureDescription =>
      'Upload and manage personal signature and profile picture';

  @override
  String get accountSettingsApiKeysTitle => 'API Keys';

  @override
  String get accountSettingsApiKeysDescription =>
      'Manage API keys for system access';

  @override
  String get accountSettingsLoginSessionsTitle => 'Login Sessions';

  @override
  String get accountSettingsLoginSessionsDescription =>
      'View and manage connected devices to your account';

  @override
  String get accountSettingsChangePasswordDescription =>
      'Change account password';

  @override
  String get accountSettingsVerificationTitle => 'Mobile & Email Verification';

  @override
  String get accountSettingsVerificationDescription =>
      'Verify mobile number and email for enhanced security';

  @override
  String get accountSettingsNotificationHistoryTitle => 'Notification History';

  @override
  String get accountSettingsNotificationHistoryDescription =>
      'View all sent notifications (OTP, password reset, tickets, etc.)';

  @override
  String get notificationCenterLevelInfo => 'Info';

  @override
  String get notificationCenterLevelWarning => 'Warning';

  @override
  String get notificationCenterLevelCritical => 'Critical';

  @override
  String notificationCenterLevelUnknown(String level) {
    return '$level';
  }

  @override
  String get notificationCenterClearAllTooltip =>
      'Clear in-app notifications from your inbox';

  @override
  String get notificationCenterClearAllTitle => 'Clear notifications?';

  @override
  String get notificationCenterClearAllMessage =>
      'All visible announcements will be hidden. Live-only messages (not stored on the server) will also be removed from this list.';

  @override
  String get notificationCenterClearAllConfirm => 'Clear';

  @override
  String get notificationCenterClearAllCancel => 'Cancel';

  @override
  String get notificationCenterCleared => 'Notifications cleared';

  @override
  String get notificationsInappRetentionTitle =>
      'In-app announcement retention';

  @override
  String get notificationsInappRetentionSubtitle =>
      'System announcements you have read will be automatically removed or hidden after the number of days you set.';

  @override
  String get notificationsInappRetentionEnabled =>
      'Enable automatic cleanup of read items';

  @override
  String get notificationsInappRetentionDays =>
      'Days after read before cleanup';

  @override
  String get apiKeysPageTitle => 'Manage API Keys';

  @override
  String get apiKeyErrorLoadingKeys => 'Error loading keys';

  @override
  String get apiKeyErrorCreatingKey => 'Error creating key';

  @override
  String get apiKeyCreatedSuccessfully => 'API Key created';

  @override
  String get apiKeySaveWarning =>
      'Please save this key. This is the only time it will be displayed.';

  @override
  String get apiKeyClose => 'Close';

  @override
  String get apiKeyCopy => 'Copy';

  @override
  String get apiKeyCopied => 'Key copied';

  @override
  String get apiKeyUpdatedSuccessfully => 'Key updated successfully';

  @override
  String get apiKeyErrorUpdating => 'Error updating key';

  @override
  String get apiKeyDeleteTitle => 'Delete API Key';

  @override
  String apiKeyDeleteConfirmation(String name) {
    return 'Are you sure you want to delete the key \"$name\"?\nThis action is irreversible.';
  }

  @override
  String get apiKeyDeletedSuccessfully => 'Key deleted successfully';

  @override
  String get apiKeyErrorDeleting => 'Error deleting key';

  @override
  String get apiKeyFilterActive => 'Active';

  @override
  String get apiKeyFilterRevoked => 'Revoked';

  @override
  String get apiKeyFilterAll => 'All';

  @override
  String get apiKeyNoActiveKeys => 'No active keys';

  @override
  String get apiKeyNoRevokedKeys => 'No revoked keys';

  @override
  String get apiKeyNoKeysCreated => 'No API keys created';

  @override
  String get apiKeyCreateNewButton => 'Create New Key';

  @override
  String get apiKeyCreateHint => 'Click the create button to create a new key';

  @override
  String get apiKeyNoRevokedHint => 'No revoked keys to display';

  @override
  String get apiKeyUsageHint =>
      'Create a key to use the API in other applications';

  @override
  String get apiKeyEdit => 'Edit';

  @override
  String get apiKeyDelete => 'Delete';

  @override
  String get apiKeyCreatedAt => 'Created';

  @override
  String get apiKeyLastUsed => 'Last Used';

  @override
  String get apiKeyExpiresAt => 'Expires';

  @override
  String get apiKeyRevokedAt => 'Revoked';

  @override
  String get apiKeyAllowedIPs => 'Allowed IPs';

  @override
  String get apiKeyCreateNewTitle => 'Create New API Key';

  @override
  String get apiKeyNameLabel => 'Key Name';

  @override
  String get apiKeyNameHint => 'Example: Production API Key';

  @override
  String get apiKeyScopeLabel => 'Access Scope (JSON)';

  @override
  String get apiKeyScopeHint =>
      'Optional - Example: {\"read\": true, \"write\": false}';

  @override
  String get apiKeyIPsLabel => 'Allowed IP List';

  @override
  String get apiKeyIPsHint =>
      'Comma separated - Example: 192.168.1.1, 10.0.0.1';

  @override
  String get apiKeyExpiryLabel => 'Expiry Date and Time (Optional)';

  @override
  String get apiKeyExpiryHint => 'Select';

  @override
  String get apiKeyNoExpiry => 'No expiry';

  @override
  String get apiKeyEditTitle => 'Edit API Key';

  @override
  String get apiKeyWithoutName => 'Unnamed';

  @override
  String get datePickerSelectDate => 'Select Date';

  @override
  String get dateInputInvalidFormat =>
      'Enter a valid date in YYYY/MM/DD format';

  @override
  String get dateInputOutOfRange => 'Date is outside the allowed range';

  @override
  String get dateInputOpenCalendar => 'Open calendar';

  @override
  String get timePickerSelectTime => 'Select Time';

  @override
  String get dateTimeLabel => 'Date and Time';

  @override
  String get dateLabel => 'Date';

  @override
  String get timeLabel => 'Time';

  @override
  String get clearButton => 'Clear';

  @override
  String get sessionsPageTitle => 'Manage Login Sessions';

  @override
  String get sessionsErrorLoading => 'Error loading sessions';

  @override
  String get sessionsCannotDeleteCurrent => 'Cannot delete current session';

  @override
  String get sessionsDeleteTitle => 'Delete Session';

  @override
  String sessionsDeleteConfirmation(String device) {
    return 'Are you sure you want to delete session \"$device\"?\nThis action is irreversible.';
  }

  @override
  String get sessionsDeletedSuccessfully => 'Session deleted successfully';

  @override
  String get sessionsErrorDeleting => 'Error deleting session';

  @override
  String get sessionsNoOtherSessions => 'No other sessions';

  @override
  String get sessionsRevokeAllTitle => 'Logout from all devices';

  @override
  String sessionsRevokeAllConfirmation(int count) {
    return 'Are you sure you want to delete $count other sessions?\nThis will logout all other devices.\nYour current session will be preserved.';
  }

  @override
  String get sessionsDeleteAll => 'Delete All';

  @override
  String sessionsDeleted(int count) {
    return '$count sessions deleted';
  }

  @override
  String get sessionsNoActive => 'No active sessions';

  @override
  String get sessionsThisDevice => 'This Device';

  @override
  String get sessionsLastUsed => 'Last Used';

  @override
  String get sessionsCreatedAt => 'Created';

  @override
  String get sessionsToday => 'Today';

  @override
  String get sessionsYesterday => 'Yesterday';

  @override
  String sessionsDaysAgo(int days) {
    return '$days days ago';
  }

  @override
  String sessionsWeeksAgo(int weeks) {
    return '$weeks weeks ago';
  }

  @override
  String sessionsMonthsAgo(int months) {
    return '$months months ago';
  }

  @override
  String get invoiceWarehouseReleaseNone => 'No warehouse document';

  @override
  String get invoiceWarehouseReleaseDraft => 'Warehouse draft';

  @override
  String get invoiceWarehouseReleasePosted => 'Post warehouse immediately';

  @override
  String get invoiceWarehouseReleaseSectionTitle =>
      'Warehouse document after save';

  @override
  String get invoiceWarehouseReleaseSectionSubtitle =>
      'Uses your business default; changes are saved per invoice type in this browser.';

  @override
  String get invoiceWarehouseReleaseBusinessTitle =>
      'Warehouse document after invoice save';

  @override
  String get invoiceWarehouseReleaseBusinessSubtitle =>
      'When post_inventory / auto_post_warehouse are omitted (or null) in the API, this mode applies.';

  @override
  String get invoiceWarehouseReleaseStockHint =>
      'With “post immediately”, the warehouse document is posted when the invoice is saved and the same shortage / negative-stock rules from the section below apply. Draft keeps it until you post manually.';

  @override
  String get ftpBackupSettingsTitle => 'FTP backup destination';

  @override
  String get ftpBackupSettingsDescription =>
      'Store connection details for optional backup upload to your FTP server.';

  @override
  String get ftpPasswordLeaveEmptyHint =>
      'Leave empty to keep the current password';

  @override
  String get ftpRemotePath => 'Remote folder';

  @override
  String get ftpPassiveMode => 'Passive mode (PASV)';

  @override
  String get ftpUseFtps => 'Use FTPS (FTP over TLS)';

  @override
  String get ftpSaveSettings => 'Save';

  @override
  String get ftpDeleteSettings => 'Remove FTP settings';

  @override
  String get ftpTestConnection => 'Test connection';

  @override
  String get ftpScanUsage => 'Scan folder usage';

  @override
  String get ftpUsageTotal => 'Total size (this folder)';

  @override
  String get ftpUsageFiles => 'Files counted';

  @override
  String get ftpUsageTruncated => 'Scan stopped early (too many files)';

  @override
  String get ftpLastScan => 'Last scan';

  @override
  String get ftpSettingsUpdatedAt => 'Settings last saved';

  @override
  String get ftpNotConfigured => 'Not configured';

  @override
  String get ftpUseSftp => 'Use SFTP (SSH)';

  @override
  String get ftpInsecureWarning =>
      'Without FTPS or SFTP, credentials and data can be read on the network. Enable FTPS or SFTP when possible.';

  @override
  String get ftpDeleteSettingsConfirmTitle => 'Remove backup destination';

  @override
  String get ftpDeleteSettingsConfirmMessage =>
      'Remove FTP/SFTP settings for this business? Automatic upload after backup will stop.';

  @override
  String ftpTestResultSampleCount(int count) {
    return 'Directory listing sample: about $count entries';
  }

  @override
  String get backupFtpUploaded => 'Copy on your server';

  @override
  String get backupFtpNotUploaded => 'Not sent to FTP';

  @override
  String get backupOpenFtpSettings => 'FTP settings';

  @override
  String get backupFtpNotConfiguredError =>
      'Save an FTP/SFTP destination in settings first.';

  @override
  String get ftpSendAfterBackup => 'Also upload to FTP after backup';

  @override
  String get ftpSendAfterBackupSubtitle =>
      'Requires saved FTP settings and permission';

  @override
  String get jobUploadingToFtp => 'Uploading to FTP';

  @override
  String get jobFtpTestStarting => 'FTP test starting';

  @override
  String get jobFtpTestRunning => 'Running FTP checks';

  @override
  String get jobFtpTestCompleted => 'FTP test completed';

  @override
  String get jobFtpTestFailed => 'FTP test failed';

  @override
  String get jobFtpUsageStarting => 'Scanning FTP usage';

  @override
  String get jobFtpUsageConnecting => 'Connecting to FTP';

  @override
  String get jobFtpUsageScanning => 'Scanning remote folders';

  @override
  String get jobFtpUsageCompleted => 'FTP usage scan completed';

  @override
  String get jobFtpUsageFailed => 'FTP usage scan failed';

  @override
  String get ftpTestResultTitle => 'Connection test';

  @override
  String get ftpClose => 'Close';

  @override
  String get settingsPermissionManageFtp => 'FTP backup connection';

  @override
  String get crmMenuNotesCalendar => 'Notes & calendar';

  @override
  String get crmNotesCalendarTitle => 'CRM notes & calendar';

  @override
  String get crmNotesRefresh => 'Refresh';

  @override
  String get crmNotesAdd => 'New note';

  @override
  String get crmNotesMonthPrev => 'Previous month';

  @override
  String get crmNotesMonthNext => 'Next month';

  @override
  String get crmNotesToday => 'Today';

  @override
  String get crmNotesViewWeek => 'Week';

  @override
  String get crmNotesViewMonth => 'Month';

  @override
  String get crmNotesWeekPrev => 'Previous week';

  @override
  String get crmNotesWeekNext => 'Next week';

  @override
  String get crmNotesMonthCalendarExpandTitle => 'Full month calendar';

  @override
  String get crmNotesPickDayTooltip => 'Choose day';

  @override
  String get crmNotesDayNotes => 'Notes for this day';

  @override
  String get crmNotesNoNotes => 'No notes';

  @override
  String get crmNotesEmptyDayHint =>
      'No notes for this day yet. Add one to keep your CRM timeline up to date.';

  @override
  String get crmNotesRetry => 'Try again';

  @override
  String get crmNotesEditorMoreOptions => 'More options';

  @override
  String get crmNotesVisibilityLabel => 'Who can see this note';

  @override
  String get crmNotesVisibilityPrivate => 'Private (only me)';

  @override
  String get crmNotesVisibilityBusiness => 'Everyone in this business';

  @override
  String get crmNotesVisibilityShared => 'Selected people';

  @override
  String get crmNotesType => 'Note type';

  @override
  String get crmNotesTitleOptional => 'Title (optional)';

  @override
  String get crmNotesBody => 'Content';

  @override
  String get crmNotesLeadOptional => 'Lead (optional)';

  @override
  String get crmNotesClearLead => 'Clear lead';

  @override
  String get crmNotesSharedUsers => 'People who can see this note';

  @override
  String get crmNotesMeetingStart => 'Start';

  @override
  String get crmNotesMeetingEnd => 'End (optional)';

  @override
  String get crmNotesSave => 'Save';

  @override
  String get crmNotesDelete => 'Delete';

  @override
  String get crmNotesComments => 'Comments';

  @override
  String get crmNotesNoComments => 'No comments yet';

  @override
  String get crmNotesCommentHint => 'Write a comment…';

  @override
  String get crmNotesSendComment => 'Send';

  @override
  String get crmNotesAudit => 'Change history';

  @override
  String get crmNotesAuditEmpty => 'No history entries yet.';

  @override
  String get crmNotesClose => 'Close';

  @override
  String get crmNotesEdit => 'Edit';

  @override
  String get crmNotesSearchLeads => 'Search leads';

  @override
  String get crmNotesApplySearch => 'Search';

  @override
  String get crmNotesErrorLoading => 'Failed to load';

  @override
  String get crmNotesErrorSaving => 'Failed to save';

  @override
  String get crmNotesAddNoteType => 'New note type';

  @override
  String get crmNotesNoteTypeCode => 'Code (Latin, e.g. follow_up)';

  @override
  String get crmNotesNoteTypeTitleFa => 'Title (Persian)';

  @override
  String get crmNotesNoteTypeTitleEn => 'Title (English)';

  @override
  String get crmNotesNoteTypeScheduling => 'Scheduling';

  @override
  String get crmNotesNoteTypeDayOnly => 'Date only';

  @override
  String get crmNotesNoteTypeMeeting => 'Meeting (date & time)';

  @override
  String get crmNotesNoteTypeAllowComments =>
      'Allow comments (for public notes)';

  @override
  String get crmNotesNoteTypeAllowCommentsHint =>
      'Only affects notes that are visible to the business (public notes).';

  @override
  String get crmNotesNoteTypeCreated => 'Note type created';

  @override
  String get crmNotesPickDateTime => 'Pick date & time';

  @override
  String get crmNotesDeleteConfirmMessage =>
      'This note will be removed. Continue?';

  @override
  String get crmNotesDeleteConfirmTitle => 'Delete note';

  @override
  String get crmNotesDeleteWarnComments =>
      'Existing comments will also be removed.';

  @override
  String get crmNoteTabDetails => 'Details';

  @override
  String get crmNoteTabComments => 'Discussion';

  @override
  String get crmNoteTabAudit => 'History';

  @override
  String get crmNotesVisibilityShortPrivate => 'Private';

  @override
  String get crmNotesVisibilityShortBusiness => 'Team';

  @override
  String get crmNotesVisibilityShortShared => 'Selected';

  @override
  String get crmNotesVisibilityHintPrivate => 'Only you can see this note.';

  @override
  String get crmNotesVisibilityHintBusiness =>
      'All members of this business who can access CRM.';

  @override
  String get crmNotesVisibilityHintShared =>
      'Only you and the people you select.';

  @override
  String get crmNotesSharedPickHint =>
      'Select at least one teammate (you are always included).';

  @override
  String get crmNotesEventDateButton => 'Choose date';

  @override
  String get crmNotesNoLeadsFound => 'No leads match your search.';

  @override
  String get crmNotesLeadSearchInDialogHint =>
      'Type name, code, phone, or email…';

  @override
  String get crmNotesCommentsDisabledTab =>
      'Comments are disabled for this note type or visibility.';

  @override
  String get crmNotesNoteTypeCodeHelper =>
      'Latin letters, numbers, and underscore only. Used internally.';

  @override
  String get crmNotesNoteTypePreview => 'Preview in current language';

  @override
  String get crmNotesNoteTypeSectionIdentity => 'Identity';

  @override
  String get crmNotesNoteTypeSectionTitles => 'Titles';

  @override
  String get crmNotesNoteTypeSectionBehavior => 'Behavior';

  @override
  String get crmNotesCommentInputLabel => 'New comment';

  @override
  String crmNotesAuditRecentLimit(int count) {
    return 'Showing the latest $count entries';
  }

  @override
  String get crmNoteAuditCreated => 'Created';

  @override
  String get crmNoteAuditUpdated => 'Updated';

  @override
  String get crmNoteAuditVisibility => 'Visibility changed';

  @override
  String get crmNoteAuditAcl => 'Sharing list changed';

  @override
  String get crmNoteAuditSoftDeleted => 'Deleted';

  @override
  String get crmNoteAuditCommentCreated => 'Comment added';

  @override
  String get crmNoteAuditCommentDeleted => 'Comment removed';

  @override
  String get crmNoteAuditOther => 'Event';

  @override
  String get crmDeleteIrreversible => 'This cannot be undone.';

  @override
  String get crmDeleteLeadTitle => 'Delete lead';

  @override
  String crmDeleteLeadMessage(Object name) {
    return 'Delete lead «$name»?';
  }

  @override
  String get crmDeleteActivityTitle => 'Delete activity';

  @override
  String crmDeleteActivityMessageNamed(Object subject) {
    return 'Delete activity «$subject»?';
  }

  @override
  String get crmDeleteActivityMessageUnnamed => 'Delete this activity?';

  @override
  String get crmDeleteDealTitle => 'Delete deal';

  @override
  String crmDeleteDealMessage(Object title) {
    return 'Delete deal «$title»?';
  }

  @override
  String get crmDeleteProcessTitle => 'Delete process';

  @override
  String crmDeleteProcessMessage(Object name) {
    return 'Delete process «$name»?';
  }

  @override
  String get crmDeleteStageTitle => 'Delete stage';

  @override
  String crmDeleteStageMessage(Object name) {
    return 'Delete stage «$name»?';
  }

  @override
  String get crmLeadFormSubtitle =>
      'Contact details, funnel stage, and follow-up.';

  @override
  String get crmActivityFormSubtitle =>
      'Link to a customer or a lead, then describe the interaction.';

  @override
  String get crmDealFormSubtitle =>
      'Customer, pipeline stage, and financial details.';

  @override
  String get crmConvertLeadTitle => 'Convert to customer';

  @override
  String get crmConvertLeadSubtitle => 'Creates a new person in contacts.';

  @override
  String get crmConvertLeadIntro =>
      'The lead will be converted and a new person record will be created in contacts.';

  @override
  String get crmConvertWithDealLabel => 'Also create a sales deal';

  @override
  String get crmConvertNoPipeline => 'No active sales pipeline is available.';

  @override
  String get crmConvertPipelineLabel => 'Sales pipeline';

  @override
  String get crmConvertStageLabel => 'Stage';

  @override
  String get crmConvertDealTitleLabel => 'Deal title';

  @override
  String get crmConvertAmountLabel => 'Amount';

  @override
  String get crmConvertSubmit => 'Convert';

  @override
  String get crmSectionIdentityContact => 'Identity & contact';

  @override
  String get crmSectionFunnel => 'Funnel & stage';

  @override
  String get crmSectionAssignmentFollowup => 'Assignment & reminder';

  @override
  String get crmSectionDescription => 'Description';

  @override
  String get crmSectionActivityLink => 'Customer or lead';

  @override
  String get crmSectionActivityScheduling => 'Schedule';

  @override
  String get crmSectionActivityDetails => 'Subject & details';

  @override
  String get crmSectionDealPipeline => 'Pipeline & identity';

  @override
  String get crmSectionDealCustomer => 'Customer & documents';

  @override
  String get crmSectionDealMoney => 'Amount, currency & dates';

  @override
  String get crmActivityPickLead => 'Search & select lead';

  @override
  String get crmActivityClearLead => 'Clear lead';

  @override
  String get crmActivityTypeCall => 'Call';

  @override
  String get crmActivityTypeEmail => 'Email';

  @override
  String get crmActivityTypeMeeting => 'Meeting';

  @override
  String get crmActivityTypeNote => 'Note';

  @override
  String get crmProcessFormSubtitle =>
      'Code, display name, and default flags for this workflow.';

  @override
  String get crmProcessSectionMain => 'Definition';

  @override
  String get crmProcessSectionStages => 'Initial stages (new only)';

  @override
  String get inventoryNegativePolicySectionTitle =>
      'Warehouse posting: stock shortage rules';

  @override
  String get inventoryNegativePolicyIntro =>
      'This is not the same as “inventory control” on each product—that toggle decides whether the item is tracked in stock at all. Here you decide whether posting an outgoing warehouse move can proceed when quantity on hand is insufficient (negative stock). By default posting is blocked; use the switches below for bulk vs unique items. Transfer documents can stay fully strict separately.';

  @override
  String get inventoryNegativePolicyBulkTitle =>
      'Allow negative stock for bulk items';

  @override
  String get inventoryNegativePolicyBulkSubtitle =>
      'Products in bulk inventory mode with inventory tracking enabled.';

  @override
  String get inventoryNegativePolicyUniqueTitle =>
      'Allow negative stock for unique items';

  @override
  String get inventoryNegativePolicyUniqueSubtitle =>
      'Serialized / unique inventory mode; higher risk of mismatches with physical stock.';

  @override
  String get inventoryNegativePolicyTransferTitle =>
      'Transfers always require sufficient stock';

  @override
  String get inventoryNegativePolicyTransferSubtitle =>
      'When enabled, transfer documents always run full shortage checks, regardless of the two options above.';

  @override
  String get workflowMarketplaceTitle => 'Workflow repository';

  @override
  String get workflowMarketplaceSubtitle =>
      'Browse workflows published by others and add them to your business.';

  @override
  String get workflowMarketplaceSearchHint =>
      'Search title and short description…';

  @override
  String get workflowMarketplaceTagFilterHint => 'Tag filter (optional)';

  @override
  String get workflowMarketplaceEmpty => 'No items in the repository yet.';

  @override
  String get workflowMarketplaceInstallCount => 'Installs';

  @override
  String get workflowMarketplacePublisher => 'Publisher';

  @override
  String get workflowMarketplacePublishedAt => 'Published';

  @override
  String get workflowMarketplaceVersion => 'Version';

  @override
  String get workflowMarketplaceInstall => 'Add to this business';

  @override
  String get workflowMarketplaceDetailTitle => 'Package details';

  @override
  String get workflowMarketplaceLongDescription => 'Full description';

  @override
  String get workflowMarketplaceChangelog => 'Changes in this version';

  @override
  String get workflowMarketplaceBrowseTab => 'Browse';

  @override
  String get workflowMarketplaceOpen => 'Workflow repository';

  @override
  String get workflowMarketplaceMyPublished => 'My published';

  @override
  String get workflowMarketplacePublish => 'Publish to repository';

  @override
  String get workflowMarketplacePublishTitleLabel => 'Repository title';

  @override
  String get workflowMarketplaceShortDescriptionLabel => 'Summary (list card)';

  @override
  String get workflowMarketplaceLongDescriptionLabel =>
      'Full description for repository';

  @override
  String get workflowMarketplaceTagsLabel => 'Tags (comma-separated)';

  @override
  String get workflowMarketplaceVersionLabel => 'Version';

  @override
  String get workflowMarketplacePublishSubmit => 'Publish';

  @override
  String get workflowMarketplacePublishSaved =>
      'Workflow published to the repository.';

  @override
  String get workflowMarketplaceInstalled => 'Workflow added as draft.';

  @override
  String get workflowMarketplaceNameAfterInstall =>
      'Workflow name after install (optional)';

  @override
  String get workflowMarketplaceError => 'Repository error';

  @override
  String get workflowMarketplaceStatusLive => 'Live';

  @override
  String get workflowMarketplaceStatusPrivate => 'Unpublished';

  @override
  String get workflowMarketplaceMyEmpty =>
      'You have not published anything to the repository yet.';

  @override
  String get workflowMarketplaceUnpublish => 'Remove from repository';

  @override
  String get workflowMarketplaceUnpublishConfirmTitle =>
      'Remove from public list?';

  @override
  String get workflowMarketplaceUnpublishConfirmBody =>
      'Others will no longer see this workflow. It will stay in your list and you can publish it again later.';

  @override
  String get workflowMarketplaceRepublish => 'Publish again';

  @override
  String get workflowMarketplaceRemovedFromRepo =>
      'Removed from the public repository.';

  @override
  String get workflowMarketplaceRepublishedToast =>
      'Published to the repository again.';

  @override
  String get distributionMenu => 'Field distribution';

  @override
  String get distributionTabDashboard => 'Dashboard';

  @override
  String get distributionTabToday => 'Daily plan';

  @override
  String get distributionTabRoutes => 'Routes';

  @override
  String get distributionTabVisits => 'Visits';

  @override
  String get distributionTabReturns => 'Returns';

  @override
  String get distributionPermissionOperate =>
      'Field work (start/end visit, returns)';

  @override
  String get distributionPermissionManage =>
      'Routes, stops, assignments, approve returns';

  @override
  String get distributionPermissionReportsTeam =>
      'Team reports and plans for other users';

  @override
  String get distributionSelectDate => 'Select date';

  @override
  String get distributionVisitsToday => 'Visits today';

  @override
  String get distributionCompletedToday => 'Completed today';

  @override
  String get distributionPendingReturns => 'Pending returns';

  @override
  String get distributionActiveRoutes => 'Active routes';

  @override
  String get distributionNoPlan => 'No route plan for this date.';

  @override
  String get distributionStartVisit => 'Start visit';

  @override
  String get distributionCompleteVisit => 'Complete visit';

  @override
  String get distributionOutcomeOrder => 'Order / invoice';

  @override
  String get distributionOutcomeNoOrder => 'No order';

  @override
  String get distributionOutcomeCancelled => 'Visit cancelled';

  @override
  String get distributionDocumentIdHint =>
      'Document ID (proforma/invoice), optional';

  @override
  String get distributionDealIdHint => 'CRM deal ID, optional';

  @override
  String get distributionNoOrderReason => 'Reason for no order';

  @override
  String get distributionLinesJson => 'Return lines (product id, qty, reason)';

  @override
  String get distributionReturnCreate => 'Submit return request';

  @override
  String get distributionRefresh => 'Refresh';

  @override
  String get distributionPluginInactive =>
      'Field distribution add-on is not active. Enable it from the marketplace.';

  @override
  String get distributionSettingsSubtitle =>
      'Routes, daily plan, field visits and returns';

  @override
  String get distributionSharedRoutingCatalog =>
      'Shared route catalog for all visitors';

  @override
  String get distributionSharedRoutingCatalogHint =>
      'When off, each visitor only sees routes assigned to them.';

  @override
  String get distributionRequireVisitInDailyPlan =>
      'Start visit only from daily plan';

  @override
  String get distributionRequireVisitInDailyPlanHint =>
      'The person must be on that visitor daily plan.';

  @override
  String get distributionSettingsSaved => 'Settings saved.';

  @override
  String get distributionNotesLabel => 'Notes';

  @override
  String get reportsDistributionSection => 'Distribution & field visits';

  @override
  String get reportsDistributionDashboardTitle => 'Visit & returns summary';

  @override
  String get reportsDistributionDashboardSubtitle =>
      'Visit and return statistics for a date range';

  @override
  String get invoiceGlobalDiscountSection => 'Invoice-level discount';

  @override
  String get invoiceGlobalDiscountTypePercent => 'Percent';

  @override
  String get invoiceGlobalDiscountTypeAmount => 'Amount';

  @override
  String get invoiceGlobalDiscountValueLabel => 'Invoice discount value';

  @override
  String invoiceGlobalDiscountLineDiscountHint(String amount) {
    return 'Line discounts subtotal: $amount';
  }

  @override
  String invoiceGlobalDiscountAmountComputedHint(String amount) {
    return 'Applied invoice discount: $amount';
  }

  @override
  String get invoiceSummarySubtotal => 'Subtotal';

  @override
  String get invoiceSummaryDiscount => 'Total discount';

  @override
  String get invoiceSummaryTax => 'Total tax';

  @override
  String get invoiceSummaryTotal => 'Grand total';

  @override
  String get businessSettingsInvoiceGlobalDiscountTitle =>
      'Invoice-level discount (calculation)';

  @override
  String get businessSettingsInvoiceGlobalDiscountBasisLabel =>
      'Percent discount basis';

  @override
  String get businessSettingsInvoiceGlobalDiscountBasisSubtotalAfterLines =>
      'Net after line discounts (pre-tax)';

  @override
  String get businessSettingsInvoiceGlobalDiscountBasisGrossBeforeLines =>
      'Gross before line discounts';

  @override
  String get businessSettingsInvoiceGlobalDiscountBasisTotalWithTax =>
      'Sum of line totals including tax';

  @override
  String get businessSettingsInvoiceGlobalDiscountTaxModeLabel =>
      'Effect on tax';

  @override
  String get businessSettingsInvoiceGlobalDiscountTaxModeRecalculate =>
      'Recalculate tax proportionally';

  @override
  String get businessSettingsInvoiceGlobalDiscountTaxModeKeep =>
      'Keep per-line tax amounts';

  @override
  String get businessSettingsInvoiceGlobalDiscountMaxPercent =>
      'Max percent (optional)';

  @override
  String get businessSettingsInvoiceGlobalDiscountMaxAmount =>
      'Max amount (optional)';

  @override
  String get editInvoiceTitle => 'Edit invoice';

  @override
  String get saveChangesTooltip => 'Save changes';

  @override
  String get invoiceProductsTab => 'Products & services';

  @override
  String get invoiceTransactionsTab => 'Transactions';

  @override
  String get invoiceInstallmentsTab => 'Installments';

  @override
  String get invoiceSettingsTab => 'Settings';

  @override
  String get invoiceGlobalDiscountPercentInvalid =>
      'Invoice discount percent must be between 0 and 100';

  @override
  String get invoiceGlobalDiscountAmountInvalid =>
      'Invoice discount amount cannot be negative';

  @override
  String get invoiceGlobalDiscountValueInvalid =>
      'Invoice discount value is invalid';

  @override
  String get fiscalYearRollbackTitle => 'Revert current fiscal year';

  @override
  String get fiscalYearRollbackRetry => 'Try again';

  @override
  String get fiscalYearRollbackTokenMissing =>
      'No confirmation code or it has expired. Tap “Refresh preview” and try again.';

  @override
  String get fiscalYearRollbackConfirmTitle => 'Final confirmation';

  @override
  String get fiscalYearRollbackConfirmWithBackupBody =>
      'A full business backup will be saved in the system first, then the current fiscal year and all its documents will be removed. Closing documents on the previous year (if any) will also be removed. This cannot be undone in the app.';

  @override
  String get fiscalYearRollbackConfirmWithoutBackupBody =>
      'The current fiscal year and all its documents will be removed. Closing documents on the previous year (if any) will also be removed. This cannot be undone in the app.';

  @override
  String get fiscalYearRollbackCancel => 'Cancel';

  @override
  String get fiscalYearRollbackConfirmDelete => 'Remove current year';

  @override
  String get fiscalYearRollbackPhaseBackupStarting =>
      'Creating full system backup…';

  @override
  String get fiscalYearRollbackBackupStartFailed => 'Could not start backup.';

  @override
  String get fiscalYearRollbackBackupJobIdMissing =>
      'Backup job id was not returned by the server.';

  @override
  String get fiscalYearRollbackPhasePreviewRefresh =>
      'Refreshing preview (new confirmation code)…';

  @override
  String get fiscalYearRollbackAfterBackupBlocked =>
      'After the backup, fiscal rollback is no longer allowed. The business state may have changed. Review the preview and try again.';

  @override
  String get fiscalYearRollbackTokenAfterBackupMissing =>
      'No confirmation code after backup. Tap “Refresh preview”.';

  @override
  String get fiscalYearRollbackTokenMissingGeneric =>
      'Confirmation code is not available.';

  @override
  String get fiscalYearRollbackPhaseDeleting => 'Removing current fiscal year…';

  @override
  String get fiscalYearRollbackSuccessFallback => 'Completed successfully';

  @override
  String get fiscalYearRollbackWarningCard =>
      'This removes all documents in the current fiscal year and makes the previous year current.';

  @override
  String get fiscalYearRollbackCurrentYearLabel =>
      'Current year (will be removed)';

  @override
  String fiscalYearRollbackYearIdSuffix(String id) {
    return 'ID $id';
  }

  @override
  String get fiscalYearRollbackNextCurrentLabel => 'Will become current';

  @override
  String fiscalYearRollbackDocCountLabel(String count) {
    return 'Documents in current year: $count';
  }

  @override
  String fiscalYearRollbackClosingDocsToDelete(String count) {
    return 'Closing documents on the previous year to be removed: $count';
  }

  @override
  String get fiscalYearRollbackBackupCheckboxTitle =>
      'Take a full backup before removing the year';

  @override
  String get fiscalYearRollbackBackupCheckboxSubtitle =>
      'Same system backup (.hbx) as in settings, for restore if needed.';

  @override
  String get fiscalYearRollbackOpenBackupPage => 'Open backup page';

  @override
  String get fiscalYearRollbackExecuteButton => 'Remove current fiscal year';

  @override
  String get fiscalYearRollbackBlockedTitle =>
      'This action is not allowed right now — reasons:';

  @override
  String get fiscalYearRollbackBlockedHint =>
      'After fixing the items below, tap “Refresh preview”.';

  @override
  String get fiscalYearRollbackRefreshPreview => 'Refresh preview';

  @override
  String fiscalYearRollbackBackupProgressPrefix(String detail) {
    return 'Backup: $detail';
  }

  @override
  String get fiscalYearRollbackPreviewFailed =>
      'Fiscal rollback preview failed.';

  @override
  String get fiscalYearRollbackNetworkUnreachable =>
      'Could not reach the server. Check your connection and sign-in.';

  @override
  String get fiscalYearRollbackExecuteFailed => 'Fiscal rollback failed.';

  @override
  String get fiscalYearRollbackExecuteFailedSupport =>
      'The operation failed. If it keeps happening, contact support.';

  @override
  String get backupJobWaitTimeout =>
      'Backup did not finish within the wait time. Check status under Settings → Backup.';

  @override
  String get backupJobStorageLimitFallback =>
      'Backup could not be saved due to storage limits. Activate a plan or free space.';

  @override
  String get settingsSideCurrenciesTitle => 'Secondary currencies';

  @override
  String get settingsSideCurrenciesSubtitle =>
      'Add and remove currencies available for this business';

  @override
  String get settingsInvoiceFxPolicyTitle => 'Invoice FX revaluation policy';

  @override
  String get settingsInvoiceFxPolicySubtitle =>
      'Reference time for the rate and behavior when no rate exists (base vs. foreign currency)';

  @override
  String get fxRevaluationSettingsTitle => 'Invoice revaluation (policy)';

  @override
  String get fxRevaluationSettingsIntro =>
      'These options define the reference time for the revaluation rate (against the base currency) for invoices in foreign currency, and what happens if no rate exists.';

  @override
  String get fxRevaluationAsOfSourceLabel =>
      'Reference time for the rate (as_of)';

  @override
  String get fxRevaluationAsOfSourceDocumentDate =>
      'Document date (time from the option below)';

  @override
  String get fxRevaluationAsOfSourceRegisteredAt =>
      'When the document is registered in the system';

  @override
  String get fxRevaluationDateEffectiveLabel =>
      'Effective time on that day (UTC)';

  @override
  String get fxRevaluationTimeStartOfDay => 'Start of day 00:00';

  @override
  String get fxRevaluationTimeNoon => 'Midday 12:00';

  @override
  String get fxRevaluationTimeEndOfDay =>
      'End of day 23:59:59 (multiple rates per day)';

  @override
  String get fxRevaluationWhenNoRateLabel =>
      'If no revaluation rate exists for the reference time';

  @override
  String get fxRevaluationWhenNoRateBlock => 'Block saving the invoice';

  @override
  String get fxRevaluationWhenNoRateAllow =>
      'Allow saving without a rate (incomplete FX on the document)';

  @override
  String get fxRevaluationSettingsFooterNote =>
      'Users without “Currency revaluation” permission cannot pick a specific rate row; the system uses the latest effective rate up to the reference time.';

  @override
  String fxRevaluationSettingsLoadError(String error) {
    return 'Failed to load: $error';
  }

  @override
  String fxRevaluationSettingsSaveError(String error) {
    return 'Could not save: $error';
  }

  @override
  String get invoiceFxRateFieldLabel => 'Revaluation rate (optional)';

  @override
  String get invoiceFxRateAuto => 'Automatic (business policy settings)';

  @override
  String get invoiceFxRateHelper =>
      'For non-base currency; “Automatic” uses the latest valid rate up to the document reference time.';

  @override
  String get invoiceFxRateStoredOnDocument => 'Rate stored on this document';

  @override
  String invoiceFxRateRow(String rate, String effective, String idPart) {
    return '$rate — $effective$idPart';
  }

  @override
  String crmWebChatError(String detail) {
    return 'Error: $detail';
  }

  @override
  String crmWebChatErrorLoadingMessages(String detail) {
    return 'Error loading messages: $detail';
  }

  @override
  String get crmWebChatStatusOpen => 'Open';

  @override
  String get crmWebChatStatusPending => 'Pending';

  @override
  String get crmWebChatStatusResolved => 'Resolved';

  @override
  String get crmWebChatFileSaved => 'File saved';

  @override
  String crmWebChatErrorDownload(String detail) {
    return 'Download error: $detail';
  }

  @override
  String get crmWebChatFileUploadDisabledCrm =>
      'File uploads are disabled in CRM settings.';

  @override
  String get crmWebChatFileReadFailed =>
      'Could not read the file (size or browser limit). Try a smaller file.';

  @override
  String get crmWebChatFileIdMissing =>
      'File id was not returned from the server.';

  @override
  String get crmWebChatFileSent => 'File sent';

  @override
  String get crmWebChatNoCrmWritePermission =>
      'You do not have permission to change CRM data.';

  @override
  String get crmWebChatMessageSent => 'Sent';

  @override
  String get crmWebChatSaved => 'Saved';

  @override
  String get crmWebChatWidgetCreated => 'Chat widget created';

  @override
  String get crmWebChatWidgetUpdated => 'Chat widget updated';

  @override
  String get crmWebChatEditConversationTitle => 'Edit conversation';

  @override
  String get crmWebChatFieldStatus => 'Status';

  @override
  String get crmWebChatAssignTo => 'Assign to';

  @override
  String get crmWebChatOptionalLeadId => 'Lead id (optional)';

  @override
  String get crmWebChatOptionalPersonId => 'Person id (optional)';

  @override
  String get crmWebChatUnassigned => '—';

  @override
  String crmWebChatEmbedSnippet(String base, String publicKey) {
    return '// API base: $base\n// Step 1: POST /api/v1/public/crm-chat/conversations/start\n// JSON body must include public_key \"$publicKey\" and first_name, last_name, email, phone, page_url.\n// Step 2: with visitor_token and conversation_id, POST to /api/v1/public/crm-chat/messages.\n// See CRM_WEB_CHAT in the Hesabix repository for details.';
  }

  @override
  String get crmWebChatDefaultWidgetName => 'Widget';

  @override
  String get crmWebChatAccessDenied => 'You do not have access to view CRM.';

  @override
  String get crmWebChatPageTitle => 'Web chat';

  @override
  String get crmWebChatSearchConversationsHint =>
      'Search conversations, ID, email…';

  @override
  String get crmWebChatMessageDeleted => 'This message was deleted';

  @override
  String get crmWebChatLoadOlder => 'Loading…';

  @override
  String get crmWebChatDeleteMessage => 'Delete message';

  @override
  String get crmWebChatDeleteMessageConfirm =>
      'Deleting this message cannot be undone. Continue?';

  @override
  String get crmWebChatDeleteConversation => 'Delete conversation';

  @override
  String get crmWebChatDeleteConversationConfirm =>
      'This conversation and all its messages will be permanently deleted. Continue?';

  @override
  String get crmWebChatConversationDeleted => 'Conversation deleted';

  @override
  String get crmWebChatEditMessageTitle => 'Edit message';

  @override
  String get crmWebChatEditMessageHint => 'New text…';

  @override
  String get crmWebChatEditMessageSaved => 'Message updated';

  @override
  String get crmWebChatMessageEditedBadge => '(edited)';

  @override
  String get crmWebChatRefreshTooltip => 'Reload';

  @override
  String get crmWebChatFilterStatusLabel => 'Status filter';

  @override
  String get crmWebChatFilterAll => 'All';

  @override
  String get crmWebChatFilterLongPressHint =>
      'To delete conversations in bulk, press and hold the status filter title.';

  @override
  String get crmWebChatCrmSettingsWidgetsIntro =>
      'Manage the public key, allowed domains, and visitor file upload for each widget.';

  @override
  String get crmWebChatCrmSettingsNoWidgets =>
      'No widgets yet. Create one with the button below.';

  @override
  String get crmWebChatAddWidgetButton => 'New widget';

  @override
  String get crmWebChatBulkDeleteTitle => 'Delete conversations in bulk';

  @override
  String get crmWebChatBulkDeleteConfirmAll =>
      'All conversations and messages for this business will be permanently deleted. This cannot be undone. Continue?';

  @override
  String crmWebChatBulkDeleteConfirmStatus(String statusLabel) {
    return 'All conversations with status «$statusLabel» and their messages will be permanently deleted. This cannot be undone. Continue?';
  }

  @override
  String crmWebChatBulkDeleteDone(int count) {
    return '$count conversation(s) deleted';
  }

  @override
  String get crmWebChatWidgetsSectionTitle => 'Chat widgets';

  @override
  String get crmWebChatWidgetsSectionHint =>
      'Use edit for the public key and to disable file upload per site.';

  @override
  String get crmWebChatVisitorAttachmentCrmOff =>
      'Visitor attachments: off (enable in CRM settings first).';

  @override
  String get crmWebChatVisitorAttachmentAllowed =>
      'Visitor attachments: allowed — business storage.';

  @override
  String get crmWebChatVisitorAttachmentWidgetOff =>
      'Visitor attachments: off for this widget.';

  @override
  String get crmWebChatWidgetStateActive =>
      'State: active — embedded on the site';

  @override
  String get crmWebChatWidgetStateInactive =>
      'State: inactive — new conversations cannot start with this key';

  @override
  String get crmWebChatPublicKeyCopied => 'Public key copied';

  @override
  String get crmWebChatEmbedGuideCopied => 'Connection guide copied';

  @override
  String get crmWebChatMenuCopyPublicKey => 'Copy public key';

  @override
  String get crmWebChatMenuCopyApiGuide => 'Copy API guide';

  @override
  String get crmWebChatMenuEdit => 'Edit…';

  @override
  String get crmWebChatNoWidgetsYet => 'No widgets yet — use + to add one.';

  @override
  String get crmWebChatNoConversations =>
      'No conversations — try changing the filter';

  @override
  String crmWebChatConversationNumber(int id) {
    return 'Conversation $id';
  }

  @override
  String get crmWebChatSelectConversation => 'Select a conversation';

  @override
  String get crmWebChatConversationNotFoundRefresh =>
      'Conversation not found — try refreshing';

  @override
  String get crmWebChatVisitorStartPageLabel =>
      'Page where chat started (visitor)';

  @override
  String get crmWebChatVisitorCurrentPageLabel => 'Visitor\'s current page';

  @override
  String crmWebChatVisitorIpLine(String ip) {
    return 'IP: $ip';
  }

  @override
  String get crmWebChatVisitorDeviceMobile => 'Mobile';

  @override
  String get crmWebChatVisitorDeviceTablet => 'Tablet';

  @override
  String get crmWebChatVisitorDeviceDesktop => 'Desktop';

  @override
  String get crmWebChatVisitorDeviceUnknown => 'Device';

  @override
  String crmWebChatWidgetLine(String name) {
    return 'Widget: $name';
  }

  @override
  String crmWebChatAssigneeLine(String name) {
    return 'Owner: $name';
  }

  @override
  String get crmWebChatEditConversationButton => 'Edit conversation';

  @override
  String get crmWebChatLeads => 'Leads';

  @override
  String get crmWebChatRoleAgent => 'Agent';

  @override
  String get crmWebChatRoleVisitor => 'Visitor';

  @override
  String get crmWebChatFileLabel => 'File';

  @override
  String get crmWebChatAttachFileTooltip =>
      'Attach file (business storage, context crm_web_chat)';

  @override
  String get crmWebChatReplyHint => 'Reply… (Ctrl+Enter to send)';

  @override
  String get crmWebChatSend => 'Send';

  @override
  String get crmWebChatWidgetDialogTitleEdit => 'Edit chat widget';

  @override
  String get crmWebChatWidgetDialogTitleNew => 'New chat widget';

  @override
  String get crmWebChatWidgetDialogIntro =>
      'After creation, copy the public key and API connection guide from the widget’s ⋯ menu. Allowed domains only affect browser security (CORS).';

  @override
  String get crmWebChatWidgetNameLabel => 'Widget name (internal)';

  @override
  String get crmWebChatWidgetNameHint => 'e.g. My shop';

  @override
  String get crmWebChatWidgetNameHelper =>
      'Only visible in your panel to tell widgets apart.';

  @override
  String get crmWebChatWidgetOriginsLabel => 'Allowed request domains';

  @override
  String get crmWebChatWidgetOriginsHint =>
      'shop.example.com, blog.shop.example.com';

  @override
  String get crmWebChatWidgetOriginsHelper =>
      'Optional. Host names only (no https://), separated by a comma. If empty, domain rules follow the API docs. For a specific site, add that host here.';

  @override
  String get crmWebChatVisitorFileSwitchTitle => 'Let site visitors send files';

  @override
  String get crmWebChatVisitorFileSwitchOn =>
      'Subject to your storage plan. You can turn this off for this widget only; if left on, it matches other widgets.';

  @override
  String get crmWebChatVisitorFileSwitchOff =>
      'Disabled at business level. In CRM settings (e.g. Communications → CRM settings), turn on web chat file upload, then return and set this switch.';

  @override
  String get crmWebChatWidgetActiveTitle => 'Widget active';

  @override
  String get crmWebChatWidgetActiveSubtitle =>
      'If off, new conversations cannot start with this public key (existing threads stay in the panel).';

  @override
  String get crmWebChatNameRequired =>
      'Enter a widget name (e.g. site or section).';

  @override
  String get crmWebChatCreate => 'Create';

  @override
  String get crmWebChatSocketLive => 'Live';

  @override
  String get crmWebChatSocketPolling => 'Polling';

  @override
  String get crmWebChatSocketOffline => 'Offline';

  @override
  String get crmWebChatSocketNoKey => 'No key';

  @override
  String get crmWebChatPeerTyping => 'Visitor is typing…';

  @override
  String get crmWebChatTooltipMessageSent => 'Sent';

  @override
  String get crmWebChatTooltipMessageRead => 'Read';

  @override
  String get crmSettingsWebChatVoiceTitle => 'Voice messages in web chat';

  @override
  String get crmSettingsWebChatVoiceSubtitle =>
      'Voice clips count toward your storage plan like other uploads.';

  @override
  String get crmWebChatVisitorVoiceSwitchTitle =>
      'Let visitors send voice messages';

  @override
  String get crmWebChatVisitorVoiceSwitchOn =>
      'Follow CRM and storage limits. Per-widget toggle off if needed.';

  @override
  String get crmWebChatVisitorVoiceSwitchOff =>
      'Voice upload is disabled in CRM settings or limited for this widget.';

  @override
  String get crmWebChatVoiceDisabledCrm =>
      'Voice messages are disabled in CRM settings for this business';

  @override
  String get crmWebChatComposerDropTarget => 'Drop to send';

  @override
  String get crmWebChatMicRecording => 'Recording…';

  @override
  String get crmWebChatMicStopSend => 'Stop & send';

  @override
  String get crmWebChatMicUnavailableWeb =>
      'Voice capture is unavailable in this browser build; attach a file instead';

  @override
  String get crmWebChatVisitorVoiceOffWidget => 'Guest voice disabled';

  @override
  String get accountSettingsAppearanceTitle => 'Appearance';

  @override
  String get accountSettingsAppearanceDescription =>
      'Business panel layout on desktop (single page vs tabs)';

  @override
  String get appearanceSettingsPageTitle => 'Appearance settings';

  @override
  String get appearanceBusinessPanelSection => 'Business panel (desktop)';

  @override
  String get appearanceNavigationSingleLabel => 'Single page';

  @override
  String get appearanceNavigationSingleSubtitle =>
      'Only one page open at a time (classic navigation)';

  @override
  String get appearanceNavigationTabsLabel => 'Tabs in top bar';

  @override
  String get appearanceNavigationTabsSubtitle =>
      'Keep multiple pages open and switch via tabs on the dark strip (desktop only). Background tabs stay mounted; stable page keys improve reuse when you return.';

  @override
  String get appearanceDesktopOnlyNote =>
      'Tabbed layout applies only on wide screens; on mobile, navigation stays single-page.';

  @override
  String get appearanceSaved => 'Saved';

  @override
  String get appearanceSaveError => 'Could not save settings';

  @override
  String get appearanceSaveButton => 'Save';

  @override
  String get businessPanelTabCloseThisTab => 'Close this tab';

  @override
  String get businessPanelTabCloseTabsToTheRight => 'Close tabs to the right';

  @override
  String get businessPanelTabCloseTabsToTheLeft => 'Close tabs to the left';

  @override
  String get businessPanelTabAllTabsTitle => 'All tabs';

  @override
  String get businessPanelTabCloseAllTabs => 'Close all tabs';

  @override
  String get businessPanelTabListTooltip => 'List all tabs';

  @override
  String get businessPanelTabRouteProjects => 'Projects';

  @override
  String get businessPanelTabRoutePriceListItems => 'Price list items';

  @override
  String get businessPanelTabRouteRepairTechnicians => 'Repair technicians';

  @override
  String get businessPanelTabRouteRepairShopSettings => 'Repair shop settings';

  @override
  String get appearanceSidebarTabBehaviorSection =>
      'Sidebar navigation (when tabs are on)';

  @override
  String get appearanceSidebarTabBehaviorReuseTitle =>
      'Reuse open tab or open a new one';

  @override
  String get appearanceSidebarTabBehaviorReuseSubtitle =>
      'If that page is already open in a tab, switch to it; otherwise add a new tab. This matches the previous default behavior.';

  @override
  String get appearanceSidebarTabBehaviorLongPressTitle =>
      'Replace the active tab; long press for the default behavior';

  @override
  String get appearanceSidebarTabBehaviorLongPressSubtitle =>
      'A normal click loads the destination in the current tab only. Long press on a sidebar item reuses an open tab or opens a new tab, like the option above.';

  @override
  String get mobileLauncherTitle => 'Mobile launcher';

  @override
  String get mobileLauncherAppearanceTile => 'Launcher look';

  @override
  String get mobileLauncherAppearancePageTitle => 'Launcher appearance';

  @override
  String get mobileLauncherBackgroundColorSection => 'Background color';

  @override
  String get mobileLauncherSaveColors => 'Save';

  @override
  String get mobileLauncherColorsSaved => 'Saved';

  @override
  String get mobileLauncherBackToAccount => 'Account';

  @override
  String get mobileLauncherOpenFullPanel => 'Full panel';

  @override
  String get mobileLauncherChooseModeTitle =>
      'How do you want to open this business?';

  @override
  String get mobileLauncherModeStandard => 'Standard panel';

  @override
  String get mobileLauncherModeLauncher => 'Mobile launcher';

  @override
  String get mobileLauncherInvalidBusiness => 'Invalid business id';

  @override
  String get mobileLauncherDisableHomeLauncherMenu =>
      'Open app to profile home';

  @override
  String get mobileLauncherDisableHomeLauncherDone =>
      'The app will open to your profile until you choose launcher again.';

  @override
  String get mobileLauncherBusinessNoAccess =>
      'You no longer have access to this business.';

  @override
  String get mobileLauncherExitAppHint => 'Press back again to exit';

  @override
  String get mobileLauncherBrandName => 'Hesabix';

  @override
  String get mobileLauncherBusinessFallback => 'Business';

  @override
  String get mobileLauncherGridLayoutSection => 'Grid layout';

  @override
  String get mobileLauncherGridColumns => 'Columns';

  @override
  String get mobileLauncherGridRows => 'Rows';

  @override
  String get mobileLauncherGridPreview => 'Preview';

  @override
  String get mobileLauncherQuickSalesTile => 'Quick sales';
}
