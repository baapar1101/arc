// Extension برای ترجمه‌های ورک‌فلو
// این فایل دسترسی راحت‌تر به ترجمه‌های نودهای ورک‌فلو را فراهم می‌کند

import '../l10n/app_localizations.dart';

/// Extension برای ترجمه‌های ورک‌فلو
extension WorkflowLocalizations on AppLocalizations {
  
  // ==================== ترجمه‌های مشترک ====================
  
  /// تنظیمات
  String get workflowSettings => localeName == 'fa' ? 'تنظیمات' : 'Settings';
  
  /// اطلاعات پایه
  String get workflowBasicInfo => localeName == 'fa' ? 'اطلاعات پایه' : 'Basic Information';
  
  /// پیشرفته
  String get workflowAdvanced => localeName == 'fa' ? 'پیشرفته' : 'Advanced';
  
  /// این فیلد الزامی است
  String get workflowRequiredField => localeName == 'fa' ? 'این فیلد الزامی است' : 'This field is required';
  
  /// اختیاری
  String get workflowOptional => localeName == 'fa' ? 'اختیاری' : 'Optional';
  
  // ==================== Create Invoice ====================
  
  /// نام اکشن
  String get workflowCreateInvoiceActionName => localeName == 'fa' ? 'ایجاد فاکتور' : 'Create Invoice';
  
  /// توضیحات اکشن
  String get workflowCreateInvoiceActionDescription => 
      localeName == 'fa' 
          ? 'ایجاد فاکتور فروش، خرید یا برگشتی با امکانات پیشرفته'
          : 'Create sales, purchase or return invoice with advanced features';
  
  /// گروه اطلاعات پایه
  String get workflowCreateInvoiceGroupBasicInfo => localeName == 'fa' ? 'اطلاعات پایه' : 'Basic Information';
  
  /// گروه آیتم‌ها
  String get workflowCreateInvoiceGroupItems => localeName == 'fa' ? 'آیتم‌های فاکتور' : 'Invoice Items';
  
  /// گروه مالی
  String get workflowCreateInvoiceGroupFinancial => localeName == 'fa' ? 'تنظیمات مالی' : 'Financial Settings';
  
  /// گروه پرداخت
  String get workflowCreateInvoiceGroupPayment => localeName == 'fa' ? 'پرداخت' : 'Payment';
  
  /// گروه انبار
  String get workflowCreateInvoiceGroupWarehouse => localeName == 'fa' ? 'انبار' : 'Warehouse';
  
  /// گروه پیشرفته
  String get workflowCreateInvoiceGroupAdvanced => localeName == 'fa' ? 'پیشرفته' : 'Advanced';
  
  /// نوع فاکتور
  String get workflowCreateInvoiceFieldInvoiceType => localeName == 'fa' ? 'نوع فاکتور' : 'Invoice Type';
  
  /// فاکتور فروش
  String get workflowCreateInvoiceInvoiceSales => localeName == 'fa' ? 'فاکتور فروش' : 'Sales Invoice';
  
  /// فاکتور خرید
  String get workflowCreateInvoiceInvoicePurchase => localeName == 'fa' ? 'فاکتور خرید' : 'Purchase Invoice';
  
  /// برگشت از فروش
  String get workflowCreateInvoiceInvoiceReturnSales => localeName == 'fa' ? 'برگشت از فروش' : 'Sales Return';
  
  /// برگشت از خرید
  String get workflowCreateInvoiceInvoiceReturnPurchase => localeName == 'fa' ? 'برگشت از خرید' : 'Purchase Return';
  
  /// طرف حساب
  String get workflowCreateInvoiceFieldPersonId => localeName == 'fa' ? 'طرف حساب' : 'Contact';
  
  /// تاریخ فاکتور
  String get workflowCreateInvoiceFieldDocumentDate => localeName == 'fa' ? 'تاریخ فاکتور' : 'Invoice Date';
  
  /// توضیحات
  String get workflowCreateInvoiceFieldDescription => localeName == 'fa' ? 'توضیحات' : 'Description';
  
  /// placeholder توضیحات
  String get workflowCreateInvoiceFieldDescriptionPlaceholder => 
      localeName == 'fa' ? 'توضیحات فاکتور را وارد کنید...' : 'Enter invoice description...';
  
