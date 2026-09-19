/// هم‌راستا با اعتبارسنجی بک‌اند (`paper_size` حداکثر ۳۲ کاراکتر).
const int kReportTemplatePaperSizeMaxLength = 32;

/// مقادیر رایج برای UI؛ هر رشتهٔ دیگر تا ۳۲ کاراکتر در API پذیرفته می‌شود.
const List<String> kReportTemplatePaperSizeOptions = [
  'A4',
  'Letter',
  'A3',
  'A5',
  'Legal',
];

/// سایزهای فیش پرینتر برای قالب فاکتور (عرض ثابت، ارتفاع تکه‌تکه).
const List<String> kInvoiceReceiptPaperSizeOptions = [
  '60mm',
  '80mm',
  '100mm',
];

String reportTemplatePaperSizeLabel(String value) {
  switch (value) {
    case '60mm':
      return '۶ سانتی‌متر (فیش)';
    case '80mm':
      return '۸ سانتی‌متر (فیش)';
    case '100mm':
      return '۱۰ سانتی‌متر (فیش)';
    default:
      return value;
  }
}

/// سایزهای رایج برای برچسب مرسوله پستی (حواله انبار).
const List<String> kWarehousePostalLabelPaperOptions = [
  'A6',
  'A5',
  'A4',
  'Letter',
  '105mm 148mm',
  '100mm 150mm',
];
