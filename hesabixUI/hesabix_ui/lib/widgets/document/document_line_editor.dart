import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/models/account_model.dart';
import 'package:hesabix_ui/models/document_model.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/widgets/document/detail_selector_widget.dart';
import 'package:hesabix_ui/constants/frequent_description_scope.dart';
import 'package:hesabix_ui/widgets/inputs/frequent_description_text_field.dart';
import 'package:hesabix_ui/widgets/invoice/account_tree_combobox_widget.dart';
import '../../utils/snackbar_helper.dart';

int _documentLineUidSeq = 0;
String _newDocumentLineUid() => '${DateTime.now().microsecondsSinceEpoch}_${_documentLineUidSeq++}';

/// مدل داخلی برای نگهداری اطلاعات یک سطر سند در حین ویرایش
class DocumentLineEdit {
  final String uid;
  Account? account;
  Map<String, dynamic>? detail; // person_id, product_id, etc.
  double debit;
  double credit;
  String? description;
  double? quantity;

  DocumentLineEdit({
    String? uid,
    this.account,
    this.detail,
    this.debit = 0,
    this.credit = 0,
    this.description,
    this.quantity,
  }) : uid = uid ?? _newDocumentLineUid();

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
      uid: uid,
      account: account,
      detail: detail != null ? Map.from(detail!) : null,
      debit: debit,
      credit: credit,
      description: description,
      quantity: quantity,
    );
  }
}

class _LineControllers {
  final TextEditingController quantityCtrl;
  final TextEditingController debitCtrl;
  final TextEditingController creditCtrl;
  final TextEditingController descCtrl;
  _LineControllers({
    required this.quantityCtrl,
    required this.debitCtrl,
    required this.creditCtrl,
    required this.descCtrl,
  });

  void dispose() {
    quantityCtrl.dispose();
    debitCtrl.dispose();
    creditCtrl.dispose();
    descCtrl.dispose();
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
  final Map<String, _LineControllers> _controllers = {};

  @override
  void initState() {
    super.initState();
    _lines = widget.initialLines.map((line) => line.copy()).toList();
    if (_lines.isEmpty) {
      _addNewLine();
      _addNewLine();
    }
    _syncControllers();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  void _syncControllers() {
    // Create missing controllers
    for (final line in _lines) {
      _controllers.putIfAbsent(line.uid, () {
        return _LineControllers(
          quantityCtrl: TextEditingController(text: _fmt(line.quantity)),
          debitCtrl: TextEditingController(text: _fmt(line.debit == 0 ? null : line.debit)),
          creditCtrl: TextEditingController(text: _fmt(line.credit == 0 ? null : line.credit)),
          descCtrl: TextEditingController(text: line.description ?? ''),
        );
      });
      // Keep description in sync if it was null
      final c = _controllers[line.uid]!;
      if ((line.description ?? '') != c.descCtrl.text) {
        // only update when line has explicit value (avoid fighting with user typing)
        if ((line.description ?? '').isEmpty && c.descCtrl.text.isNotEmpty) {
          // keep controller
        }
      }
    }
    // Dispose removed controllers
    final alive = _lines.map((e) => e.uid).toSet();
    final toRemove = _controllers.keys.where((k) => !alive.contains(k)).toList();
    for (final k in toRemove) {
      _controllers.remove(k)?.dispose();
    }
  }

  String _fmt(double? v) {
    if (v == null || v == 0) return '';
    return formatNumberForInput(v);
  }

  void _addNewLine() {
    setState(() {
      _lines.add(DocumentLineEdit());
      _syncControllers();
    });
    _notifyChanged();
  }

  void _removeLine(int index) {
    if (_lines.length <= 2) {
      SnackBarHelper.show(context, message: 'سند باید حداقل 2 سطر داشته باشد');
      return;
    }

    setState(() {
      final removed = _lines.removeAt(index);
      _controllers.remove(removed.uid)?.dispose();
    });
    _notifyChanged();
  }

  void _notifyChanged() {
    _syncControllers();
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // هدر
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'سطرهای سند',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                FilledButton.icon(
                  onPressed: _addNewLine,
                  icon: const Icon(Icons.add),
                  label: const Text('افزودن سطر'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (isCompact)
              _buildMobileCards(theme)
            else
              _buildDesktopTable(theme),

            const SizedBox(height: 16),
            _buildSummary(theme),
          ],
        );
      },
    );
  }

