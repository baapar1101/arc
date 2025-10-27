import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/widgets/document/detail_selector_widget.dart';
import 'package:hesabix_ui/widgets/invoice/account_tree_combobox_widget.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';

/// مدل داخلی برای نگهداری اطلاعات یک سطر سند در حین ویرایش
class DocumentLineEdit {
  Account? account;
  Map<String, dynamic>? detail; // person_id, product_id, etc.
  double debit;
  double credit;
  String? description;
  double? quantity;

  DocumentLineEdit({
    this.account,
    this.detail,
    this.debit = 0,
    this.credit = 0,
    this.description,
    this.quantity,
  });

  /// تبدیل به DocumentLineCreateRequest
  DocumentLineCreateRequest toRequest() {
    if (account == null) {
      throw Exception('حساب نباید خالی باشد');
    }
    return DocumentLineCreateRequest(
      accountId: account!.id!,
      personId: detail?['person_id'],
      productId: detail?['product_id'],
      bankAccountId: detail?['bank_account_id'],
      cashRegisterId: detail?['cash_register_id'],
      pettyCashId: detail?['petty_cash_id'],
      checkId: detail?['check_id'],
      quantity: quantity,
      debit: debit,
      credit: credit,
      description: description,
    );
  }

  /// کپی
  DocumentLineEdit copy() {
    return DocumentLineEdit(
      account: account,
      detail: detail != null ? Map.from(detail!) : null,
      debit: debit,
      credit: credit,
      description: description,
      quantity: quantity,
    );
  }
}

/// ویجت ویرایشگر سطرهای سند
class DocumentLinesEditor extends StatefulWidget {
  final int businessId;
  final List<DocumentLineEdit> initialLines;
  final ValueChanged<List<DocumentLineEdit>> onChanged;

  const DocumentLinesEditor({
    super.key,
    required this.businessId,
    required this.initialLines,
    required this.onChanged,
  });

  @override
  State<DocumentLinesEditor> createState() => _DocumentLinesEditorState();
}

class _DocumentLinesEditorState extends State<DocumentLinesEditor> {
  late List<DocumentLineEdit> _lines;

  @override
  void initState() {
    super.initState();
    _lines = widget.initialLines.map((line) => line.copy()).toList();
    if (_lines.isEmpty) {
      _addNewLine();
      _addNewLine();
    }
  }

  void _addNewLine() {
    setState(() {
      _lines.add(DocumentLineEdit());
    });
    _notifyChanged();
  }

  void _removeLine(int index) {
    if (_lines.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سند باید حداقل 2 سطر داشته باشد')),
      );
      return;
    }

