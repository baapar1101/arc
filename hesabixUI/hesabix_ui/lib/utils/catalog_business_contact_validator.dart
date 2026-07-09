import '../models/business_models.dart';

/// بررسی آمادگی اطلاعات تماس کسب‌وکار برای انتشار در شبکهٔ تأمین.
class CatalogBusinessContactValidator {
  CatalogBusinessContactValidator._();

  static List<String> warnings(BusinessResponse business) {
    final items = <String>[];
    final address = (business.address ?? '').trim();
    final province = (business.province ?? '').trim();
    final city = (business.city ?? '').trim();
    final phone = (business.phone ?? '').trim();
    final mobile = (business.mobile ?? '').trim();

    if (address.isEmpty) {
      items.add('نشانی کسب‌وکار ثبت نشده است.');
    }
    if (province.isEmpty && city.isEmpty) {
      items.add('استان یا شهر کسب‌وکار مشخص نشده است.');
    }
    if (business.publicCatalogShowContact) {
      if (phone.isEmpty && mobile.isEmpty) {
        items.add('نمایش تماس در کاتالوگ فعال است اما تلفن یا موبایل ثبت نشده.');
      }
    } else {
      items.add(
        'برای نمایش شماره تماس در شبکهٔ تأمین، گزینه «نمایش شماره تماس در کاتالوگ» را در تنظیمات کسب‌وکار فعال کنید.',
      );
    }
    return items;
  }

  static bool isComplete(BusinessResponse business) => warnings(business).isEmpty;

  static String blockingMessage(BusinessResponse business) {
    final items = warnings(business);
    if (items.isEmpty) return '';
    return 'برای انتشار در شبکهٔ تأمین ابتدا اطلاعات تماس کسب‌وکار را تکمیل کنید: ${items.first}';
  }
}
