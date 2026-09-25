/// سایزهای کاغذ چاپ فاکتور (A-series و فیش پرینتر).
class InvoicePrintPaperOption {
  final String value;
  final String labelFa;
  final bool isReceipt;

  const InvoicePrintPaperOption({
    required this.value,
    required this.labelFa,
    required this.isReceipt,
  });
}

const List<InvoicePrintPaperOption> kInvoicePrintPaperOptions = [
  InvoicePrintPaperOption(value: 'A4', labelFa: 'A4', isReceipt: false),
  InvoicePrintPaperOption(value: 'A5', labelFa: 'A5', isReceipt: false),
  InvoicePrintPaperOption(value: 'A6', labelFa: 'A6', isReceipt: false),
  InvoicePrintPaperOption(value: '60mm', labelFa: '۶ سانتی‌متر (فیش)', isReceipt: true),
  InvoicePrintPaperOption(value: '80mm', labelFa: '۸ سانتی‌متر (فیش)', isReceipt: true),
  InvoicePrintPaperOption(value: '100mm', labelFa: '۱۰ سانتی‌متر (فیش)', isReceipt: true),
];

const List<String> kInvoiceReceiptPaperSizeValues = ['60mm', '80mm', '100mm'];

bool isInvoiceReceiptPaper(String? paperSize) {
  final v = (paperSize ?? '').trim().toLowerCase();
  if (v.isEmpty) return false;
  if (kInvoiceReceiptPaperSizeValues.contains(v)) return true;
  if (v == '6cm' || v == '8cm' || v == '10cm') return true;
  return v.startsWith('60mm') || v.startsWith('80mm') || v.startsWith('100mm');
}

String invoicePrintTemplateSubtypeForPaper(String? paperSize) {
  return isInvoiceReceiptPaper(paperSize) ? 'receipt' : 'detail';
}

String invoicePrintOrientationForPaper(String? paperSize, String? current) {
  if (isInvoiceReceiptPaper(paperSize)) return 'portrait';
  final o = (current ?? '').trim();
  if (o == 'portrait' || o == 'landscape') return o;
  return 'landscape';
}