    setState(() {
      _lines.removeAt(index);
    });
    _notifyChanged();
  }

  void _notifyChanged() {
    widget.onChanged(_lines);
  }

  /// محاسبه جمع بدهکار
  double get _totalDebit {
    return _lines.fold(0.0, (sum, line) => sum + line.debit);
  }

  /// محاسبه جمع بستانکار
  double get _totalCredit {
    return _lines.fold(0.0, (sum, line) => sum + line.credit);
  }

  /// محاسبه مانده (تفاوت)
  double get _balance {
    return _totalDebit - _totalCredit;
  }

  /// آیا سند متوازن است؟
  bool get _isBalanced {
    return _balance.abs() < 0.01;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // هدر
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'سطرهای سند',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _addNewLine,
              icon: const Icon(Icons.add),
              label: const Text('افزودن سطر'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // جدول سطرها
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              // هدر جدول
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        '#',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'حساب',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'تفضیل',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: Text(
                        'بدهکار',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: Text(
                        'بستانکار',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'توضیحات',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      child: Text(
                        'عملیات',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

              // سطرهای جدول
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _lines.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: theme.dividerColor,
                ),
                itemBuilder: (context, index) {
                  return _buildLineRow(index);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // خلاصه و جمع
        _buildSummary(theme),
      ],
    );
  }

  /// ساخت یک سطر از جدول
  Widget _buildLineRow(int index) {
    final line = _lines[index];
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شماره ردیف
          SizedBox(
            width: 40,
            child: Center(
              child: CircleAvatar(
                radius: 14,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),

          // حساب
          Expanded(
            flex: 3,
            child: AccountTreeComboboxWidget(
              businessId: widget.businessId,
              selectedAccount: line.account,
              onChanged: (account) {
                setState(() {
                  line.account = account;
                  // ریست کردن تفضیل وقتی حساب عوض می‌شود
                  line.detail = null;
                });
                _notifyChanged();
              },
              label: '',
              hintText: 'انتخاب حساب',
              isRequired: true,
            ),
          ),
          const SizedBox(width: 8),

          // تفضیل
          Expanded(
            flex: 2,
            child: DetailSelectorWidget(
              businessId: widget.businessId,
              selectedAccount: line.account,
              detailType: _getAccountDetailType(line.account),
              selectedDetailId: line.detail?['person_id'] ??
                  line.detail?['product_id'] ??
                  line.detail?['bank_account_id'],
              onChanged: (detail) {
                setState(() {
                  line.detail = detail;
                });
                _notifyChanged();
              },
              label: '',
            ),
          ),
          const SizedBox(width: 8),

          // بدهکار
          SizedBox(
            width: 120,
            child: TextFormField(
              initialValue: line.debit > 0 ? line.debit.toString() : '',
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.left,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              onChanged: (value) {
                line.debit = double.tryParse(value) ?? 0;
                // اگر بدهکار وارد شد، بستانکار را صفر کن
                if (line.debit > 0) {
                  line.credit = 0;
                }
                setState(() {});
                _notifyChanged();
              },
            ),
          ),
          const SizedBox(width: 8),

          // بستانکار
          SizedBox(
            width: 120,
            child: TextFormField(
              initialValue: line.credit > 0 ? line.credit.toString() : '',
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.left,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              onChanged: (value) {
                line.credit = double.tryParse(value) ?? 0;
                // اگر بستانکار وارد شد، بدهکار را صفر کن
                if (line.credit > 0) {
                  line.debit = 0;
                }
                setState(() {});
                _notifyChanged();
              },
            ),
          ),
          const SizedBox(width: 8),

          // توضیحات
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: line.description,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'توضیحات',
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                isDense: true,
              ),
              maxLines: 1,
              onChanged: (value) {
                line.description = value.isEmpty ? null : value;
                _notifyChanged();
              },
            ),
          ),
          const SizedBox(width: 8),

          // دکمه حذف
          SizedBox(
            width: 48,
            child: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'حذف سطر',
              onPressed: () => _removeLine(index),
            ),
          ),
        ],
      ),
    );
  }

  /// ساخت بخش خلاصه
  Widget _buildSummary(ThemeData theme) {
    return Card(
      elevation: 2,
      color: _isBalanced
          ? theme.colorScheme.primaryContainer.withOpacity(0.3)
          : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // جمع بدهکار
            Column(
              children: [
                const Text(
                  'جمع بدهکار',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatWithThousands(_totalDebit.toInt()),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.red,
                    fontFamily: 'monospace',
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),

            Container(
              width: 2,
              height: 40,
              color: theme.dividerColor,
            ),

            // جمع بستانکار
            Column(
              children: [
                const Text(
                  'جمع بستانکار',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatWithThousands(_totalCredit.toInt()),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.green,
                    fontFamily: 'monospace',
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),

            Container(
              width: 2,
              height: 40,
              color: theme.dividerColor,
            ),

            // مانده
            Column(
              children: [
                const Text(
                  'مانده',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      formatWithThousands(_balance.abs().toInt()),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: _isBalanced ? Colors.green : Colors.orange,
                        fontFamily: 'monospace',
                      ),
                      textDirection: TextDirection.ltr,
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      _isBalanced ? Icons.check_circle : Icons.warning,
                      color: _isBalanced ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),

            // وضعیت
            if (!_isBalanced)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '⚠️ سند متوازن نیست',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '✓ سند متوازن است',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// تشخیص نوع تفضیل بر اساس حساب
  /// TODO: باید از API یا از metadata حساب بیاید
  String? _getAccountDetailType(Account? account) {
    if (account == null) return null;

    // این یک پیاده‌سازی ساده است
    // در واقع باید از account.detailType یا API استفاده شود
    final accountName = account.name.toLowerCase();

    if (accountName.contains('دریافتنی') ||
        accountName.contains('پرداختنی') ||
        accountName.contains('مشتری') ||
        accountName.contains('تامین')) {
      return 'person';
    }

    if (accountName.contains('موجودی') ||
        accountName.contains('کالا') ||
        accountName.contains('انبار')) {
      return 'product';
    }

    if (accountName.contains('بانک')) {
      return 'bank_account';
    }

    if (accountName.contains('صندوق')) {
      return 'cash_register';
    }

    if (accountName.contains('تنخواه')) {
      return 'petty_cash';
    }

    if (accountName.contains('چک')) {
      return 'check';
    }

    return null; // حساب نیاز به تفضیل ندارد
  }
}

