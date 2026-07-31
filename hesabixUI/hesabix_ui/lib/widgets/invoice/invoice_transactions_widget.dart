import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../models/invoice_transaction.dart';
import '../../models/person_model.dart';
import '../../models/account_tree_node.dart';
import '../../core/date_utils.dart';
import '../../core/calendar_controller.dart';
import '../../core/auth_store.dart';
import '../../utils/number_formatters.dart';
import '../../services/bank_account_service.dart';
import '../../services/cash_register_service.dart';
import '../../services/petty_cash_service.dart';
import '../../services/person_service.dart';
import '../../services/account_service.dart';
import '../../services/currency_service.dart';
import '../../services/business_currency_rate_service.dart';
import '../../services/business_fx_global_rate_service.dart';
import 'person_combobox_widget.dart';
import 'bank_account_combobox_widget.dart';
import 'cash_register_combobox_widget.dart';
import 'petty_cash_combobox_widget.dart';
import 'account_tree_combobox_widget.dart';
import 'check_combobox_widget.dart';
import '../../models/invoice_type_model.dart';
import '../../utils/number_normalizer.dart';
import '../../core/api_client.dart';
import '../../widgets/date_input_field.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/error_extractor.dart';
import '../../utils/invoice_transaction_preferences.dart';
import '../../widgets/money/amount_field_words_tooltip.dart';
import '../../utils/currency_display_utils.dart';

class InvoiceTransactionsWidget extends StatefulWidget {
  final List<InvoiceTransaction> transactions;
  final ValueChanged<List<InvoiceTransaction>> onChanged;
  final int businessId;
  final CalendarController calendarController;
  final InvoiceType invoiceType;
  final int? selectedCurrencyId;
  final CheckPickerMode checkPickerMode;
  final AuthStore? authStore;
  final num? invoiceTotal; // مبلغ کل فاکتور
  /// نرخ تسعیر فاکتور (پیش‌فرض فیلد fx_rate در پرداخت بین‌ارزی).
  final num? invoiceFxRate;
  /// داخل [SingleChildScrollView] یا محور عمودی بدون ارتفاع محدود؛ لیست به‌اندازهٔ محتوا بلند می‌شود و اسکرول به والد سپرده می‌شود.
  final bool shrinkWrapBody;
  /// حالت فشرده برای دیالوگ‌های پرتراکم (مثلاً دریافت/پرداخت).
  final bool compactMode;

  const InvoiceTransactionsWidget({
    super.key,
    required this.transactions,
    required this.onChanged,
    required this.businessId,
    required this.calendarController,
    required this.invoiceType,
    this.selectedCurrencyId,
    this.checkPickerMode = CheckPickerMode.any,
    this.authStore,
    this.invoiceTotal,
    this.invoiceFxRate,
    this.shrinkWrapBody = false,
    this.compactMode = false,
  });

  @override
  State<InvoiceTransactionsWidget> createState() => _InvoiceTransactionsWidgetState();
}

class _InvoiceTransactionsWidgetState extends State<InvoiceTransactionsWidget> {
  final CurrencyService _currencyService = CurrencyService(ApiClient());
  String? _currencySymbol;
  Map<int, Map<String, dynamic>> _currencyById = {};
  
  @override
  void initState() {
    super.initState();
    _loadCurrencyInfo();
  }
  
