import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../models/warehouse_invoice_source.dart';
import '../../services/warehouse_service.dart';

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

  const WarehouseDocWizardDialog({
    super.key,
    required this.businessId,
    required this.apiClient,
  });

  @override
  State<WarehouseDocWizardDialog> createState() => _WarehouseDocWizardDialogState();
}

class _WarehouseDocWizardDialogState extends State<WarehouseDocWizardDialog> {
  late final WarehouseService _service;
  int _currentStep = 0;
  WarehouseDocSourceOption? _selectedOption;
  final TextEditingController _searchCtrl = TextEditingController();
  bool _includeCompleted = false;
  bool _loadingInvoices = false;
  String? _invoiceError;
  List<WarehouseInvoiceSource> _invoiceItems = const [];
  int _page = 1;
  int _totalPages = 1;
  WarehouseInvoiceSource? _selectedInvoice;

  @override
  void initState() {
    super.initState();
    _service = WarehouseService(apiClient: widget.apiClient);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInvoices({bool resetPage = false}) async {
    if (_selectedOption == null || _selectedOption!.isManual) return;
    setState(() {
      _loadingInvoices = true;
      _invoiceError = null;
      if (resetPage) _page = 1;
    });
    try {
      final payload = {
        'invoice_type': _selectedOption!.key,
        'take': 20,
        'skip': (_page - 1) * 20,
        if (_searchCtrl.text.trim().isNotEmpty) 'search': _searchCtrl.text.trim(),
        if (_includeCompleted) 'include_completed': true,
      };
      final res = await _service.searchInvoiceSources(businessId: widget.businessId, payload: payload);
      final items = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      if (!mounted) return;
      setState(() {
        _invoiceItems = items.map((e) => WarehouseInvoiceSource.fromJson(e)).toList();
        _totalPages = (res['total_pages'] as num?)?.toInt() ?? 1;
        _selectedInvoice = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _invoiceError = e.toString();
        _invoiceItems = const [];
      });
    } finally {
      if (mounted) {
        setState(() => _loadingInvoices = false);
      }
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
    });
    _loadInvoices(resetPage: true);
  }

  void _confirmInvoiceSelection() {
    if (_selectedOption == null || _selectedInvoice == null) return;
    Navigator.of(context).pop(
      WarehouseDocWizardResult.invoice(
        sourceKey: _selectedOption!.key,
        docType: _selectedOption!.docType ?? _selectedInvoice!.warehouseDocTypeHint ?? 'issue',
        invoiceId: _selectedInvoice!.invoiceId,
        invoiceCode: _selectedInvoice!.code,
        sourceLabel: _selectedOption!.title,
      ),
    );
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
    return SizedBox(
      width: 700,
      child: Column(
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
                  width: 210,
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
      ),
    );
  }

  Widget _buildInvoiceStep() {
    return SizedBox(
      width: 760,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('انتخاب فاکتور مرتبط (${_selectedOption?.title ?? ''})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'جستجو بر اساس کد فاکتور',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _loadInvoices(resetPage: true),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: FilledButton.tonalIcon(
                  onPressed: () => _loadInvoices(resetPage: true),
                  icon: const Icon(Icons.search),
                  label: const Text('اعمال'),
                ),
              ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('نمایش فاکتورهایی که حواله کامل دارند'),
            value: _includeCompleted,
            onChanged: (val) {
              setState(() => _includeCompleted = val ?? false);
              _loadInvoices(resetPage: true);
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loadingInvoices
                ? const Center(child: CircularProgressIndicator())
                : _invoiceError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('خطا: $_invoiceError'),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: () => _loadInvoices(resetPage: false),
                              child: const Text('تلاش مجدد'),
                            ),
                          ],
                        ),
                      )
                    : _invoiceItems.isEmpty
                        ? const Center(child: Text('فاکتوری مطابق فیلتر یافت نشد'))
                        : ListView.builder(
                            itemCount: _invoiceItems.length,
                            itemBuilder: (context, index) {
                              final item = _invoiceItems[index];
                              final selected = _selectedInvoice?.invoiceId == item.invoiceId;
                              return Card(
                                child: RadioListTile<WarehouseInvoiceSource>(
                                  value: item,
                                  groupValue: _selectedInvoice,
                                  onChanged: (val) => setState(() => _selectedInvoice = val),
                                  title: Row(
                                    children: [
                                      Expanded(child: Text(item.code)),
                                      Chip(
                                        label: Text(_stateLabel(item.warehouseState)),
                                        backgroundColor: _stateColor(context, item.warehouseState).withOpacity(0.15),
                                        labelStyle: TextStyle(
                                          color: _stateColor(context, item.warehouseState),
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.personName ?? 'بدون طرف حساب'),
                                      Text(
                                        'تاریخ: ${item.documentDate?.toIso8601String().split('T').first ?? '-'} | مبلغ: ${item.netAmount?.toStringAsFixed(0) ?? '-'}',
                                      ),
                                      if (item.warehouseDocuments.isNotEmpty)
                                        Wrap(
                                          spacing: 6,
                                          children: item.warehouseDocuments
                                              .map(
                                                (doc) => Chip(
                                                  label: Text('${doc.code} (${doc.status})'),
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                    ],
                                  ),
                                  selected: selected,
                                ),
                              );
                            },
                          ),
          ),
          if (!_loadingInvoices)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('صفحه $_page از $_totalPages'),
                Row(
                  children: [
                    IconButton(
                      onPressed: _page > 1 && !_loadingInvoices
                          ? () {
                              setState(() => _page -= 1);
                              _loadInvoices(resetPage: false);
                            }
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    IconButton(
                      onPressed: _page < _totalPages && !_loadingInvoices
                          ? () {
                              setState(() => _page += 1);
                              _loadInvoices(resetPage: false);
                            }
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_currentStep == 0 ? 'ایجاد حواله جدید' : 'انتخاب فاکتور'),
      content: SizedBox(
        height: _currentStep == 0 ? 360 : 520,
        child: _currentStep == 0 ? _buildSourceStep() : _buildInvoiceStep(),
      ),
      actions: [
        if (_currentStep == 1)
          TextButton(
            onPressed: () => setState(() {
              _currentStep = 0;
              _selectedInvoice = null;
            }),
            child: const Text('بازگشت'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
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
    );
  }
}

