import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/account_model.dart';
import '../../utils/invoice_adjustments_account_filter.dart';
import '../../utils/number_normalizer.dart';
import '../../utils/number_formatters.dart';
import 'account_tree_combobox_widget.dart';

/// ردیف فرم اضافات/کسورات فاکتور (فروش یا خرید) — هم‌خوان با `extra_info.invoice_adjustments` در API.
class InvoiceAdjustmentFormRow {
  InvoiceAdjustmentFormRow({
    this.kind = 'addition',
    this.account,
  })  : amountController = TextEditingController(),
        taxRateController = TextEditingController(),
        descriptionController = TextEditingController();

  /// `addition` یا `deduction`
  String kind;
  Account? account;
  final TextEditingController amountController;
  final TextEditingController taxRateController;
  final TextEditingController descriptionController;

  factory InvoiceAdjustmentFormRow.fromSavedMap(
    Map<String, dynamic> m, {
    Account? account,
  }) {
    final row = InvoiceAdjustmentFormRow(
      kind: (m['kind']?.toString().toLowerCase() == 'deduction')
          ? 'deduction'
          : 'addition',
      account: account,
    );
    final amt = m['amount'];
    if (amt != null) {
      final parsed = amt is num ? amt : num.tryParse(amt.toString());
      row.amountController.text = formatNumberForInput(parsed);
    }
    final tr = m['tax_rate'];
    if (tr != null) {
      final parsed = tr is num ? tr : num.tryParse(tr.toString());
      row.taxRateController.text = formatNumberForInput(parsed);
    }
    final d = m['description'];
    if (d != null) row.descriptionController.text = d.toString();
    return row;
  }

  void dispose() {
    amountController.dispose();
    taxRateController.dispose();
    descriptionController.dispose();
  }

  bool get isBlankRow {
    final a = amountController.text.replaceAll(',', '').trim();
    return account == null && a.isEmpty;
  }
}

num invoiceAdjustmentsRound2(num x) {
  final f = math.pow(10, 2).toDouble();
  return (x * f).round() / f;
}

num _rowAmount(InvoiceAdjustmentFormRow r) {
  final t = r.amountController.text.replaceAll(',', '').trim();
  return num.tryParse(t) ?? 0;
}

num _rowTaxRate(InvoiceAdjustmentFormRow r) {
  final t = r.taxRateController.text.replaceAll(',', '').trim();
  if (t.isEmpty) return 0;
  return num.tryParse(t) ?? 0;
}

num rowSignedNet(InvoiceAdjustmentFormRow r) {
  final amt = _rowAmount(r);
  if (amt <= 0) return 0;
  return r.kind == 'deduction' ? -amt : amt;
}

num rowSignedTax(InvoiceAdjustmentFormRow r) {
  final amt = _rowAmount(r);
  if (amt <= 0) return 0;
  final tr = _rowTaxRate(r);
  if (tr < 0 || tr > 100) return 0;
  final tax = invoiceAdjustmentsRound2(amt * tr / 100);
  return r.kind == 'deduction' ? -tax : tax;
}

/// جمع خالص با علامت (برای نمایش و `totals.adjustments_net`).
num sumSignedAdjustmentsNet(List<InvoiceAdjustmentFormRow> rows) {
  num s = 0;
  for (final r in rows) {
    s += rowSignedNet(r);
  }
  return invoiceAdjustmentsRound2(s);
}

/// جمع مالیات با علامت (`totals.adjustments_tax`).
num sumSignedAdjustmentsTax(List<InvoiceAdjustmentFormRow> rows) {
  num s = 0;
  for (final r in rows) {
    s += rowSignedTax(r);
  }
  return invoiceAdjustmentsRound2(s);
}

bool adjustmentRowsHasNonEmpty(List<InvoiceAdjustmentFormRow> rows) {
  for (final r in rows) {
    if (!r.isBlankRow) return true;
  }
  return false;
}

/// اعتبارسنجی پیش از ذخیره؛ در صورت خطا رشتهٔ خطا، وگرنه null.
String? validateAdjustmentRows(
  List<InvoiceAdjustmentFormRow> rows, {
  required bool invoiceTypeSupportsAdjustments,
  String? invoiceTypeValue,
  Map<String, dynamic>? accountFilterRules,
}) {
  if (!invoiceTypeSupportsAdjustments) {
    if (adjustmentRowsHasNonEmpty(rows)) {
      return 'اضافات و کسورات فقط برای فاکتور فروش یا خرید مجاز است';
    }
    return null;
  }
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final amt = _rowAmount(r);
    final hasAmt = amt > 0;
    final hasAcct = r.account != null;
    if (!hasAmt && !hasAcct) continue;
    if (!hasAmt) {
      return 'ردیف ${i + 1} اضافات/کسورات: مبلغ الزامی است';
    }
    if (amt <= 0) {
      return 'ردیف ${i + 1}: مبلغ باید بزرگ‌تر از صفر باشد';
    }
    if (!hasAcct) {
      return 'ردیف ${i + 1}: انتخاب حساب الزامی است';
    }
    final expectedDocType = adjustmentAccountDocumentType(
      invoiceTypeValue: invoiceTypeValue,
      kind: r.kind,
      serverRules: accountFilterRules,
    );
    if (!isAdjustmentAccountAllowedForDocumentType(r.account, expectedDocType)) {
      return 'ردیف ${i + 1}: حساب انتخابی با نوع ${r.kind == 'addition' ? 'اضافه' : 'کسر'} همخوانی ندارد';
    }
    final tr = _rowTaxRate(r);
    if (tr < 0 || tr > 100) {
      return 'ردیف ${i + 1}: نرخ مالیات باید بین ۰ تا ۱۰۰ باشد';
    }
  }
  return null;
}

