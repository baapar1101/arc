import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart' show HesabixDateUtils;
import '../../utils/number_formatters.dart' show formatWithThousands;
import '../../widgets/invoice/person_combobox_widget.dart';
import '../../widgets/invoice/invoice_transactions_widget.dart';
import '../../widgets/invoice/check_combobox_widget.dart';
import '../../widgets/date_input_field.dart';
import '../../widgets/project/project_selector_widget.dart';
import '../../models/invoice_transaction.dart';
import '../../models/invoice_type_model.dart';
import '../../models/person_model.dart';
import '../../models/business_dashboard_models.dart';
import '../../widgets/banking/currency_picker_widget.dart';
import '../../core/auth_store.dart';
import '../../core/api_client.dart';
import '../../services/receipt_payment_service.dart';
import '../../services/invoice_service.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/snackbar_helper.dart';

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
                          authStore: widget.authStore,
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
                        authStore: widget.authStore,
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
  final AuthStore? authStore;
  const _BulkSettlementDialog({
    required this.businessId,
    required this.calendarController,
    required this.isReceipt,
    this.businessInfo,
    this.initial,
    required this.apiClient,
    this.authStore,
  });

  @override
  State<_BulkSettlementDialog> createState() => _BulkSettlementDialogState();
}

class _BulkSettlementDialogState extends State<_BulkSettlementDialog> {
  final _formKey = GlobalKey<FormState>();

  late DateTime _docDate;
  late bool _isReceipt;
  int? _selectedCurrencyId;
  int? _selectedProjectId;
  final TextEditingController _descriptionController = TextEditingController();
  final List<_PersonLine> _personLines = <_PersonLine>[];
  final List<InvoiceTransaction> _centerTransactions = <InvoiceTransaction>[];

