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
import 'package:hesabix_ui/models/person_share_link.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/business_storage_service.dart';
import 'package:hesabix_ui/services/person_service.dart';
import 'package:hesabix_ui/widgets/attached_files/attached_files_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/document/document_details_dialog.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:intl/intl.dart';

class PersonDetailsDialog extends StatefulWidget {
  final int businessId;
  final Person person;
  final AuthStore authStore;

  const PersonDetailsDialog({
    super.key,
    required this.businessId,
    required this.person,
    required this.authStore,
  });

  @override
  State<PersonDetailsDialog> createState() => _PersonDetailsDialogState();
}

class _PersonDetailsDialogState extends State<PersonDetailsDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late final PersonService _personService;
  late final BusinessStorageService _storageService;
  final AttachedFilesWidgetKey _attachedFilesKey = AttachedFilesWidgetKey();
  final GlobalKey _kardexTableKey = GlobalKey();
  Person? _person;
  bool _loadingDetails = false;
  String? _detailsError;
  bool _uploadingFile = false;
  CalendarController? _calendarController;
  bool _loadingCalendar = false;
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
  int? _selectedExpiryHours = 168;
  bool _includeLedger = true;
  bool _includeInvoices = true;
  int _documentsLimit = 50;
  final TextEditingController _maxViewsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _person = widget.person;
    _personService = PersonService();
    _storageService = BusinessStorageService(ApiClient());
    _tabController = TabController(length: 4, vsync: this);
    _loadPersonDetails();
    _ensureCalendarController();
    _initFinancialContext();
    _loadShareLinkStatus();
  }

  Future<void> _ensureCalendarController() async {
    if (_calendarController != null || _loadingCalendar) return;
    _loadingCalendar = true;
    final controller = await CalendarController.load();
    if (!mounted) return;
    setState(() {
      _calendarController = controller;
      _loadingCalendar = false;
    });
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
        _summaryError = e.toString();
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
        _shareLinkError = e.toString();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لینک اشتراک با موفقیت ایجاد شد'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shareLinkError = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا در ایجاد لینک: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
        _maxViewsController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لینک اشتراک لغو شد'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا در لغو لینک: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _revokingShareLink = false);
      }
    }
  }

  Future<void> _copyShareLink() async {
    final link = _shareLink?.shortUrl;
    if (link == null || link.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('لینک در کلیپ‌بورد کپی شد'),
        backgroundColor: Colors.green,
      ),
    );
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
        _detailsError = 'خطا در بارگذاری اطلاعات شخص: $e';
        _loadingDetails = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _maxViewsController.dispose();
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
                tabs: const [
                  Tab(icon: Icon(Icons.info_outline), text: 'اطلاعات شخص'),
                  Tab(icon: Icon(Icons.assignment), text: 'کارت حساب'),
                  Tab(icon: Icon(Icons.attach_file), text: 'فایل‌ها'),
                  Tab(icon: Icon(Icons.share), text: 'اشتراک‌گذاری'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildInfoTab(theme),
                  _buildAccountCardTab(t, theme),
                  _buildAttachmentsTab(theme),
                  _buildShareTab(theme),
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
            _InfoRow('نام', person.firstName),
            _InfoRow('نام خانوادگی', person.lastName),
            _InfoRow('انواع شخص', person.personTypes.map((e) => e.persianName).join('، ')),
            _InfoRow('نام سازمان', person.companyName),
            _InfoRow('شناسه پرداخت', person.paymentId),
          ]),
          const SizedBox(height: 24),
          _buildSectionHeader('اطلاعات تماس'),
          _buildInfoGrid([
            _InfoRow('موبایل', person.mobile),
            _InfoRow('تلفن ثابت', person.phone),
            _InfoRow('ایمیل', person.email),
            _InfoRow('وب‌سایت', person.website),
            _InfoRow('کد پستی', person.postalCode),
            _InfoRow('آدرس', person.address),
          ]),
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

  Widget _buildShareTab(ThemeData theme) {
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
              label: const Text('تلاش مجدد'),
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
          if (_shareLink != null) _buildActiveShareLinkCard(theme, _shareLink!),
          _buildShareLinkSettingsCard(theme),
        ],
      ),
    );
  }

  Widget _buildActiveShareLinkCard(ThemeData theme, PersonShareLink link) {
    final formatter = NumberFormat('#,##0');
    final isJalali = _calendarController?.isJalali ?? true;
    final expiryText = link.expiresAt != null ? HesabixDateUtils.formatDateTime(link.expiresAt, isJalali) : 'بدون انقضا';
    final lastViewText = link.lastViewAt != null ? HesabixDateUtils.formatDateTime(link.lastViewAt, isJalali) : 'ثبت نشده';
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
                      Text('لینک فعال', style: theme.textTheme.titleMedium),
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
                  tooltip: 'کپی لینک',
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
                _shareLinkStatChip(theme, 'وضعیت', link.status, statusColor),
                _shareLinkStatChip(theme, 'انقضا', expiryText, theme.colorScheme.onSurface),
                _shareLinkStatChip(theme, 'بازدید', viewCount, theme.colorScheme.primary),
                _shareLinkStatChip(theme, 'آخرین بازدید', lastViewText, theme.colorScheme.onSurface),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _copyShareLink,
                  icon: const Icon(Icons.share),
                  label: const Text('کپی و ارسال لینک'),
                ),
                OutlinedButton.icon(
                  onPressed: _revokingShareLink ? null : _revokeShareLink,
                  icon: _revokingShareLink
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link_off),
                  label: Text(_revokingShareLink ? 'در حال لغو...' : 'لغو لینک'),
                ),
                TextButton.icon(
                  onPressed: _loadingShareLink ? null : _loadShareLinkStatus,
                  icon: const Icon(Icons.refresh),
                  label: const Text('بروزرسانی وضعیت'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'این لینک کوتاه برای ارسال در پیامک و شبکه‌های اجتماعی آماده است.',
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

  Widget _buildShareLinkSettingsCard(ThemeData theme) {
    final expiryOptions = <Map<String, dynamic>>[
      {'label': '۷ روز (پیش‌فرض)', 'value': 168},
      {'label': '۱۴ روز', 'value': 336},
      {'label': '۳۰ روز', 'value': 720},
      {'label': 'بدون انقضا', 'value': null},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ساخت لینک جدید', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              'با ایجاد لینک جدید، لینک قبلی (در صورت وجود) غیرفعال می‌شود.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int?>(
              value: _selectedExpiryHours,
              decoration: const InputDecoration(labelText: 'زمان اعتبار لینک'),
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
              decoration: const InputDecoration(
                labelText: 'حداکثر تعداد بازدید مجاز',
                hintText: 'مثلاً 5 (خالی = بدون محدودیت)',
              ),
            ),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تعداد ردیف کارت حساب', style: theme.textTheme.bodyMedium),
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
              title: const Text('نمایش کارت حساب'),
              subtitle: const Text('فهرست تراکنش‌های حساب شخص'),
              onChanged: (value) => setState(() => _includeLedger = value),
            ),
            SwitchListTile.adaptive(
              value: _includeInvoices,
              title: const Text('نمایش لیست فاکتورها'),
              subtitle: const Text('آخرین فاکتورهای مرتبط با این شخص'),
              onChanged: (value) => setState(() => _includeInvoices = value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _creatingShareLink ? null : _createShareLink,
                  icon: _creatingShareLink
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link),
                  label: Text(_creatingShareLink ? 'در حال تولید...' : _shareLink == null ? 'ایجاد لینک' : 'تولید لینک جدید'),
                ),
                TextButton.icon(
                  onPressed: _loadingShareLink ? null : _loadShareLinkStatus,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تازه‌سازی اطلاعات'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فایل با موفقیت الصاق شد'), backgroundColor: Colors.green),
        );
        _attachedFilesKey.refresh();
      } on DioException catch (e) {
        if (!mounted) return;
        await _handleUploadError(e);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در آپلود فایل: $e'), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) {
          setState(() => _uploadingFile = false);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingFile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا: $e'), backgroundColor: Colors.red),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red),
        );
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('خطا در آپلود فایل'), backgroundColor: Colors.red),
    );
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