/// ساخت آرایه برای API؛ ردیف‌های خالی حذف می‌شوند.
List<Map<String, dynamic>> buildAdjustmentsPayloadList(List<InvoiceAdjustmentFormRow> rows) {
  final out = <Map<String, dynamic>>[];
  for (final r in rows) {
    if (r.isBlankRow) continue;
    final amt = _rowAmount(r);
    if (amt <= 0 || r.account?.id == null) continue;
    final tr = _rowTaxRate(r);
    final desc = r.descriptionController.text.trim();
    out.add({
      'kind': r.kind,
      'amount': amt.toDouble(),
      'tax_rate': tr.toDouble(),
      'account_id': r.account!.id,
      if (desc.isNotEmpty) 'description': desc,
    });
  }
  return out;
}

void disposeInvoiceAdjustmentRows(List<InvoiceAdjustmentFormRow> rows) {
  for (final r in rows) {
    r.dispose();
  }
}

/// محتوای تب «اضافات و کسورات».
class InvoiceAdjustmentsTabContent extends StatelessWidget {
  final int businessId;
  final List<InvoiceAdjustmentFormRow> rows;
  final VoidCallback onChanged;
  final int decimalPlaces;
  final String? invoiceTypeValue;
  final Map<String, dynamic>? accountFilterRules;

  const InvoiceAdjustmentsTabContent({
    super.key,
    required this.businessId,
    required this.rows,
    required this.onChanged,
    this.decimalPlaces = 2,
    this.invoiceTypeValue,
    this.accountFilterRules,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = sumSignedAdjustmentsNet(rows);
    final tax = sumSignedAdjustmentsTax(rows);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اضافات و کسورات فاکتور',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'برای هر ردیف نوع (اضافه/کسر)، مبلغ خالص، در صورت نیاز نرخ مالیات و حساب طرف را مشخص کنید. '
                'مبلغ نهایی فاکتور پس از کالاها با این مقادیر به‌روز می‌شود.',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () {
                    rows.add(InvoiceAdjustmentFormRow());
                    onChanged();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('ردیف جدید'),
                ),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'ردیفی ثبت نشده است.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...List.generate(rows.length, (i) {
                  final r = rows[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final narrow = c.maxWidth < 560;
                          Widget kindField = SizedBox(
                            height: 56,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(color: Theme.of(context).dividerColor),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Center(
                                child: SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  segments: const [
                                    ButtonSegment(value: 'addition', label: Text('اضافه')),
                                    ButtonSegment(value: 'deduction', label: Text('کسر')),
                                  ],
                                  selected: {r.kind},
                                  onSelectionChanged: (s) {
                                    r.kind = s.first;
                                    final expectedDocType = adjustmentAccountDocumentType(
                                      invoiceTypeValue: invoiceTypeValue,
                                      kind: r.kind,
                                      serverRules: accountFilterRules,
                                    );
                                    if (!isAdjustmentAccountAllowedForDocumentType(r.account, expectedDocType)) {
                                      r.account = null;
                                    }
                                    onChanged();
                                  },
                                ),
                              ),
                            ),
                          );
                          final docTypeFilter = adjustmentAccountDocumentType(
                            invoiceTypeValue: invoiceTypeValue,
                            kind: r.kind,
                            serverRules: accountFilterRules,
                          );
                          final accountField = AccountTreeComboboxWidget(
                            businessId: businessId,
                            selectedAccount: r.account,
                            label: 'حساب',
                            hintText: docTypeFilter == 'expense'
                                ? 'انتخاب حساب هزینه'
                                : 'انتخاب حساب درآمد',
                            isRequired: false,
                            documentTypeFilter: docTypeFilter,
                            dense: true,
                            onChanged: (a) {
                              r.account = a;
                              onChanged();
                            },
                          );
                          final amountField = TextField(
                            controller: r.amountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'مبلغ خالص',
                              border: OutlineInputBorder(),
                            ),
                            inputFormatters: const [
                              EnglishDigitsFormatter(),
                              ThousandsSeparatorInputFormatter(allowDecimal: true),
                            ],
                            onChanged: (_) => onChanged(),
                          );
                          final taxField = TextField(
                            controller: r.taxRateController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'نرخ مالیات ٪ (اختیاری)',
                              border: OutlineInputBorder(),
                            ),
                            inputFormatters: const [
                              EnglishDigitsFormatter(),
                              FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                            ],
                            onChanged: (_) => onChanged(),
                          );
                          final descField = TextField(
                            controller: r.descriptionController,
                            decoration: const InputDecoration(
                              labelText: 'شرح (اختیاری)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => onChanged(),
                          );
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text('ردیف ${i + 1}', style: theme.textTheme.titleSmall)),
                                  IconButton(
                                    tooltip: 'حذف ردیف',
                                    onPressed: () {
                                      r.dispose();
                                      rows.removeAt(i);
                                      onChanged();
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (narrow) ...[
                                kindField,
                                const SizedBox(height: 8),
                                accountField,
                                const SizedBox(height: 8),
                                amountField,
                                const SizedBox(height: 8),
                                taxField,
                                const SizedBox(height: 8),
                                descField,
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 2, child: kindField),
                                    const SizedBox(width: 8),
                                    Expanded(flex: 3, child: accountField),
                                    const SizedBox(width: 8),
                                    Expanded(flex: 2, child: amountField),
                                    const SizedBox(width: 8),
                                    Expanded(flex: 2, child: taxField),
                                  ],
                                ),
                              if (!narrow) ...[
                                const SizedBox(height: 8),
                                descField,
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text('جمع خالص اضافات/کسورات: ${formatWithThousands(net, decimalPlaces: decimalPlaces)}'),
                  Text('جمع مالیات: ${formatWithThousands(tax, decimalPlaces: decimalPlaces)}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