  @override
  void initState() {
    super.initState();
    _docDate = widget.initial?.documentDate ?? DateTime.now();
    _isReceipt = widget.initial?.isReceipt ?? widget.isReceipt;
    _selectedCurrencyId = widget.businessInfo?.defaultCurrency?.id;
    _selectedProjectId = widget.initial?.projectId;
    if (widget.initial != null) {
      // تبدیل personLines از ReceiptPaymentDocument به _PersonLine
      // widget.initial!.personLines از نوع List<PersonLine> است (از ReceiptPaymentDocument)
      // اما در واقع از نوع List<_PersonLine> است چون initial از نوع _BulkSettlementDraft است
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
    final bool isEdit = widget.initial != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 900;
        final bool isSmall = constraints.maxWidth < 600;

        final Widget personsPanel = _PersonsPanel(
          businessId: widget.businessId,
          isReceipt: _isReceipt,
          lines: _personLines,
          selectedCurrencyId: _selectedCurrencyId,
          onChanged: (ls) => setState(() {
            _personLines
              ..clear()
              ..addAll(ls);
          }),
        );

        final Widget transactionsPanel = Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.accounts,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: InvoiceTransactionsWidget(
                      transactions: _centerTransactions,
                      onChanged: (txs) => setState(() {
                        _centerTransactions
                          ..clear()
                          ..addAll(txs);
                      }),
                      businessId: widget.businessId,
                      calendarController: widget.calendarController,
                      invoiceType: InvoiceType.sales,
                      checkPickerMode: _isReceipt ? CheckPickerMode.receipt : CheckPickerMode.payment,
                      authStore: widget.authStore,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 1100 : constraints.maxWidth,
              maxHeight: constraints.maxHeight,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: isWide
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              t.receiptsAndPayments,
                                              style: Theme.of(context).textTheme.titleLarge,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              isEdit ? 'ویرایش سند دریافت/پرداخت' : 'ثبت سند دریافت/پرداخت جدید',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      SegmentedButton<bool>(
                                        segments: [
                                          ButtonSegment<bool>(value: true, label: Text(t.receipts)),
                                          ButtonSegment<bool>(value: false, label: Text(t.payments)),
                                        ],
                                        selected: {_isReceipt},
                                        onSelectionChanged: (s) => setState(() => _isReceipt = s.first),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 220,
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
                                        width: 220,
                                        child: CurrencyPickerWidget(
                                          businessId: widget.businessId,
                                          selectedCurrencyId: _selectedCurrencyId,
                                          onChanged: (currencyId) => setState(() => _selectedCurrencyId = currencyId),
                                          label: 'ارز',
                                          hintText: 'انتخاب ارز',
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ProjectSelectorWidget(
                                          businessId: widget.businessId,
                                          apiClient: widget.apiClient,
                                          selectedProjectId: _selectedProjectId,
                                          onChanged: (projectId) => setState(() => _selectedProjectId = projectId),
                                          allowNull: true,
                                          labelText: 'پروژه',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    t.receiptsAndPayments,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    isEdit ? 'ویرایش سند دریافت/پرداخت' : 'ثبت سند دریافت/پرداخت جدید',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: SegmentedButton<bool>(
                                      segments: [
                                        ButtonSegment<bool>(value: true, label: Text(t.receipts)),
                                        ButtonSegment<bool>(value: false, label: Text(t.payments)),
                                      ],
                                      selected: {_isReceipt},
                                      onSelectionChanged: (s) => setState(() => _isReceipt = s.first),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  DateInputField(
                                    value: _docDate,
                                    calendarController: widget.calendarController,
                                    onChanged: (d) => setState(() => _docDate = d ?? DateTime.now()),
                                    labelText: 'تاریخ سند',
                                    hintText: 'انتخاب تاریخ',
                                  ),
                                  const SizedBox(height: 8),
                                  CurrencyPickerWidget(
                                    businessId: widget.businessId,
                                    selectedCurrencyId: _selectedCurrencyId,
                                    onChanged: (currencyId) => setState(() => _selectedCurrencyId = currencyId),
                                    label: 'ارز',
                                    hintText: 'انتخاب ارز',
                                  ),
                                  const SizedBox(height: 8),
                                  ProjectSelectorWidget(
                                    businessId: widget.businessId,
                                    apiClient: widget.apiClient,
                                    selectedProjectId: _selectedProjectId,
                                    onChanged: (projectId) => setState(() => _selectedProjectId = projectId),
                                    allowNull: true,
                                    labelText: 'پروژه',
                                  ),
                                ],
                              ),
                      ),
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
                    child: isWide
                        ? Row(
                            children: [
                              Expanded(child: personsPanel),
                              const VerticalDivider(width: 1),
                              Expanded(child: transactionsPanel),
                            ],
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                personsPanel,
                                const Divider(height: 16),
                                transactionsPanel,
                              ],
                            ),
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: isSmall
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                spacing: 16,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _TotalChip(label: t.people, value: sumPersons),
                                  _TotalChip(label: t.accounts, value: sumCenters),
                                  _TotalChip(label: 'اختلاف', value: diff, isError: diff != 0),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(t.cancel),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: diff == 0 && _personLines.isNotEmpty && _centerTransactions.isNotEmpty
                                    ? _onSave
                                    : null,
                                icon: const Icon(Icons.save),
                                label: Text(t.save),
                              ),
                            ],
                          )
                        : Row(
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
      },
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
      final personLinesData = _personLines.map((line) {
        final personLine = <String, dynamic>{
          'person_id': int.parse(line.personId!),
          'person_name': line.personName,
          'amount': line.amount,
          if (line.description != null && line.description!.isNotEmpty)
            'description': line.description,
        };
        
        // اضافه کردن اطلاعات فاکتور در extra_info
        if (line.linkToInvoice && line.invoiceId != null) {
          personLine['extra_info'] = {
            'invoice_id': line.invoiceId,
            'invoice_code': line.invoiceCode,
            'link_to_invoice': true,
          };
        }
        
        return personLine;
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
        projectId: _selectedProjectId,
      );
      
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // بستن dialog اصلی با موفقیت
      Navigator.pop(context, null);
      
      // نمایش پیام موفقیت
      SnackBarHelper.showSuccess(context, message: _isReceipt 
              ? 'سند دریافت با موفقیت ثبت شد'
              : 'سند پرداخت با موفقیت ثبت شد',);
    } catch (e) {
      if (!mounted) return;
      
      // بستن dialog loading
      Navigator.pop(context);
      
      // نمایش خطا
      SnackBarHelper.showError(context, message: 'خطا: ${e.toString()}');
    }
  }
}

class _PersonsPanel extends StatefulWidget {
  final int businessId;
  final bool isReceipt;
  final List<_PersonLine> lines;
  final ValueChanged<List<_PersonLine>> onChanged;
  final int? selectedCurrencyId;
  const _PersonsPanel({
    required this.businessId,
    required this.isReceipt,
    required this.lines,
    required this.onChanged,
    this.selectedCurrencyId,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool hasBoundedHeight = constraints.maxHeight < double.infinity;

          final listView = widget.lines.isEmpty
              ? Center(child: Text(t.noDataFound))
              : ListView.separated(
                  shrinkWrap: !hasBoundedHeight,
                  physics: hasBoundedHeight ? null : const NeverScrollableScrollPhysics(),
                  itemCount: widget.lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final line = widget.lines[i];
                    return _PersonLineTile(
                      businessId: widget.businessId,
                      isReceipt: widget.isReceipt,
                      line: line,
                      selectedCurrencyId: widget.selectedCurrencyId,
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
                );

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.people,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
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
              if (hasBoundedHeight)
                Expanded(child: listView)
              else
                listView,
            ],
          );

          return Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: content,
            ),
          );
        },
      ),
    );
  }
}

