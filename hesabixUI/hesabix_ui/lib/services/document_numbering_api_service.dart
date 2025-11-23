import '../core/api_client.dart';
import '../models/document_numbering_models.dart';

class DocumentNumberingApiService {
  static final ApiClient _api = ApiClient();

  static String _basePath(int businessId) =>
      '/api/v1/businesses/$businessId/document-numbering-settings';

  /// دریافت تمام تنظیمات شماره‌گذاری اسناد یک کسب و کار
  static Future<List<DocumentNumberingSetting>> getSettings(int businessId) async {
    final resp = await _api.get(_basePath(businessId));
    if (resp.data['success'] == true) {
      final List items = resp.data['data'] ?? [];
      return items.map((e) => DocumentNumberingSetting.fromJson(
        Map<String, dynamic>.from(e),
      )).toList();
    }
    throw Exception(resp.data['message'] ?? 'خطا در دریافت تنظیمات شماره‌گذاری');
  }

  /// دریافت تنظیمات شماره‌گذاری برای یک نوع سند خاص
  static Future<DocumentNumberingSetting> getSetting(
    int businessId,
    String documentType,
  ) async {
    final resp = await _api.get('${_basePath(businessId)}/$documentType');
    if (resp.data['success'] == true) {
      // اگر تنظیمات وجود نداشت، از پیش‌فرض استفاده می‌کنیم
      final data = resp.data['data'];
      if (data is Map && data.containsKey('id')) {
        return DocumentNumberingSetting.fromJson(
          Map<String, dynamic>.from(data),
        );
      } else {
        // داده پیش‌فرض است، باید به DocumentNumberingSetting تبدیل کنیم
        final defaultData = Map<String, dynamic>.from(data ?? {});
        return DocumentNumberingSetting(
          businessId: businessId,
          documentType: documentType,
          prefix: defaultData['prefix'],
          includeDate: defaultData['include_date'] ?? true,
          calendarType: defaultData['calendar_type'] ?? 'gregorian',
          dateFormat: defaultData['date_format'],
          separator: defaultData['separator'] ?? '-',
          startNumber: defaultData['start_number'] ?? 1,
          numberPadding: defaultData['number_padding'] ?? 4,
          resetPeriod: defaultData['reset_period'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }
    }
    throw Exception(resp.data['message'] ?? 'خطا در دریافت تنظیمات شماره‌گذاری');
  }

  /// ذخیره تنظیمات شماره‌گذاری (ایجاد یا به‌روزرسانی)
  static Future<DocumentNumberingSetting> saveSetting(
    int businessId,
    DocumentNumberingSetting setting,
  ) async {
    final resp = await _api.post(_basePath(businessId), data: setting.toJson());
    if (resp.data['success'] == true) {
      return DocumentNumberingSetting.fromJson(
        Map<String, dynamic>.from(resp.data['data']),
      );
    }
    throw Exception(resp.data['message'] ?? 'خطا در ذخیره تنظیمات شماره‌گذاری');
  }

  /// حذف تنظیمات شماره‌گذاری (بازگشت به پیش‌فرض)
  static Future<void> deleteSetting(int businessId, String documentType) async {
    final resp = await _api.delete('${_basePath(businessId)}/$documentType');
    if (resp.data['success'] != true) {
      throw Exception(resp.data['message'] ?? 'خطا در حذف تنظیمات شماره‌گذاری');
    }
  }
}