  Widget _buildDesktopTable(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text('#', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
                Expanded(flex: 3, child: Text('حساب', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: Text('تفضیل', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                SizedBox(width: 100, child: Text('تعداد', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                const SizedBox(width: 8),
                SizedBox(width: 120, child: Text('بدهکار', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                const SizedBox(width: 8),
                SizedBox(width: 120, child: Text('بستانکار', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: Text('توضیحات', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                SizedBox(width: 48, child: Text('عملیات', style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _lines.length,
            separatorBuilder: (context, index) => Divider(height: 1, color: theme.dividerColor),
            itemBuilder: (context, index) => _buildLineRow(index),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCards(ThemeData theme) {
    return Column(
      children: [
        for (int i = 0; i < _lines.length; i++) ...[
          _buildLineCard(i, theme),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildLineCard(int index, ThemeData theme) {
    final line = _lines[index];
    final c = _controllers[line.uid]!;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('سطر ${index + 1}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  tooltip: 'حذف سطر',
                  onPressed: () => _removeLine(index),
                  icon: const Icon(Icons.delete, color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AccountTreeComboboxWidget(
              key: ValueKey('acc_${line.uid}'),
              businessId: widget.businessId,
              selectedAccount: line.account,
              onChanged: (account) {
                setState(() {
                  line.account = account;
                  line.detail = null;
                  line.quantity = null;
                  c.quantityCtrl.text = '';
                });
                _notifyChanged();
              },
              label: 'حساب',
              hintText: 'انتخاب حساب',
              isRequired: true,
            ),
            const SizedBox(height: 10),
            DetailSelectorWidget(
              key: ValueKey('det_${line.uid}'),
              businessId: widget.businessId,
              selectedAccount: line.account,
              detailType: _getAccountDetailType(line.account),
              selectedDetailId: line.detail?['person_id'] ??
                  line.detail?['product_id'] ??
                  line.detail?['bank_account_id'],
              onChanged: (detail) {
                setState(() {
                  if (detail == null || _getAccountDetailType(line.account) != 'product') {
                    line.quantity = null;
                    c.quantityCtrl.text = '';
                  }
                  line.detail = detail;
                });
                _notifyChanged();
              },
              label: 'تفضیل',
            ),
            if (_shouldShowQuantityField(line)) ...[
              const SizedBox(height: 10),
              TextFormField(
                key: ValueKey('qty_${line.uid}'),
                controller: c.quantityCtrl,
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'تعداد', hintText: '0'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.left,
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,6}')),
                ],
                onChanged: (value) {
                  final parsed = double.tryParse(value);
                  line.quantity = (parsed != null && parsed > 0) ? parsed : null;
                  _notifyChanged();
                },
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('debit_${line.uid}'),
                    controller: c.debitCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'بدهکار'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.left,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodyLarge,
                    inputFormatters: [
                      const NumberInputFormatter(allowDecimal: true),
                      FilteringTextInputFormatter.allow(RegExp(r'^(?:[\d,]*\.?\d{0,2})?$')),
                    ],
                    onChanged: (value) {
                      line.debit = parseFormattedDouble(value) ?? 0;
                      if (line.debit > 0) {
                        line.credit = 0;
                        if (c.creditCtrl.text.isNotEmpty) c.creditCtrl.text = '';
                      }
                      _notifyChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('credit_${line.uid}'),
                    controller: c.creditCtrl,
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'بستانکار'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.left,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.bodyLarge,
                    inputFormatters: [
                      const NumberInputFormatter(allowDecimal: true),
                      FilteringTextInputFormatter.allow(RegExp(r'^(?:[\d,]*\.?\d{0,2})?$')),
                    ],
                    onChanged: (value) {
                      line.credit = parseFormattedDouble(value) ?? 0;
                      if (line.credit > 0) {
                        line.debit = 0;
                        if (c.debitCtrl.text.isNotEmpty) c.debitCtrl.text = '';
                      }
                      _notifyChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FrequentDescriptionTextField(
              key: ValueKey('desc_${line.uid}'),
              businessId: widget.businessId,
              scope: FrequentDescriptionScope.documentLine,
              controller: c.descCtrl,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'توضیحات', hintText: 'اختیاری'),
              maxLines: 2,
              onChanged: (value) {
                line.description = value.trim().isEmpty ? null : value;
                _notifyChanged();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// ساخت یک سطر از جدول
  Widget _buildLineRow(int index) {
    final line = _lines[index];
    final theme = Theme.of(context);
    final c = _controllers[line.uid]!;

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
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
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
              key: ValueKey('acc_${line.uid}'),
              businessId: widget.businessId,
              selectedAccount: line.account,
              onChanged: (account) {
                setState(() {
                  line.account = account;
                  // ریست کردن تفضیل و تعداد وقتی حساب عوض می‌شود
                  line.detail = null;
                  line.quantity = null;
                  c.quantityCtrl.text = '';
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
              key: ValueKey('det_${line.uid}'),
              businessId: widget.businessId,
              selectedAccount: line.account,
              detailType: _getAccountDetailType(line.account),
              selectedDetailId: line.detail?['person_id'] ??
                  line.detail?['product_id'] ??
                  line.detail?['bank_account_id'],
              onChanged: (detail) {
                setState(() {
                  // اگر تفضیل حذف شد یا نوع حساب دیگر کالا نیست، تعداد را ریست کن
                  if (detail == null || _getAccountDetailType(line.account) != 'product') {
                    line.quantity = null;
                    c.quantityCtrl.text = '';
                  }
                  line.detail = detail;
                });
                _notifyChanged();
              },
              label: '',
            ),
          ),
          const SizedBox(width: 8),

          // تعداد کالا (فقط برای حساب‌های کالا که تفضیل انتخاب شده)
          SizedBox(
            width: 100,
            child: _shouldShowQuantityField(line)
                ? TextFormField(
                    key: ValueKey('quantity_${line.uid}'),
                    controller: c.quantityCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'تعداد',
                      hintText: '0',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.left,
                    inputFormatters: [
                      const EnglishDigitsFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,6}')),
                    ],
                    onChanged: (value) {
                      final parsedValue = double.tryParse(value);
                      line.quantity = parsedValue != null && parsedValue > 0 ? parsedValue : null;
                      setState(() {});
                      _notifyChanged();
                    },
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),

          // بدهکار
          SizedBox(
            width: 120,
            child: TextFormField(
              key: ValueKey('debit_${line.uid}'),
              controller: c.debitCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodyLarge,
              inputFormatters: [
                const NumberInputFormatter(allowDecimal: true),
                FilteringTextInputFormatter.allow(RegExp(r'^(?:[\d,]*\.?\d{0,2})?$')),
              ],
              onChanged: (value) {
                line.debit = parseFormattedDouble(value) ?? 0;
                // اگر بدهکار وارد شد، بستانکار را صفر کن
                if (line.debit > 0) {
                  line.credit = 0;
                  if (c.creditCtrl.text.isNotEmpty) c.creditCtrl.text = '';
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
              key: ValueKey('credit_${line.uid}'),
              controller: c.creditCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              style: theme.textTheme.bodyLarge,
              inputFormatters: [
                const NumberInputFormatter(allowDecimal: true),
                FilteringTextInputFormatter.allow(RegExp(r'^(?:[\d,]*\.?\d{0,2})?$')),
              ],
              onChanged: (value) {
                line.credit = parseFormattedDouble(value) ?? 0;
                // اگر بستانکار وارد شد، بدهکار را صفر کن
                if (line.credit > 0) {
                  line.debit = 0;
                  if (c.debitCtrl.text.isNotEmpty) c.debitCtrl.text = '';
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
            child: FrequentDescriptionTextField(
              key: ValueKey('desc_${line.uid}'),
              businessId: widget.businessId,
              scope: FrequentDescriptionScope.documentLine,
              controller: c.descCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'توضیحات',
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
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
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
                  formatWithThousands(_totalDebit),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
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
                  formatWithThousands(_totalCredit),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
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
                      formatWithThousands(_balance.abs()),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _isBalanced ? Colors.green : Colors.orange,
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
  String? _getAccountDetailType(Account? account) {
    if (account == null) return null;

    // اول چک کردن accountType که دقیق‌تر است
    if (account.accountType == 'product') {
      return 'product';
    }

    // سپس چک کردن نام حساب به عنوان fallback
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

    if (account.accountType == 'bank' || accountName.contains('بانک')) {
      return 'bank_account';
    }

    if (account.accountType == 'cash_register' || accountName.contains('صندوق')) {
      return 'cash_register';
    }

    if (account.accountType == 'petty_cash' || accountName.contains('تنخواه')) {
      return 'petty_cash';
    }

    if (account.accountType == 'check' || accountName.contains('چک')) {
      return 'check';
    }

    if (account.accountType == 'person') {
      return 'person';
    }

    return null; // حساب نیاز به تفضیل ندارد
  }

  /// آیا حساب انتخاب شده از نوع کالا است و تفضیل کالا انتخاب شده؟
  bool _shouldShowQuantityField(DocumentLineEdit line) {
    final detailType = _getAccountDetailType(line.account);
    return detailType == 'product' &&
        line.detail != null &&
        line.detail!['product_id'] != null;
  }
}

