import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../widgets/invoice/invoice_transactions_widget.dart';
import '../../widgets/date_input_field.dart';
import '../../models/invoice_transaction.dart';
import '../../models/invoice_type_model.dart';
import '../../models/person_model.dart';
import '../../models/business_dashboard_models.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';
import '../../services/receipt_payment_service.dart';
import '../../utils/number_normalizer.dart';

class ReceiptsPaymentsPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final AuthStore authStore;
  final ApiClient apiClient;
  const ReceiptsPaymentsPage({
    super.key,
    required this.businessId,
    required this.calendarController,
    required this.authStore,
    required this.apiClient,
  });

  @override
  State<ReceiptsPaymentsPage> createState() => _ReceiptsPaymentsPageState();
}

class _ReceiptsPaymentsPageState extends State<ReceiptsPaymentsPage> {
  int _tabIndex = 0;
  final List<_BulkSettlementDraft> _drafts = <_BulkSettlementDraft>[];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.receiptsAndPayments,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final draft = await showDialog<_BulkSettlementDraft>(
                        context: context,
                        builder: (_) => _BulkSettlementDialog(
                          businessId: widget.businessId,
                          calendarController: widget.calendarController,
                          isReceipt: _tabIndex == 0,
                          businessInfo: widget.authStore.currentBusiness,
                          apiClient: widget.apiClient,
                        ),
                      );
                      if (draft != null) {
                        setState(() {
                          _drafts.removeWhere((d) => d.id == draft.id);
                          _drafts.add(draft);
                        });
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: Text(t.add),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment<int>(value: 0, label: Text(t.receipts), icon: const Icon(Icons.download_done_outlined)),
                  ButtonSegment<int>(value: 1, label: Text(t.payments), icon: const Icon(Icons.upload_outlined)),
                ],
                selected: {_tabIndex},
                onSelectionChanged: (set) => setState(() => _tabIndex = set.first),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _DraftsList(
                  businessId: widget.businessId,
                  drafts: _drafts.where((d) => d.isReceipt == (_tabIndex == 0)).toList(),
                  onEdit: (d) async {
                    final updated = await showDialog<_BulkSettlementDraft>(
                      context: context,
                      builder: (_) => _BulkSettlementDialog(
                        businessId: widget.businessId,
                        calendarController: widget.calendarController,
                        isReceipt: d.isReceipt,
                        initial: d,
                        apiClient: widget.apiClient,
                      ),
                    );
                    if (updated != null) {
                      setState(() {
                        final idx = _drafts.indexWhere((x) => x.id == updated.id);
                        if (idx >= 0) {
                          _drafts[idx] = updated;
                        } else {
                          _drafts.add(updated);
                        }
                      });
                    }
                  },
                  onDelete: (d) {
                    setState(() => _drafts.removeWhere((x) => x.id == d.id));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftsList extends StatelessWidget {
  final int businessId;
  final List<_BulkSettlementDraft> drafts;
  final ValueChanged<_BulkSettlementDraft> onEdit;
  final ValueChanged<_BulkSettlementDraft> onDelete;
  const _DraftsList({
    required this.businessId,
    required this.drafts,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: Text(t.receiptsAndPayments, style: Theme.of(context).textTheme.titleMedium)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: drafts.isEmpty
                ? Center(child: Text(t.noDataFound))
                : ListView.builder(
                    itemCount: drafts.length,
                    itemBuilder: (ctx, i) {
                      final d = drafts[i];
                      final sumPersons = d.personLines.fold<double>(0, (p, e) => p + e.amount);
                      final sumCenters = d.centerTransactions.fold<double>(0, (p, e) => p + (e.amount.toDouble()));
                      return ListTile(
                        title: Text('${formatWithThousands(sumPersons)}  |  ${formatWithThousands(sumCenters)}'),
                        subtitle: Text('${HesabixDateUtils.formatForDisplay(d.documentDate, true)}  •  ${d.isReceipt ? t.receipts : t.payments}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit), onPressed: () => onEdit(d)),
                            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => onDelete(d)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BulkSettlementDialog extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;
  final bool isReceipt;
  final BusinessWithPermission? businessInfo;
  final _BulkSettlementDraft? initial;
  final ApiClient apiClient;
  const _BulkSettlementDialog({
    required this.businessId,
    required this.calendarController,
    required this.isReceipt,
    this.businessInfo,
    this.initial,
    required this.apiClient,
  });

  @override
  State<_BulkSettlementDialog> createState() => _BulkSettlementDialogState();
}

class _BulkSettlementDialogState extends State<_BulkSettlementDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _docDate;
  late bool _isReceipt;
  int? _selectedCurrencyId;
  final TextEditingController _descriptionController = TextEditingController();
  final List<_PersonLine> _personLines = <_PersonLine>[];
  final List<InvoiceTransaction> _centerTransactions = <InvoiceTransaction>[];

  @override
  void initState() {
    super.initState();
    _docDate = widget.initial?.documentDate ?? DateTime.now();
    _isReceipt = widget.initial?.isReceipt ?? widget.isReceipt;
    _selectedCurrencyId = widget.businessInfo?.defaultCurrency?.id;
    if (widget.initial != null) {
      _personLines.addAll(widget.initial!.personLines);
      _centerTransactions.addAll(widget.initial!.centerTransactions);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final sumPersons = _personLines.fold<double>(0, (p, e) => p + e.amount);
    final sumCenters = _centerTransactions.fold<double>(0, (p, e) => p + (e.amount.toDouble()));
    final diff = (_isReceipt ? sumCenters - sumPersons : sumPersons - sumCenters).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.receiptsAndPayments,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment<bool>(value: true, label: Text(t.receipts)),
                        ButtonSegment<bool>(value: false, label: Text(t.payments)),
                      ],
                      selected: {_isReceipt},
                      onSelectionChanged: (s) => setState(() => _isReceipt = s.first),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: DateInputField(
                        value: _docDate,
                        calendarController: widget.calendarController,
                        onChanged: (d) => setState(() => _docDate = d ?? DateTime.now()),
                        labelText: 'تاریخ سند',
                        hintText: 'انتخاب تاریخ',
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 200,
                      child: CurrencyPickerWidget(
                        businessId: widget.businessId,
                        selectedCurrencyId: _selectedCurrencyId,
                        onChanged: (currencyId) => setState(() => _selectedCurrencyId = currencyId),
                        label: 'ارز',
                        hintText: 'انتخاب ارز',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات کلی سند',
                    hintText: 'توضیحات اختیاری...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _PersonsPanel(
                        businessId: widget.businessId,
                        lines: _personLines,
                        onChanged: (ls) => setState(() {
                          _personLines.clear();
                          _personLines.addAll(ls);
                        }),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: InvoiceTransactionsWidget(
                          transactions: _centerTransactions,
                          onChanged: (txs) => setState(() {
                            _centerTransactions.clear();
                            _centerTransactions.addAll(txs);
                          }),
                          businessId: widget.businessId,
                          calendarController: widget.calendarController,
                          invoiceType: InvoiceType.sales,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _TotalChip(label: t.people, value: sumPersons),
                          _TotalChip(label: t.accounts, value: sumCenters),
                          _TotalChip(label: 'اختلاف', value: diff, isError: diff != 0),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t.cancel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: diff == 0 && _personLines.isNotEmpty && _centerTransactions.isNotEmpty
                          ? _onSave
                          : null,
                      icon: const Icon(Icons.save),
                      label: Text(t.save),
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

  Future<void> _onSave() async {
    if (!mounted) return;
    
    // نمایش loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final service = ReceiptPaymentService(widget.apiClient);
      
      // تبدیل personLines به فرمت مورد نیاز API
      final personLinesData = _personLines.map((line) => {
        'person_id': int.parse(line.personId!),
        'person_name': line.personName,
        'amount': line.amount,
        if (line.description != null && line.description!.isNotEmpty)
          'description': line.description,
      }).toList();
      
      // تبدیل centerTransactions به فرمت مورد نیاز API
      final accountLinesData = _centerTransactions.map((tx) => {
        'account_id': tx.accountId,
        'amount': tx.amount.toDouble(),
        'transaction_type': tx.type.value,
        'transaction_date': tx.transactionDate.toIso8601String(),
        if (tx.commission != null && tx.commission! > 0)
          'commission': tx.commission!.toDouble(),
        if (tx.description != null && tx.description!.isNotEmpty)
          'description': tx.description,
        // اطلاعات اضافی بر اساس نوع تراکنش
        if (tx.type == TransactionType.bank) ...{
          'bank_id': tx.bankId,
          'bank_name': tx.bankName,
        },
        if (tx.type == TransactionType.cashRegister) ...{
          'cash_register_id': tx.cashRegisterId,
          'cash_register_name': tx.cashRegisterName,
        },
        if (tx.type == TransactionType.pettyCash) ...{
          'petty_cash_id': tx.pettyCashId,
          'petty_cash_name': tx.pettyCashName,
        },
        if (tx.type == TransactionType.check) ...{
          'check_id': tx.checkId,
          'check_number': tx.checkNumber,
        },
        if (tx.type == TransactionType.person) ...{
          'person_id': tx.personId,
          'person_name': tx.personName,
        },
      }).toList();
      
      // ارسال به سرور
      await service.createReceiptPayment(
        businessId: widget.businessId,
        documentType: _isReceipt ? 'receipt' : 'payment',
        documentDate: _docDate,
        currencyId: _selectedCurrencyId!,
        description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
        personLines: personLinesData,
        accountLines: accountLinesData,
      );
      
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // بستن dialog اصلی با موفقیت
      Navigator.pop(context, null);
      
      // نمایش پیام موفقیت
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isReceipt 
              ? 'سند دریافت با موفقیت ثبت شد'
              : 'سند پرداخت با موفقیت ثبت شد',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // نمایش خطا
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطا: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _PersonsPanel extends StatefulWidget {
  final int businessId;
  final List<_PersonLine> lines;
  final ValueChanged<List<_PersonLine>> onChanged;
  const _PersonsPanel({
    required this.businessId,
    required this.lines,
    required this.onChanged,
  });

  @override
  State<_PersonsPanel> createState() => _PersonsPanelState();
}

class _PersonsPanelState extends State<_PersonsPanel> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(t.people, style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                onPressed: () {
                  final newLines = List<_PersonLine>.from(widget.lines);
                  newLines.add(_PersonLine.empty());
                  widget.onChanged(newLines);
                },
                icon: const Icon(Icons.add),
                tooltip: t.add,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.lines.isEmpty
                ? Center(child: Text(t.noDataFound))
                : ListView.separated(
                    itemCount: widget.lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final line = widget.lines[i];
                      return _PersonLineTile(
                        businessId: widget.businessId,
                        line: line,
                        onChanged: (l) {
                          final newLines = List<_PersonLine>.from(widget.lines);
                          newLines[i] = l;
                          widget.onChanged(newLines);
                        },
                        onDelete: () {
                          final newLines = List<_PersonLine>.from(widget.lines);
                          newLines.removeAt(i);
                          widget.onChanged(newLines);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PersonLineTile extends StatefulWidget {
  final int businessId;
  final _PersonLine line;
  final ValueChanged<_PersonLine> onChanged;
  final VoidCallback onDelete;
  const _PersonLineTile({
    required this.businessId,
    required this.line,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_PersonLineTile> createState() => _PersonLineTileState();
}

class _PersonLineTileState extends State<_PersonLineTile> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.line.amount == 0 ? '' : formatNumberForInput(widget.line.amount);
    _descController.text = widget.line.description ?? '';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: PersonComboboxWidget(
                    businessId: widget.businessId,
                    selectedPerson: widget.line.personId != null 
                        ? Person(
                            id: int.tryParse(widget.line.personId!),
                            businessId: widget.businessId,
                            aliasName: widget.line.personName ?? '',
                            personTypes: const [],
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          )
                        : null,
                    onChanged: (opt) {
                      widget.onChanged(widget.line.copyWith(personId: opt?.id?.toString(), personName: opt?.displayName));
                    },
                    label: t.people,
                    hintText: t.search,
                    isRequired: true,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: t.amount,
                      hintText: '1,000,000',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      EnglishDigitsFormatter(),
                      ThousandsSeparatorInputFormatter(allowDecimal: false),
                    ],
                    validator: (v) {
                      final val = parseFormattedDouble(v);
                      if (val == null || val <= 0) return t.mustBePositiveNumber;
                      return null;
                    },
                    onChanged: (v) {
                      final val = parseFormattedDouble(v) ?? 0;
                      widget.onChanged(widget.line.copyWith(amount: val));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descController,
              decoration: InputDecoration(
                labelText: t.description,
              ),
              onChanged: (v) => widget.onChanged(widget.line.copyWith(description: v.trim().isEmpty ? null : v.trim())),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final double value;
  final bool isError;
  const _TotalChip({required this.label, required this.value, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text('$label: ${formatWithThousands(value)}'),
      backgroundColor: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
      labelStyle: TextStyle(color: isError ? scheme.onErrorContainer : scheme.onSurfaceVariant),
    );
  }
}

class _BulkSettlementDraft {
  final String id;
  final bool isReceipt;
  final DateTime documentDate;
  final List<_PersonLine> personLines;
  final List<InvoiceTransaction> centerTransactions;
  _BulkSettlementDraft({
    required this.id,
    required this.isReceipt,
    required this.documentDate,
    required this.personLines,
    required this.centerTransactions,
  });
}

class _PersonLine {
  final String? personId;
  final String? personName;
  final double amount;
  final String? description;

  const _PersonLine({this.personId, this.personName, required this.amount, this.description});

  factory _PersonLine.empty() => const _PersonLine(amount: 0);

  _PersonLine copyWith({String? personId, String? personName, double? amount, String? description}) {
    return _PersonLine(
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      amount: amount ?? this.amount,
      description: description ?? this.description,
    );
  }
}