  /// ارز
  String get workflowCreateInvoiceFieldCurrencyId => localeName == 'fa' ? 'ارز' : 'Currency';
  
  /// آیتم‌ها
  String get workflowCreateInvoiceFieldItems => localeName == 'fa' ? 'آیتم‌ها' : 'Items';
  
  /// راهنمای آیتم‌ها
  String get workflowCreateInvoiceFieldItemsHelp => 
      localeName == 'fa'
          ? 'محصولات فاکتور را اضافه کنید. می‌توانید از reference به نودهای قبلی استفاده کنید: \$node_id.items'
          : 'Add invoice products. You can use references to previous nodes: \$node_id.items';
  
  /// محصول
  String get workflowCreateInvoiceItemProductId => localeName == 'fa' ? 'محصول' : 'Product';
  
  /// تعداد
  String get workflowCreateInvoiceItemQuantity => localeName == 'fa' ? 'تعداد' : 'Quantity';
  
  /// قیمت واحد
  String get workflowCreateInvoiceItemUnitPrice => localeName == 'fa' ? 'قیمت واحد' : 'Unit Price';
  
  /// درصد تخفیف
  String get workflowCreateInvoiceItemDiscountPercent => localeName == 'fa' ? 'درصد تخفیف' : 'Discount %';
  
  /// درصد مالیات
  String get workflowCreateInvoiceItemTaxPercent => localeName == 'fa' ? 'درصد مالیات' : 'Tax %';
  
  /// پیش‌فاکتور
  String get workflowCreateInvoiceFieldIsProforma => localeName == 'fa' ? 'پیش‌فاکتور' : 'Proforma Invoice';
  
  /// راهنمای پیش‌فاکتور
  String get workflowCreateInvoiceFieldIsProformaHelp =>
      localeName == 'fa'
          ? 'پیش‌فاکتور بر روی حسابداری و موجودی تأثیر نمی‌گذارد'
          : 'Proforma invoices don\'t affect accounting and inventory';
  
  // ==================== Send Telegram ====================
  
  /// نام اکشن
  String get workflowSendTelegramActionName => localeName == 'fa' ? 'ارسال پیام تلگرام' : 'Send Telegram Message';
  
  /// توضیحات اکشن
  String get workflowSendTelegramActionDescription => 
      localeName == 'fa'
          ? 'ارسال پیام به کاربر عضو کسب و کار از طریق تلگرام (فقط کاربران متصل به ربات)'
          : 'Send message to business member via Telegram (only connected users)';
  
  /// کاربر دریافت‌کننده
  String get workflowSendTelegramFieldUserId => localeName == 'fa' ? 'کاربر دریافت‌کننده' : 'Recipient User';
  
  /// متن پیام
  String get workflowSendTelegramFieldMessage => localeName == 'fa' ? 'متن پیام' : 'Message Text';
  
  /// placeholder متن پیام
  String get workflowSendTelegramFieldMessagePlaceholder =>
      localeName == 'fa' ? 'متن پیام خود را وارد کنید...' : 'Enter your message...';
  
  /// حالت پارس
  String get workflowSendTelegramFieldParseMode => localeName == 'fa' ? 'حالت پارس' : 'Parse Mode';
  
  /// تلاش مجدد در صورت خطا
  String get workflowSendTelegramFieldRetryOnFailure => localeName == 'fa' ? 'تلاش مجدد در صورت خطا' : 'Retry on Failure';
  
  // ==================== Send Email ====================
  
  /// نام اکشن
  String get workflowSendEmailActionName => localeName == 'fa' ? 'ارسال ایمیل' : 'Send Email';
  
  /// گیرنده
  String get workflowSendEmailFieldTo => localeName == 'fa' ? 'گیرنده' : 'To';
  
  /// موضوع
  String get workflowSendEmailFieldSubject => localeName == 'fa' ? 'موضوع' : 'Subject';
  
  /// متن ایمیل
  String get workflowSendEmailFieldBody => localeName == 'fa' ? 'متن ایمیل' : 'Body';
  
  // ==================== تابع کمکی ====================
  
  /// فرمت کردن نام فیلد (تبدیل snake_case به عنوان)
  String formatFieldName(String fieldKey) {
    return fieldKey
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}
