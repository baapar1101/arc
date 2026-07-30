import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_widget.dart';
import 'package:hesabix_ui/widgets/data_table/data_table_config.dart';
import 'package:hesabix_ui/services/business_dashboard_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/widgets/data_table/helpers/data_table_utils.dart';
import 'package:hesabix_ui/services/list_filter_preferences_service.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/widgets/invoice/person_combobox_widget.dart';
import 'package:hesabix_ui/widgets/invoice/account_tree_combobox_widget.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/models/person_model.dart';
import 'package:hesabix_ui/widgets/project/project_selector_widget.dart';
import 'package:hesabix_ui/utils/responsive_helper.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/currency_display_utils.dart';

class GeneralLedgerReportPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final Account? initialAccount;
  final int? initialFiscalYearId;
  final DateTime? initialDateFrom;
  final DateTime? initialDateTo;
  final int? initialCurrencyId;
  final int? initialProjectId;
  
  const GeneralLedgerReportPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    this.initialAccount,
    this.initialFiscalYearId,
    this.initialDateFrom,
    this.initialDateTo,
    this.initialCurrencyId,
    this.initialProjectId,
  });

  @override
  State<GeneralLedgerReportPage> createState() => _GeneralLedgerReportPageState();
}

class _GeneralLedgerReportPageState extends State<GeneralLedgerReportPage> {
  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedFiscalYearId;
  int? _selectedCurrencyId;
  int? _selectedProjectId;  // 🆕 فیلتر پروژه
  List<Account> _selectedAccounts = [];
  Account? _accountToAdd;
  Person? _selectedPerson;
  bool _includeProforma = false;
  
  // Data
  List<Map<String, dynamic>> _fiscalYears = [];
  List<Map<String, dynamic>> _currencies = [];
  
  // Summary from API response
  Map<String, dynamic>? _summary;
  bool _isExportingElectronic = false;

