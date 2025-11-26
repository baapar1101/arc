import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../models/warehouse_invoice_source.dart';
import '../../utils/number_formatters.dart';
import '../../widgets/data_table/data_table_widget.dart';
import '../../widgets/data_table/data_table_config.dart';

class WarehouseDocWizardResult {
  final bool isManual;
  final String? sourceKey;
  final String? docType;
  final int? invoiceId;
  final String? invoiceCode;
  final String? sourceLabel;

  const WarehouseDocWizardResult.manual()
      : isManual = true,
        sourceKey = null,
        docType = null,
        invoiceId = null,
        invoiceCode = null,
        sourceLabel = null;

  const WarehouseDocWizardResult.invoice({
    required this.sourceKey,
    required this.docType,
    required this.invoiceId,
    required this.invoiceCode,
    required this.sourceLabel,
  }) : isManual = false;
}

class WarehouseDocSourceOption {
  final String key;
  final String title;
  final String description;
  final IconData icon;
  final String? docType;
  const WarehouseDocSourceOption({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    this.docType,
  });

  bool get isManual => key == 'manual';
}

const List<WarehouseDocSourceOption> _sourceOptions = [
  WarehouseDocSourceOption(
    key: 'manual',
    title: 'حواله دستی',
    description: 'تعریف حواله بدون وابستگی به فاکتور (ورود، خروج، انتقال و ...)',
    icon: Icons.edit_note,
  ),
  WarehouseDocSourceOption(
    key: 'sales',
    title: 'فاکتور فروش',
    description: 'انتخاب فاکتورهای فروش بدون حواله یا ناقص',
    icon: Icons.shopping_cart_checkout,
    docType: 'issue',
  ),
  WarehouseDocSourceOption(
    key: 'purchase',
    title: 'فاکتور خرید',
    description: 'ورود کالاهای خریداری‌شده به انبار',
    icon: Icons.inventory_2_outlined,
    docType: 'receipt',
  ),
  WarehouseDocSourceOption(
    key: 'sales_return',
    title: 'برگشت از فروش',
    description: 'بازگشت کالا از مشتری',
    icon: Icons.assignment_return,
    docType: 'receipt',
  ),
  WarehouseDocSourceOption(
    key: 'purchase_return',
    title: 'برگشت از خرید',
    description: 'خروج کالاهای مرجوع‌شده به تأمین‌کننده',
    icon: Icons.assignment_return_outlined,
    docType: 'issue',
  ),
  WarehouseDocSourceOption(
    key: 'production',
    title: 'تولید',
    description: 'حواله مرتبط با دستور تولید یا مونتاژ',
    icon: Icons.precision_manufacturing,
    docType: 'issue',
  ),
  WarehouseDocSourceOption(
    key: 'waste',
    title: 'ضایعات',
    description: 'خروج کالاهای معیوب/ضایعات از انبار',
    icon: Icons.delete_outline,
    docType: 'issue',
  ),
  WarehouseDocSourceOption(
    key: 'direct_consumption',
    title: 'مصرف مستقیم',
    description: 'کالاهای مصرف‌شده در پروژه یا واحد تولیدی',
    icon: Icons.local_fire_department_outlined,
    docType: 'issue',
  ),
];

class WarehouseDocWizardDialog extends StatefulWidget {
  final int businessId;
  final ApiClient apiClient;
  final CalendarController? calendarController;

  const WarehouseDocWizardDialog({
    super.key,
    required this.businessId,
    required this.apiClient,
    this.calendarController,
  });

  @override
  State<WarehouseDocWizardDialog> createState() => _WarehouseDocWizardDialogState();
}

class _WarehouseDocWizardDialogState extends State<WarehouseDocWizardDialog> {
  int _currentStep = 0;
  WarehouseDocSourceOption? _selectedOption;
  WarehouseInvoiceSource? _selectedInvoice;
  bool _includeCompleted = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _selectInvoice(Map<String, dynamic> item) {
    try {
      final invoice = WarehouseInvoiceSource.fromJson(item);
      setState(() {
        _selectedInvoice = invoice;
      });
      debugPrint('Invoice selected: ${invoice.code}, ID: ${invoice.invoiceId}');
    } catch (e) {
      debugPrint('Error parsing invoice: $e');
      debugPrint('Item data: $item');
    }
  }

