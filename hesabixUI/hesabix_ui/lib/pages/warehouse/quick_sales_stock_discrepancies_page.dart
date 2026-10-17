import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../core/api_client.dart';
import '../../services/goods_expense_income_service.dart';
import '../../services/quick_sales_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../utils/snackbar_helper.dart';
import '../../widgets/date_input_field.dart';

class QuickSalesStockDiscrepanciesPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const QuickSalesStockDiscrepanciesPage({
    super.key,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<QuickSalesStockDiscrepanciesPage> createState() =>
      _QuickSalesStockDiscrepanciesPageState();
}

class _QuickSalesStockDiscrepanciesPageState
    extends State<QuickSalesStockDiscrepanciesPage> {
  final QuickSalesService _service = QuickSalesService();
  final GoodsExpenseIncomeService _goodsService = GoodsExpenseIncomeService();
  List<Map<String, dynamic>> _cases = const [];
  String _status = 'open';
  bool _loading = false;
  bool _allowManualUnitCost = false;

  bool get _canResolve {
    final auth = ApiClient.getAuthStore();
    return auth?.hasBusinessPermission('goods_expense_income', 'add') == true &&
        auth?.hasBusinessPermission('goods_expense_income', 'post') == true;
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadCorrectionSettings();
  }

  Future<void> _loadCorrectionSettings() async {
    if (!_canResolve) return;
    try {
      final settings = await _goodsService.getSettings(
        businessId: widget.businessId,
      );
      if (!mounted) return;
      setState(() {
        _allowManualUnitCost =
            settings['allow_manual_unit_cost'] == true &&
            (ApiClient.getAuthStore()?.hasBusinessPermission(
                  'goods_expense_income',
                  'change_unit_cost',
                ) ==
                true);
      });
    } catch (_) {
      // بهای پایه کالا همچنان قابل استفاده است؛ فقط ویرایش دستی غیرفعال می‌ماند.
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.listStockDiscrepancies(
        businessId: widget.businessId,
        status: _status == 'all' ? null : _status,
      );
      final items = (result['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      setState(() => _cases = items);
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            'خطا در دریافت مغایرت‌ها: ${ErrorExtractor.forContext(error, context)}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(Map<String, dynamic> discrepancy) async {
    final payload = await showGlassDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ResolveDiscrepancyDialog(
        discrepancy: discrepancy,
        calendarController: widget.calendarController,
        allowManualUnitCost: _allowManualUnitCost,
      ),
    );
    if (payload == null || !mounted) return;

    final caseId = (discrepancy['id'] as num?)?.toInt();
    if (caseId == null) return;
    setState(() => _loading = true);
    try {
      await _service.resolveStockDiscrepancy(
        businessId: widget.businessId,
        caseId: caseId,
        payload: payload,
      );
      if (!mounted) return;
      SnackBarHelper.showSuccess(
        context,
        message: 'مغایرت رفع و سند کالای درآمدشده قطعی شد',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message:
            'اصلاح موجودی انجام نشد: ${ErrorExtractor.forContext(error, context)}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _reasonLabel(String? code) {
    switch (code) {
      case 'physical_stock_exists':
        return 'کالا به‌صورت فیزیکی موجود بوده است';
      case 'urgent_sale':
        return 'فروش فوری؛ اصلاح بعدی';
      case 'other':
        return 'سایر';
      default:
        return code ?? '-';
    }
  }

  String _dateTime(dynamic value) {
    final parsed = value == null ? null : DateTime.tryParse(value.toString());
    return HesabixDateUtils.formatDateTime(
      parsed,
      widget.calendarController.isJalali,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مغایرت‌های موجودی فروش سریع'),
        actions: [
          IconButton(
            tooltip: 'بازخوانی',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'وضعیت پرونده',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'open', child: Text('باز')),
                      DropdownMenuItem(
                        value: 'resolved',
                        child: Text('رفع‌شده'),
                      ),
                      DropdownMenuItem(value: 'all', child: Text('همه')),
                    ],
                    onChanged: _loading
                        ? null
                        : (value) {
                            if (value == null || value == _status) return;
                            setState(() => _status = value);
                            _load();
                          },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'فروش‌هایی که با مجوز یک‌باره موجودی منفی ثبت شده‌اند در این بخش رسیدگی می‌شوند.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _cases.isEmpty && !_loading
                ? _EmptyState(status: _status)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _cases.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _buildCaseCard(_cases[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaseCard(Map<String, dynamic> item) {
    final isOpen = item['status'] == 'open';
    final lines = (item['lines'] as List? ?? const [])
        .whereType<Map>()
        .map((line) => Map<String, dynamic>.from(line))
        .toList();
    final invoiceCode = item['invoice_code']?.toString();
    final invoiceId = item['invoice_document_id'];
    final note = item['reason_note']?.toString().trim() ?? '';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'پرونده #${item['id']}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  avatar: Icon(
                    isOpen
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(isOpen ? 'باز' : 'رفع‌شده'),
                  side: BorderSide.none,
                ),
                Text('فاکتور: ${invoiceCode ?? '#$invoiceId'}'),
                Text('ثبت: ${_dateTime(item['created_at'])}'),
                if (!isOpen && item['resolved_at'] != null)
                  Text('رفع: ${_dateTime(item['resolved_at'])}'),
              ],
            ),
            const SizedBox(height: 6),
            Text('علت: ${_reasonLabel(item['reason_code']?.toString())}'),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('توضیح: $note'),
            ],
            const SizedBox(height: 12),
            _DiscrepancyLinesTable(lines: lines),
            if (!isOpen && item['resolution_document_id'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'سند اصلاح: #${item['resolution_document_id']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (isOpen && _canResolve) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.icon(
                  onPressed: _loading ? null : () => _resolve(item),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('رفع مغایرت'),
                ),
              ),
            ] else if (isOpen) ...[
              const SizedBox(height: 12),
              Text(
                'برای رفع مغایرت، مجوزهای ایجاد و قطعی‌کردن کالای درآمدشده لازم است.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiscrepancyLinesTable extends StatelessWidget {
  final List<Map<String, dynamic>> lines;

  const _DiscrepancyLinesTable({required this.lines});

  num _number(Map<String, dynamic> line, String key) =>
      line[key] is num ? line[key] as num : num.tryParse('${line[key]}') ?? 0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 24,
        headingRowHeight: 40,
        dataRowMinHeight: 42,
        dataRowMaxHeight: 56,
        columns: const [
          DataColumn(label: Text('کالا')),
          DataColumn(label: Text('انبار')),
          DataColumn(label: Text('موجودی زمان فروش'), numeric: true),
          DataColumn(label: Text('مقدار فروش'), numeric: true),
          DataColumn(label: Text('کسری'), numeric: true),
          DataColumn(label: Text('اصلاح‌شده'), numeric: true),
        ],
        rows: lines.map((line) {
          final productName =
              line['product_name'] ?? 'کالای #${line['product_id']}';
          final productCode = line['product_code']?.toString();
          return DataRow(
            cells: [
              DataCell(
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(productName.toString()),
                    if (productCode != null && productCode.isNotEmpty)
                      Text(
                        productCode,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              DataCell(
                Text('${line['warehouse_name'] ?? '#${line['warehouse_id']}'}'),
              ),
              DataCell(
                Text(formatWithThousands(_number(line, 'available_quantity'))),
              ),
              DataCell(
                Text(formatWithThousands(_number(line, 'requested_quantity'))),
              ),
              DataCell(
                Text(formatWithThousands(_number(line, 'shortage_quantity'))),
              ),
              DataCell(
                Text(formatWithThousands(_number(line, 'resolved_quantity'))),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ResolveDiscrepancyDialog extends StatefulWidget {
  final Map<String, dynamic> discrepancy;
  final CalendarController calendarController;
  final bool allowManualUnitCost;

  const _ResolveDiscrepancyDialog({
    required this.discrepancy,
    required this.calendarController,
    required this.allowManualUnitCost,
  });

  @override
  State<_ResolveDiscrepancyDialog> createState() =>
      _ResolveDiscrepancyDialogState();
}

class _ResolveDiscrepancyDialogState extends State<_ResolveDiscrepancyDialog> {
  late final List<Map<String, dynamic>> _lines;
  late final List<TextEditingController> _costControllers;
  DateTime? _documentDate = DateTime.now();
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _lines = (widget.discrepancy['lines'] as List? ?? const [])
        .whereType<Map>()
        .map((line) => Map<String, dynamic>.from(line))
        .toList();
    _costControllers = List.generate(
      _lines.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final controller in _costControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  double _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _parseCost(String value) {
    var normalized = value
        .trim()
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .replaceAll(' ', '');
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      normalized = normalized
          .replaceAll(persianDigits[i], '$i')
          .replaceAll(arabicDigits[i], '$i');
    }
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  void _submit() {
    if (_documentDate == null || !_confirmed) return;
    final requestLines = <Map<String, dynamic>>[];
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      final rawCost = _costControllers[index].text.trim();
      final unitCost = _parseCost(rawCost);
      if (rawCost.isNotEmpty && (unitCost == null || unitCost < 0)) {
        SnackBarHelper.showError(
          context,
          message: 'بهای واحد سطر ${index + 1} معتبر نیست',
        );
        return;
      }
      final remaining =
          _number(line['shortage_quantity']) -
          _number(line['resolved_quantity']);
      final requestLine = <String, dynamic>{
        'case_line_id': line['id'],
        'quantity': remaining,
      };
      if (unitCost != null) requestLine['unit_cost'] = unitCost;
      requestLines.add(requestLine);
    }

    Navigator.of(context).pop({
      'document_date': HesabixDateUtils.formatForApiDate(_documentDate!),
      'lines': requestLines,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('رفع مغایرت پرونده #${widget.discrepancy['id']}'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'این عملیات به‌اندازه تمام کسری، سند قطعی «کالای درآمدشده» می‌سازد، موجودی را اصلاح می‌کند و بهای تمام‌شده فاکتور را بازشناسی می‌کند.',
              ),
              const SizedBox(height: 8),
              Text(
                'تاریخ اصلاح باید روز واقعی کشف و ثبت اصلاح باشد. اگر خرید، انتقال یا موجودی ابتدای دوره ثبت نشده، ابتدا همان سند اصلی را ثبت کنید.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 260,
                child: DateInputField(
                  value: _documentDate,
                  onChanged: (value) => setState(() => _documentDate = value),
                  labelText: 'تاریخ اصلاح',
                  calendarController: widget.calendarController,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              ...List.generate(_lines.length, (index) {
                final line = _lines[index];
                final remaining =
                    _number(line['shortage_quantity']) -
                    _number(line['resolved_quantity']);
                final suggested = _number(line['suggested_unit_cost']);
                return Card.outlined(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${line['product_name'] ?? 'کالای #${line['product_id']}'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'انبار: ${line['warehouse_name'] ?? '#${line['warehouse_id']}'} — مقدار اصلاح: ${formatWithThousands(remaining)}',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _costControllers[index],
                            enabled: widget.allowManualUnitCost,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9۰-۹٠-٩.,٬]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: widget.allowManualUnitCost
                                  ? 'بهای واحد (اختیاری)'
                                  : 'بهای واحد پایه',
                              hintText: suggested > 0
                                  ? formatWithThousands(suggested)
                                  : 'قیمت خرید پایه',
                              helperText: widget.allowManualUnitCost
                                  ? 'خالی = بهای پایه کالا'
                                  : 'از قیمت خرید پایه کالا خوانده می‌شود',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmed,
                onChanged: (value) =>
                    setState(() => _confirmed = value == true),
                title: const Text(
                  'تأیید می‌کنم این موجودی فیزیکی، مازادِ ثبت‌نشده با منشأ نامشخص است.',
                ),
                subtitle: const Text(
                  'این گزینه جایگزین ثبت سند خرید، انتقال یا موجودی اول دوره نیست.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          onPressed: _confirmed && _documentDate != null ? _submit : null,
          child: const Text('ثبت اصلاح و بستن پرونده'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String status;

  const _EmptyState({required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status == 'open' ? Icons.inventory_2_outlined : Icons.search_off,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              status == 'open'
                  ? 'پرونده مغایرت بازی وجود ندارد'
                  : 'موردی برای نمایش پیدا نشد',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