class _PersonLineTile extends StatefulWidget {
  final int businessId;
  final bool isReceipt;
  final _PersonLine line;
  final ValueChanged<_PersonLine> onChanged;
  final VoidCallback onDelete;
  final int? selectedCurrencyId;
  const _PersonLineTile({
    required this.businessId,
    required this.isReceipt,
    required this.line,
    required this.onChanged,
    required this.onDelete,
    this.selectedCurrencyId,
  });

  @override
  State<_PersonLineTile> createState() => _PersonLineTileState();
}

class _PersonLineTileState extends State<_PersonLineTile> {
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  List<Map<String, dynamic>> _invoices = [];
  bool _loadingInvoices = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.line.amount == 0 ? '' : formatNumberForInput(widget.line.amount);
    _descController.text = widget.line.description ?? '';
    if (widget.line.linkToInvoice && widget.line.personId != null) {
      _loadInvoices();
    }
  }

  @override
  void didUpdateWidget(_PersonLineTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // اگر شخص تغییر کرد و لینک فاکتور فعال است، فاکتورها را دوباره لود کن
    if (widget.line.linkToInvoice && 
        widget.line.personId != null && 
        widget.line.personId != oldWidget.line.personId) {
      _loadInvoices();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  /// محاسبه مانده فاکتور بر اساس تراکنش‌های مرتبط
  Future<double> _calculateInvoiceRemaining(Map<String, dynamic> invoice) async {
    try {
      final invoiceId = (invoice['id'] as num?)?.toInt();
      if (invoiceId == null) return 0;
      
      // دریافت مبلغ کل فاکتور
      final totalAmount = _getInvoiceTotal(invoice);
      
      // دریافت لیست اسناد دریافت/پرداخت مرتبط
      final receiptPaymentService = ReceiptPaymentService(ApiClient());
      double totalPaid = 0;
      
      // 1. بررسی از طریق links.receipt_payment_document_ids
      final extraInfo = invoice['extra_info'] as Map<String, dynamic>?;
      if (extraInfo != null) {
        final links = extraInfo['links'] as Map<String, dynamic>?;
        if (links != null) {
          final receiptPaymentIds = links['receipt_payment_document_ids'] as List<dynamic>?;
          if (receiptPaymentIds != null && receiptPaymentIds.isNotEmpty) {
            for (final id in receiptPaymentIds) {
              try {
                final docId = id is int ? id : int.tryParse(id.toString());
                if (docId == null) continue;
                
                final doc = await receiptPaymentService.getById(docId);
                if (doc == null) continue;
                
                // مجموع account_lines (بدون کارمزد)
                for (final accountLine in doc.accountLines) {
                  final isCommission = accountLine.extraInfo?['is_commission_line'] == true;
                  if (!isCommission) {
                    totalPaid += accountLine.amount;
                  }
                }
              } catch (e) {
                // ادامه در صورت خطا
              }
            }
          }
        }
      }
      
      // 2. بررسی از طریق جستجو در اسناد دریافت/پرداخت که invoice_id دارند
      try {
        final receiptPaymentList = await receiptPaymentService.listReceiptsPayments(
          businessId: widget.businessId,
          skip: 0,
          take: 1000,
        );
        
        final items = (receiptPaymentList['items'] as List<dynamic>?) ?? [];
        final Set<int> processedDocIds = {};
        
        // محاسبه receipt_payment_document_ids برای جلوگیری از تکرار
        if (extraInfo != null) {
          final links = extraInfo['links'] as Map<String, dynamic>?;
          if (links != null) {
            final receiptPaymentIds = links['receipt_payment_document_ids'] as List<dynamic>?;
            if (receiptPaymentIds != null) {
              for (final id in receiptPaymentIds) {
                final docId = id is int ? id : int.tryParse(id.toString());
                if (docId != null) {
                  processedDocIds.add(docId);
                }
              }
            }
          }
        }
        
        for (final item in items) {
          try {
            final docId = (item['id'] as num?)?.toInt();
            if (docId == null || processedDocIds.contains(docId)) continue;
            
            // بررسی person_lines برای invoice_id
            final personLines = item['person_lines'] as List<dynamic>?;
            if (personLines == null) continue;
            
            bool hasInvoiceLink = false;
            for (final pl in personLines) {
              final plExtraInfo = pl['extra_info'] as Map<String, dynamic>?;
              if (plExtraInfo != null) {
                final plInvoiceId = plExtraInfo['invoice_id'];
                if (plInvoiceId is int && plInvoiceId == invoiceId) {
                  hasInvoiceLink = true;
                  break;
                } else if (plInvoiceId is num && plInvoiceId.toInt() == invoiceId) {
                  hasInvoiceLink = true;
                  break;
                }
              }
            }
            
            if (!hasInvoiceLink) continue;
            
            // دریافت جزئیات کامل سند
            final doc = await receiptPaymentService.getById(docId);
            if (doc == null) continue;
            
            processedDocIds.add(docId);
            
            // مجموع account_lines (بدون کارمزد)
            for (final accountLine in doc.accountLines) {
              final isCommission = accountLine.extraInfo?['is_commission_line'] == true;
              if (!isCommission) {
                totalPaid += accountLine.amount;
              }
            }
          } catch (e) {
            // ادامه در صورت خطا
          }
        }
      } catch (e) {
        // در صورت خطا در جستجو، فقط از links استفاده می‌کنیم
      }
      
      return totalAmount - totalPaid;
    } catch (e) {
      return 0;
    }
  }

  /// استخراج مبلغ کل فاکتور
  double _getInvoiceTotal(Map<String, dynamic> invoice) {
    try {
      // اول از total_amount
      if (invoice['total_amount'] != null) {
        final total = invoice['total_amount'];
        if (total is num) return total.toDouble();
        if (total is String) return double.tryParse(total) ?? 0;
      }
      
      // سپس از extra_info.totals.net
      final extraInfo = invoice['extra_info'] as Map<String, dynamic>?;
      if (extraInfo != null) {
        final totals = extraInfo['totals'] as Map<String, dynamic>?;
        if (totals != null && totals['net'] != null) {
          final net = totals['net'];
          if (net is num) return net.toDouble();
          if (net is String) return double.tryParse(net) ?? 0;
        }
      }
      
      // در نهایت از total
      if (invoice['total'] != null) {
        final total = invoice['total'];
        if (total is num) return total.toDouble();
        if (total is String) return double.tryParse(total) ?? 0;
      }
      
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> _loadInvoices() async {
    if (widget.line.personId == null) return;
    
    setState(() {
      _loadingInvoices = true;
    });

    try {
      final invoiceService = InvoiceService(apiClient: ApiClient());
      
      // تعیین نوع فاکتورهای مناسب
      final List<String> invoiceTypes;
      if (widget.isReceipt) {
        // برای دریافت: فاکتورهای فروش و برگشت از خرید
        invoiceTypes = ['invoice_sales', 'invoice_purchase_return'];
      } else {
        // برای پرداخت: فاکتورهای خرید و برگشت از فروش
        invoiceTypes = ['invoice_purchase', 'invoice_sales_return'];
      }

      final filters = <String, dynamic>{
        'document_type': invoiceTypes,
        'person_id': int.tryParse(widget.line.personId!) ?? 0,
        'is_proforma': false, // فقط فاکتورهای قطعی
      };
      
      // اضافه کردن فیلتر ارز اگر انتخاب شده باشد
      if (widget.selectedCurrencyId != null) {
        filters['currency_id'] = widget.selectedCurrencyId;
      }

      final result = await invoiceService.searchInvoices(
        businessId: widget.businessId,
        page: 1,
        limit: 100,
        filters: filters,
      );

      if (mounted) {
        final items = (result['items'] as List<dynamic>?)
            ?.map((item) => Map<String, dynamic>.from(item as Map))
            .toList() ?? [];
        
        // محاسبه مانده برای هر فاکتور و فیلتر کردن فاکتورهای تسویه شده
        final List<Map<String, dynamic>> validInvoices = [];
        for (final invoice in items) {
          final remaining = await _calculateInvoiceRemaining(invoice);
          // فقط فاکتورهایی که مانده > 0 دارند (تسویه نشده‌اند)
          if (remaining > 0.01) { // tolerance برای خطای ممیز شناور
            validInvoices.add({
              ...invoice,
              '_remaining': remaining,
            });
          }
        }
        
        setState(() {
          _invoices = validInvoices;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _invoices = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingInvoices = false;
        });
      }
    }
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
                      widget.onChanged(widget.line.copyWith(
                        personId: opt?.id?.toString(), 
                        personName: opt?.displayName,
                        // اگر شخص تغییر کرد و لینک فاکتور فعال است، فاکتورها را reset کن
                        invoiceId: opt == null ? null : widget.line.invoiceId,
                        invoiceCode: opt == null ? null : widget.line.invoiceCode,
                      ));
                      // اگر شخص انتخاب شد و لینک فاکتور فعال است، فاکتورها را لود کن
                      if (opt != null && widget.line.linkToInvoice) {
                        Future.microtask(() => _loadInvoices());
                      }
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
            const SizedBox(height: 8),
            // سوئیچ لینک به فاکتور
            SwitchListTile(
              title: const Text('لینک به فاکتور'),
              subtitle: Text(widget.isReceipt 
                  ? 'این دریافت را به فاکتور فروش مرتبط کن'
                  : 'این پرداخت را به فاکتور خرید مرتبط کن'),
              value: widget.line.linkToInvoice,
              onChanged: widget.line.personId != null
                  ? (value) {
                      widget.onChanged(widget.line.copyWith(
                        linkToInvoice: value,
                        invoiceId: value ? null : null,
                        invoiceCode: value ? null : null,
                      ));
                      if (value) {
                        _loadInvoices();
                      }
                    }
                  : null,
            ),
            // Dropdown انتخاب فاکتور (فقط اگر سوئیچ فعال باشد)
            if (widget.line.linkToInvoice && widget.line.personId != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: widget.line.invoiceId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'فاکتور',
                  hintText: _loadingInvoices ? 'در حال بارگذاری...' : 'انتخاب فاکتور',
                  border: const OutlineInputBorder(),
                ),
                items: _loadingInvoices
                    ? [
                        const DropdownMenuItem<int>(
                          value: null,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      ]
                    : _invoices.map((invoice) {
                        final id = (invoice['id'] as num?)?.toInt();
                        final code = invoice['code']?.toString() ?? '';
                        final total = _getInvoiceTotal(invoice);
                        final remaining = (invoice['_remaining'] as num?)?.toDouble() ?? (total - 0);
                        final dateStr = invoice['document_date']?.toString();
                        final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
                        final dateDisplay = date != null ? HesabixDateUtils.formatForDisplay(date, true) : '';
                        
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                code,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                dateDisplay.isNotEmpty 
                                    ? 'تاریخ: $dateDisplay'
                                    : '',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'مبلغ کل: ${formatWithThousands(total)}',
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'مانده: ${formatWithThousands(remaining)}',
                                style: TextStyle(
                                  color: remaining > 0 
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                selectedItemBuilder: (context) {
                  // نمایش کد فاکتور انتخاب شده در dropdown
                  if (widget.line.invoiceId == null) {
                    return [
                      const Text(
                        'انتخاب فاکتور',
                        overflow: TextOverflow.ellipsis,
                      )
                    ];
                  }
                  final selectedInvoice = _invoices.firstWhere(
                    (inv) => (inv['id'] as num?)?.toInt() == widget.line.invoiceId,
                    orElse: () => <String, dynamic>{},
                  );
                  final code = selectedInvoice['code']?.toString() ?? '';
                  return [
                    Text(
                      code.isNotEmpty ? code : 'انتخاب فاکتور',
                      overflow: TextOverflow.ellipsis,
                    )
                  ];
                },
                onChanged: (invoiceId) {
                  final invoice = _invoices.firstWhere(
                    (inv) => (inv['id'] as num?)?.toInt() == invoiceId,
                    orElse: () => <String, dynamic>{},
                  );
                  widget.onChanged(widget.line.copyWith(
                    invoiceId: invoiceId,
                    invoiceCode: invoice['code']?.toString(),
                  ));
                },
              ),
            ],
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
  final int? projectId;
  _BulkSettlementDraft({
    required this.id,
    required this.isReceipt,
    required this.documentDate,
    required this.personLines,
    required this.centerTransactions,
    this.projectId,
  });
}

class _PersonLine {
  final String? personId;
  final String? personName;
  final double amount;
  final String? description;
  final bool linkToInvoice;
  final int? invoiceId;
  final String? invoiceCode;

  const _PersonLine({
    this.personId, 
    this.personName, 
    required this.amount, 
    this.description,
    this.linkToInvoice = false,
    this.invoiceId,
    this.invoiceCode,
  });

  factory _PersonLine.empty() => const _PersonLine(amount: 0);

  _PersonLine copyWith({
    String? personId, 
    String? personName, 
    double? amount, 
    String? description,
    bool? linkToInvoice,
    int? invoiceId,
    String? invoiceCode,
  }) {
    return _PersonLine(
      personId: personId ?? this.personId,
      personName: personName ?? this.personName,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      linkToInvoice: linkToInvoice ?? this.linkToInvoice,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceCode: invoiceCode ?? this.invoiceCode,
    );
  }
}