  /// فیلترها به‌صورت پیش‌فرض بسته تا فضای کمتری اشغال شود
  bool _filtersExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialAccount != null) {
      _selectedAccounts = [widget.initialAccount!];
    }
    if (widget.initialFiscalYearId != null) {
      _selectedFiscalYearId = widget.initialFiscalYearId;
    }
    if (widget.initialDateFrom != null) {
      _fromDate = widget.initialDateFrom;
    }
    if (widget.initialDateTo != null) {
      _toDate = widget.initialDateTo;
    }
    if (widget.initialCurrencyId != null) {
      _selectedCurrencyId = widget.initialCurrencyId;
    }
    if (widget.initialProjectId != null) {
      _selectedProjectId = widget.initialProjectId;
    }
    _loadFiscalYears();
    _loadCurrencies();
  }

  Future<void> _loadFiscalYears() async {
    try {
      final svc = BusinessDashboardService(ApiClient());
      final items = await svc.listFiscalYears(widget.businessId);
      if (!mounted) return;
      setState(() {
        _fiscalYears = items;
        if (_selectedFiscalYearId == null) {
          final current = items.firstWhere(
            (e) => (e['is_current'] == true),
            orElse: () => const <String, dynamic>{},
          );
          final id = current['id'];
          if (id is int) {
            _selectedFiscalYearId = id;
          }
        }
      });
    } catch (_) {
      // ignore errors
    }
  }

  Future<void> _loadCurrencies() async {
    try {
      final svc = CurrencyService(ApiClient());
      final items = await svc.listBusinessCurrencies(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _currencies = items;
        if (items.length <= 1) {
          // تک‌ارزی: بدون فیلتر ارز
          _selectedCurrencyId = null;
        } else if (_selectedCurrencyId == null && widget.initialCurrencyId == null) {
          // چندارزی: پیش‌فرض همه (= پایه)
          _selectedCurrencyId = null;
        } else if (_selectedCurrencyId == null && widget.initialCurrencyId != null) {
          _selectedCurrencyId = widget.initialCurrencyId;
        }
      });
    } catch (_) {
      // ignore errors
    }
  }

  void _refreshData() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _fetchSummary() async {
    if (_selectedAccounts.isEmpty) return;
    
    try {
      final api = ApiClient();
      final requestData = <String, dynamic>{
        'take': 1,
        'skip': 0,
        ..._additionalParams(),
      };
      
      final res = await api.post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/reports/general-ledger',
        data: requestData,
      );
      
      final body = res.data;
      if (body is Map<String, dynamic> && body['data'] is Map<String, dynamic>) {
        final data = body['data'] as Map<String, dynamic>;
        final summary = data['summary'] as Map<String, dynamic>?;
        if (summary != null && mounted) {
          setState(() {
            _summary = summary;
          });
        }
      }
    } catch (_) {
      // Ignore errors
    }
  }

  void _addAccount(Account? account) {
    if (account == null) return;
    if (_selectedAccounts.any((a) => a.id == account.id)) return;
    setState(() {
      _selectedAccounts.add(account);
      _accountToAdd = null;
    });
    _refreshData();
  }

  void _removeAccount(Account account) {
    setState(() {
      _selectedAccounts.removeWhere((a) => a.id == account.id);
    });
    _refreshData();
  }

  Map<String, dynamic> _additionalParams() {
    return {
      if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
      if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
      if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
      if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
      if (_selectedAccounts.isNotEmpty) 'account_ids': _selectedAccounts.map((a) => a.id).toList(),
      if (_selectedPerson != null) 'person_id': _selectedPerson!.id,
      if (_selectedProjectId != null) 'project_id': _selectedProjectId,  // 🆕 فیلتر پروژه
      'include_proforma': _includeProforma,
    };
  }

  bool _isSelectedCurrencyRial() {
    if (_selectedCurrencyId == null) return false;
    for (final currency in _currencies) {
      if (currency['id'] == _selectedCurrencyId) {
        final code = (currency['code'] ?? currency['name'] ?? '').toString().toUpperCase();
        return code == 'IRR' || code == 'RIAL';
      }
    }
    return false;
  }

  Future<void> _exportElectronicBooks() async {
    if (_isExportingElectronic) return;

    if (!_isSelectedCurrencyRial()) {
      SnackBarHelper.showError(
        context,
        message: 'برای خروجی دفتر الکترونیکی باید ارز ریال (IRR) انتخاب شود.',
      );
      return;
    }

    setState(() => _isExportingElectronic = true);
    final t = AppLocalizations.of(context);

    try {
      final api = ApiClient();
      final params = <String, dynamic>{
        if (_fromDate != null) 'date_from': _fromDate!.toIso8601String().split('T').first,
        if (_toDate != null) 'date_to': _toDate!.toIso8601String().split('T').first,
        if (_selectedFiscalYearId != null) 'fiscal_year_id': _selectedFiscalYearId,
        if (_selectedCurrencyId != null) 'currency_id': _selectedCurrencyId,
        'include_proforma': _includeProforma,
        'format': 'auto',
      };

      final response = await api.post<List<int>>(
        '/api/v1/businesses/${widget.businessId}/reports/general-ledger/export/electronic-books',
        data: params,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'X-Calendar-Type': widget.calendarController.isJalali ? 'jalali' : 'gregorian',
          },
        ),
      );

      final data = response.data;
      if (data == null || data.isEmpty) {
        throw Exception('پاسخ خالی از سرور');
      }

      final exportFormat = response.headers.value('x-export-format')?.toLowerCase() ?? 'xlsx';
      final extension = exportFormat == 'csv' ? 'csv' : 'xlsx';

      final result = await BytesExportService.exportResponse(
        response: response,
        fallbackBaseName:
            'electronic_general_ledger_${DateTime.now().millisecondsSinceEpoch}',
        fallbackExt: extension,
      );

      if (!mounted) return;
      BytesExportService.showFeedback(context, result);
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: '${t.exportError}: ${ErrorExtractor.forContext(e, context)}',
      );
    } finally {
      if (mounted) {
        setState(() => _isExportingElectronic = false);
      }
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value.toDouble() : double.tryParse(value.toString()) ?? 0.0;
    return DataTableUtils.formatNumber(n);
  }

  String get _baseCurrencyUnit {
    Map<String, dynamic>? def;
    for (final c in _currencies) {
      if (c['is_default'] == true) {
        def = c;
        break;
      }
    }
    def ??= _currencies.isNotEmpty ? _currencies.first : null;
    if (def == null) return 'ریال';
    return currencyUnitLabelFromBusinessCurrencyMap(def);
  }

  String _formatLedgerAmount(Map<String, dynamic> m, String amountKey, String nativeKey) {
    final amountsInBase = m['amounts_in_base'] == true || _selectedCurrencyId == null;
    final unit = (m['document_currency_symbol'] ?? m['document_currency_code'] ?? '')
        .toString();
    final dp = (m['document_currency_decimal_places'] as num?)?.toInt() ?? 2;
    return formatReportLedgerAmount(
      amount: m[amountKey],
      amountsInBase: amountsInBase,
      nativeAmount: m[nativeKey],
      documentCurrencyUnit: unit,
      baseUnit: _baseCurrencyUnit,
      baseDecimalPlaces: 0,
      nativeDecimalPlaces: dp,
    );
  }

  String _formatBalance(dynamic balance, dynamic balanceType) {
    if (balance == null) return '0';
    final b = balance is num ? balance.toDouble() : double.tryParse(balance.toString()) ?? 0.0;
    final formatted = DataTableUtils.formatNumber(b.abs());
    final type = (balanceType?.toString() ?? '').toLowerCase();
    if (type == 'debit') {
      return '$formatted بدهکار';
    } else if (type == 'credit') {
      return '$formatted بستانکار';
    }
    return formatted;
  }

  DataTableConfig<Map<String, dynamic>> _buildTableConfig(AppLocalizations t) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/businesses/${widget.businessId}/reports/general-ledger',
      businessId: widget.businessId,
      persistTableFiltersPageId: ListFilterPageIds.generalLedgerReportTable,
      reportModuleKey: 'general_ledger',
      reportSubtype: 'list',
      title: t.reportsGeneralLedgerTitle,
      showRowNumbers: true,
      columns: [
        DateColumn(
          'document_date',
          'تاریخ سند',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final date = m['document_date'];
            if (date == null) return '';
            DateTime? dateObj;
            if (date is DateTime) {
              dateObj = date;
            } else if (date is String) {
              dateObj = DateTime.tryParse(date);
            }
            if (dateObj == null) return date.toString();
            return HesabixDateUtils.formatForDisplay(
              dateObj,
              widget.calendarController.isJalali,
            );
          },
        ),
        TextColumn(
          'document_type_name',
          'نوع سند',
          formatter: (item) => (item as Map<String, dynamic>)['document_type_name']?.toString() ?? '',
        ),
        TextColumn(
          'document_code',
          'شماره سند',
          formatter: (item) => (item as Map<String, dynamic>)['document_code']?.toString() ?? '',
        ),
        TextColumn(
          'description',
          'شرح',
          formatter: (item) => (item as Map<String, dynamic>)['description']?.toString() ?? '',
        ),
        TextColumn(
          'counterpart_name',
          'طرف حساب',
          formatter: (item) => (item as Map<String, dynamic>)['counterpart_name']?.toString() ?? '',
        ),
        NumberColumn(
          'debit',
          'بدهکار',
          formatter: (item) => _formatLedgerAmount(
            item as Map<String, dynamic>,
            'debit',
            'native_debit',
          ),
        ),
        NumberColumn(
          'credit',
          'بستانکار',
          formatter: (item) => _formatLedgerAmount(
            item as Map<String, dynamic>,
            'credit',
            'native_credit',
          ),
        ),
        TextColumn(
          'balance',
          'مانده',
          formatter: (item) {
            final m = item as Map<String, dynamic>;
            final balance = m['balance'];
            final balanceType = m['balance_type'];
            return _formatBalance(balance, balanceType);
          },
        ),
      ],
      searchFields: const ['document_code', 'description', 'counterpart_name'],
      defaultPageSize: 50,
      additionalParams: _additionalParams(),
      showExportButtons: true,
      customHeaderActions: [
        Tooltip(
          message: 'خروجی دفتر کل الکترونیکی مطابق قالب سازمان امور مالیاتی (تمام حساب‌ها)',
          child: FilledButton.tonalIcon(
            onPressed: _isExportingElectronic ? null : _exportElectronicBooks,
            icon: _isExportingElectronic
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
            label: const Text('دفتر کل الکترونیکی'),
          ),
        ),
      ],
      excelEndpoint: '/api/v1/businesses/${widget.businessId}/reports/general-ledger/export/excel',
      pdfEndpoint: '/api/v1/businesses/${widget.businessId}/reports/general-ledger/export/pdf',
      getExportParams: () => _additionalParams(),
      footerTotals: {
        'debit': 'جمع بدهکار',
        'credit': 'جمع بستانکار',
      },
      defaultSortBy: 'document_date',
      defaultSortDesc: false,
      expandBodyHeightToFitRows: true,
    );
  }

  /// چیدمان فشرده و رسپانسیو فیلترها (داخل پنل جمع‌شونده)
  Widget _buildFilterGrid(BuildContext context, ColorScheme cs, bool isMobile) {
    final fullWidth = MediaQuery.sizeOf(context).width - 32;
    final fieldWidth = isMobile ? fullWidth : (fullWidth / 2).clamp(140.0, 260.0);

    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: isMobile ? double.infinity : fieldWidth,
        child: child,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ردیف اول: سال مالی، از تاریخ، تا تاریخ، ارز
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            cell(
              DropdownButtonFormField<int>(
                value: _selectedFiscalYearId,
                decoration: InputDecoration(
                  hintText: 'سال مالی',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                isExpanded: true,
                items: _fiscalYears.map((fy) {
                  return DropdownMenuItem<int>(
                    value: fy['id'] as int?,
                    child: Text(
                      fy['title']?.toString() ?? '',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedFiscalYearId = value;
                  });
                  _refreshData();
                },
              ),
            ),
            cell(
              DateInputField(
                value: _fromDate,
                calendarController: widget.calendarController,
                onChanged: (date) {
                  setState(() => _fromDate = date);
                  _refreshData();
                },
                hintText: 'از تاریخ',
              ),
            ),
            cell(
              DateInputField(
                value: _toDate,
                calendarController: widget.calendarController,
                onChanged: (date) {
                  setState(() => _toDate = date);
                  _refreshData();
                },
                hintText: 'تا تاریخ',
              ),
            ),
            cell(
              _currencies.length > 1
                  ? DropdownButtonFormField<int?>(
                value: _selectedCurrencyId,
                decoration: InputDecoration(
                  hintText: 'ارز',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('همه ارزها (معادل پایه)')),
                  ..._currencies.map<DropdownMenuItem<int?>>((c) {
                    final id = c['id'] as int?;
                    final code = (c['code'] ?? '').toString();
                    final name = (c['title'] ?? c['name'] ?? '').toString();
                    final displayName = code.isNotEmpty ? '$code - $name' : name;
                    return DropdownMenuItem<int?>(
                      key: ValueKey('currency_$id'),
                      value: id,
                      child: Text(displayName, overflow: TextOverflow.ellipsis, maxLines: 1),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() => _selectedCurrencyId = val);
                  _refreshData();
                },
              )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        // ردیف دوم: طرف حساب، پروژه، پیش‌نویس
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            cell(
              PersonComboboxWidget(
                businessId: widget.businessId,
                selectedPerson: _selectedPerson,
                onChanged: (person) {
                  setState(() => _selectedPerson = person);
                  _refreshData();
                },
              ),
            ),
            cell(
              ProjectSelectorWidget(
                businessId: widget.businessId,
                apiClient: ApiClient(),
                selectedProjectId: _selectedProjectId,
                onChanged: (projectId) {
                  setState(() => _selectedProjectId = projectId);
                  _refreshData();
                },
                allowNull: true,
                labelText: 'پروژه (همه)',
              ),
            ),
            cell(
              CheckboxListTile(
                title: const Text('شامل اسناد پیش‌نویس', style: TextStyle(fontSize: 13)),
                value: _includeProforma,
                onChanged: (value) {
                  setState(() => _includeProforma = value ?? false);
                  _refreshData();
                },
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ],
        ),
        // افزودن حساب و چیپ‌ها
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: isMobile ? fullWidth : 260,
              child: AccountTreeComboboxWidget(
                businessId: widget.businessId,
                selectedAccount: _accountToAdd,
                onChanged: _addAccount,
                label: 'افزودن حساب',
                hintText: 'انتخاب حساب',
              ),
            ),
            if (!isMobile) const SizedBox(width: 12),
            if (!isMobile)
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedAccounts.isEmpty
                      ? [
                          Text(
                            'هیچ حسابی انتخاب نشده',
                            style: TextStyle(color: cs.error, fontSize: 12),
                          ),
                        ]
                      : _selectedAccounts.map((account) {
                          return Chip(
                            label: Text(
                              '${account.code} - ${account.name}',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 12),
                            ),
                            onDeleted: () => _removeAccount(account),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                ),
              ),
          ],
        ),
        if (isMobile && _selectedAccounts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selectedAccounts.map((account) {
              return Chip(
                label: Text(
                  '${account.code} - ${account.name}',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12),
                ),
                onDeleted: () => _removeAccount(account),
                deleteIcon: const Icon(Icons.close, size: 16),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCards(BuildContext context, ColorScheme cs, bool isMobile) {
    final cards = [
      ('مانده ابتدای دوره', _formatBalance(_summary!['opening_balance'], _summary!['opening_balance_type'])),
      ('جمع بدهکار', _formatNumber(_summary!['total_debit'])),
      ('جمع بستانکار', _formatNumber(_summary!['total_credit'])),
      ('مانده انتهای دوره', _formatBalance(_summary!['closing_balance'], _summary!['closing_balance_type'])),
    ];
    if (isMobile) {
      return Column(
        children: cards.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.$1, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                    Text(e.$2, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      );
    }
    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(cards[i].$1, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.7))),
                    const SizedBox(height: 2),
                    Text(cards[i].$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isMobile = ResponsiveHelper.isMobile(context);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(t.reportsGeneralLedgerTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _refreshData,
          ),
        ],
      ),
      body: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // فیلترها — قابل جمع شدن، کمترین فضا
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    initiallyExpanded: _filtersExpanded,
                    onExpansionChanged: (v) => setState(() => _filtersExpanded = v),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    title: Row(
                      children: [
                        Icon(Icons.filter_list, size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          'فیلترها',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_selectedAccounts.isNotEmpty)
                          Text(
                            '(${_selectedAccounts.length} حساب)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.7),
                            ),
                          ),
                      ],
                    ),
                    subtitle: _selectedAccounts.isEmpty
                        ? Text(
                            'حداقل یک حساب انتخاب کنید',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.error.withOpacity(0.9),
                            ),
                          )
                        : null,
                    children: [
                      _buildFilterGrid(context, cs, isMobile),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // کارت‌های خلاصه
                if (_summary != null) ...[
                  _buildSummaryCards(context, cs, isMobile),
                  const SizedBox(height: 12),
                ],
                // جدول؛ اسکرول عمودی با کل صفحه
                _selectedAccounts.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.account_tree_outlined, size: 48, color: cs.onSurface.withOpacity(0.5)),
                              const SizedBox(height: 12),
                              Text(
                                'لطفاً حداقل یک حساب انتخاب کنید',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurface.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : DataTableWidget<Map<String, dynamic>>(
                        key: ValueKey(
                          'general_ledger_${_selectedAccounts.map((a) => a.id).join('_')}_${_selectedFiscalYearId}_${_selectedCurrencyId}_${_selectedPerson?.id}_${_includeProforma}_${_fromDate?.toIso8601String()}_${_toDate?.toIso8601String()}',
                        ),
                        config: _buildTableConfig(t),
                        fromJson: (json) => Map<String, dynamic>.from(json),
                        calendarController: widget.calendarController,
                        onRefresh: _fetchSummary,
                      ),
              ],
            ),
          ),
    );
  }
}