  void _goToInvoices() {
    if (_selectedOption == null) return;
    if (_selectedOption!.isManual) {
      Navigator.of(context).pop(const WarehouseDocWizardResult.manual());
      return;
    }
    setState(() {
      _currentStep = 1;
      _selectedInvoice = null;
    });
  }

  void _confirmInvoiceSelection() {
    debugPrint('_confirmInvoiceSelection called');
    debugPrint('_selectedOption: ${_selectedOption?.key}');
    debugPrint('_selectedInvoice: ${_selectedInvoice?.code} (ID: ${_selectedInvoice?.invoiceId})');
    
    if (_selectedOption == null || _selectedInvoice == null) {
      debugPrint('Cannot confirm: _selectedOption or _selectedInvoice is null');
      return;
    }
    
    final result = WarehouseDocWizardResult.invoice(
      sourceKey: _selectedOption!.key,
      docType: _selectedOption!.docType ?? _selectedInvoice!.warehouseDocTypeHint ?? 'issue',
      invoiceId: _selectedInvoice!.invoiceId,
      invoiceCode: _selectedInvoice!.code,
      sourceLabel: _selectedOption!.title,
    );
    
    debugPrint('Returning result: invoiceId=${result.invoiceId}, code=${result.invoiceCode}');
    Navigator.of(context).pop(result);
  }

  String _stateLabel(String state) {
    switch (state) {
      case 'draft':
        return 'دارای پیش‌نویس';
      case 'posted':
        return 'تکمیل شده';
      case 'partial':
        return 'ناقص';
      case 'missing':
        return 'بدون حواله';
      default:
        return state;
    }
  }

