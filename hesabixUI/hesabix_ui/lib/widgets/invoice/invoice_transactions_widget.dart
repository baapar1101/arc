import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/invoice_transaction.dart';
import '../../core/date_utils.dart';
import '../../core/calendar_controller.dart';
import '../../utils/number_formatters.dart';

class InvoiceTransactionsWidget extends StatefulWidget {
  final List<InvoiceTransaction> transactions;
  final ValueChanged<List<InvoiceTransaction>> onChanged;
  final int businessId;
  final CalendarController calendarController;

  const InvoiceTransactionsWidget({
    super.key,
    required this.transactions,
    required this.onChanged,
    required this.businessId,
    required this.calendarController,
  });

  @override
  State<InvoiceTransactionsWidget> createState() => _InvoiceTransactionsWidgetState();
}

class _InvoiceTransactionsWidgetState extends State<InvoiceTransactionsWidget> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
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
              'تراکنش‌های فاکتور',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _addTransaction,
              icon: const Icon(Icons.add),
              label: const Text('افزودن تراکنش'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // لیست تراکنش‌ها
        if (widget.transactions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
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
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'برای افزودن تراکنش روی دکمه "افزودن تراکنش" کلیک کنید',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.transactions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final transaction = widget.transactions[index];
              return _buildTransactionCard(transaction, index);
            },
          ),
      ],
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
        
        // تاریخ و مبلغ
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
}

class TransactionDialog extends StatefulWidget {
  final InvoiceTransaction? transaction;
  final int businessId;
  final CalendarController calendarController;
  final ValueChanged<InvoiceTransaction> onSave;

  const TransactionDialog({
    super.key,
    this.transaction,
    required this.businessId,
    required this.calendarController,
    required this.onSave,
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
  
  // فیلدهای خاص هر نوع تراکنش
  String? _selectedBankId;
  String? _selectedCashRegisterId;
  String? _selectedPettyCashId;
  String? _selectedCheckId;
  String? _selectedPersonId;
  String? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.transaction?.type ?? TransactionType.person;
    _transactionDate = widget.transaction?.transactionDate ?? DateTime.now();
    _amountController.text = widget.transaction?.amount.toString() ?? '';
    _commissionController.text = widget.transaction?.commission?.toString() ?? '';
    _descriptionController.text = widget.transaction?.description ?? '';
    
    // تنظیم فیلدهای خاص
    _selectedBankId = widget.transaction?.bankId;
    _selectedCashRegisterId = widget.transaction?.cashRegisterId;
    _selectedPettyCashId = widget.transaction?.pettyCashId;
    _selectedCheckId = widget.transaction?.checkId;
    _selectedPersonId = widget.transaction?.personId;
    _selectedAccountId = widget.transaction?.accountId;
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
                        items: TransactionType.allTypes.map((type) {
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
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'مبلغ الزامی است';
                                }
                                if (double.tryParse(value) == null) {
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

  Widget _buildBankFields() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedBankId,
      decoration: const InputDecoration(
        labelText: 'بانک *',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'bank1', child: Text('بانک ملی')),
        DropdownMenuItem(value: 'bank2', child: Text('بانک صادرات')),
        DropdownMenuItem(value: 'bank3', child: Text('بانک ملت')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedBankId = value;
        });
      },
    );
  }

  Widget _buildCashRegisterFields() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCashRegisterId,
      decoration: const InputDecoration(
        labelText: 'صندوق *',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'cash1', child: Text('صندوق اصلی')),
        DropdownMenuItem(value: 'cash2', child: Text('صندوق فرعی')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedCashRegisterId = value;
        });
      },
    );
  }

  Widget _buildPettyCashFields() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedPettyCashId,
      decoration: const InputDecoration(
        labelText: 'تنخواهگردان *',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'petty1', child: Text('تنخواهگردان اصلی')),
        DropdownMenuItem(value: 'petty2', child: Text('تنخواهگردان فرعی')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedPettyCashId = value;
        });
      },
    );
  }

  Widget _buildCheckFields() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCheckId,
      decoration: const InputDecoration(
        labelText: 'چک *',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'check1', child: Text('چک شماره 123456')),
        DropdownMenuItem(value: 'check2', child: Text('چک شماره 789012')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedCheckId = value;
        });
      },
    );
  }

  Widget _buildCheckExpenseFields() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCheckId,
      decoration: const InputDecoration(
        labelText: 'خرج چک *',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'expense1', child: Text('خرج چک شماره 123456')),
        DropdownMenuItem(value: 'expense2', child: Text('خرج چک شماره 789012')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedCheckId = value;
        });
      },
    );
  }

  Widget _buildPersonFields() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedPersonId,
      decoration: const InputDecoration(
        labelText: 'شخص *',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'person1', child: Text('احمد محمدی')),
        DropdownMenuItem(value: 'person2', child: Text('فاطمه احمدی')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedPersonId = value;
        });
      },
    );
  }

  Widget _buildAccountFields() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedAccountId,
      decoration: const InputDecoration(
        labelText: 'حساب *',
        border: OutlineInputBorder(),
      ),
      items: const [
        DropdownMenuItem(value: 'account1', child: Text('حساب جاری')),
        DropdownMenuItem(value: 'account2', child: Text('حساب پس‌انداز')),
      ],
      onChanged: (value) {
        setState(() {
          _selectedAccountId = value;
        });
      },
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
    
    final amount = double.parse(_amountController.text);
    final commission = _commissionController.text.isNotEmpty 
        ? double.parse(_commissionController.text) 
        : null;
    
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
      checkNumber: _getCheckNumber(_selectedCheckId),
      personId: _selectedPersonId,
      personName: _getPersonName(_selectedPersonId),
      accountId: _selectedAccountId,
      accountName: _getAccountName(_selectedAccountId),
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
    switch (id) {
      case 'bank1': return 'بانک ملی';
      case 'bank2': return 'بانک صادرات';
      case 'bank3': return 'بانک ملت';
      default: return null;
    }
  }

  String? _getCashRegisterName(String? id) {
    switch (id) {
      case 'cash1': return 'صندوق اصلی';
      case 'cash2': return 'صندوق فرعی';
      default: return null;
    }
  }

  String? _getPettyCashName(String? id) {
    switch (id) {
      case 'petty1': return 'تنخواهگردان اصلی';
      case 'petty2': return 'تنخواهگردان فرعی';
      default: return null;
    }
  }

  String? _getCheckNumber(String? id) {
    switch (id) {
      case 'check1': return '123456';
      case 'check2': return '789012';
      default: return null;
    }
  }

  String? _getPersonName(String? id) {
    switch (id) {
      case 'person1': return 'احمد محمدی';
      case 'person2': return 'فاطمه احمدی';
      default: return null;
    }
  }

  String? _getAccountName(String? id) {
    switch (id) {
      case 'account1': return 'حساب جاری';
      case 'account2': return 'حساب پس‌انداز';
      default: return null;
    }
  }
}
