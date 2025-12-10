import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/auth_store.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../utils/number_formatters.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';
import '../../widgets/date_input_field.dart';
import '../../services/check_service.dart';
import '../../utils/snackbar_helper.dart';

class CheckReconciliationPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const CheckReconciliationPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<CheckReconciliationPage> createState() => _CheckReconciliationPageState();
}

class _CheckReconciliationPageState extends State<CheckReconciliationPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _checkService = CheckService();
  final GlobalKey _tableKey = GlobalKey();
  final GlobalKey _checkSelectionTableKey = GlobalKey();

  // Tab 1: Calculate
  final Set<int> _selectedCheckIds = {};
  DateTime? _baseDate;
  Map<String, dynamic>? _calculationResult;
  bool _calculating = false;
  String? _calculationError;

  // Tab 2: History
  void _refreshHistory() {
    try { (_tableKey.currentState as dynamic)?.refresh(); } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _baseDate = DateTime.now();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    if (!widget.authStore.canReadSection('checks')) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('راس‌گیری چک‌ها'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/business/${widget.businessId}/dashboard');
              }
            },
          ),
        ),
        body: const Center(child: Text('دسترسی ندارید')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('راس‌گیری چک‌ها'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/business/${widget.businessId}/dashboard');
            }
          },
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.calculate), text: 'محاسبه راس'),
            Tab(icon: Icon(Icons.history), text: 'تاریخچه'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCalculateTab(t),
          _buildHistoryTab(t),
        ],
      ),
    );
  }

  Widget _buildCalculateTab(AppLocalizations t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // انتخاب چک‌ها
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('انتخاب چک‌ها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            if (_selectedCheckIds.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  '${_selectedCheckIds.length} چک انتخاب شده',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildCheckSelectionWidget(),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              
              // تاریخ مبنا
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('تاریخ مبنا', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      DateInputField(
                        value: _baseDate,
                        labelText: 'تاریخ مبنا *',
                        hintText: 'انتخاب تاریخ مبنا',
                        calendarController: widget.calendarController,
                        onChanged: (d) => setState(() => _baseDate = d),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // دکمه محاسبه
              FilledButton.icon(
                onPressed: _selectedCheckIds.length < 2 || _baseDate == null || _calculating
                    ? null
                    : _calculateReconciliation,
                icon: _calculating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.calculate),
                label: Text(_calculating ? 'در حال محاسبه...' : 'محاسبه راس'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 16),

              // نمایش خطا
              if (_calculationError != null)
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _calculationError!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // نمایش نتیجه - دیگر نیازی به نمایش inline نیست چون در دیالوگ نمایش داده می‌شود
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckSelectionWidget() {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DataTableWidget<Map<String, dynamic>>(
        key: _checkSelectionTableKey,
        config: DataTableConfig<Map<String, dynamic>>(
          endpoint: '/api/v1/checks/businesses/${widget.businessId}/checks',
          title: '',
          showBackButton: false,
          showTableIcon: false,
          showRowNumbers: true,
          enableRowSelection: true,
          enableMultiRowSelection: true,
          showColumnSearch: false,
          showActiveFilters: false,
          showClearFiltersButton: false,
          columns: [
            TextColumn('check_number', 'شماره چک', width: ColumnWidth.medium,
              formatter: (row) => (row['check_number'] ?? '-').toString(),
            ),
            TextColumn('person_name', 'شخص', width: ColumnWidth.large,
              formatter: (row) => (row['person_name'] ?? '-').toString(),
            ),
            DateColumn('due_date', 'تاریخ سررسید', width: ColumnWidth.medium,
              formatter: (row) {
                final value = row['due_date'];
                if (value == null) return '-';
                try {
                  final date = DateTime.parse(value.toString().split('T').first);
                  return HesabixDateUtils.formatForDisplay(date, widget.calendarController.isJalali);
                } catch (e) {
                  return value.toString();
                }
              },
            ),
            NumberColumn('amount', 'مبلغ', width: ColumnWidth.medium,
              formatter: (row) => formatWithThousands(row['amount']),
            ),
            TextColumn('status', 'وضعیت', width: ColumnWidth.small,
              formatter: (row) {
                final s = (row['status'] ?? '').toString();
                switch (s) {
                  case 'RECEIVED_ON_HAND': return 'در دست';
                  case 'TRANSFERRED_ISSUED': return 'صادر شده';
                  case 'DEPOSITED': return 'سپرده';
                  case 'CLEARED': return 'پاس شده';
                  case 'ENDORSED': return 'واگذار شده';
                  case 'RETURNED': return 'عودت';
                  case 'BOUNCED': return 'برگشت';
                  case 'CANCELLED': return 'ابطال';
                }
                return '-';
              },
            ),
          ],
          defaultPageSize: 10,
          onRowSelectionChanged: (selectedRowIndices) {
            // دریافت ردیف‌های واقعی از DataTableWidget
            // استفاده از Future.microtask برای اطمینان از اینکه setState در DataTableWidget کامل شده است
            Future.microtask(() {
              if (!mounted) return;
              try {
                final tableState = _checkSelectionTableKey.currentState;
                if (tableState != null) {
                  // استفاده از getSelectedItems() برای دریافت ردیف‌های واقعی
                  final selectedItems = (tableState as dynamic).getSelectedItems() as List<Map<String, dynamic>>?;
                  if (selectedItems != null && mounted) {
                    setState(() {
                      _selectedCheckIds.clear();
                      for (var row in selectedItems) {
                        final id = row['id'];
                        if (id is int) {
                          _selectedCheckIds.add(id);
                        }
                      }
                    });
                  }
                }
              } catch (e) {
                // در صورت خطا، از شاخص‌ها استفاده نمی‌کنیم
                if (mounted) {
                }
              }
            });
          },
        ),
        fromJson: (json) => json,
        calendarController: widget.calendarController,
      ),
    );
  }


  Future<void> _showReconciliationResultDialog(Map<String, dynamic> result) async {
    final items = result['items'] as List<dynamic>? ?? [];
    final averageDays = result['calculated_average_days'] as num? ?? 0;
    final calculatedDate = result['calculated_date'] as String?;
    final totalAmount = result['total_amount'] as num? ?? 0;
    final checkCount = result['check_count'] as num? ?? 0;
    final totalWeighted = items.fold<double>(0.0, (sum, item) {
      return sum + ((item['weighted_value'] as num?)?.toDouble() ?? 0.0);
    });

    DateTime? calculatedDateDt;
    if (calculatedDate != null) {
      try {
        calculatedDateDt = DateTime.parse(calculatedDate.split('T').first);
      } catch (e) {
        // ignore
      }
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary,
                      colorScheme.primary.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calculate,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'نتیجه محاسبه راس‌گیری',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${formatWithThousands(checkCount)} چک',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              'مجموع مبلغ',
                              formatWithThousands(totalAmount),
                              Icons.account_balance_wallet,
                              colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryCard(
                              'میانگین سررسید',
                              '${averageDays.toStringAsFixed(2)} روز',
                              Icons.calendar_today,
                              colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryCard(
                              'تاریخ راس',
                              calculatedDateDt != null
                                  ? HesabixDateUtils.formatForDisplay(
                                      calculatedDateDt,
                                      widget.calendarController.isJalali,
                                    )
                                  : '-',
                              Icons.event,
                              colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Chart Section
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.bar_chart,
                                  color: colorScheme.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'نمودار وزن چک‌ها',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildWeightChart(items, totalWeighted),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Details Table
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outline.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.list_alt,
                                  color: colorScheme.primary,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'جزئیات چک‌ها',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildDetailsTable(items),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Footer Actions
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('بستن'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        // نمایش دیالوگ ذخیره (بدون بستن دیالوگ نتایج)
                        final saved = await _saveReconciliation();
                        // اگر ذخیره موفق بود، دیالوگ نتایج را ببند و صفحه را refresh کنیم
                        if (saved == true) {
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            _refreshHistory();
                          }
                        }
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('ذخیره جلسه راس‌گیری'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightChart(List<dynamic> items, double totalWeighted) {
    if (items.isEmpty || totalWeighted == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      children: items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final weighted = (item['weighted_value'] as num?)?.toDouble() ?? 0.0;
        final percentage = (weighted / totalWeighted * 100);
        final checkNumber = item['check_number']?.toString() ?? '-';
        final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        final days = (item['days_to_maturity'] as num?)?.toInt() ?? 0;

        final colors = [
          Colors.blue,
          Colors.green,
          Colors.orange,
          Colors.purple,
          Colors.red,
          Colors.teal,
          Colors.pink,
          Colors.indigo,
        ];
        final color = colors[index % colors.length];

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'چک #$checkNumber',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: percentage / 100,
                  minHeight: 24,
                  backgroundColor: color.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${formatWithThousands(amount)} × $days روز',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    formatWithThousands(weighted),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDetailsTable(List<dynamic> items) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(1.5),
        3: FlexColumnWidth(1.5),
        4: FlexColumnWidth(2),
      },
      border: TableBorder(
        horizontalInside: BorderSide(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      children: [
        // Header
        TableRow(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          ),
          children: [
            _buildTableCell('ردیف', isHeader: true),
            _buildTableCell('شماره چک', isHeader: true),
            _buildTableCell('مبلغ', isHeader: true),
            _buildTableCell('روز تا سررسید', isHeader: true),
            _buildTableCell('وزن', isHeader: true),
          ],
        ),
        // Rows
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final checkNumber = item['check_number']?.toString() ?? '-';
          final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
          final days = (item['days_to_maturity'] as num?)?.toInt() ?? 0;
          final weighted = (item['weighted_value'] as num?)?.toDouble() ?? 0.0;

          return TableRow(
            children: [
              _buildTableCell('${index + 1}'),
              _buildTableCell(checkNumber),
              _buildTableCell(formatWithThousands(amount)),
              _buildTableCell('$days'),
              _buildTableCell(
                formatWithThousands(weighted),
                isBold: true,
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: isHeader || isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: isHeader ? 14 : 13,
          color: isHeader
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
      ),
    );
  }

  Future<void> _calculateReconciliation() async {
    if (_selectedCheckIds.length < 2 || _baseDate == null) return;

    setState(() {
      _calculating = true;
      _calculationError = null;
      _calculationResult = null;
    });

    try {
      final result = await _checkService.calculateReconciliation(
        businessId: widget.businessId,
        body: {
          'check_ids': _selectedCheckIds.toList(),
          'base_date': _baseDate!.toIso8601String(),
        },
      );
      setState(() {
        _calculationResult = result;
        _calculating = false;
      });
      // نمایش دیالوگ نتایج
      _showReconciliationResultDialog(result);
    } catch (e) {
      setState(() {
        _calculationError = e.toString();
        _calculating = false;
      });
    }
  }

  Future<bool?> _saveReconciliation() async {
    if (_calculationResult == null) return false;

    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ذخیره جلسه راس‌گیری'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'نام جلسه *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'توضیحات (اختیاری)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                SnackBarHelper.show(ctx, message: 'نام جلسه الزامی است');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );

    if (saved != true) return false;

    try {
      await _checkService.createReconciliation(
        businessId: widget.businessId,
        body: {
          'name': nameController.text.trim(),
          'check_ids': _selectedCheckIds.toList(),
          'base_date': _baseDate!.toIso8601String(),
          'description': descriptionController.text.trim().isEmpty
              ? null
              : descriptionController.text.trim(),
        },
      );

      if (mounted) {
        SnackBarHelper.show(context, message: 'جلسه راس‌گیری با موفقیت ذخیره شد');
        _tabController.animateTo(1);
        _refreshHistory();
      }
      return true;
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا در ذخیره: $e');
      }
      return false;
    }
  }

  Widget _buildHistoryTab(AppLocalizations t) {
    return DataTableWidget<Map<String, dynamic>>(
      key: _tableKey,
      config: _buildHistoryConfig(t, context),
      fromJson: (json) => json,
      calendarController: widget.calendarController,
    );
  }

  DataTableConfig<Map<String, dynamic>> _buildHistoryConfig(AppLocalizations t, BuildContext context) {
    return DataTableConfig<Map<String, dynamic>>(
      endpoint: '/api/v1/checks/businesses/${widget.businessId}/checks/reconciliations/list',
      title: 'تاریخچه راس‌گیری',
      showBackButton: false,
      showTableIcon: false,
      showRowNumbers: true,
      enableRowSelection: false,
      showColumnSearch: true,
      showActiveFilters: false,
      showClearFiltersButton: false,
      columns: [
        TextColumn('name', 'نام جلسه', width: ColumnWidth.large,
          formatter: (row) => (row['name'] ?? '-').toString(),
        ),
        DateColumn('base_date', 'تاریخ مبنا', width: ColumnWidth.medium,
          formatter: (row) {
            final value = row['base_date'];
            if (value == null) return '-';
            try {
              final date = DateTime.parse(value.toString().split('T').first);
              return HesabixDateUtils.formatForDisplay(date, widget.calendarController.isJalali);
            } catch (e) {
              return value.toString();
            }
          },
        ),
        DateColumn('calculated_date', 'تاریخ راس', width: ColumnWidth.medium,
          formatter: (row) {
            final value = row['calculated_date'];
            if (value == null) return '-';
            try {
              final date = DateTime.parse(value.toString().split('T').first);
              return HesabixDateUtils.formatForDisplay(date, widget.calendarController.isJalali);
            } catch (e) {
              return value.toString();
            }
          },
        ),
        NumberColumn('calculated_average_days', 'میانگین (روز)', width: ColumnWidth.small,
          formatter: (row) => (row['calculated_average_days'] ?? 0).toStringAsFixed(2),
        ),
        NumberColumn('total_amount', 'مجموع مبلغ', width: ColumnWidth.medium,
          formatter: (row) => formatWithThousands(row['total_amount']),
        ),
        NumberColumn('check_count', 'تعداد چک', width: ColumnWidth.small,
          formatter: (row) => (row['check_count'] ?? 0).toString(),
        ),
        DateColumn('created_at', 'تاریخ ایجاد', width: ColumnWidth.medium,
          formatter: (row) {
            final value = row['created_at'];
            if (value == null) return '-';
            try {
              final date = DateTime.parse(value.toString().split('T').first);
              return HesabixDateUtils.formatForDisplay(date, widget.calendarController.isJalali);
            } catch (e) {
              return value.toString();
            }
          },
        ),
        ActionColumn('actions', t.actions, actions: [
          DataTableAction(
            icon: Icons.visibility,
            label: 'جزئیات',
            onTap: (row) => _showReconciliationDetails(row as Map<String, dynamic>),
          ),
          if (widget.authStore.canWriteSection('checks'))
            DataTableAction(
              icon: Icons.delete,
              label: t.delete,
              onTap: (row) => _confirmDelete(row as Map<String, dynamic>),
              isDestructive: true,
            ),
        ]),
      ],
      defaultPageSize: 20,
    );
  }

  void _showReconciliationDetails(Map<String, dynamic> row) {
    final id = row['id'] as int?;
    if (id == null) return;

    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<Map<String, dynamic>>(
        future: _checkService.getReconciliationById(id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: SizedBox(
                width: 200,
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return AlertDialog(
              title: const Text('خطا'),
              content: Text(snapshot.error?.toString() ?? 'خطا در بارگذاری'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('بستن'),
                ),
              ],
            );
          }

          final data = snapshot.data!;
          final items = data['items'] as List<dynamic>? ?? [];

          return AlertDialog(
            title: Text(data['name']?.toString() ?? 'جزئیات راس‌گیری'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow('تعداد چک‌ها', (data['check_count'] ?? 0).toString()),
                    _buildDetailRow('مجموع مبلغ', formatWithThousands(data['total_amount'] ?? 0)),
                    _buildDetailRow('میانگین سررسید', '${(data['calculated_average_days'] ?? 0).toStringAsFixed(2)} روز'),
                    if (data['description'] != null)
                      _buildDetailRow('توضیحات', data['description'].toString()),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('جزئیات چک‌ها:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...items.map((item) {
                      final checkNumber = item['check_number']?.toString() ?? '-';
                      final amount = item['amount'] as num? ?? 0;
                      final days = item['days_to_maturity'] as num? ?? 0;
                      final weighted = item['weighted_value'] as num? ?? 0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('چک #$checkNumber: ${formatWithThousands(amount)} × $days روز'),
                            ),
                            Text(
                              '= ${formatWithThousands(weighted)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('بستن'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final id = row['id'] as int?;
    final name = row['name']?.toString() ?? 'نامشخص';
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف جلسه راس‌گیری'),
        content: Text('آیا از حذف جلسه "$name" مطمئن هستید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('خیر'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('بله، حذف کن'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _checkService.deleteReconciliation(id);
      if (mounted) {
        SnackBarHelper.show(context, message: 'جلسه راس‌گیری با موفقیت حذف شد');
        _refreshHistory();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'خطا در حذف: $e');
      }
    }
  }
}

