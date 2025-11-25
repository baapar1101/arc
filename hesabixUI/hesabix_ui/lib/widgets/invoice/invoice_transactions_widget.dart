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
import 'person_combobox_widget.dart';
import 'bank_account_combobox_widget.dart';
import 'cash_register_combobox_widget.dart';
import 'petty_cash_combobox_widget.dart';
import 'account_tree_combobox_widget.dart';
import 'check_combobox_widget.dart';
import '../../models/invoice_type_model.dart';
import '../../utils/number_normalizer.dart';
import '../../core/api_client.dart';

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
  });

  @override
  State<InvoiceTransactionsWidget> createState() => _InvoiceTransactionsWidgetState();
}

class _InvoiceTransactionsWidgetState extends State<InvoiceTransactionsWidget> {
  final CurrencyService _currencyService = CurrencyService(ApiClient());
  String? _currencySymbol;
  
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
    if (widget.selectedCurrencyId == null) {
      setState(() {
        _currencySymbol = null;
      });
      return;
    }
    
    try {
      final currencies = await _currencyService.listBusinessCurrencies(
        businessId: widget.businessId,
      );
      final currency = currencies.firstWhere(
        (c) => (c['id'] as num?)?.toInt() == widget.selectedCurrencyId,
        orElse: () => <String, dynamic>{},
      );
      
      setState(() {
        _currencySymbol = currency['symbol']?.toString() ?? currency['code']?.toString() ?? 'ریال';
      });
    } catch (e) {
      setState(() {
        _currencySymbol = 'ریال'; // fallback
      });
    }
  }
  
  // محاسبه مجموع تراکنش‌ها (بدون کارمزد)
  num get _totalPaid {
    return widget.transactions.fold<num>(0, (sum, t) => sum + t.amount);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = _isDesktop(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // هدر
        Row(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: theme.colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'تراکنش‌ها',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            // در موبایل فقط آیکون نمایش داده می‌شود
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
                  backgroundColor: _canAddTransaction 
                      ? theme.colorScheme.primary 
                      : theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: _canAddTransaction 
                      ? theme.colorScheme.onPrimary 
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        
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
  Widget _buildMobileLayout(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // نمایش مانده فاکتور یا پیام عدم وجود ردیف کالا
        if (widget.invoiceTotal != null && widget.invoiceTotal! > 0) ...[
          _buildBalanceCard(theme),
          const SizedBox(height: 16),
        ] else if (widget.invoiceTotal != null && widget.invoiceTotal! == 0) ...[
          _buildNoItemsMessage(theme),
          const SizedBox(height: 16),
        ],
        
        // لیست تراکنش‌ها
        Expanded(
          child: widget.transactions.isEmpty
              ? _buildEmptyState(theme)
              : ListView.separated(
                  itemCount: widget.transactions.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final transaction = widget.transactions[index];
                    return _buildTransactionCard(transaction, index);
                  },
                ),
        ),
      ],
    );
  }
  
  // چیدمان دسکتاپ: دو ستون
  Widget _buildDesktopLayout(ThemeData theme) {
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
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
              const SizedBox(height: 12),
              // لیست تراکنش‌ها
              Expanded(
                child: widget.transactions.isEmpty
                    ? _buildEmptyState(theme)
                    : ListView.separated(
                        itemCount: widget.transactions.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final transaction = widget.transactions[index];
                          return _buildTransactionCard(transaction, index);
                        },
                      ),
              ),
            ],
          ),
        ),
        
        const SizedBox(width: 16),
        
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
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
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
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
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // هدر تراکنش
            Row(
              children: [
                Icon(
                  _getTransactionIcon(transaction.type),
                  color: theme.colorScheme.primary,
                  size: 20,
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
                ),
                IconButton(
                  onPressed: () => _removeTransaction(index),
                  icon: const Icon(Icons.delete),
                  tooltip: 'حذف',
                  color: theme.colorScheme.error,
                ),
              ],
            ),
            const SizedBox(height: 12),
            
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
                'مبلغ:',
                formatWithThousands(transaction.amount, decimalPlaces: 0),
              ),
            ),
            if (transaction.commission != null)
              Expanded(
                child: _buildDetailRow(
                  'کارمزد:',
                  formatWithThousands(transaction.commission!, decimalPlaces: 0),
                ),
              ),
          ],
        ),
        
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

  void _showTransactionDialog({InvoiceTransaction? transaction, int? index}) {
    showDialog(
      context: context,
      builder: (context) => TransactionDialog(
        transaction: transaction,
        businessId: widget.businessId,
        calendarController: widget.calendarController,
        invoiceType: widget.invoiceType,
        selectedCurrencyId: widget.selectedCurrencyId,
        checkPickerMode: widget.checkPickerMode,
        authStore: widget.authStore,
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
            // در دسکتاپ: نمایش عمودی (یک ستون)
            // در موبایل: نمایش دو ستونه
            if (isDesktop) ...[
              _buildBalanceRow(
                theme,
                'مبلغ کل فاکتور:',
                formatWithThousands(widget.invoiceTotal!, decimalPlaces: 0),
                theme.colorScheme.onSurface,
                isDesktop: true,
              ),
              const SizedBox(height: 16),
              _buildBalanceRow(
                theme,
                'مجموع تراکنش‌ها:',
                formatWithThousands(_totalPaid, decimalPlaces: 0),
                theme.colorScheme.onSurface,
                isDesktop: true,
              ),
              const SizedBox(height: 16),
              Divider(color: theme.colorScheme.outline.withOpacity(0.2)),
              const SizedBox(height: 16),
              _buildBalanceRow(
                theme,
                'مانده فاکتور:',
                formatWithThousands(_remainingBalance, decimalPlaces: 0),
                remainingColor,
                isBold: true,
                isDesktop: true,
              ),
              const SizedBox(height: 12),
              _buildBalanceRow(
                theme,
                'درصد مانده:',
                '${_remainingPercentage.toStringAsFixed(1)}%',
                remainingColor,
                isBold: true,
                isDesktop: true,
                showCurrency: false,
              ),
              const SizedBox(height: 12),
              _buildBalanceRow(
                theme,
                'درصد پرداخت شده:',
                '${_paidPercentage.toStringAsFixed(1)}%',
                theme.colorScheme.onSurface,
                isDesktop: true,
                showCurrency: false,
              ),
            ] else ...[
              // موبایل: دو ستونه
              Row(
                children: [
                  Expanded(
                    child: _buildBalanceRow(
                      theme,
                      'مبلغ کل فاکتور:',
                      formatWithThousands(widget.invoiceTotal!, decimalPlaces: 0),
                      theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildBalanceRow(
                      theme,
                      'مجموع تراکنش‌ها:',
                      formatWithThousands(_totalPaid, decimalPlaces: 0),
                      theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildBalanceRow(
                      theme,
                      'مانده فاکتور:',
                      formatWithThousands(_remainingBalance, decimalPlaces: 0),
                      remainingColor,
                      isBold: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildBalanceRow(
                      theme,
                      'درصد مانده:',
                      '${_remainingPercentage.toStringAsFixed(1)}%',
                      remainingColor,
                      isBold: true,
                      showCurrency: false,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildBalanceRow(
                theme,
                'درصد پرداخت شده:',
                '${_paidPercentage.toStringAsFixed(1)}%',
                theme.colorScheme.onSurface,
                showCurrency: false,
              ),
            ],
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
          width: isDesktop ? 150 : 120,
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
            textAlign: TextAlign.left,
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
  final int businessId;
  final CalendarController calendarController;
  final ValueChanged<InvoiceTransaction> onSave;
  final InvoiceType invoiceType;
  final int? selectedCurrencyId;
  final CheckPickerMode checkPickerMode;
  final AuthStore? authStore;

  const TransactionDialog({
    super.key,
    this.transaction,
    required this.businessId,
    required this.calendarController,
    required this.invoiceType,
    this.selectedCurrencyId,
    required this.onSave,
    this.checkPickerMode = CheckPickerMode.any,
    this.authStore,
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
  
  // سرویس‌ها
  final BankAccountService _bankService = BankAccountService();
  final CashRegisterService _cashRegisterService = CashRegisterService();
  final PettyCashService _pettyCashService = PettyCashService();
  final PersonService _personService = PersonService();
  final AccountService _accountService = AccountService();
  
  // فیلدهای خاص هر نوع تراکنش
  String? _selectedBankId;
  String? _selectedCashRegisterId;
  String? _selectedPettyCashId;
  String? _selectedCheckId;
  int? _selectedCheckCurrencyId;
  String? _selectedCheckNumber;
  String? _selectedPersonId;
  AccountTreeNode? _selectedAccount;
  
  // لیست‌های داده
  List<Map<String, dynamic>> _banks = [];
  List<Map<String, dynamic>> _cashRegisters = [];
  List<Map<String, dynamic>> _pettyCashList = [];
  List<Map<String, dynamic>> _persons = [];
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.transaction?.type ?? TransactionType.person;
    _transactionDate = widget.transaction?.transactionDate ?? DateTime.now();
    _amountController.text = widget.transaction?.amount != null 
        ? formatWithThousands(widget.transaction!.amount, decimalPlaces: 0)
        : '';
    _commissionController.text = widget.transaction?.commission != null
        ? formatWithThousands(widget.transaction!.commission!, decimalPlaces: 0)
        : '';
    _descriptionController.text = widget.transaction?.description ?? '';
    
    // تنظیم فیلدهای خاص
    _selectedBankId = widget.transaction?.bankId;
    _selectedCashRegisterId = widget.transaction?.cashRegisterId;
    _selectedPettyCashId = widget.transaction?.pettyCashId;
    _selectedCheckId = widget.transaction?.checkId;
    _selectedCheckNumber = widget.transaction?.checkNumber;
    _selectedPersonId = widget.transaction?.personId;
    
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
    setState(() {
      _isLoading = true;
    });
    
    try {
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
      
    } catch (e) {
      // در صورت خطا، لیست‌ها خالی باقی می‌مانند
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commissionController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 600),
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
                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else
                        _buildTypeSpecificFields(),
                      const SizedBox(height: 16),
                      
                      // تاریخ تراکنش
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'تاریخ تراکنش *',
                                border: const OutlineInputBorder(),
                                suffixIcon: const Icon(Icons.calendar_today),
                              ),
                              onTap: () => _selectDate(),
                              controller: TextEditingController(
                                text: HesabixDateUtils.formatForDisplay(
                                  _transactionDate,
                                  widget.calendarController.isJalali == true,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // مبلغ و کارمزد
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _amountController,
                              decoration: const InputDecoration(
                                labelText: 'مبلغ *',
                                border: OutlineInputBorder(),
                                suffixText: 'ریال',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                EnglishDigitsFormatter(),
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'مبلغ الزامی است';
                                }
                                final cleanValue = value.replaceAll(',', '');
                                if (double.tryParse(cleanValue) == null) {
                                  return 'مبلغ باید عدد باشد';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _commissionController,
                              decoration: const InputDecoration(
                                labelText: 'کارمزد',
                                border: OutlineInputBorder(),
                                suffixText: 'ریال',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                EnglishDigitsFormatter(),
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                                ThousandsSeparatorInputFormatter(allowDecimal: false),
                              ],
                            ),
                          ),
                        ],
                      ),
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
      filterCurrencyId: widget.selectedCurrencyId,
      onChanged: (opt) {
        setState(() {
          _selectedBankId = opt?.id;
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
      filterCurrencyId: widget.selectedCurrencyId,
      onChanged: (opt) {
        setState(() {
          _selectedCashRegisterId = opt?.id;
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
      filterCurrencyId: widget.selectedCurrencyId,
      onChanged: (opt) {
        setState(() {
          _selectedPettyCashId = opt?.id;
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
      filterCurrencyId: widget.selectedCurrencyId,
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

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    
    if (date != null) {
      setState(() {
        _transactionDate = date;
      });
    }
  }

  void _saveTransaction() {
    if (!_formKey.currentState!.validate()) return;
    
    final amount = double.parse(_amountController.text.replaceAll(',', ''));
    final commission = _commissionController.text.isNotEmpty 
        ? double.parse(_commissionController.text.replaceAll(',', '')) 
        : null;
    // اعتبارسنجی هم‌خوانی ارز با ارز فاکتور برای انواع دارای ارز
    final invoiceCurrencyId = widget.selectedCurrencyId;
    if (invoiceCurrencyId != null) {
      if (_selectedType == TransactionType.bank && _selectedBankId != null) {
        final bank = _banks.firstWhere(
          (b) => b['id']?.toString() == _selectedBankId,
          orElse: () => <String, dynamic>{},
        );
        final bankCurrencyId = int.tryParse('${bank['currency_id'] ?? bank['currencyId'] ?? ''}');
        if (bankCurrencyId != null && bankCurrencyId != invoiceCurrencyId) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ارز بانک انتخابی با ارز فاکتور هم‌خوانی ندارد')),
          );
          return;
        }
      }
      if (_selectedType == TransactionType.cashRegister && _selectedCashRegisterId != null) {
        final cr = _cashRegisters.firstWhere(
          (c) => c['id']?.toString() == _selectedCashRegisterId,
          orElse: () => <String, dynamic>{},
        );
        final crCurrencyId = int.tryParse('${cr['currency_id'] ?? cr['currencyId'] ?? ''}');
        if (crCurrencyId != null && crCurrencyId != invoiceCurrencyId) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ارز صندوق انتخابی با ارز فاکتور هم‌خوانی ندارد')),
          );
          return;
        }
      }
      if (_selectedType == TransactionType.pettyCash && _selectedPettyCashId != null) {
        final pc = _pettyCashList.firstWhere(
          (p) => p['id']?.toString() == _selectedPettyCashId,
          orElse: () => <String, dynamic>{},
        );
        final pcCurrencyId = int.tryParse('${pc['currency_id'] ?? pc['currencyId'] ?? ''}');
        if (pcCurrencyId != null && pcCurrencyId != invoiceCurrencyId) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ارز تنخواه‌گردان انتخابی با ارز فاکتور هم‌خوانی ندارد')),
          );
          return;
        }
      }
      if (_selectedType == TransactionType.check && _selectedCheckId != null) {
        final chkCurrencyId = _selectedCheckCurrencyId;
        if (chkCurrencyId != null && chkCurrencyId != invoiceCurrencyId) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ارز چک انتخابی با ارز فاکتور هم‌خوانی ندارد')),
          );
          return;
        }
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
    );
    
    widget.onSave(transaction);
    Navigator.pop(context);
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
