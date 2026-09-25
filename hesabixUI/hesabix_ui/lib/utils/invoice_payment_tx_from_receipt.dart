import 'package:hesabix_ui/models/invoice_transaction.dart';
import 'package:hesabix_ui/models/receipt_payment_document.dart';
import 'package:uuid/uuid.dart';

num? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) {
    final t = v.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    return num.tryParse(t);
  }
  return null;
}

/// استخراج `fx_settlement` از سند دریافت/پرداخت (سطح سند یا خط شخص).
Map<String, dynamic>? extractFxSettlementFromReceiptDoc(ReceiptPaymentDocument doc) {
  final rawDoc = doc.extraInfo?['fx_settlement'];
  if (rawDoc is Map) {
    return Map<String, dynamic>.from(rawDoc);
  }
  for (final pl in doc.personLines) {
    final raw = pl.extraInfo?['fx_settlement'];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
  }
  return null;
}

bool isFxAdjustmentAccountLine(AccountLine line) =>
    line.extraInfo?['fx_adjustment'] == true;

/// مبلغ پرداخت‌شده به **ارز فاکتور** از یک سند دریافت/پرداخت مرتبط.
///
/// بین‌ارزی: `fx_settlement.settles_amount`
/// هم‌ارز: جمع خطوط حساب (بدون کارمزد و بدون خط تعدیل تسعیر)
double paidTowardInvoiceCurrencyFromReceiptDoc(ReceiptPaymentDocument doc) {
  final fx = extractFxSettlementFromReceiptDoc(doc);
  final settles = _toNum(fx?['settles_amount']);
  if (settles != null) {
    return settles.toDouble();
  }
  var total = 0.0;
  for (final line in doc.accountLines) {
    if (line.isCommissionLine) continue;
    if (isFxAdjustmentAccountLine(line)) continue;
    total += line.amount;
  }
  return total;
}

/// تبدیل خطوط حساب سند دریافت به تراکنش‌های فاکتور با حفظ settles/fx.
List<InvoiceTransaction> invoiceTransactionsFromReceiptPaymentDoc(
  ReceiptPaymentDocument doc, {
  String Function()? idFactory,
}) {
  final fx = extractFxSettlementFromReceiptDoc(doc);
  final settlesTotal = _toNum(fx?['settles_amount']);
  final fxRate = _toNum(fx?['rate'] ?? fx?['tx_rate']);
  final paymentCurrencyId = (fx?['payment_currency_id'] as num?)?.toInt();
  final paymentAmountMeta = _toNum(fx?['payment_amount']);

  final payableLines = <AccountLine>[
    for (final al in doc.accountLines)
      if (!al.isCommissionLine &&
          !isFxAdjustmentAccountLine(al) &&
          al.transactionType != null &&
          TransactionType.fromValue(al.transactionType!) != null)
        al,
  ];

  final out = <InvoiceTransaction>[];
  final uuid = const Uuid();
  var settlesAssigned = false;

  for (final accountLine in payableLines) {
    final transactionType = TransactionType.fromValue(accountLine.transactionType!)!;

    // مبلغ بومی پرداخت (ارز حساب)؛ در بین‌ارزی از account_currency_amount / payment_amount
    num amount = accountLine.amount;
    final native = _toNum(accountLine.extraInfo?['account_currency_amount']);
    if (native != null) {
      amount = native;
    } else if (paymentAmountMeta != null && payableLines.length == 1) {
      amount = paymentAmountMeta;
    }

    final linePayCur = (accountLine.extraInfo?['account_currency_id'] as num?)?.toInt() ??
        paymentCurrencyId;

    // settles فقط یک‌بار به اولین خط پرداخت نسبت داده می‌شود تا مانده دو برابر نشود
    num? settlesForLine;
    if (settlesTotal != null && !settlesAssigned) {
      settlesForLine = settlesTotal;
      settlesAssigned = true;
    } else if (settlesTotal != null && payableLines.length > 1) {
      // چند خط: settles را متناسب با سهم مبلغ بومی تقسیم نکن مگر متادیتا داشته باشیم؛
      // برای جلوگیری از دوبل‌شماری فقط روی خط اول می‌گذاریم.
      settlesForLine = null;
    }

    out.add(
      InvoiceTransaction(
        id: idFactory?.call() ?? uuid.v4(),
        type: transactionType,
        amount: amount,
        transactionDate: accountLine.transactionDate ?? doc.documentDate,
        description: accountLine.description,
        commission: accountLine.commission,
        bankId: accountLine.extraInfo?['bank_id']?.toString(),
        bankName: accountLine.extraInfo?['bank_name'] as String?,
        cashRegisterId: accountLine.extraInfo?['cash_register_id']?.toString(),
        cashRegisterName: accountLine.extraInfo?['cash_register_name'] as String?,
        pettyCashId: accountLine.extraInfo?['petty_cash_id']?.toString(),
        pettyCashName: accountLine.extraInfo?['petty_cash_name'] as String?,
        checkId: accountLine.extraInfo?['check_id']?.toString(),
        checkNumber: accountLine.extraInfo?['check_number'] as String?,
        personId: accountLine.extraInfo?['person_id']?.toString(),
        personName: accountLine.extraInfo?['person_name'] as String?,
        accountId: accountLine.accountId.toString(),
        accountName: accountLine.accountName,
        settlesAmount: settlesForLine,
        fxRate: settlesForLine != null ? fxRate : null,
        paymentCurrencyId: settlesForLine != null ? linePayCur : (fx != null ? linePayCur : null),
      ),
    );
  }

  // اگر فقط خط تعدیل/کارمزد بوده و settles داریم، یک ردیف مجازی نساز — UI باید خالی بماند
  // ولی اگر settles هست و هیچ خط پرداختی نبود، از متادیتا یک ردیف بانک بساز تا مانده درست شود
  if (out.isEmpty && settlesTotal != null && paymentAmountMeta != null) {
    out.add(
      InvoiceTransaction(
        id: idFactory?.call() ?? uuid.v4(),
        type: TransactionType.bank,
        amount: paymentAmountMeta,
        transactionDate: doc.documentDate,
        description: doc.description,
        settlesAmount: settlesTotal,
        fxRate: fxRate,
        paymentCurrencyId: paymentCurrencyId,
      ),
    );
  }

  return out;
}