  Color _stateColor(BuildContext context, String state) {
    switch (state) {
      case 'draft':
        return Colors.orange;
      case 'posted':
        return Colors.green;
      case 'partial':
        return Colors.amber;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Widget _buildSourceStep() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 600;
        final isTablet = screenWidth >= 600 && screenWidth < 1024;
        final cardWidth = isMobile
            ? (constraints.maxWidth - 24) / 2
            : isTablet
                ? (constraints.maxWidth - 36) / 3
                : 210.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ابتدا مشخص کنید این حواله برای چه فرآیندی است:'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _sourceOptions.map((option) {
                final selected = _selectedOption?.key == option.key;
                return GestureDetector(
                  onTap: () => setState(() => _selectedOption = option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: cardWidth,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                        width: selected ? 2 : 1,
                      ),
                      color: selected ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4) : Colors.white,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(option.icon, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 8),
                        Text(
                          option.title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInvoiceStep() {
    if (_selectedOption == null || _selectedOption!.isManual) {
      return const SizedBox.shrink();
    }

    final isJalali = widget.calendarController?.isJalali ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'انتخاب فاکتور مرتبط (${_selectedOption?.title ?? ''})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('نمایش فاکتورهایی که حواله کامل دارند'),
          value: _includeCompleted,
          onChanged: (val) {
            setState(() {
              _includeCompleted = val ?? false;
            });
          },
        ),
        const SizedBox(height: 8),
        Expanded(
          child: DataTableWidget<Map<String, dynamic>>(
            key: ValueKey('${_selectedOption?.key}_$_includeCompleted'),
            config: DataTableConfig<Map<String, dynamic>>(
              endpoint: '/api/v1/warehouse-docs/business/${widget.businessId}/sources/invoices/search',
              title: null,
              showSearch: true,
              showFilters: false,
              showPagination: true,
              showColumnSearch: false,
              showRefreshButton: false,
              showClearFiltersButton: false,
              showBackButton: false,
              showTableIcon: false,
              enableRowSelection: false,
              enableMultiRowSelection: false,
              searchFields: ['code'],
              columns: [
                TextColumn(
                  'code',
                  'کد فاکتور',
                  width: ColumnWidth.medium,
                ),
                TextColumn(
                  'person_name',
                  'طرف حساب',
                  width: ColumnWidth.medium,
                  formatter: (item) => item['person_name']?.toString() ?? 'بدون طرف حساب',
                ),
                DateColumn(
                  'document_date',
                  'تاریخ',
                  width: ColumnWidth.medium,
                  formatter: (item) {
                    final dateStr = item['document_date']?.toString();
                    if (dateStr == null || dateStr.isEmpty) return null;
                    final date = DateTime.tryParse(dateStr);
                    if (date == null) return null;
                    return HesabixDateUtils.formatForDisplay(date, isJalali);
                  },
                ),
                NumberColumn(
                  'net_amount',
                  'مبلغ',
                  width: ColumnWidth.medium,
                  decimalPlaces: 0,
                  formatter: (item) {
                    final amount = item['net_amount'];
                    if (amount == null) return null;
                    return formatWithThousands(amount, decimalPlaces: 0);
                  },
                ),
                CustomColumn(
                  'warehouse_state',
                  'وضعیت',
                  width: ColumnWidth.small,
                  builder: (item, index) {
                    final state = item['warehouse_state']?.toString() ?? 'missing';
                    return Chip(
                      label: Text(_stateLabel(state)),
                      backgroundColor: _stateColor(context, state).withOpacity(0.15),
                      labelStyle: TextStyle(
                        color: _stateColor(context, state),
                        fontSize: 12,
                      ),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),
              ],
              additionalParams: {
                'invoice_type': _selectedOption!.key,
                if (_includeCompleted) 'include_completed': true,
              },
              rowColorBuilder: (item, index) {
                try {
                  final invoice = WarehouseInvoiceSource.fromJson(item);
                  if (_selectedInvoice?.invoiceId == invoice.invoiceId) {
                    return Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3);
                  }
                } catch (e) {
                  // Ignore parsing errors
                }
                return null;
              },
              onRowTap: (item) {
                _selectInvoice(item);
              },
              onRowDoubleTap: (item) {
                // Double tap to quickly confirm selection
                _selectInvoice(item);
                if (_selectedInvoice != null && _selectedOption != null) {
                  Future.microtask(() => _confirmInvoiceSelection());
                }
              },
              emptyStateMessage: 'فاکتوری مطابق فیلتر یافت نشد',
            ),
            fromJson: (json) => json,
            calendarController: widget.calendarController,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;

    final dialogWidth = (isMobile
        ? screenWidth * 0.95
        : isTablet
            ? screenWidth * 0.85
            : screenWidth > 1200
                ? 900.0
                : screenWidth * 0.75).toDouble();

    final dialogHeight = (_currentStep == 0
        ? (isMobile ? screenHeight * 0.6 : 400.0)
        : (isMobile ? screenHeight * 0.75 : 580.0)).toDouble();

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: EdgeInsets.all(isMobile ? 8 : 16),
        child: Container(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: screenHeight * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentStep == 0 ? Icons.add_circle_outline : Icons.receipt_long,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentStep == 0 ? 'ایجاد حواله جدید' : 'انتخاب فاکتور',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'بستن',
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: dialogHeight,
                  minHeight: isMobile ? 300 : 360,
                ),
                padding: const EdgeInsets.all(16),
                child: _currentStep == 0 ? _buildSourceStep() : _buildInvoiceStep(),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_currentStep == 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TextButton(
                        onPressed: () => setState(() {
                          _currentStep = 0;
                          _selectedInvoice = null;
                        }),
                        child: const Text('بازگشت'),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 8),
                  if (_currentStep == 0)
                    FilledButton(
                      onPressed: _selectedOption == null ? null : _goToInvoices,
                      child: const Text('ادامه'),
                    )
                  else
                    FilledButton(
                      onPressed: _selectedInvoice == null ? null : _confirmInvoiceSelection,
                      child: const Text('تأیید و ادامه'),
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
}

