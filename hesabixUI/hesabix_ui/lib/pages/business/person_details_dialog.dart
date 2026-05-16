import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/models/person_social_platforms.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hesabix_ui/models/person_share_link.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/services/warranty_service.dart';
import 'package:hesabix_ui/models/warranty_models.dart';
import 'package:hesabix_ui/widgets/attached_files/attached_files_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/document/document_details_dialog.dart';
import 'package:hesabix_ui/widgets/warranty/warranty_code_details_dialog.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

String? _firstNonEmptyPersonMobile(Person? p) {
  if (p == null) return null;
  for (final s in <String?>[p.mobile, p.mobile2, p.mobile3]) {
    final t = s?.trim();
    if (t != null && t.isNotEmpty) return t;
  }
  return null;
}

class PersonDetailsDialog extends StatefulWidget {
  final int businessId;
  final Person person;
  final AuthStore authStore;
  final bool isWarrantyPluginActive;

  const PersonDetailsDialog({
    super.key,
    required this.businessId,
    required this.person,
    required this.authStore,
    required this.isWarrantyPluginActive,
  });

  @override
  State<PersonDetailsDialog> createState() => _PersonDetailsDialogState();
}

class _PersonDetailsDialogState extends State<PersonDetailsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final PersonService _personService;
  late final BusinessStorageService _storageService;
  late final WarrantyService _warrantyService;
  final AttachedFilesWidgetKey _attachedFilesKey = AttachedFilesWidgetKey();
  final GlobalKey _kardexTableKey = GlobalKey();
  Person? _person;
  bool _loadingDetails = false;
  String? _detailsError;
  bool _uploadingFile = false;
  CalendarController? _calendarController;
  bool _loadingCalendar = false;
  Future<void>? _calendarLoadInFlight;
  double? _summaryDebit;
  double? _summaryCredit;
  double? _summaryBalance;
  String? _summaryStatus;
  bool _loadingSummary = false;
  String? _summaryError;
  int? _currentFiscalYearId;
  String? _currentFiscalYearName;
  bool _loadingFiscalYear = false;
  PersonShareLink? _shareLink;
  bool _loadingShareLink = false;
  String? _shareLinkError;
  bool _creatingShareLink = false;
  bool _revokingShareLink = false;
  bool _sendingLinkSms = false;
  int? _selectedExpiryHours = 168;
  bool _includeLedger = true;
  bool _includeInvoices = true;
  int _documentsLimit = 50;
  int _activitiesRefreshKey = 0;
  final TextEditingController _maxViewsController = TextEditingController();
  final TextEditingController _smsRecipientController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _person = widget.person;
    _personService = PersonService();
    _storageService = BusinessStorageService(ApiClient());
    _warrantyService = WarrantyService();
    final crmTab = widget.authStore.canReadSection('crm');
    _tabController = TabController(
      length: 4 + (widget.isWarrantyPluginActive ? 1 : 0) + (crmTab ? 2 : 0),
      vsync: this,
    );
    _loadPersonDetails();
    _ensureCalendarController();
    _initFinancialContext();
    _loadShareLinkStatus();
  }

  Future<void> _ensureCalendarController() async {
    if (_calendarController != null) return;
    _calendarLoadInFlight ??= () async {
      _loadingCalendar = true;
      try {
        final controller = await CalendarController.load();
        if (!mounted) return;
        setState(() {
          _calendarController = controller;
        });
      } finally {
        _loadingCalendar = false;
        _calendarLoadInFlight = null;
      }
    }();
    await _calendarLoadInFlight;
  }

  Future<DateTime?> _pickActivityDate(BuildContext pickerContext, DateTime initial) async {
    await _ensureCalendarController();
    if (!mounted) return null;
    final firstDate = DateTime(2000);
    final lastDate = DateTime(2100);
    return showAdaptiveDatePicker(
      context: pickerContext,
      calendarController: _calendarController,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  String _activityDateDisplayLabel(DateTime date) {
    final isJalali = _calendarController?.isJalali ?? true;
    return HesabixDateUtils.formatForDisplay(date.toLocal(), isJalali);
  }

  Future<void> _initFinancialContext() async {
    await _loadFiscalYearInfo();
    if (!mounted) return;
    await _loadFinancialSummary();
  }

  Future<void> _loadFiscalYearInfo() async {
    setState(() {
      _loadingFiscalYear = true;
    });
    try {
      final service = BusinessDashboardService(ApiClient());
      final items = await service.listFiscalYears(widget.businessId);
      Map<String, dynamic>? current;
      if (items.isNotEmpty) {
        try {
          current = items.firstWhere(
            (fy) => fy['is_last'] == true || fy['isLast'] == true,
          );
        } catch (_) {
          current = items.first;
        }
      }
      if (!mounted) return;
      setState(() {
        _currentFiscalYearId = current?['id'] as int?;
        _currentFiscalYearName = current?['title']?.toString() ?? current?['name']?.toString();
      });
      _refreshKardexTable();
    } finally {
      if (mounted) {
        setState(() {
          _loadingFiscalYear = false;
        });
      }
    }
  }

  void _refreshKardexTable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        ( _kardexTableKey.currentState as dynamic)?.refresh();
      } catch (_) {}
    });
  }

  Future<void> _loadFinancialSummary() async {
    if (_person?.id == null) return;
    setState(() {
      _loadingSummary = true;
      _summaryError = null;
    });
    try {
      final result = await _fetchLedgerTotals(_person!.id!, _currentFiscalYearId);
      if (!mounted) return;
      setState(() {
        _summaryDebit = result.debit;
        _summaryCredit = result.credit;
        _summaryBalance = result.balance;
        _summaryStatus = result.status;
        _loadingSummary = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = ErrorExtractor.forContext(e, context);
        _loadingSummary = false;
      });
    }
  }

  void _applyShareLinkOptions(PersonShareLink link) {
    _includeLedger = link.options.includeLedger;
    _includeInvoices = link.options.includeInvoices;
    _documentsLimit = link.options.documentsLimit;
    _maxViewsController.text = link.maxViewCount?.toString() ?? '';
    final remaining = link.remainingHours;
    if (remaining == null || remaining <= 0) {
      _selectedExpiryHours = null;
    } else {
      final rounded = remaining.round();
      _selectedExpiryHours = rounded < 1
          ? 1
          : rounded > 720
              ? 720
              : rounded;
    }
  }

  Future<void> _loadShareLinkStatus() async {
    final personId = widget.person.id;
    if (personId == null) return;
    setState(() {
      _loadingShareLink = true;
      _shareLinkError = null;
    });
    try {
      final link = await _personService.getPersonShareLink(personId);
      if (!mounted) return;
      setState(() {
        _shareLink = link;
        _loadingShareLink = false;
      });
      if (link != null) {
        setState(() {
          _applyShareLinkOptions(link);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shareLinkError = _friendlyShareLinkError(e);
        _loadingShareLink = false;
      });
    }
  }

  Future<void> _createShareLink() async {
    final personId = widget.person.id;
    if (personId == null || _creatingShareLink) return;
    setState(() {
      _creatingShareLink = true;
      _shareLinkError = null;
    });
    try {
      final maxViewsText = _maxViewsController.text.trim();
      final maxViews = maxViewsText.isEmpty ? null : int.tryParse(maxViewsText);
      final options = PersonShareLinkOptionsModel(
        includeLedger: _includeLedger,
        includeInvoices: _includeInvoices,
        documentsLimit: _documentsLimit,
      );
      final link = await _personService.createPersonShareLink(
        personId: personId,
        expiresInHours: _selectedExpiryHours,
        maxViewCount: maxViews,
        options: options,
      );
      if (!mounted) return;
      setState(() {
        _shareLink = link;
      });
      SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).personShareLinkCreated);
    } catch (e) {
      if (!mounted) return;
      final friendly = _friendlyShareLinkError(e);
      setState(() {
        _shareLinkError = friendly;
      });
      SnackBarHelper.showError(context, message: AppLocalizations.of(context).personShareLinkCreateError);
    } finally {
      if (mounted) {
        setState(() => _creatingShareLink = false);
      }
    }
  }

  Future<void> _revokeShareLink() async {
    final personId = widget.person.id;
    if (personId == null || _revokingShareLink) return;
    setState(() => _revokingShareLink = true);
    try {
      await _personService.revokePersonShareLink(personId);
      if (!mounted) return;
      setState(() {
        _shareLink = null;
        _shareLinkError = null;
        _maxViewsController.clear();
        _selectedExpiryHours = 168;
        _includeLedger = true;
        _includeInvoices = true;
        _documentsLimit = 50;
      });
      SnackBarHelper.show(context, message: AppLocalizations.of(context).personShareLinkRevoked);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shareLinkError = _friendlyShareLinkError(e);
      });
      SnackBarHelper.showError(context, message: AppLocalizations.of(context).personShareLinkRevokeError);
    } finally {
      if (mounted) {
        setState(() => _revokingShareLink = false);
      }
    }
  }

  /// پیام خطای قابل‌نمایش برای کاربر (بدون جزئیات فنی)
  static String _friendlyShareLinkError(Object? e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 403) return 'دسترسی غیرمجاز.';
      if (code == 404) return 'منبع یافت نشد.';
      if (code != null && code >= 500) return 'خطای سرور. لطفاً بعداً تلاش کنید.';
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        return 'خطای ارتباط با سرور.';
      }
    }
    return 'عملیات ناموفق بود.';
  }

  Future<void> _copyShareLink() async {
    final link = _shareLink?.shortUrl;
    if (link == null || link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).personShareLinkCopied);
  }

  Future<void> _copyAndShareLink() async {
    final link = _shareLink?.shortUrl;
    if (link == null || link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    await Share.share(link);
    if (!mounted) return;
    SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).personShareLinkCopiedAndShare);
  }

  /// ارسال لینک کارت حساب با پیامک از طریق قالب تایید‌شده نوتیفیکیشن
  Future<void> _sendShareLinkBySms() async {
    final t = AppLocalizations.of(context);
    final personId = _person?.id;
    final link = _shareLink?.shortUrl;
    final mobileFromPerson = _firstNonEmptyPersonMobile(_person);
    final mobileOverride = _smsRecipientController.text.trim();
    final effectiveMobile = mobileOverride.isNotEmpty ? mobileOverride : mobileFromPerson;

    if (link == null || link.isEmpty) {
      SnackBarHelper.show(context, message: t.personShareCreateLinkFirst);
      return;
    }
    if (personId == null) {
      SnackBarHelper.showError(context, message: 'شناسه شخص معتبر نیست.');
      return;
    }
    if ((effectiveMobile ?? '').isEmpty) {
      SnackBarHelper.show(context, message: t.personShareNoMobileHint);
      return;
    }
    if (!widget.authStore.hasBusinessPermission('notifications', 'send')) {
      SnackBarHelper.showError(context, message: 'دسترسی ارسال نوتیفیکیشن ندارید.');
      return;
    }

    setState(() => _sendingLinkSms = true);
    try {
      final api = ApiClient();
      final response = await api.post<Map<String, dynamic>>(
        '/api/v1/business-notifications/businesses/${widget.businessId}/send',
        data: {
          'person_id': personId,
          'event_type': 'person_share_link.sms',
          'context': {
            'share_link': link,
            'customer_name': _person?.displayName ?? '',
            'customer_mobile': effectiveMobile,
          },
          'channel': 'sms',
          if (mobileOverride.isNotEmpty) 'recipient_mobile': mobileOverride,
        },
      );
      if (!mounted) return;
      final result = (response.data as Map<String, dynamic>?)?['data'] as Map<String, dynamic>?;
      final results = result?['results'] as Map<String, dynamic>?;
      final smsResult = results?['sms'] as Map<String, dynamic>?;
      final success = smsResult?['success'] == true;
      if (success) {
        SnackBarHelper.showSuccess(context, message: t.personShareSmsSent);
      } else {
        final error = smsResult?['error']?.toString() ?? 'خطا در ارسال';
        if (error.contains('قالب') || error.contains('فعال')) {
          SnackBarHelper.showError(context, message: t.personShareNoTemplateHint);
        } else {
          SnackBarHelper.showError(context, message: error);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      if (raw.contains('403') || raw.contains('FORBIDDEN')) {
        SnackBarHelper.showError(context, message: 'دسترسی ارسال نوتیفیکیشن ندارید.');
      } else if (raw.contains('قالب') || raw.contains('فعال')) {
        SnackBarHelper.showError(context, message: t.personShareNoTemplateHint);
      } else {
        SnackBarHelper.showError(
          context,
          message: 'خطا در ارسال پیامک: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    } finally {
      if (mounted) setState(() => _sendingLinkSms = false);
    }
  }

  Future<_FinancialSummaryResult> _fetchLedgerTotals(int personId, int? fiscalYearId) async {
    final api = ApiClient();
    const pageSize = 250;
    int skip = 0;
    double totalDebit = 0;
    double totalCredit = 0;
    while (true) {
      final payload = <String, dynamic>{
        'take': pageSize,
        'skip': skip,
        'sort_desc': false,
        'sort_by': 'document_date',
        'person_ids': [personId],
        'match_mode': 'any',
        'result_scope': 'lines_matching',
      };
      if (fiscalYearId != null) {
        payload['fiscal_year_id'] = fiscalYearId;
      }
      final response = await api.post<Map<String, dynamic>>(
        '/api/v1/kardex/businesses/${widget.businessId}/lines',
        data: payload,
      );
      final body = response.data;
      if (body is! Map<String, dynamic> || body['success'] != true) {
        final message = body?['message']?.toString() ?? 'خطا در دریافت اطلاعات کاردکس';
        throw Exception(message);
      }
      final data = body['data'] as Map<String, dynamic>? ?? const {};
      final items = (data['items'] as List?) ?? const [];
      for (final raw in items) {
        if (raw is Map<String, dynamic>) {
          final debitVal = raw['debit'];
          final creditVal = raw['credit'];
          if (debitVal is num) {
            totalDebit += debitVal.toDouble();
          } else if (debitVal != null) {
            totalDebit += double.tryParse('$debitVal') ?? 0;
          }
          if (creditVal is num) {
            totalCredit += creditVal.toDouble();
          } else if (creditVal != null) {
            totalCredit += double.tryParse('$creditVal') ?? 0;
          }
        }
      }
      if (items.length < pageSize) {
        break;
      }
      skip += pageSize;
    }
    final balance = totalCredit - totalDebit;
    final status = _resolveStatus(totalDebit, totalCredit, balance);
    return _FinancialSummaryResult(
      debit: totalDebit,
      credit: totalCredit,
      balance: balance,
      status: status,
    );
  }

  String _resolveStatus(double debit, double credit, double balance) {
    if (debit == 0 && credit == 0) return 'بدون تراکنش';
    if (balance > 0) return 'بستانکار';
    if (balance < 0) return 'بدهکار';
    return 'بالانس';
  }

  Future<void> _loadPersonDetails() async {
    final personId = widget.person.id;
    if (personId == null) return;
    setState(() {
      _loadingDetails = true;
      _detailsError = null;
    });
    try {
      final data = await _personService.getPerson(personId);
      if (!mounted) return;
      setState(() {
        _person = data;
        _loadingDetails = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detailsError =
            'خطا در بارگذاری اطلاعات شخص: ${ErrorExtractor.forContext(e, context)}';
        _loadingDetails = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _maxViewsController.dispose();
    _smsRecipientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 820),
        child: Column(
          children: [
            _buildHeader(theme),
            Material(
              color: theme.colorScheme.surface,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: [
                  const Tab(icon: Icon(Icons.info_outline), text: 'اطلاعات شخص'),
                  const Tab(icon: Icon(Icons.assignment), text: 'کارت حساب'),
                  if (widget.isWarrantyPluginActive)
                    Tab(icon: const Icon(Icons.verified_user), text: t.warranty ?? 'گارانتی'),
                  const Tab(icon: Icon(Icons.attach_file), text: 'فایل‌ها'),
                  if (widget.authStore.canReadSection('crm'))
                    const Tab(icon: Icon(Icons.history), text: 'تاریخچه تعامل'),
                  if (widget.authStore.canReadSection('crm'))
                    const Tab(icon: Icon(Icons.trending_up), text: 'فرصت‌های فروش'),
                  const Tab(icon: Icon(Icons.share), text: 'اشتراک‌گذاری'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildInfoTab(theme),
                  _buildAccountCardTab(t, theme),
                  if (widget.isWarrantyPluginActive) _buildWarrantyTab(t, theme),
                  _buildAttachmentsTab(theme),
                  if (widget.authStore.canReadSection('crm')) _buildActivitiesTab(t, theme),
                  if (widget.authStore.canReadSection('crm')) _buildDealsTab(t, theme),
                  _buildShareTab(t, theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final balance = _person?.balance ?? 0;
    final balanceColor = balance > 0
        ? Colors.green
        : balance < 0
            ? Colors.red
            : theme.colorScheme.onSurfaceVariant;
    final formatter = NumberFormat('#,##0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            child: Text(
              (_person?.aliasName ?? '?').isNotEmpty ? (_person?.aliasName ?? '?')[0] : '?',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _person?.displayName ?? 'بدون نام',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (_person?.code != null)
                      _buildHeaderChip('کد: ${_person!.code}', theme),
                    _buildHeaderChip(
                      'تراز: ${formatter.format(balance)}',
                      theme,
                      icon: Icons.account_balance,
                      iconColor: balanceColor,
                    ),
                    if ((_person?.status ?? '').isNotEmpty)
                      _buildHeaderChip('وضعیت: ${_person!.status}', theme, icon: Icons.circle, iconColor: balanceColor),
                    if (_loadingDetails)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 6),
                          Text('در حال بروزرسانی...'),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTab(ThemeData theme) {
    if (_detailsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(_detailsError!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadPersonDetails, child: const Text('تلاش مجدد')),
          ],
        ),
      );
    }

    final person = _person;
    if (person == null) {
      return const Center(child: Text('اطلاعاتی برای نمایش وجود ندارد.'));
    }

    final t = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFinancialSummaryCard(theme),
          const SizedBox(height: 24),
          _buildSectionHeader('مشخصات پایه'),
          _buildInfoGrid([
            _InfoRow('نام مستعار', person.aliasName),
            _InfoRow(t.personNamePrefix, (person.namePrefix != null && person.namePrefix!.trim().isNotEmpty) ? person.namePrefix! : '—'),
            _InfoRow(t.personLegalEntityType, person.legalEntityType == 'legal' ? t.personLegalEntityLegal : t.personLegalEntityNatural),
            _InfoRow('نام', person.firstName),
            _InfoRow('نام خانوادگی', person.lastName),
            _InfoRow('انواع شخص', person.personTypes.map((e) => e.persianName).join('، ')),
            _InfoRow(t.personGroup, person.personGroupName ?? '—'),
            _InfoRow('نام سازمان', person.companyName),
            _InfoRow('شناسه پرداخت', person.paymentId),
          ]),
          const SizedBox(height: 24),
          _buildSectionHeader('اطلاعات تماس'),
          _buildInfoGrid([
            _InfoRow(t.personMobile, person.mobile),
            _InfoRow(t.personMobile2, person.mobile2),
            _InfoRow(t.personMobile3, person.mobile3),
            _InfoRow('تلفن ثابت', person.phone),
            _InfoRow('ایمیل', person.email),
            _InfoRow('وب‌سایت', person.website),
            _InfoRow('کد پستی', person.postalCode),
            _InfoRow('آدرس', person.address),
          ]),
          if (person.socialContacts.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSectionHeader(t.personSocialNetworks),
            ...person.socialContacts.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        personSocialPlatformLabelFa(s.platformKey, customLabel: s.customLabel),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: _personSocialValueWidget(context, s.value)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _buildSectionHeader('اطلاعات ثبتی'),
          _buildInfoGrid([
            _InfoRow('کد ملی', person.nationalId),
            _InfoRow('شناسه اقتصادی', person.economicId),
            _InfoRow('شماره ثبت', person.registrationNumber),
            _InfoRow('کشور', person.country),
            _InfoRow('استان', person.province),
            _InfoRow('شهر', person.city),
          ]),
        ],
      ),
    );
  }

  Widget _buildAccountCardTab(AppLocalizations t, ThemeData theme) {
    if (widget.person.id == null) {
      return const Center(child: Text('این شخص شناسه معتبر ندارد.'));
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Text(
                'لیست اسناد مرتبط با شخص',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              if (_currentFiscalYearName != null)
                Chip(
                  label: Text(
                    _currentFiscalYearName!,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  backgroundColor: theme.colorScheme.surface,
                )
              else
                Text(
                  'سال مالی جاری',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              if (_loadingFiscalYear) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'بروزرسانی کارت حساب',
                onPressed: () {
                  _refreshKardexTable();
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: DataTableWidget<Map<String, dynamic>>(
            key: _kardexTableKey,
            config: _buildKardexConfig(t),
            fromJson: (json) => json,
          ),
        ),
      ],
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildKardexConfig(AppLocalizations t) {
    Future<void> openDocument(Map<String, dynamic> item) async {
      final docId = (item['document_id'] as num?)?.toInt();
      if (docId == null) return;
      if (_calendarController == null) {
        await _ensureCalendarController();
        if (!mounted || _calendarController == null) return;
      }
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => DocumentDetailsDialog(
          documentId: docId,
          calendarController: _calendarController!,
        ),
      );
    }

    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/kardex/businesses/${widget.businessId}/lines',
      title: t.kardexDocuments,
      showActiveFilters: false,
      showClearFiltersButton: false,
      showColumnSearch: false,
      showRowNumbers: true,
      showExportButtons: false,
      showBackButton: false,
      additionalParams: {
        'person_ids': [widget.person.id],
        'result_scope': 'lines_matching',
        if (_currentFiscalYearId != null) 'fiscal_year_id': _currentFiscalYearId,
      },
      columns: [
        DateColumn(
          'document_date',
          t.documentDate,
          filterType: ColumnFilterType.dateRange,
          formatter: (item) => (item as Map<String, dynamic>)['document_date']?.toString(),
        ),
        TextColumn(
          'document_code',
          t.documentCode,
          formatter: (item) => (item as Map<String, dynamic>)['document_code']?.toString(),
        ),
        TextColumn(
          'document_type',
          t.documentType,
          formatter: (item) {
            final map = item as Map<String, dynamic>;
            return map['document_type_name']?.toString() ?? map['document_type']?.toString() ?? '-';
          },
        ),
        TextColumn(
          'description',
          t.description,
          width: ColumnWidth.large,
          formatter: (item) => (item as Map<String, dynamic>)['description']?.toString(),
        ),
        NumberColumn(
          'debit',
          t.debit,
          formatter: (item) => (item as Map<String, dynamic>)['debit']?.toString(),
        ),
        NumberColumn(
          'credit',
          t.credit,
          formatter: (item) => (item as Map<String, dynamic>)['credit']?.toString(),
        ),
        CustomColumn(
          'running_amount',
          t.runningAmount,
          builder: (item, _) {
            final value = (item as Map<String, dynamic>)['running_amount'];
            final double amount = (value is num) ? value.toDouble() : double.tryParse('$value') ?? 0;
            final color = amount > 0
                ? Colors.green[700]
                : amount < 0
                    ? Colors.red[700]
                    : null;
            return Text(
              amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2),
              style: TextStyle(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            );
          },
        ),
        ActionColumn(
          'actions',
          t.actions,
          actions: [
            DataTableAction(
              icon: Icons.open_in_new,
              label: t.viewDocument,
              onTap: (item) => openDocument(item as Map<String, dynamic>),
            ),
          ],
        ),
      ],
      searchFields: const ['document_code', 'document_type', 'description'],
      defaultPageSize: 10,
    );
  }

  Widget _buildWarrantyTab(AppLocalizations t, ThemeData theme) {
    return FutureBuilder<List<WarrantyCode>>(
      future: _loadPersonWarranties(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  'خطا در بارگذاری گارانتی‌ها: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                ),
              ],
            ),
          );
        }
        final warranties = snapshot.data ?? [];
        if (warranties.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'گارانتی‌ای برای این شخص ثبت نشده است',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.warrantyCodes ?? 'کدهای گارانتی',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...warranties.map((warranty) => _buildWarrantyCard(theme, warranty, t)),
            ],
          ),
        );
      },
    );
  }

  Future<List<WarrantyCode>> _loadPersonWarranties() async {
    if (!widget.isWarrantyPluginActive) {
      return [];
    }
    if (widget.person.id == null) {
      return [];
    }
    try {
      final response = await _warrantyService.listCodesByPerson(
        widget.businessId,
        widget.person.id!,
        limit: 100,
        skip: 0,
      );
      return response.items;
    } catch (e) {
      return [];
    }
  }

  Widget _buildWarrantyCard(ThemeData theme, WarrantyCode warranty, AppLocalizations t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          Icons.verified_user,
          color: _getStatusColor(warranty.status, theme),
        ),
        title: Text(warranty.code),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سریال: ${warranty.warrantySerial}'),
            Text('وضعیت: ${_getStatusLabel(warranty.status, t)}'),
            if (warranty.activatedAt != null)
              Text('فعال شده: ${HesabixDateUtils.formatDateTime(warranty.activatedAt!, _calendarController?.isJalali ?? true)}'),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: () {
            final calendarController = _calendarController ?? ApiClient.getCalendarController();
            if (calendarController == null) {
              CalendarController.load().then((c) {
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => WarrantyCodeDetailsDialog(
                      warrantyCode: warranty,
                      calendarController: c,
                    ),
                  );
                }
              });
            } else {
              showDialog(
                context: context,
                builder: (context) => WarrantyCodeDetailsDialog(
                  warrantyCode: warranty,
                  calendarController: calendarController,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Color _getStatusColor(WarrantyStatus status, ThemeData theme) {
    switch (status) {
      case WarrantyStatus.activated:
        return Colors.green;
      case WarrantyStatus.expired:
        return Colors.orange;
      case WarrantyStatus.revoked:
        return Colors.red;
      default:
        return theme.colorScheme.primary;
    }
  }

  String _getStatusLabel(WarrantyStatus status, AppLocalizations t) {
    switch (status) {
      case WarrantyStatus.generated:
        return t.warrantyGenerated;
      case WarrantyStatus.activated:
        return t.warrantyActivated;
      case WarrantyStatus.expired:
        return t.warrantyExpired;
      case WarrantyStatus.used:
        return t.warrantyUsed;
      case WarrantyStatus.revoked:
        return t.warrantyRevoked;
    }
  }

  Widget _buildAttachmentsTab(ThemeData theme) {
    final personId = widget.person.id;
    if (personId == null) {
      return const Center(child: Text('برای الصاق فایل نیاز به شناسه معتبر شخص است.'));
    }

    final canAttach = widget.authStore.canWriteSection('people');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AttachedFilesWidget(
              refreshKey: _attachedFilesKey,
              businessId: widget.businessId,
              moduleContext: 'persons',
              contextId: personId.toString(),
              title: 'فایل‌های الصاق شده',
              allowDelete: canAttach,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: canAttach && !_uploadingFile ? _attachFile : null,
            icon: _uploadingFile
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.attach_file),
            label: Text(_uploadingFile ? 'در حال آپلود...' : 'افزودن فایل'),
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesTab(AppLocalizations t, ThemeData theme) {
    final personId = widget.person.id;
    if (personId == null) {
      return const Center(child: Text('برای مشاهده تاریخچه تعامل نیاز به شناسه معتبر شخص است.'));
    }
    final crmService = CrmService(apiClient: ApiClient());
    final canAdd = widget.authStore.hasBusinessPermission('crm', 'write');
    return KeyedSubtree(
      key: ValueKey('activities_$_activitiesRefreshKey'),
      child: FutureBuilder<Map<String, dynamic>>(
        future: crmService.listActivities(businessId: widget.businessId, personId: personId, limit: 100),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text('خطا در بارگذاری: ${snapshot.error}', textAlign: TextAlign.center),
              ],
            ),
          );
        }
        final data = snapshot.data ?? <String, dynamic>{};
        final items = data['items'] is List ? (data['items'] as List).cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canAdd)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => _showAddActivityDialog(personId, crmService, () {
                    setState(() => _activitiesRefreshKey++);
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('ثبت فعالیت'),
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 48, color: theme.colorScheme.outline),
                          const SizedBox(height: 12),
                          Text('هنوز فعالیتی ثبت نشده است.', style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final a = items[index];
                        final type = a['activity_type']?.toString() ?? '';
                        final subject = a['subject']?.toString() ?? '';
                        final desc = a['description']?.toString() ?? '';
                        final date = a['activity_date_formatted'] ?? a['activity_date']?.toString() ?? '';
                        final typeLabel = _activityTypeLabel(type);
                        final activityId = a['id'] as int?;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Icon(_activityTypeIcon(type), color: theme.colorScheme.onPrimaryContainer),
                            ),
                            title: Text(subject.isNotEmpty ? subject : typeLabel),
                            subtitle: Text(desc.isNotEmpty ? desc : typeLabel),
                            trailing: canAdd
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(date, style: theme.textTheme.bodySmall),
                                      PopupMenuButton<String>(
                                        onSelected: (v) {
                                          if (v == 'edit') _showEditActivityDialog(personId, crmService, a, () => setState(() => _activitiesRefreshKey++));
                                          if (v == 'delete' && activityId != null) _deleteActivity(crmService, activityId, () => setState(() => _activitiesRefreshKey++));
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                          const PopupMenuItem(value: 'delete', child: Text('حذف')),
                                        ],
                                      ),
                                    ],
                                  )
                                : Text(date, style: theme.textTheme.bodySmall),
                            onTap: canAdd ? () => _showEditActivityDialog(personId, crmService, a, () => setState(() => _activitiesRefreshKey++)) : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
      ),
    );
  }

  Widget _buildDealsTab(AppLocalizations t, ThemeData theme) {
    final personId = widget.person.id;
    if (personId == null) {
      return const Center(child: Text('برای مشاهده فرصت‌های فروش نیاز به شناسه معتبر شخص است.'));
    }
    final crmService = CrmService(apiClient: ApiClient());
    return FutureBuilder<Map<String, dynamic>>(
      future: crmService.listDeals(
        businessId: widget.businessId,
        personId: personId,
        limit: 100,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 12),
                Text('خطا در بارگذاری: ${snapshot.error}', textAlign: TextAlign.center),
              ],
            ),
          );
        }
        final data = snapshot.data ?? <String, dynamic>{};
        final items = data['items'] is List
            ? (data['items'] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.trending_up_outlined, size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 12),
                Text('فرصت فروشی برای این مشتری ثبت نشده است.', style: theme.textTheme.bodyMedium),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final d = items[index];
            final title = d['title']?.toString() ?? '';
            final stageName = d['stage_name']?.toString() ?? '';
            final amount = (d['amount'] is num) ? (d['amount'] as num).toDouble() : 0.0;
            final formatter = NumberFormat('#,##0');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.trending_up, color: theme.colorScheme.onPrimaryContainer),
                ),
                title: Text(title),
                subtitle: Text('$stageName · ${formatter.format(amount)} ریال'),
              ),
            );
          },
        );
      },
    );
  }

  IconData _activityTypeIcon(String type) {
    switch (type) {
      case 'call':
        return Icons.phone;
      case 'email':
        return Icons.email;
      case 'meeting':
        return Icons.event;
      case 'note':
        return Icons.note;
      default:
        return Icons.history;
    }
  }

  String _activityTypeLabel(String type) {
    switch (type) {
      case 'call':
        return 'تماس';
      case 'email':
        return 'ایمیل';
      case 'meeting':
        return 'جلسه';
      case 'note':
        return 'یادداشت';
      default:
        return type.isNotEmpty ? type : 'فعالیت';
    }
  }

  Future<void> _showAddActivityDialog(int personId, CrmService crmService, VoidCallback onSaved) async {
    await _ensureCalendarController();
    if (!mounted) return;
    List<Map<String, dynamic>> activityTypes = [];
    try {
      final result = await crmService.listProcessDefinitions(
        businessId: widget.businessId,
        processType: 'activity_type',
        isActive: true,
      );
      final list = result is List ? result : (result is Map && result['data'] is List ? result['data'] as List : <dynamic>[]);
      for (final p in list) {
        final proc = p as Map<String, dynamic>?;
        if (proc == null) continue;
        final stages = proc['stages'] as List<dynamic>? ?? [];
        for (final s in stages) {
          final stage = s as Map<String, dynamic>?;
          if (stage == null) continue;
          final code = stage['stage_code']?.toString() ?? '';
          final name = stage['name']?.toString() ?? code;
          if (code.isNotEmpty) {
            activityTypes.add({'code': code, 'name': name});
          }
        }
      }
    } catch (_) {}
    if (activityTypes.isEmpty) {
      activityTypes = [
        {'code': 'call', 'name': 'تماس'},
        {'code': 'email', 'name': 'ایمیل'},
        {'code': 'meeting', 'name': 'جلسه'},
        {'code': 'note', 'name': 'یادداشت'},
      ];
    }
    final subjectController = TextEditingController();
    final descController = TextEditingController();
    var selectedType = 'call';
    if (activityTypes.isNotEmpty) {
      final firstCode = activityTypes.first['code'] as String?;
      if (firstCode != null && firstCode.isNotEmpty) selectedType = firstCode;
    }
    var selectedDate = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('ثبت فعالیت'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'نوع فعالیت'),
                  items: activityTypes.map((t) => DropdownMenuItem<String>(
                        value: t['code'] as String?,
                        child: Text(t['name']?.toString() ?? t['code']?.toString() ?? ''),
                      )).toList(),
                  onChanged: (v) => setState(() => selectedType = v ?? selectedType),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: subjectController,
                  decoration: const InputDecoration(labelText: 'موضوع'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'توضیحات'),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('تاریخ: ${_activityDateDisplayLabel(selectedDate)}'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await _pickActivityDate(context, selectedDate);
                      if (picked != null) setState(() => selectedDate = picked);
                    },
                    child: const Text('تغییر'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('انصراف')),
            FilledButton(
              onPressed: () async {
                try {
                  await crmService.createActivity(
                    businessId: widget.businessId,
                    personId: personId,
                    activityType: selectedType,
                    subject: subjectController.text.trim().isEmpty ? null : subjectController.text.trim(),
                    description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                    activityDate: selectedDate,
                  );
                  if (!mounted) return;
                  Navigator.of(ctx).pop(true);
                  SnackBarHelper.show(context, message: 'فعالیت ثبت شد');
                  onSaved();
                } catch (e) {
                  if (mounted) SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditActivityDialog(int personId, CrmService crmService, Map<String, dynamic> a, VoidCallback onSaved) async {
    await _ensureCalendarController();
    if (!mounted) return;
    final activityId = (a['id'] as num?)?.toInt();
    if (activityId == null) return;
    final subjectController = TextEditingController(text: a['subject']?.toString() ?? '');
    final descController = TextEditingController(text: a['description']?.toString() ?? '');
    var selectedType = a['activity_type']?.toString() ?? 'call';
    var selectedDate = a['activity_date'] != null ? DateTime.tryParse(a['activity_date'].toString()) ?? DateTime.now() : DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('ویرایش فعالیت'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedType,
                  decoration: const InputDecoration(labelText: 'نوع فعالیت'),
                  items: const [
                    DropdownMenuItem(value: 'call', child: Text('تماس')),
                    DropdownMenuItem(value: 'email', child: Text('ایمیل')),
                    DropdownMenuItem(value: 'meeting', child: Text('جلسه')),
                    DropdownMenuItem(value: 'note', child: Text('یادداشت')),
                  ],
                  onChanged: (v) => setState(() => selectedType = v ?? selectedType),
                ),
                const SizedBox(height: 12),
                TextField(controller: subjectController, decoration: const InputDecoration(labelText: 'موضوع')),
                const SizedBox(height: 12),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'توضیحات'), maxLines: 3),
                const SizedBox(height: 12),
                ListTile(
                  title: Text('تاریخ: ${_activityDateDisplayLabel(selectedDate)}'),
                  trailing: TextButton(
                    onPressed: () async {
                      final picked = await _pickActivityDate(context, selectedDate);
                      if (picked != null) setState(() => selectedDate = picked);
                    },
                    child: const Text('تغییر'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('انصراف')),
            FilledButton(
              onPressed: () async {
                try {
                  await crmService.updateActivity(
                    businessId: widget.businessId,
                    activityId: activityId,
                    activityType: selectedType,
                    subject: subjectController.text.trim().isEmpty ? null : subjectController.text.trim(),
                    description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                    activityDate: selectedDate,
                  );
                  if (!mounted) return;
                  Navigator.of(ctx).pop(true);
                  SnackBarHelper.show(context, message: 'فعالیت ویرایش شد');
                  onSaved();
                } catch (e) {
                  if (mounted) SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) onSaved();
  }

  Future<void> _deleteActivity(CrmService crmService, int activityId, VoidCallback onSaved) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف فعالیت'),
        content: const Text('آیا از حذف این فعالیت اطمینان دارید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('خیر')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('بله، حذف')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await crmService.deleteActivity(businessId: widget.businessId, activityId: activityId);
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'فعالیت حذف شد');
      onSaved();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.show(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}', isError: true);
    }
  }

  Widget _buildShareTab(AppLocalizations t, ThemeData theme) {
    if (_loadingShareLink) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_shareLinkError != null && _shareLink == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _shareLinkError!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadShareLinkStatus,
              icon: const Icon(Icons.refresh),
              label: Text(t.personShareRetry),
            ),
          ],
        ),
      );
    }

    final canEditPeople = widget.authStore.canWriteSection('people');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_shareLink != null) _buildActiveShareLinkCard(t, theme, _shareLink!, canEditPeople),
          _buildShareLinkSettingsCard(t, theme, canEditPeople),
        ],
      ),
    );
  }

  Widget _buildActiveShareLinkCard(AppLocalizations t, ThemeData theme, PersonShareLink link, bool canEditPeople) {
    final formatter = NumberFormat('#,##0');
    final isJalali = _calendarController?.isJalali ?? true;
    final expiryText = link.expiresAt != null ? HesabixDateUtils.formatDateTime(link.expiresAt, isJalali) : t.personShareNoExpiry;
    final lastViewText = link.lastViewAt != null ? HesabixDateUtils.formatDateTime(link.lastViewAt, isJalali) : t.personShareNotSet;
    final viewCount = formatter.format(link.viewCount);

    Color statusColor;
    switch (link.status) {
      case 'فعال':
        statusColor = Colors.green[700] ?? theme.colorScheme.primary;
        break;
      case 'منقضی':
        statusColor = theme.colorScheme.error;
        break;
      default:
        statusColor = theme.colorScheme.secondary;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.personShareLinkActive, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      SelectableText(
                        link.shortUrl,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: t.copyLink,
                  onPressed: _copyShareLink,
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _shareLinkStatChip(theme, t.personShareStatus, link.status, statusColor),
                _shareLinkStatChip(theme, t.personShareExpiry, expiryText, theme.colorScheme.onSurface),
                _shareLinkStatChip(theme, t.personShareViews, viewCount, theme.colorScheme.primary),
                _shareLinkStatChip(theme, t.personShareLastView, lastViewText, theme.colorScheme.onSurface),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _smsRecipientController,
              decoration: InputDecoration(
                labelText: t.personShareSendToNumberLabel,
                hintText: t.personShareSendToNumberHint,
                prefixIcon: const Icon(Icons.phone_outlined),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _copyAndShareLink,
                  icon: const Icon(Icons.share),
                  label: Text(t.personShareCopyAndSendLink),
                ),
                OutlinedButton.icon(
                  onPressed: (((_firstNonEmptyPersonMobile(_person)?.isNotEmpty == true) ||
                              _smsRecipientController.text.trim().isNotEmpty) &&
                          widget.authStore.hasBusinessPermission('notifications', 'send') &&
                          !_sendingLinkSms)
                      ? _sendShareLinkBySms
                      : null,
                  icon: _sendingLinkSms
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sms),
                  label: Text(_sendingLinkSms ? t.personShareSendingSms : t.personShareSendLinkBySms),
                ),
                OutlinedButton.icon(
                  onPressed: canEditPeople && !_revokingShareLink ? _revokeShareLink : null,
                  icon: _revokingShareLink
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link_off),
                  label: Text(_revokingShareLink ? t.personShareRevoking : t.personShareRevokeLink),
                ),
                TextButton.icon(
                  onPressed: _loadingShareLink ? null : _loadShareLinkStatus,
                  icon: const Icon(Icons.refresh),
                  label: Text(t.personShareRefreshStatus),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t.personShareLinkHint,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareLinkStatChip(ThemeData theme, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareLinkSettingsCard(AppLocalizations t, ThemeData theme, bool canEditPeople) {
    final expiryOptions = <Map<String, dynamic>>[
      {'label': t.personShareExpiry7Days, 'value': 168},
      {'label': t.personShareExpiry14Days, 'value': 336},
      {'label': t.personShareExpiry30Days, 'value': 720},
      {'label': t.personShareExpiryNone, 'value': null},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.personShareCreateNew, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              t.personShareCreateWarning,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int?>(
              value: _selectedExpiryHours,
              decoration: InputDecoration(labelText: t.personShareExpiryLabel),
              items: expiryOptions
                  .map(
                    (opt) => DropdownMenuItem<int?>(
                      value: opt['value'] as int?,
                      child: Text(opt['label'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (val) => setState(() => _selectedExpiryHours = val),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _maxViewsController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.personShareMaxViewsLabel,
                hintText: t.personShareMaxViewsHint,
              ),
            ),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.personShareDocumentsLimit, style: theme.textTheme.bodyMedium),
                Slider(
                  value: _documentsLimit.toDouble(),
                  min: 10,
                  max: 200,
                  divisions: 19,
                  label: '$_documentsLimit ردیف',
                  onChanged: (value) => setState(() => _documentsLimit = value.round()),
                ),
              ],
            ),
            SwitchListTile.adaptive(
              value: _includeLedger,
              title: Text(t.personShareIncludeLedger),
              subtitle: Text(t.personShareIncludeLedgerSubtitle),
              onChanged: (value) => setState(() => _includeLedger = value),
            ),
            SwitchListTile.adaptive(
              value: _includeInvoices,
              title: Text(t.personShareIncludeInvoices),
              subtitle: Text(t.personShareIncludeInvoicesSubtitle),
              onChanged: (value) => setState(() => _includeInvoices = value),
            ),
            if (!_includeLedger && !_includeInvoices) ...[
              const SizedBox(height: 8),
              Text(
                t.personShareValidationAtLeastOne,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: canEditPeople && !_creatingShareLink && (_includeLedger || _includeInvoices) ? _createShareLink : null,
                  icon: _creatingShareLink
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link),
                  label: Text(_creatingShareLink ? t.personShareCreating : _shareLink == null ? t.personShareCreateButton : t.personShareCreateButtonNew),
                ),
                TextButton.icon(
                  onPressed: _loadingShareLink ? null : _loadShareLinkStatus,
                  icon: const Icon(Icons.refresh),
                  label: Text(t.personShareRefresh),
                ),
              ],
            ),
            if (_shareLinkError != null) ...[
              const SizedBox(height: 12),
              Text(
                _shareLinkError!,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (!canEditPeople) ...[
              const SizedBox(height: 12),
              Text(
                t.personSharePermissionHint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    );
  }

  Widget _buildFinancialSummaryCard(ThemeData theme) {
    final formatter = NumberFormat('#,##0');
    final statusText = _summaryStatus ?? _person?.status ?? 'نامشخص';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'خلاصه وضعیت مالی سال جاری',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                if (_currentFiscalYearName != null)
                  Chip(
                    label: Text(_currentFiscalYearName!),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                    backgroundColor: theme.colorScheme.surfaceContainerLowest,
                  )
                else
                  Text(
                    'سال مالی جاری',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'تازه‌سازی خلاصه مالی',
                  onPressed: _loadingSummary ? null : _loadFinancialSummary,
                  icon: _loadingSummary
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_summaryError != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _summaryError!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                  TextButton(onPressed: _loadFinancialSummary, child: const Text('تلاش مجدد')),
                ],
              )
            else if (_loadingSummary && _summaryDebit == null && _summaryCredit == null)
              const LinearProgressIndicator()
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildSummaryStat(
                    theme,
                    label: 'جمع بدهکار',
                    value: _summaryDebit,
                    color: theme.colorScheme.error,
                    icon: Icons.south_west,
                    formatter: formatter,
                  ),
                  _buildSummaryStat(
                    theme,
                    label: 'جمع بستانکار',
                    value: _summaryCredit,
                    color: Colors.green[700],
                    icon: Icons.north_east,
                    formatter: formatter,
                  ),
                  _buildSummaryStat(
                    theme,
                    label: 'تراز',
                    value: _summaryBalance ?? _person?.balance,
                    color: _summaryBalance == null
                        ? theme.colorScheme.primary
                        : (_summaryBalance! > 0
                            ? Colors.green[700]
                            : _summaryBalance! < 0
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary),
                    icon: Icons.account_balance_wallet,
                    formatter: formatter,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _statusColor(statusText).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _statusColor(statusText).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified, size: 18, color: _statusColor(statusText)),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('وضعیت', style: theme.textTheme.bodySmall),
                            Text(
                              statusText,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: _statusColor(statusText),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(
    ThemeData theme, {
    required String label,
    required double? value,
    required Color? color,
    required IconData icon,
    required NumberFormat formatter,
  }) {
    final display = value == null ? '-' : formatter.format(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color ?? theme.colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text(
                display,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color ?? theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'بستانکار':
        return Colors.green[700] ?? Colors.green;
      case 'بدهکار':
        return Colors.red;
      case 'بدون تراکنش':
        return Colors.blueGrey;
      case 'بالانس':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  Uri? _socialValueToUri(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('http://') ||
        s.startsWith('https://') ||
        s.startsWith('tel:') ||
        s.startsWith('mailto:') ||
        s.startsWith('tg:') ||
        s.startsWith('intent:')) {
      try {
        return Uri.parse(s);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Widget _personSocialValueWidget(BuildContext context, String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) {
      return Text('—', style: Theme.of(context).textTheme.bodyMedium);
    }
    final uri = _socialValueToUri(t);
    if (uri != null) {
      return InkWell(
        onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
        child: Text(
          t,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
        ),
      );
    }
    return SelectableText(t, style: Theme.of(context).textTheme.bodyMedium);
  }

  Widget _buildInfoGrid(List<_InfoRow> rows) {
    final visibleRows = rows.where((row) => row.value != null && row.value!.trim().isNotEmpty && row.value != '-').toList();
    if (visibleRows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: visibleRows.map((row) => _InfoTile(row: row)).toList(),
    );
  }

  Widget _buildHeaderChip(String text, ThemeData theme, {IconData? icon, Color? iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor ?? theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _attachFile() async {
    final personId = widget.person.id;
    if (personId == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) return;

      setState(() => _uploadingFile = true);
      try {
        await _storageService.uploadFile(
          businessId: widget.businessId,
          fileBytes: file.bytes!,
          filename: file.name,
          moduleContext: 'persons',
          contextId: personId.toString(),
        );
        if (!mounted) return;
        SnackBarHelper.showSuccess(context, message: 'فایل با موفقیت الصاق شد');
        _attachedFilesKey.refresh();
      } on DioException catch (e) {
        if (!mounted) return;
        await _handleUploadError(e);
      } catch (e) {
        if (!mounted) return;
        SnackBarHelper.showError(
          context,
          message:
              'خطا در آپلود فایل: ${ErrorExtractor.forContext(e, context)}',
        );
      } finally {
        if (mounted) {
          setState(() => _uploadingFile = false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingFile = false);
      SnackBarHelper.showError(context, message: 'خطا: ${ErrorExtractor.forContext(e, context)}');
    }
  }

  Future<void> _handleUploadError(DioException e) async {
    final response = e.response;
    if (response != null && response.data is Map) {
      final map = Map<String, dynamic>.from(response.data as Map);
      final error = map['error'];
      if (error is Map && error['code'] == 'STORAGE_LIMIT_EXCEEDED') {
        await _showStorageLimitDialog(Map<String, dynamic>.from(error));
        return;
      }
      final message = error is Map<String, dynamic> ? error['message']?.toString() : null;
      if (message != null) {
        if (!mounted) return;
        SnackBarHelper.showError(context, message: message);
        return;
      }
    }
    if (!mounted) return;
    SnackBarHelper.showError(context, message: 'خطا در آپلود فایل');
  }

  Future<void> _showStorageLimitDialog(Map<String, dynamic> error) async {
    final totalLimit = (error['total_limit_gb'] as num?)?.toDouble() ?? 0;
    final currentUsage = (error['current_usage_gb'] as num?)?.toDouble() ?? 0;
    final required = (error['required_gb'] as num?)?.toDouble() ?? 0;
    final available = (error['available_gb'] as num?)?.toDouble() ?? 0;
    final overUsage = (error['over_usage_gb'] as num?)?.toDouble() ?? 0;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('محدودیت فضای ذخیره‌سازی'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(error['message']?.toString() ?? 'حجم فایل از محدودیت فضای ذخیره‌سازی بیشتر است.'),
              const SizedBox(height: 16),
              _buildStorageInfoRow('فضای کل', '$totalLimit GB', theme),
              _buildStorageInfoRow('مصرف شده', '$currentUsage GB', theme),
              _buildStorageInfoRow('فضای آزاد', '$available GB', theme),
              const Divider(),
              _buildStorageInfoRow('حجم مورد نیاز', '$required GB', theme, highlight: true),
              _buildStorageInfoRow('حجم اضافه', '$overUsage GB', theme, highlight: true, isError: true),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('باشه')),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                context.go('/business/${widget.businessId}/storage-files');
              },
              icon: const Icon(Icons.storage),
              label: const Text('مدیریت فضا'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStorageInfoRow(String label, String value, ThemeData theme, {bool highlight = false, bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
              color: isError ? Colors.red : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String? value;

  const _InfoRow(this.label, this.value);
}

class _InfoTile extends StatelessWidget {
  final _InfoRow row;

  const _InfoTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue = (row.value == null || row.value!.trim().isEmpty) ? '-' : row.value!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(row.label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(
            displayValue,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _FinancialSummaryResult {
  final double debit;
  final double credit;
  final double balance;
  final String status;

  const _FinancialSummaryResult({
    required this.debit,
    required this.credit,
    required this.balance,
    required this.status,
  });
}