  @override
  void didUpdateWidget(InvoiceTransactionsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCurrencyId != widget.selectedCurrencyId) {
      _loadCurrencyInfo();
    }
  }
  
  Future<void> _loadCurrencyInfo() async {
    try {
      final currencies = await _currencyService.listBusinessCurrencies(
        businessId: widget.businessId,
      );
      final byId = <int, Map<String, dynamic>>{};
      for (final c in currencies) {
        final id = (c['id'] as num?)?.toInt();
        if (id != null) byId[id] = Map<String, dynamic>.from(c);
      }
      String? symbol;
      if (widget.selectedCurrencyId != null && byId.containsKey(widget.selectedCurrencyId)) {
        final currency = byId[widget.selectedCurrencyId]!;
        symbol = currency['symbol']?.toString() ?? currency['code']?.toString() ?? 'ریال';
      }
      if (!mounted) return;
      setState(() {
        _currencyById = byId;
        _currencySymbol = symbol;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currencySymbol = widget.selectedCurrencyId != null ? 'ریال' : null;
      });
    }
  }

  String _unitForCurrencyId(int? id, {String fallback = 'ریال'}) {
    if (id == null) return fallback;
    final c = _currencyById[id];
    if (c == null) return fallback;
    return currencyUnitLabelFromBusinessCurrencyMap(c, fallback: fallback);
  }
  
  // مجموع مبالغ تسویه به ارز فاکتور (پرداخت بین‌ارزی از settles_amount استفاده می‌کند)
  num get _totalPaid {
    return widget.transactions.fold<num>(0, (sum, t) => sum + t.settlesAgainstInvoice);
  }
  
  // محاسبه مانده فاکتور
  num get _remainingBalance {
    if (widget.invoiceTotal == null) return 0;
    return widget.invoiceTotal! - _totalPaid;
  }
  
  // محاسبه درصد پرداخت شده
  double get _paidPercentage {
    if (widget.invoiceTotal == null || widget.invoiceTotal == 0) return 0;
    return (_totalPaid / widget.invoiceTotal!) * 100;
  }
  
  // محاسبه درصد مانده
  double get _remainingPercentage {
    if (widget.invoiceTotal == null || widget.invoiceTotal == 0) return 0;
    return (_remainingBalance / widget.invoiceTotal!) * 100;
  }
  
  // تعیین رنگ مانده
  Color _getRemainingBalanceColor(ThemeData theme) {
    if (widget.invoiceTotal == null) return theme.colorScheme.onSurface;
    if (_remainingBalance > 0) {
      return theme.colorScheme.error; // قرمز برای مانده مثبت (بدهکار)
    } else if (_remainingBalance < 0) {
      return theme.colorScheme.tertiary; // آبی/سبز برای مانده منفی (بستانکار)
    } else {
      return theme.colorScheme.primary; // سبز برای تسویه کامل
    }
  }

  // بررسی اینکه آیا باید از چیدمان دو ستونه استفاده کنیم
  bool _isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 900; // از 900 پیکسل به بالا دو ستونه
  }
  
  // بررسی اینکه آیا می‌توان تراکنش اضافه کرد
  // اگر invoiceTotal null باشد (مثل حالت دریافت و پرداخت)، همیشه فعال است
  // در غیر این صورت، باید invoiceTotal بیشتر از صفر باشد
  bool get _canAddTransaction {
    if (widget.invoiceTotal == null) {
      return true; // برای حالت دریافت و پرداخت که invoiceTotal ندارند
    }
    return widget.invoiceTotal! > 0;
  }

  /// ماندهٔ مثبت برای پر کردن ردیف خالی (مبلغ صفر) یا باز کردن دیالوگ تراکنش جدید.
  bool get _canFillRemainingBalance {
    if (widget.invoiceTotal == null || widget.invoiceTotal! <= 0) return false;
    return _remainingBalance > 0;
  }

  void _fillRemainingBalance() {
    final total = widget.invoiceTotal;
    if (total == null || total <= 0) return;

    final remainder = total - _totalPaid;
    if (remainder <= 0) {
      if (remainder < 0) {
        SnackBarHelper.showError(
          context,
          message: 'مجموع تراکنش‌ها از مبلغ فاکتور بیشتر است؛ ابتدا مبالغ را اصلاح کنید.',
        );
      } else {
        SnackBarHelper.showError(context, message: 'مانده‌ای برای پر کردن وجود ندارد.');
      }
      return;
    }

    final zeroIdx = widget.transactions.indexWhere((t) => t.amount == 0);
    if (zeroIdx >= 0) {
      final t = widget.transactions[zeroIdx];
      final newList = List<InvoiceTransaction>.from(widget.transactions);
      newList[zeroIdx] = t.copyWith(amount: remainder);
      widget.onChanged(newList);
      return;
    }

    _showTransactionDialog(initialAmount: remainder);
  }

  Widget _buildHeaderRow(ThemeData theme) {
    final isDesktop = _isDesktop(context);
    final showFillRemaining =
        widget.invoiceTotal != null && widget.invoiceTotal! > 0;
    final titleStyle = widget.compactMode
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)
        : theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold);

    Widget fillRemainingIconButton() {
      if (!showFillRemaining) return const SizedBox.shrink();
      final enabled = _canFillRemainingBalance;
      return IconButton(
        onPressed: enabled ? _fillRemainingBalance : null,
        icon: const Icon(Icons.price_change_outlined),
        tooltip: enabled
            ? 'پر کردن ماندهٔ باقی‌مانده در تراکنش (ردیف با مبلغ صفر یا تراکنش جدید)'
            : 'ماندهٔ مثبت برای پر کردن وجود ندارد',
        style: IconButton.styleFrom(
          visualDensity:
              widget.compactMode ? VisualDensity.compact : null,
          foregroundColor: enabled
              ? theme.colorScheme.secondary
              : theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Row(
      children: [
        Icon(
          Icons.receipt_long_outlined,
          color: theme.colorScheme.primary,
          size: widget.compactMode ? 20 : 24,
        ),
        SizedBox(width: widget.compactMode ? 6 : 8),
        Expanded(
          child: Text(
            'تراکنش‌ها',
            style: titleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        fillRemainingIconButton(),
        if (showFillRemaining) const SizedBox(width: 4),
        if (isDesktop)
          ElevatedButton.icon(
            onPressed: _canAddTransaction ? _addTransaction : null,
            icon: const Icon(Icons.add),
            label: const Text('افزودن تراکنش'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
          )
        else
          IconButton(
            onPressed: _canAddTransaction ? _addTransaction : null,
            icon: const Icon(Icons.add),
            tooltip: _canAddTransaction
                ? 'افزودن تراکنش'
                : 'ابتدا باید ردیف‌های کالا را اضافه کنید',
            style: IconButton.styleFrom(
              visualDensity:
                  widget.compactMode ? VisualDensity.compact : null,
              backgroundColor: _canAddTransaction
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: _canAddTransaction
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = _isDesktop(context);
    final gap = widget.compactMode ? 10.0 : 16.0;

    if (widget.shrinkWrapBody) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderRow(theme),
          SizedBox(height: gap),
          _buildMobileLayout(theme, shrinkWrap: true),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeaderRow(theme),
        SizedBox(height: gap),

        // محتوای اصلی: دو ستونه در دسکتاپ، یک ستونه در موبایل
        Expanded(
          child: isDesktop
              ? _buildDesktopLayout(theme)
              : _buildMobileLayout(theme),
        ),
      ],
    );
  }
  
  // چیدمان موبایل: یک ستون
  Widget _buildMobileLayout(ThemeData theme, {bool shrinkWrap = false}) {
    final separatorGap = widget.compactMode ? 8.0 : 12.0;
    final sectionGap = widget.compactMode ? 10.0 : 16.0;
    final listSection = widget.transactions.isEmpty
        ? _buildEmptyState(theme)
        : ListView.separated(
            shrinkWrap: shrinkWrap,
            physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
            itemCount: widget.transactions.length,
            separatorBuilder: (context, index) => SizedBox(height: separatorGap),
            itemBuilder: (context, index) {
              final transaction = widget.transactions[index];
              return _buildTransactionCard(transaction, index);
            },
          );

    return Column(
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // نمایش مانده فاکتور یا پیام عدم وجود ردیف کالا
        if (widget.invoiceTotal != null && widget.invoiceTotal! > 0) ...[
          _buildBalanceCard(theme),
          SizedBox(height: sectionGap),
        ] else if (widget.invoiceTotal != null && widget.invoiceTotal! == 0) ...[
          _buildNoItemsMessage(theme),
          SizedBox(height: sectionGap),
        ],

        // لیست تراکنش‌ها
        if (shrinkWrap)
          listSection
        else
          Expanded(child: listSection),
      ],
    );
  }
  
  // چیدمان دسکتاپ: دو ستون
  Widget _buildDesktopLayout(ThemeData theme) {
    final separatorGap = widget.compactMode ? 8.0 : 12.0;
    final sectionGap = widget.compactMode ? 8.0 : 12.0;
    final colGap = widget.compactMode ? 10.0 : 16.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ستون سمت راست: لیست تراکنش‌ها
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // هدر لیست تراکنش‌ها
              Row(
                children: [
                  Text(
                    'لیست تراکنش‌ها',
                    style: (widget.compactMode
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.titleMedium)
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.transactions.length} تراکنش',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              SizedBox(height: sectionGap),
              // لیست تراکنش‌ها
              Expanded(
                child: widget.transactions.isEmpty
                    ? _buildEmptyState(theme)
                    : ListView.separated(
                        itemCount: widget.transactions.length,
                        separatorBuilder: (context, index) =>
                            SizedBox(height: separatorGap),
                        itemBuilder: (context, index) {
                          final transaction = widget.transactions[index];
                          return _buildTransactionCard(transaction, index);
                        },
                      ),
              ),
            ],
          ),
        ),
        
        SizedBox(width: colGap),
        
        // ستون سمت چپ: کارت مانده فاکتور یا پیام عدم وجود ردیف کالا
        if (widget.invoiceTotal != null && widget.invoiceTotal! > 0)
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // هدر کارت مانده
                Text(
                  'خلاصه مالی',
                  style: (widget.compactMode
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: sectionGap),
                // کارت مانده (sticky در بالای صفحه)
                Flexible(
                  child: SingleChildScrollView(
                    child: _buildBalanceCard(theme),
                  ),
                ),
              ],
            ),
          )
        else if (widget.invoiceTotal != null && widget.invoiceTotal! == 0)
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // هدر
                Text(
                  'خلاصه مالی',
                  style: (widget.compactMode
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: sectionGap),
                // پیام عدم وجود ردیف کالا
                Flexible(
                  child: SingleChildScrollView(
                    child: _buildNoItemsMessage(theme),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
  
  // حالت خالی (بدون تراکنش)
  Widget _buildEmptyState(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'هیچ تراکنشی اضافه نشده است',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'برای افزودن تراکنش روی دکمه "افزودن تراکنش" کلیک کنید',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(InvoiceTransaction transaction, int index) {
    final theme = Theme.of(context);
    final cardPad = widget.compactMode ? 10.0 : 16.0;
    final headerGap = widget.compactMode ? 8.0 : 12.0;
    final iconSize = widget.compactMode ? 18.0 : 20.0;
    
    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // هدر تراکنش
            Row(
              children: [
                Icon(
                  _getTransactionIcon(transaction.type),
                  color: theme.colorScheme.primary,
                  size: iconSize,
                ),
                const SizedBox(width: 8),
                Text(
                  transaction.type.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  formatWithThousands(transaction.amount, decimalPlaces: 0),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _editTransaction(index),
                  icon: const Icon(Icons.edit),
                  tooltip: 'ویرایش',
                  visualDensity:
                      widget.compactMode ? VisualDensity.compact : null,
                ),
                IconButton(
                  onPressed: () => _removeTransaction(index),
                  icon: const Icon(Icons.delete),
                  tooltip: 'حذف',
                  color: theme.colorScheme.error,
                  visualDensity:
                      widget.compactMode ? VisualDensity.compact : null,
                ),
              ],
            ),
            SizedBox(height: headerGap),
            
            // جزئیات تراکنش
            _buildTransactionDetails(transaction),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionDetails(InvoiceTransaction transaction) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // نام/عنوان تراکنش
        if (transaction.bankName != null)
          _buildDetailRow('بانک:', transaction.bankName!),
        if (transaction.cashRegisterName != null)
          _buildDetailRow('صندوق:', transaction.cashRegisterName!),
        if (transaction.pettyCashName != null)
          _buildDetailRow('تنخواهگردان:', transaction.pettyCashName!),
        if (transaction.checkNumber != null)
          _buildDetailRow('شماره چک:', transaction.checkNumber!),
        if (transaction.personName != null)
          _buildDetailRow('شخص:', transaction.personName!),
        if (transaction.accountName != null)
          _buildDetailRow('حساب:', transaction.accountName!),
        
        const SizedBox(height: 8),
        
        // تاریخ، مبلغ و کارمزد
        Row(
          children: [
            Expanded(
              child: _buildDetailRow(
                'تاریخ:',
                HesabixDateUtils.formatForDisplay(
                  transaction.transactionDate,
                  widget.calendarController.isJalali == true,
                ),
              ),
            ),
            Expanded(
              child: _buildDetailRow(
                transaction.settlesAmount != null ? 'مبلغ پرداخت:' : 'مبلغ:',
                transaction.settlesAmount != null
                    ? formatAmountWithCurrencyUnit(
                        transaction.amount,
                        unit: _unitForCurrencyId(
                          transaction.paymentCurrencyId,
                          fallback: '',
                        ),
                        decimalPlaces: 0,
                      )
                    : formatWithThousands(transaction.amount, decimalPlaces: 0),
              ),
            ),
            if (transaction.commission != null)
              Expanded(
                child: _buildDetailRow(
                  'کارمزد بانکی:',
                  formatWithThousands(transaction.commission!, decimalPlaces: 0),
                ),
              ),
          ],
        ),
        if (transaction.settlesAmount != null) ...[
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .secondaryContainer
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'تسویه بین‌ارزی',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatCrossCurrencyPaymentDisplay(
                      settlesAmount: transaction.settlesAmount,
                      invoiceCurrencyUnit: _currencySymbol ?? 'ارز فاکتور',
                      paymentAmount: transaction.amount,
                      paymentCurrencyUnit: _unitForCurrencyId(
                        transaction.paymentCurrencyId,
                        fallback: 'ارز پرداخت',
                      ),
                      fxRate: transaction.fxRate,
                      settlesDecimalPlaces: 2,
                      paymentDecimalPlaces: 0,
                      rateDisplayUnit: widget.authStore?.currentBusiness
                          ?.fxRevaluationPolicy?['rate_display_unit']
                          ?.toString(),
                      baseCurrencyCode: widget
                          .authStore?.currentBusiness?.defaultCurrency?.code,
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
        
        // توضیحات
        if (transaction.description != null && transaction.description!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildDetailRow('توضیحات:', transaction.description!),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTransactionIcon(TransactionType type) {
    switch (type) {
      case TransactionType.bank:
        return Icons.account_balance;
      case TransactionType.cashRegister:
        return Icons.point_of_sale;
      case TransactionType.pettyCash:
        return Icons.wallet;
      case TransactionType.check:
        return Icons.receipt;
      case TransactionType.checkExpense:
        return Icons.receipt_long;
      case TransactionType.person:
        return Icons.person;
      case TransactionType.account:
        return Icons.account_balance_wallet;
    }
  }

  void _addTransaction() {
    _showTransactionDialog();
  }

  void _editTransaction(int index) {
    _showTransactionDialog(transaction: widget.transactions[index], index: index);
  }

  void _removeTransaction(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف تراکنش'),
        content: const Text('آیا از حذف این تراکنش اطمینان دارید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeTransactionAt(index);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _removeTransactionAt(int index) {
    final newTransactions = List<InvoiceTransaction>.from(widget.transactions);
    newTransactions.removeAt(index);
    widget.onChanged(newTransactions);
  }

  List<TransactionType> _availableTransactionTypesForInvoice() {
    final showCheckExpense = widget.invoiceType == InvoiceType.purchase ||
        widget.invoiceType == InvoiceType.salesReturn;
    final all = TransactionType.allTypes;
    if (showCheckExpense) return all;
    return all.where((t) => t != TransactionType.checkExpense).toList();
  }

  Future<void> _showTransactionDialog({
    InvoiceTransaction? transaction,
    int? index,
    num? initialAmount,
  }) async {
    TransactionType? initialTransactionType;
    if (transaction == null) {
      initialTransactionType =
          await InvoiceTransactionPreferences.resolveInitialTransactionType(
        widget.businessId,
        _availableTransactionTypesForInvoice(),
      );
      if (!mounted) return;
    }

    showDialog(
      context: context,
      builder: (context) => TransactionDialog(
        transaction: transaction,
        initialAmount: initialAmount,
        initialTransactionType: initialTransactionType,
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        invoiceType: widget.invoiceType,
        selectedCurrencyId: widget.selectedCurrencyId,
        currencyUnit: _currencySymbol ?? 'ریال',
        checkPickerMode: widget.checkPickerMode,
        authStore: widget.authStore,
        invoiceFxRate: widget.invoiceFxRate,
        onSave: (newTransaction) {
          if (index != null) {
            // ویرایش تراکنش موجود
            final newTransactions = List<InvoiceTransaction>.from(widget.transactions);
            newTransactions[index] = newTransaction;
            widget.onChanged(newTransactions);
          } else {
            // افزودن تراکنش جدید
            final newTransactions = List<InvoiceTransaction>.from(widget.transactions);
            newTransactions.add(newTransaction);
            widget.onChanged(newTransactions);
          }
        },
      ),
    );
  }
  
  Widget _buildBalanceCard(ThemeData theme) {
    final remainingColor = _getRemainingBalanceColor(theme);
    final isFullyPaid = _remainingBalance == 0;
    final isOverPaid = _remainingBalance < 0;
    final hasRemaining = _remainingBalance > 0;
    final isDesktop = _isDesktop(context);
    
    return Card(
      color: hasRemaining 
          ? theme.colorScheme.errorContainer.withOpacity(0.3)
          : isOverPaid
              ? theme.colorScheme.tertiaryContainer.withOpacity(0.3)
              : theme.colorScheme.primaryContainer.withOpacity(0.3),
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 20 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: isDesktop ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Row(
              children: [
                Icon(
                  hasRemaining 
                      ? Icons.warning_amber_rounded
                      : isOverPaid
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                  color: remainingColor,
                  size: isDesktop ? 28 : 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'مانده فاکتور',
                    style: isDesktop 
                        ? theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          )
                        : theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // یک ستون تمام‌عرض در موبایل و دسکتاپ (جلوگیری از فشردگی و به‌هم‌ریختگی)
            _buildBalanceRow(
              theme,
              'مبلغ کل فاکتور:',
              formatWithThousands(widget.invoiceTotal!, decimalPlaces: 0),
              theme.colorScheme.onSurface,
              isDesktop: isDesktop,
            ),
            SizedBox(height: isDesktop ? 16 : 12),
            _buildBalanceRow(
              theme,
              'مجموع تراکنش‌ها:',
              formatWithThousands(_totalPaid, decimalPlaces: 0),
              theme.colorScheme.onSurface,
              isDesktop: isDesktop,
            ),
            SizedBox(height: isDesktop ? 16 : 12),
            Divider(color: theme.colorScheme.outline.withOpacity(0.2)),
            SizedBox(height: isDesktop ? 16 : 12),
            _buildBalanceRow(
              theme,
              'مانده فاکتور:',
              formatWithThousands(_remainingBalance, decimalPlaces: 0),
              remainingColor,
              isBold: true,
              isDesktop: isDesktop,
            ),
            SizedBox(height: isDesktop ? 12 : 8),
            _buildBalanceRow(
              theme,
              'درصد مانده:',
              '${_remainingPercentage.toStringAsFixed(1)}%',
              remainingColor,
              isBold: true,
              isDesktop: isDesktop,
              showCurrency: false,
            ),
            SizedBox(height: isDesktop ? 12 : 8),
            _buildBalanceRow(
              theme,
              'درصد پرداخت شده:',
              '${_paidPercentage.toStringAsFixed(1)}%',
              theme.colorScheme.onSurface,
              isDesktop: isDesktop,
              showCurrency: false,
            ),
            // هشدار در صورت مانده مثبت
            if (hasRemaining) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.error,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'فاکتور هنوز تسویه نشده است. مانده باقی‌مانده: ${formatWithThousands(_remainingBalance, decimalPlaces: 0)} ${_currencySymbol ?? 'ریال'}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // اطلاع در صورت پرداخت اضافی
            if (isOverPaid) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.tertiary,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.tertiary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'مبلغ پرداخت شده بیشتر از مبلغ فاکتور است. مبلغ اضافی: ${formatWithThousands(-_remainingBalance, decimalPlaces: 0)} ${_currencySymbol ?? 'ریال'}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.tertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // پیام تسویه کامل
            if (isFullyPaid) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'فاکتور به طور کامل تسویه شده است.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildBalanceRow(
    ThemeData theme,
    String label,
    String value,
    Color valueColor, {
    bool isBold = false,
    bool isDesktop = false,
    bool showCurrency = true,
  }) {
    final displayValue = showCurrency && _currencySymbol != null
        ? '$value $_currencySymbol'
        : value;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: isDesktop ? 150 : 130,
          child: Text(
            label,
            style: (isDesktop 
                ? theme.textTheme.bodyLarge 
                : theme.textTheme.bodyMedium)?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            displayValue,
            style: (isDesktop 
                ? theme.textTheme.bodyLarge 
                : theme.textTheme.bodyMedium)?.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: valueColor,
              fontSize: isDesktop && isBold ? 18 : null,
            ),
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );
  }
  
  // پیام عدم وجود ردیف کالا یا مبلغ صفر
  Widget _buildNoItemsMessage(ThemeData theme) {
    final isDesktop = _isDesktop(context);
    
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 24 : 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: isDesktop ? 64 : 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'فاکتور بدون ردیف کالا',
              style: (isDesktop 
                  ? theme.textTheme.titleLarge 
                  : theme.textTheme.titleMedium)?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'برای افزودن تراکنش، ابتدا باید ردیف‌های کالا و خدمات را در تب "کالاها و خدمات" اضافه کنید.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'مبلغ کل فاکتور باید بیشتر از صفر باشد تا بتوانید تراکنش اضافه کنید.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionDialog extends StatefulWidget {
  final InvoiceTransaction? transaction;
  /// هنگام افزودن تراکنش جدید، مقدار اولیهٔ فیلد مبلغ (مثلاً ماندهٔ فاکتور).
  final num? initialAmount;
  /// نوع تراکنش پیش‌فرض (قبل از باز شدن دیالوگ resolve شده تا setState میانی فوکوس را نگیرد).
  final TransactionType? initialTransactionType;
  final int businessId;
  final CalendarController calendarController;
  final ValueChanged<InvoiceTransaction> onSave;
  final InvoiceType invoiceType;
  final int? selectedCurrencyId;
  /// واحد پول برای suffix فیلد مبلغ و متن tooltip (مثلاً ریال یا نماد ارز).
  final String currencyUnit;
  final CheckPickerMode checkPickerMode;
  final AuthStore? authStore;
  /// نرخ تسعیر فاکتور برای پیش‌فرض fx_rate.
  final num? invoiceFxRate;

  const TransactionDialog({
    super.key,
    this.transaction,
    this.initialAmount,
    this.initialTransactionType,
    required this.businessId,
    required this.calendarController,
    required this.invoiceType,
    this.selectedCurrencyId,
    this.currencyUnit = 'ریال',
    required this.onSave,
    this.checkPickerMode = CheckPickerMode.any,
    this.authStore,
    this.invoiceFxRate,
  });

  @override
  State<TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<TransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _uuid = const Uuid();
  
  late TransactionType _selectedType;
  DateTime _transactionDate = DateTime.now();
  final _amountController = TextEditingController();
  final _commissionController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _settlesAmountController = TextEditingController();
  final _fxRateController = TextEditingController();
  /// اگر کاربر مبلغ پرداخت را دستی عوض کرده، همگام خودکار بازنویسی نکند.
  bool _paymentAmountManuallyEdited = false;
  bool _syncingPaymentAmount = false;
  /// کاربر نرخ را دستی عوض کرده؛ resolve خودکار بازنویسی نکند.
  bool _fxRateManuallyEdited = false;
  bool _syncingFxRate = false;
  bool _fxRateLoading = false;
  bool _fxRateRefreshing = false;
  String? _fxRateSourceHint;
  /// نرخ‌های resolve‌شده به پایه (برای محاسبه صحیح فرعی↔فرعی).
  double? _resolvedSettleRateToBase;
  double? _resolvedPayRateToBase;
  
  // سرویس‌ها
  final BankAccountService _bankService = BankAccountService();
  final CashRegisterService _cashRegisterService = CashRegisterService();
  final PettyCashService _pettyCashService = PettyCashService();
  final PersonService _personService = PersonService();
  final AccountService _accountService = AccountService();
  final ApiClient _apiClient = ApiClient();
  late final CurrencyService _currencyService = CurrencyService(_apiClient);
  late final BusinessCurrencyRateService _rateService =
      BusinessCurrencyRateService(_apiClient);
  late final BusinessFxGlobalRateService _globalFxService =
      BusinessFxGlobalRateService(_apiClient);
  
  // فیلدهای خاص هر نوع تراکنش
  String? _selectedBankId;
  String? _selectedCashRegisterId;
  String? _selectedPettyCashId;
  String? _selectedCheckId;
  int? _selectedCheckCurrencyId;
  String? _selectedCheckNumber;
  String? _selectedPersonId;
  AccountTreeNode? _selectedAccount;
  int? _selectedPaymentCurrencyId;
  String? _paymentCurrencyUnit;
  
  // لیست‌های داده
  List<Map<String, dynamic>> _banks = [];
  List<Map<String, dynamic>> _cashRegisters = [];
  List<Map<String, dynamic>> _pettyCashList = [];
  List<Map<String, dynamic>> _persons = [];
  Map<int, Map<String, dynamic>> _currencyById = {};

  bool get _isMultiCurrency => widget.authStore?.isMultiCurrency ?? false;

  int? get _baseCurrencyId => widget.authStore?.currentBusiness?.defaultCurrency?.id;

  bool get _isCrossCurrencyPayment {
    final inv = widget.selectedCurrencyId;
    final pay = _selectedPaymentCurrencyId;
    if (inv == null || pay == null) return false;
    return inv != pay;
  }

  @override
  void initState() {
    super.initState();
    _selectedType = widget.transaction?.type ??
        widget.initialTransactionType ??
        TransactionType.bank;
    _transactionDate = widget.transaction?.transactionDate ?? DateTime.now();
    if (widget.transaction != null) {
      _amountController.text =
          formatWithThousands(widget.transaction!.amount, decimalPlaces: 0);
      _paymentAmountManuallyEdited = true;
    } else {
      // مبلغ پرداخت را بعد از مشخص شدن ارز حساب از روی تسویه×نرخ پر می‌کنیم
      // تا عدد ارزی فاکتور اشتباهاً به‌عنوان مبلغ ریالی ثبت نشود.
      _amountController.text = '';
    }
    _commissionController.text = widget.transaction?.commission != null
        ? formatWithThousands(widget.transaction!.commission!, decimalPlaces: 0)
        : '';
    _descriptionController.text = widget.transaction?.description ?? '';
    if (widget.transaction?.settlesAmount != null) {
      _settlesAmountController.text = formatWithThousands(
        widget.transaction!.settlesAmount!,
        decimalPlaces: 2,
      );
    } else if (widget.initialAmount != null && widget.transaction == null) {
      _settlesAmountController.text = formatWithThousands(
        widget.initialAmount!,
        decimalPlaces: 2,
      );
    }
    if (widget.transaction?.fxRate != null) {
      _fxRateController.text = formatFxRateForDisplay(widget.transaction!.fxRate);
      _fxRateManuallyEdited = true;
      _fxRateSourceHint = 'نرخ ثبت‌شده روی تراکنش';
    } else if (widget.invoiceFxRate != null) {
      _fxRateController.text = formatFxRateForDisplay(widget.invoiceFxRate);
      _fxRateSourceHint = 'نرخ تسعیر سند';
    }

    _settlesAmountController.addListener(_onSettlesOrRateChanged);
    _fxRateController.addListener(_onFxRateEdited);
    _amountController.addListener(_onAmountEdited);
    
    // تنظیم فیلدهای خاص
    _selectedBankId = widget.transaction?.bankId;
    _selectedCashRegisterId = widget.transaction?.cashRegisterId;
    _selectedPettyCashId = widget.transaction?.pettyCashId;
    _selectedCheckId = widget.transaction?.checkId;
    _selectedCheckNumber = widget.transaction?.checkNumber;
    _selectedPersonId = widget.transaction?.personId;
    _selectedPaymentCurrencyId = widget.transaction?.paymentCurrencyId;
    
    // اگر حساب انتخاب شده است، باید آن را از API دریافت کنیم
    if (widget.transaction?.accountId != null) {
      _loadSelectedAccount();
    }
    
    // لود کردن داده‌ها از دیتابیس
    _loadData();
  }

  Future<void> _loadSelectedAccount() async {
    try {
      final response = await _accountService.getAccountsTree(businessId: widget.businessId);
      final items = (response['items'] as List<dynamic>?)
          ?.map((item) => AccountTreeNode.fromJson(item as Map<String, dynamic>))
          .toList() ?? [];
      
      // جستجو برای پیدا کردن حساب انتخاب شده
      final accountId = int.tryParse(widget.transaction?.accountId ?? '');
      if (accountId != null) {
        for (final account in items) {
          final foundAccount = account.getAllAccounts().firstWhere(
            (acc) => acc.id == accountId,
            orElse: () => throw StateError('Account not found'),
          );
          if (foundAccount.id == accountId) {
            setState(() {
              _selectedAccount = foundAccount;
            });
            break;
          }
        }
      }
    } catch (e, stackTrace) {
      if (mounted) {
        debugPrint('Failed to load selected account: $e');
        debugPrint('$stackTrace');
      }
    }
  }

  Future<void> _loadData() async {
    try {
      try {
        final currencies = await _currencyService.listBusinessCurrencies(
          businessId: widget.businessId,
        );
        final map = <int, Map<String, dynamic>>{};
        for (final c in currencies) {
          final id = (c['id'] as num?)?.toInt();
          if (id != null) map[id] = c;
        }
        _currencyById = map;
      } catch (_) {}

      // لود کردن بانک‌ها
      final bankResponse = await _bankService.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      _banks = (bankResponse['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      
      // لود کردن صندوق‌ها
      final cashRegisterResponse = await _cashRegisterService.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      _cashRegisters = (cashRegisterResponse['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      
      // لود کردن تنخواهگردان‌ها
      final pettyCashResponse = await _pettyCashService.list(
        businessId: widget.businessId,
        queryInfo: {'take': 100, 'skip': 0},
      );
      _pettyCashList = (pettyCashResponse['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      
      // لود کردن اشخاص
      final personResponse = await _personService.getPersons(
        businessId: widget.businessId,
        limit: 100,
      );
      _persons = (personResponse['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

      if (mounted) {
        setState(() {
          _syncPaymentCurrencyFromSelection();
        });
      }
    } catch (e) {
      // در صورت خطا، لیست‌ها خالی باقی می‌مانند
    }
  }

  void _onAmountEdited() {
    if (_syncingPaymentAmount) return;
    _paymentAmountManuallyEdited = true;
  }

  void _onFxRateEdited() {
    if (_syncingFxRate) return;
    _fxRateManuallyEdited = true;
    _fxRateSourceHint = 'نرخ دستی';
    _onSettlesOrRateChanged();
  }

  void _onSettlesOrRateChanged() {
    if (!_isCrossCurrencyPayment) return;
    if (_paymentAmountManuallyEdited) return;
    _recalcPaymentAmountFromSettles(force: false);
  }

  double? _parseMoneyField(String raw) {
    final t = raw.replaceAll(',', '').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  bool get _paymentIsBase {
    final base = _baseCurrencyId;
    final pay = _selectedPaymentCurrencyId;
    return base != null && pay != null && pay == base;
  }

  bool get _settleIsBase {
    final base = _baseCurrencyId;
    final inv = widget.selectedCurrencyId;
    return base != null && inv != null && inv == base;
  }

  String get _fxRateHelperText {
    if (_paymentIsBase) {
      return '۱ واحد ارز فاکتور = نرخ × ارز پایه (حساب پرداخت)';
    }
    if (_settleIsBase) {
      return '۱ واحد ارز حساب پرداخت = نرخ × ارز پایه';
    }
    return 'نرخ متقاطع: ۱ واحد ارز فاکتور ≈ نرخ × ارز حساب پرداخت';
  }

  /// مبلغ پرداخت مورد انتظار مطابق بک‌اند: تسویه × (نرخ‌تسویه / نرخ‌پرداخت).
  double? _expectedPaymentAmount() {
    final settles = _parseMoneyField(_settlesAmountController.text);
    if (settles == null || settles <= 0) return null;

    final rate = _parseMoneyField(_fxRateController.text);
    if (rate != null && rate > 0) {
      if (_paymentIsBase) return settles * rate;
      if (_settleIsBase) return settles / rate;
      // فرعی↔فرعی: فیلد نرخ = متقاطع
      return settles * rate;
    }

    final rSettle = _resolvedSettleRateToBase;
    final rPay = _resolvedPayRateToBase;
    if (rSettle != null && rPay != null && rSettle > 0 && rPay > 0) {
      return settles * rSettle / rPay;
    }
    return null;
  }

  void _recalcPaymentAmountFromSettles({bool force = false}) {
    if (!_isCrossCurrencyPayment) return;
    if (!force && _paymentAmountManuallyEdited) return;
    final expected = _expectedPaymentAmount();
    if (expected == null) return;
    _syncingPaymentAmount = true;
    _amountController.text = formatWithThousands(expected, decimalPlaces: 0);
    _syncingPaymentAmount = false;
    if (force) _paymentAmountManuallyEdited = false;
    if (mounted) setState(() {});
  }

  String _asOfIso() {
    final d = _transactionDate.toUtc();
    return d.toIso8601String();
  }

  Future<double?> _resolveRateToBase(int currencyId) async {
    final base = _baseCurrencyId;
    if (base != null && currencyId == base) return 1.0;
    try {
      final out = await _rateService.resolve(
        businessId: widget.businessId,
        currencyId: currencyId,
        asOfIso: _asOfIso(),
      );
      final r = out['rate'];
      if (r == null) return null;
      return double.tryParse(r.toString().replaceAll(',', ''));
    } catch (_) {
      return null;
    }
  }

  /// پر کردن نرخ از آخرین سند تسعیر (resolve دفتر نرخ).
  Future<void> _loadFxRateFromLedger({bool force = false}) async {
    if (!_isCrossCurrencyPayment) return;
    if (!force && _fxRateManuallyEdited && _fxRateController.text.trim().isNotEmpty) {
      return;
    }
    if (!force &&
        widget.transaction?.fxRate != null &&
        _fxRateController.text.trim().isNotEmpty) {
      return;
    }

    final inv = widget.selectedCurrencyId;
    final pay = _selectedPaymentCurrencyId;
    if (inv == null || pay == null) return;

    if (mounted) setState(() => _fxRateLoading = true);
    try {
      final rSettle = await _resolveRateToBase(inv);
      final rPay = await _resolveRateToBase(pay);
      if (!mounted) return;

      _resolvedSettleRateToBase = rSettle;
      _resolvedPayRateToBase = rPay;

      double? displayRate;
      String? hint;
      if (rSettle != null && rPay != null && rSettle > 0 && rPay > 0) {
        if (_paymentIsBase) {
          displayRate = rSettle;
          hint = 'از آخرین نرخ تسعیر ارز فاکتور';
        } else if (_settleIsBase) {
          displayRate = rPay;
          hint = 'از آخرین نرخ تسعیر ارز حساب پرداخت';
        } else {
          displayRate = rSettle / rPay;
          hint = 'نرخ متقاطع از آخرین تسعیر هر دو ارز';
        }
      } else if (widget.invoiceFxRate != null) {
        displayRate = widget.invoiceFxRate!.toDouble();
        hint = 'نرخ تسعیر سند (نرخ دفتر برای این ارز یافت نشد)';
      }

      if (displayRate != null && displayRate > 0) {
        _syncingFxRate = true;
        _fxRateController.text = formatFxRateForDisplay(displayRate);
        _syncingFxRate = false;
        if (force) _fxRateManuallyEdited = false;
        _fxRateSourceHint = hint;
      } else if (_fxRateController.text.trim().isEmpty) {
        _fxRateSourceHint = 'نرخی در دفتر تسعیر یافت نشد — دستی وارد کنید یا از اسنپ‌شات بگیرید';
      }

      _recalcPaymentAmountFromSettles(
        force: force || !_paymentAmountManuallyEdited,
      );
    } finally {
      if (mounted) setState(() => _fxRateLoading = false);
    }
  }

  /// گرفتن آخرین نرخ از اسنپ‌شات مرکزی، ثبت در دفتر تسعیر، و اعمال در فیلد.
  Future<void> _refreshFxRateFromGlobal() async {
    if (!_isCrossCurrencyPayment) return;
    final canAdd =
        widget.authStore?.hasBusinessPermission('currency_revaluation', 'add') ??
            false;
    if (!canAdd) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'مجوز ثبت نرخ تسعیر ندارید',
        );
      }
      return;
    }

    final inv = widget.selectedCurrencyId;
    final pay = _selectedPaymentCurrencyId;
    final base = _baseCurrencyId;
    if (inv == null || pay == null || base == null) return;

    final foreignIds = <int>{};
    if (inv != base) foreignIds.add(inv);
    if (pay != base) foreignIds.add(pay);
    if (foreignIds.isEmpty) return;

    if (mounted) setState(() => _fxRateRefreshing = true);
    try {
      final latest =
          await _globalFxService.latest(businessId: widget.businessId);
      final globalItems = (latest['items'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (globalItems.isEmpty) {
        if (!mounted) return;
        SnackBarHelper.showError(
          context,
          message:
              'اسنپ‌شات مرکزی خالی است. ابتدا از مدیریت کل، واکشی نرخ را انجام دهید.',
        );
        return;
      }

      if (latest['stale'] == true && mounted) {
        final age = latest['max_age_hours'];
        final cont = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('اسنپ‌شات قدیمی'),
            content: Text(
              'آخرین واکشی مرکزی حدود ${age ?? '—'} ساعت پیش بوده است. ادامه می‌دهید؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ادامه'),
              ),
            ],
          ),
        );
        if (cont != true) return;
      }

      final applyItems = <Map<String, dynamic>>[];
      for (final g in globalItems) {
        final cid = (g['business_currency_id'] as num?)?.toInt();
        if (cid == null || !foreignIds.contains(cid)) continue;
        applyItems.add({
          'currency_id': cid,
          'symbol': g['symbol'],
        });
      }
      if (applyItems.isEmpty) {
        if (!mounted) return;
        SnackBarHelper.showError(
          context,
          message: 'برای ارز(های) این تراکنش نرخی در اسنپ‌شات مرکزی نیست',
        );
        return;
      }

      await _globalFxService.applyFromGlobal(
        businessId: widget.businessId,
        items: applyItems,
        note: 'از دیالوگ تراکنش دریافت/پرداخت',
      );

      _fxRateManuallyEdited = false;
      await _loadFxRateFromLedger(force: true);
      if (!mounted) return;
      SnackBarHelper.show(
        context,
        message: 'نرخ از اسنپ‌شات مرکزی ثبت و اعمال شد',
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(
        context,
        message: ErrorExtractor.forContext(e, context),
      );
    } finally {
      if (mounted) setState(() => _fxRateRefreshing = false);
    }
  }

  void _setPaymentCurrency(int? currencyId) {
    final wasCross = _isCrossCurrencyPayment;
    final prevPay = _selectedPaymentCurrencyId;
    _selectedPaymentCurrencyId = currencyId;
    if (currencyId != null && _currencyById.containsKey(currencyId)) {
      final c = _currencyById[currencyId]!;
      _paymentCurrencyUnit =
          c['symbol']?.toString() ?? c['code']?.toString() ?? widget.currencyUnit;
    } else {
      _paymentCurrencyUnit = null;
    }
    if (_isCrossCurrencyPayment) {
      if (_settlesAmountController.text.trim().isEmpty &&
          widget.initialAmount != null) {
        _settlesAmountController.text = formatWithThousands(
          widget.initialAmount!,
          decimalPlaces: 2,
        );
      }
      // ورود به حالت بین‌ارزی یا تغییر ارز حساب → مبلغ پرداخت را از تسویه×نرخ بساز
      final shouldForce = !wasCross ||
          prevPay != currencyId ||
          !_paymentAmountManuallyEdited;
      final enteredCross = !wasCross || prevPay != currencyId;
      if (enteredCross) {
        // نرخ را از دفتر تسعیر بگیر (مگر ویرایش دستی قبلی روی همین تراکنش)
        _loadFxRateFromLedger(force: widget.transaction == null);
      } else if (_fxRateController.text.trim().isEmpty &&
          widget.invoiceFxRate != null) {
        _syncingFxRate = true;
        _fxRateController.text = formatFxRateForDisplay(widget.invoiceFxRate);
        _syncingFxRate = false;
      }
      _recalcPaymentAmountFromSettles(
        force: shouldForce || _amountController.text.trim().isEmpty,
      );
    }
  }

  void _syncPaymentCurrencyFromSelection() {
    switch (_selectedType) {
      case TransactionType.bank:
        if (_selectedBankId != null) {
          final bank = _banks.firstWhere(
            (b) => b['id']?.toString() == _selectedBankId,
            orElse: () => <String, dynamic>{},
          );
          _setPaymentCurrency(
            int.tryParse('${bank['currency_id'] ?? bank['currencyId'] ?? ''}'),
          );
        }
        break;
      case TransactionType.cashRegister:
        if (_selectedCashRegisterId != null) {
          final cr = _cashRegisters.firstWhere(
            (c) => c['id']?.toString() == _selectedCashRegisterId,
            orElse: () => <String, dynamic>{},
          );
          _setPaymentCurrency(
            int.tryParse('${cr['currency_id'] ?? cr['currencyId'] ?? ''}'),
          );
        }
        break;
      case TransactionType.pettyCash:
        if (_selectedPettyCashId != null) {
          final pc = _pettyCashList.firstWhere(
            (p) => p['id']?.toString() == _selectedPettyCashId,
            orElse: () => <String, dynamic>{},
          );
          _setPaymentCurrency(
            int.tryParse('${pc['currency_id'] ?? pc['currencyId'] ?? ''}'),
          );
        }
        break;
      case TransactionType.check:
      case TransactionType.checkExpense:
        _setPaymentCurrency(_selectedCheckCurrencyId);
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _settlesAmountController.removeListener(_onSettlesOrRateChanged);
    _fxRateController.removeListener(_onFxRateEdited);
    _amountController.removeListener(_onAmountEdited);
    _amountController.dispose();
    _commissionController.dispose();
    _descriptionController.dispose();
    _settlesAmountController.dispose();
    _fxRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // هدر
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    color: theme.colorScheme.onPrimary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.transaction != null ? 'ویرایش تراکنش' : 'افزودن تراکنش',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: theme.colorScheme.onPrimary,
                  ),
                ],
              ),
            ),
            
            // فرم
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // انتخاب نوع تراکنش
                      DropdownButtonFormField<TransactionType>(
                        initialValue: _selectedType,
                        decoration: const InputDecoration(
                          labelText: 'نوع تراکنش *',
                          border: OutlineInputBorder(),
                        ),
                        items: _availableTransactionTypes().map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedType = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // فیلدهای خاص بر اساس نوع تراکنش
                      _buildTypeSpecificFields(),
                      const SizedBox(height: 16),
                      
                      // تاریخ تراکنش
                      DateInputField(
                        value: _transactionDate,
                        onChanged: (date) {
                          if (date != null) {
                            setState(() {
                              _transactionDate = date;
                            });
                          }
                        },
                        labelText: 'تاریخ تراکنش *',
                        helpText: 'انتخاب تاریخ تراکنش',
                        calendarController: widget.calendarController,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'تاریخ تراکنش الزامی است';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // مبلغ و کارمزد — در حالت بین‌ارزی مبلغ پرداخت داخل باکس پایین است
                      if (!(_isMultiCurrency && _isCrossCurrencyPayment))
                        Row(
                          children: [
                            Expanded(
                              child: _TransactionDialogMoneyField(
                                key: const ValueKey('transaction_amount_field'),
                                controller: _amountController,
                                label: 'مبلغ *',
                                currencyUnit: widget.currencyUnit,
                                isRequired: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _TransactionDialogMoneyField(
                                key: const ValueKey('transaction_commission_field'),
                                controller: _commissionController,
                                label: 'کارمزد',
                                currencyUnit: widget.currencyUnit,
                                isRequired: false,
                              ),
                            ),
                          ],
                        ),
                      if (_isMultiCurrency && _isCrossCurrencyPayment) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'پرداخت بین‌ارزی',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'فقط «مبلغ تسویه» را وارد کنید؛ مبلغ پرداخت با نرخ '
                                'به‌صورت خودکار محاسبه می‌شود. نرخ از آخرین تسعیر پر می‌شود '
                                'و در صورت نیاز قابل ویرایش است.',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 12),
                              _TransactionDialogMoneyField(
                                key: const ValueKey('transaction_settles_field'),
                                controller: _settlesAmountController,
                                label: 'مبلغ تسویه (ارز فاکتور) *',
                                currencyUnit: widget.currencyUnit,
                                isRequired: true,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _fxRateController,
                                decoration: InputDecoration(
                                  labelText: 'نرخ تبدیل *',
                                  border: const OutlineInputBorder(),
                                  helperText: _fxRateSourceHint != null
                                      ? '$_fxRateHelperText\n$_fxRateSourceHint'
                                      : _fxRateHelperText,
                                  helperMaxLines: 3,
                                  suffixIcon: (_fxRateLoading || _fxRateRefreshing)
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]'),
                                  ),
                                ],
                                validator: (v) {
                                  if (!_isCrossCurrencyPayment) return null;
                                  final t = (v ?? '').trim().replaceAll(',', '');
                                  if (t.isEmpty) return 'نرخ تبدیل الزامی است';
                                  final n = double.tryParse(t);
                                  if (n == null || n <= 0) {
                                    return 'نرخ نامعتبر است';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: (_fxRateLoading ||
                                            _fxRateRefreshing)
                                        ? null
                                        : () => _loadFxRateFromLedger(
                                              force: true,
                                            ),
                                    icon: const Icon(Icons.history, size: 18),
                                    label: const Text('آخرین تسعیر'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: (_fxRateLoading ||
                                            _fxRateRefreshing)
                                        ? null
                                        : _refreshFxRateFromGlobal,
                                    icon: const Icon(
                                      Icons.cloud_download_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('اسنپ‌شات مرکزی'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _TransactionDialogMoneyField(
                                      key: const ValueKey(
                                        'transaction_amount_field_cross',
                                      ),
                                      controller: _amountController,
                                      label: _paymentAmountManuallyEdited
                                          ? 'مبلغ پرداخت (دستی) *'
                                          : 'مبلغ پرداخت (محاسبه‌شده) *',
                                      currencyUnit:
                                          _paymentCurrencyUnit ??
                                              widget.currencyUnit,
                                      isRequired: true,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    children: [
                                      IconButton(
                                        tooltip:
                                            'بازنشانی مبلغ پرداخت از تسویه × نرخ',
                                        onPressed: () =>
                                            _recalcPaymentAmountFromSettles(
                                          force: true,
                                        ),
                                        icon: const Icon(Icons.calculate_outlined),
                                      ),
                                      if (_paymentAmountManuallyEdited)
                                        Text(
                                          'دستی',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: theme.colorScheme.tertiary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              if (_expectedPaymentAmount() != null &&
                                  _paymentAmountManuallyEdited) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'معادل نرخ‌دار: '
                                  '${formatWithThousands(_expectedPaymentAmount(), decimalPlaces: 0)}'
                                  ' ${_paymentCurrencyUnit ?? ''}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              _TransactionDialogMoneyField(
                                key: const ValueKey(
                                  'transaction_commission_field_cross',
                                ),
                                controller: _commissionController,
                                label: 'کارمزد',
                                currencyUnit: widget.currencyUnit,
                                isRequired: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      
                      // توضیحات
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'توضیحات',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // دکمه‌ها
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('انصراف'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saveTransaction,
                    child: Text(widget.transaction != null ? 'ذخیره' : 'افزودن'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSpecificFields() {
    switch (_selectedType) {
      case TransactionType.bank:
        return _buildBankFields();
      case TransactionType.cashRegister:
        return _buildCashRegisterFields();
      case TransactionType.pettyCash:
        return _buildPettyCashFields();
      case TransactionType.check:
        return _buildCheckFields();
      case TransactionType.checkExpense:
        return _buildCheckExpenseFields();
      case TransactionType.person:
        return _buildPersonFields();
      case TransactionType.account:
        return _buildAccountFields();
    }
  }

  List<TransactionType> _availableTransactionTypes() {
    // خرج چک فقط برای خرید یا برگشت از فروش نمایش داده شود
    final showCheckExpense = widget.invoiceType == InvoiceType.purchase || widget.invoiceType == InvoiceType.salesReturn;
    final all = TransactionType.allTypes;
    if (showCheckExpense) return all;
    return all.where((t) => t != TransactionType.checkExpense).toList();
  }

  Widget _buildBankFields() {
    return BankAccountComboboxWidget(
      businessId: widget.businessId,
      selectedAccountId: _selectedBankId,
      // چندارزی: همه حساب‌ها؛ تک‌ارزی: فقط هم‌ارز فاکتور
      filterCurrencyId: _isMultiCurrency ? null : widget.selectedCurrencyId,
      onChanged: (opt) {
        setState(() {
          _selectedBankId = opt?.id;
          _setPaymentCurrency(opt?.currencyId);
        });
      },
      label: 'بانک *',
      hintText: 'جست‌وجو و انتخاب بانک',
      isRequired: true,
    );
  }

  Widget _buildCashRegisterFields() {
    return CashRegisterComboboxWidget(
      businessId: widget.businessId,
      selectedRegisterId: _selectedCashRegisterId,
      filterCurrencyId: _isMultiCurrency ? null : widget.selectedCurrencyId,
      onChanged: (opt) {
        setState(() {
          _selectedCashRegisterId = opt?.id;
          _setPaymentCurrency(opt?.currencyId);
        });
      },
      label: 'صندوق *',
      hintText: 'جست‌وجو و انتخاب صندوق',
      isRequired: true,
    );
  }

  Widget _buildPettyCashFields() {
    return PettyCashComboboxWidget(
      businessId: widget.businessId,
      selectedPettyCashId: _selectedPettyCashId,
      filterCurrencyId: _isMultiCurrency ? null : widget.selectedCurrencyId,
      onChanged: (opt) {
        setState(() {
          _selectedPettyCashId = opt?.id;
          _setPaymentCurrency(opt?.currencyId);
        });
      },
      label: 'تنخواهگردان *',
      hintText: 'جست‌وجو و انتخاب تنخواه‌گردان',
      isRequired: true,
    );
  }

  Widget _buildCheckFields({
    CheckPickerMode? pickerMode,
    String label = 'چک *',
    String hintText = 'جست‌وجو و انتخاب چک',
  }) {
    return CheckComboboxWidget(
      businessId: widget.businessId,
      selectedCheckId: _selectedCheckId,
      selectedCheckNumber: _selectedCheckNumber,
      filterCurrencyId: _isMultiCurrency ? null : widget.selectedCurrencyId,
      mode: pickerMode ?? widget.checkPickerMode,
      onChanged: _onCheckSelected,
      label: label,
      hintText: hintText,
      authStore: widget.authStore,
      calendarController: widget.calendarController,
    );
  }

  Widget _buildCheckExpenseFields() {
    return _buildCheckFields(
      pickerMode: CheckPickerMode.payment,
      label: 'خرج چک *',
      hintText: 'انتخاب چک خرج‌شده',
    );
  }

  void _onCheckSelected(CheckOption? option) {
    setState(() {
      _selectedCheckId = option?.id;
      _selectedCheckCurrencyId = option?.currencyId;
      _selectedCheckNumber = option?.number;
      _setPaymentCurrency(option?.currencyId);
    });
  }

  Widget _buildPersonFields() {
    // پیدا کردن شخص انتخاب شده از لیست
    Person? selectedPerson;
    if (_selectedPersonId != null) {
      try {
        final personData = _persons.firstWhere(
          (p) => p['id']?.toString() == _selectedPersonId,
        );
        selectedPerson = Person.fromJson(personData);
      } catch (e) {
        selectedPerson = null;
      }
    }

    return PersonComboboxWidget(
      businessId: widget.businessId,
      showFinancialBalance: true,
      selectedPerson: selectedPerson,
      onChanged: (person) {
        setState(() {
          _selectedPersonId = person?.id?.toString();
        });
      },
      label: 'شخص *',
      hintText: 'انتخاب شخص',
      isRequired: true,
    );
  }

  Widget _buildAccountFields() {
    return AccountTreeComboboxWidget(
      businessId: widget.businessId,
      selectedAccount: _selectedAccount?.toAccount(),
      onChanged: (account) {
        setState(() {
          // تبدیل Account به AccountTreeNode - فقط id را نگه می‌داریم
          // برای استفاده کامل، باید از tree اصلی پیدا شود
          if (account != null) {
            _selectedAccount = AccountTreeNode(
              id: account.id!,
              code: account.code,
              name: account.name,
              accountType: account.accountType,
              parentId: account.parentId,
            );
          } else {
            _selectedAccount = null;
          }
        });
      },
      label: 'حساب *',
      hintText: 'انتخاب حساب',
      isRequired: true,
    );
  }


  Future<void> _saveTransaction() async {
    // قبل از validate: مبلغ پرداخت را از تسویه×نرخ همگام کن تا فیلد خالی نماند
    if (_isCrossCurrencyPayment && !_paymentAmountManuallyEdited) {
      _recalcPaymentAmountFromSettles(force: true);
    }
    if (!_formKey.currentState!.validate()) return;
    
    // اعتبارسنجی انتخاب فیلدهای خاص هر نوع تراکنش
    switch (_selectedType) {
      case TransactionType.person:
        if (_selectedPersonId == null || _selectedPersonId!.isEmpty) {
          SnackBarHelper.showError(context, message: 'انتخاب شخص الزامی است');
          return;
        }
        break;
      case TransactionType.bank:
        if (_selectedBankId == null || _selectedBankId!.isEmpty) {
          SnackBarHelper.showError(context, message: 'انتخاب بانک الزامی است');
          return;
        }
        break;
      case TransactionType.cashRegister:
        if (_selectedCashRegisterId == null || _selectedCashRegisterId!.isEmpty) {
          SnackBarHelper.showError(context, message: 'انتخاب صندوق الزامی است');
          return;
        }
        break;
      case TransactionType.pettyCash:
        if (_selectedPettyCashId == null || _selectedPettyCashId!.isEmpty) {
          SnackBarHelper.showError(context, message: 'انتخاب تنخواه‌گردان الزامی است');
          return;
        }
        break;
      case TransactionType.check:
      case TransactionType.checkExpense:
        if (_selectedCheckId == null || _selectedCheckId!.isEmpty) {
          SnackBarHelper.showError(context, message: 'انتخاب چک الزامی است');
          return;
        }
        break;
      case TransactionType.account:
        if (_selectedAccount == null) {
          SnackBarHelper.showError(context, message: 'انتخاب حساب الزامی است');
          return;
        }
        break;
    }
    
    final amountRaw = _amountController.text.replaceAll(',', '').trim();
    var amount = amountRaw.isEmpty ? 0.0 : (double.tryParse(amountRaw) ?? 0.0);
    if (amountRaw.isEmpty && !(_isMultiCurrency && _isCrossCurrencyPayment)) {
      SnackBarHelper.showError(context, message: 'مبلغ الزامی است');
      return;
    }
    final commission = _commissionController.text.isNotEmpty 
        ? double.parse(_commissionController.text.replaceAll(',', '')) 
        : null;
    // اعتبارسنجی هم‌خوانی ارز با ارز فاکتور
    final invoiceCurrencyId = widget.selectedCurrencyId;
    if (invoiceCurrencyId != null) {
      int? accountCurrencyId;
      String? mismatchMsg;
      if (_selectedType == TransactionType.bank && _selectedBankId != null) {
        final bank = _banks.firstWhere(
          (b) => b['id']?.toString() == _selectedBankId,
          orElse: () => <String, dynamic>{},
        );
        accountCurrencyId =
            int.tryParse('${bank['currency_id'] ?? bank['currencyId'] ?? ''}');
        mismatchMsg = 'ارز بانک انتخابی با ارز فاکتور هم‌خوانی ندارد';
      } else if (_selectedType == TransactionType.cashRegister &&
          _selectedCashRegisterId != null) {
        final cr = _cashRegisters.firstWhere(
          (c) => c['id']?.toString() == _selectedCashRegisterId,
          orElse: () => <String, dynamic>{},
        );
        accountCurrencyId =
            int.tryParse('${cr['currency_id'] ?? cr['currencyId'] ?? ''}');
        mismatchMsg = 'ارز صندوق انتخابی با ارز فاکتور هم‌خوانی ندارد';
      } else if (_selectedType == TransactionType.pettyCash &&
          _selectedPettyCashId != null) {
        final pc = _pettyCashList.firstWhere(
          (p) => p['id']?.toString() == _selectedPettyCashId,
          orElse: () => <String, dynamic>{},
        );
        accountCurrencyId =
            int.tryParse('${pc['currency_id'] ?? pc['currencyId'] ?? ''}');
        mismatchMsg = 'ارز تنخواه‌گردان انتخابی با ارز فاکتور هم‌خوانی ندارد';
      } else if ((_selectedType == TransactionType.check ||
              _selectedType == TransactionType.checkExpense) &&
          _selectedCheckId != null) {
        accountCurrencyId = _selectedCheckCurrencyId;
        mismatchMsg = 'ارز چک انتخابی با ارز فاکتور هم‌خوانی ندارد';
      }

      if (accountCurrencyId != null && accountCurrencyId != invoiceCurrencyId) {
        if (!_isMultiCurrency) {
          SnackBarHelper.showError(context, message: mismatchMsg ?? 'عدم تطابق ارز');
          return;
        }
        // بین‌ارزی: نرخ و مبلغ تسویه الزامی است (فرعی↔فرعی با دو نرخ به پایه پشتیبانی می‌شود)
        if (_fxRateController.text.trim().isEmpty && widget.invoiceFxRate != null) {
          _fxRateController.text = widget.invoiceFxRate.toString();
        }
        _setPaymentCurrency(accountCurrencyId);
      } else if (accountCurrencyId != null) {
        _setPaymentCurrency(accountCurrencyId);
      }
    }

    // قبل از اعتبارسنجی بین‌ارزی، ارز حساب را از انتخاب فعلی دوباره بخوان
    _syncPaymentCurrencyFromSelection();

    num? settlesAmount;
    num? fxRate;
    var allowLargeFxDiff = false;
    // تشخیص بین‌ارزی حتی اگر فلگ MC در کلاینت دیر به‌روز شده باشد
    final payCur = _selectedPaymentCurrencyId;
    final invCur = widget.selectedCurrencyId;
    final isCross = invCur != null && payCur != null && invCur != payCur;
    // فاکتور ارزی با ارز حساب نامشخص: settles را بفرست تا بک‌اند تبدیل کند
    final foreignInvoiceNeedsSettles = !isCross &&
        invCur != null &&
        _baseCurrencyId != null &&
        invCur != _baseCurrencyId;

    if (isCross || foreignInvoiceNeedsSettles) {
      // اگر فیلد تسویه خالی است، مبلغ واردشده را تسویهٔ ارزی فاکتور بگیر
      var settlesText = _settlesAmountController.text.replaceAll(',', '').trim();
      if (settlesText.isEmpty) {
        settlesText = amountRaw.isNotEmpty ? amountRaw : '';
        if (settlesText.isNotEmpty) {
          _settlesAmountController.text = formatWithThousands(
            double.tryParse(settlesText) ?? 0,
            decimalPlaces: 2,
          );
        }
      }
      if (settlesText.isEmpty && widget.initialAmount != null) {
        settlesText = widget.initialAmount!.toString();
        _settlesAmountController.text = formatWithThousands(
          widget.initialAmount!,
          decimalPlaces: 2,
        );
      }
      if (settlesText.isEmpty) {
        SnackBarHelper.showError(
          context,
          message: 'مبلغ تسویه به ارز فاکتور الزامی است',
        );
        return;
      }
      settlesAmount = double.tryParse(settlesText);
      if (settlesAmount == null || settlesAmount <= 0) {
        SnackBarHelper.showError(context, message: 'مبلغ تسویه نامعتبر است');
        return;
      }
      if (_fxRateController.text.trim().isEmpty && widget.invoiceFxRate != null) {
        _fxRateController.text = formatFxRateForDisplay(widget.invoiceFxRate);
      }
      final rateText = _fxRateController.text.replaceAll(',', '').trim();
      fxRate = double.tryParse(rateText);
      // نرخ خالی: بک‌اند از نرخ فاکتور/دفتر نرخ استفاده می‌کند؛ اینجا settles را می‌فرستیم

      if (isCross && fxRate != null && fxRate > 0) {
        // اگر مبلغ پرداخت هنوز خالی یا برابر عدد تسویه (بدون تبدیل) است، اصلاح کن
        final expected = _expectedPaymentAmount() ?? (settlesAmount * fxRate);
        final looksUnconverted = amount > 0 &&
            (amount - settlesAmount).abs() < 0.0001 &&
            (expected - amount).abs() > 0.01;
        if (amount <= 0 || looksUnconverted) {
          amount = expected.toDouble();
          _syncingPaymentAmount = true;
          _amountController.text = formatWithThousands(expected, decimalPlaces: 0);
          _syncingPaymentAmount = false;
        } else {
          final fxDiffRatio =
              expected == 0 ? 0.0 : (expected - amount).abs() / expected;
          if (fxDiffRatio > 0.25) {
            final cont = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('اختلاف تسعیر غیرعادی'),
                content: Text(
                  'مبلغ پرداخت (${formatWithThousands(amount, decimalPlaces: 0)}) '
                  'با معادل نرخ‌دار تسویه (${formatWithThousands(expected, decimalPlaces: 0)}) '
                  'بیش از ۲۵٪ اختلاف دارد.\n'
                  'آیا عمداً همین مبلغ را ثبت می‌کنید؟',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('انصراف'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('ثبت با همین مبلغ'),
                  ),
                ],
              ),
            );
            if (cont != true) return;
            if (!mounted) return;
            allowLargeFxDiff = true;
          }
        }
      } else if (amount <= 0) {
        // بدون نرخ یا ارز حساب نامشخص: حداقل settles را به‌عنوان amount بفرست تا بک‌اند تبدیل کند
        amount = settlesAmount.toDouble();
      }
      if (amount <= 0) {
        SnackBarHelper.showError(context, message: 'مبلغ پرداخت نامعتبر است');
        return;
      }
    }
    
    final transaction = InvoiceTransaction(
      id: widget.transaction?.id ?? _uuid.v4(),
      type: _selectedType,
      bankId: _selectedBankId,
      bankName: _getBankName(_selectedBankId),
      cashRegisterId: _selectedCashRegisterId,
      cashRegisterName: _getCashRegisterName(_selectedCashRegisterId),
      pettyCashId: _selectedPettyCashId,
      pettyCashName: _getPettyCashName(_selectedPettyCashId),
      checkId: _selectedCheckId,
      checkNumber: _selectedCheckNumber,
      personId: _selectedPersonId,
      personName: _getPersonName(_selectedPersonId),
      accountId: _selectedAccount?.id.toString(),
      accountName: _selectedAccount?.name,
      transactionDate: _transactionDate,
      amount: amount,
      commission: commission,
      description: _descriptionController.text.trim().isEmpty 
          ? null 
          : _descriptionController.text.trim(),
      settlesAmount: settlesAmount,
      fxRate: fxRate,
      paymentCurrencyId: isCross ? payCur : null,
      allowLargeFxDiff: allowLargeFxDiff,
    );
    
    widget.onSave(transaction);
    await InvoiceTransactionPreferences.setLastUsedTransactionType(
      widget.businessId,
      _selectedType,
    );
    if (mounted) Navigator.pop(context);
  }

  String? _getBankName(String? id) {
    if (id == null) return null;
    final bank = _banks.firstWhere(
      (b) => b['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    return bank['name']?.toString();
  }

  String? _getCashRegisterName(String? id) {
    if (id == null) return null;
    final cashRegister = _cashRegisters.firstWhere(
      (c) => c['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    return cashRegister['name']?.toString();
  }

  String? _getPettyCashName(String? id) {
    if (id == null) return null;
    final pettyCash = _pettyCashList.firstWhere(
      (p) => p['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    return pettyCash['name']?.toString();
  }

  String? _getPersonName(String? id) {
    if (id == null) return null;
    final person = _persons.firstWhere(
      (p) => p['id']?.toString() == id,
      orElse: () => <String, dynamic>{},
    );
    return person['alias_name']?.toString() ?? person['name']?.toString();
  }

}

/// فیلد مبلغ/کارمزد با State جدا تا بازسازی فرم دیالوگ فوکوس را نگیرد.
class _TransactionDialogMoneyField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String currencyUnit;
  final bool isRequired;

  const _TransactionDialogMoneyField({
    super.key,
    required this.controller,
    required this.label,
    required this.currencyUnit,
    this.isRequired = true,
  });

  @override
  State<_TransactionDialogMoneyField> createState() =>
      _TransactionDialogMoneyFieldState();
}

class _TransactionDialogMoneyFieldState extends State<_TransactionDialogMoneyField> {
  @override
  Widget build(BuildContext context) {
    return AmountFieldWordsTooltip(
      controller: widget.controller,
      currencyUnit: widget.currencyUnit,
      child: TextFormField(
        controller: widget.controller,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          suffixText: widget.currencyUnit,
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [
          EnglishDigitsFormatter(),
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ThousandsSeparatorInputFormatter(allowDecimal: false),
        ],
        validator: widget.isRequired
            ? (value) {
                if (value == null || value.isEmpty) {
                  return 'مبلغ الزامی است';
                }
                final cleanValue = value.replaceAll(',', '');
                if (double.tryParse(cleanValue) == null) {
                  return 'مبلغ باید عدد باشد';
                }
                return null;
              }
            : null,
      ),
    );
  }
}
