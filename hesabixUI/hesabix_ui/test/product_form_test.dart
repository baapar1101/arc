import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/product_form_data.dart';
import 'package:hesabix_ui/utils/product_form_validator.dart';

void main() {
  group('ProductFormData Tests', () {
    test('should create default instance', () {
      final formData = ProductFormData();
      
      expect(formData.itemType, 'کالا');
      expect(formData.name, '');
      expect(formData.trackInventory, false);
      expect(formData.isSalesTaxable, false);
      expect(formData.isPurchaseTaxable, false);
      expect(formData.selectedAttributeIds, isEmpty);
    });

    test('should create from product data', () {
      final productData = {
        'id': 1,
        'name': 'کالای تست',
        'code': 'TEST001',
        'item_type': 'خدمت',
        'base_sales_price': 100000,
        'track_inventory': true,
        'is_sales_taxable': true,
        'sales_tax_rate': 9.0,
      };

      final formData = ProductFormData.fromProduct(productData);

      expect(formData.name, 'کالای تست');
      expect(formData.code, 'TEST001');
      expect(formData.itemType, 'خدمت');
      expect(formData.baseSalesPrice, 100000);
      expect(formData.trackInventory, true);
      expect(formData.isSalesTaxable, true);
      expect(formData.salesTaxRate, 9.0);
    });

    test('should copy with new values', () {
      final original = ProductFormData();
      final updated = original.copyWith(
        name: 'کالای جدید',
        baseSalesPrice: 50000,
      );

      expect(updated.name, 'کالای جدید');
      expect(updated.baseSalesPrice, 50000);
      expect(updated.itemType, original.itemType); // unchanged
    });

    test('should convert to payload', () {
      final formData = ProductFormData(
        name: 'کالای تست',
        code: 'TEST001',
        baseSalesPrice: 100000,
        trackInventory: true,
      );

      final payload = formData.toPayload();

      expect(payload['name'], 'کالای تست');
      expect(payload['code'], 'TEST001');
      expect(payload['base_sales_price'], 100000);
      expect(payload['track_inventory'], true);
      expect(payload.containsKey('description'), false); // null values removed
    });
  });

  group('ProductFormValidator Tests', () {
    test('should validate name correctly', () {
      expect(ProductFormValidator.validateName(null), 'نام کالا الزامی است');
      expect(ProductFormValidator.validateName(''), 'نام کالا الزامی است');
      expect(ProductFormValidator.validateName(' '), 'نام کالا الزامی است');
      expect(ProductFormValidator.validateName('ک'), 'نام کالا باید حداقل ۲ کاراکتر باشد');
      expect(ProductFormValidator.validateName('کالا'), null);
    });

    test('should validate price correctly', () {
      expect(ProductFormValidator.validatePrice(''), null);
      expect(ProductFormValidator.validatePrice('100'), null);
      expect(ProductFormValidator.validatePrice('100.50'), null);
      expect(ProductFormValidator.validatePrice('abc'), 'قیمت باید عدد معتبر باشد');
      expect(ProductFormValidator.validatePrice('-10'), 'قیمت نمی‌تواند منفی باشد');
    });

    test('should validate tax rate correctly', () {
      expect(ProductFormValidator.validateTaxRate(''), null);
      expect(ProductFormValidator.validateTaxRate('9'), null);
      expect(ProductFormValidator.validateTaxRate('9.5'), null);
      expect(ProductFormValidator.validateTaxRate('100'), null);
      expect(ProductFormValidator.validateTaxRate('abc'), 'نرخ مالیات باید عدد معتبر باشد');
      expect(ProductFormValidator.validateTaxRate('-5'), 'نرخ مالیات نمی‌تواند منفی باشد');
      expect(ProductFormValidator.validateTaxRate('101'), 'نرخ مالیات نمی‌تواند بیشتر از ۱۰۰٪ باشد');
    });

    test('should validate conversion factor correctly', () {
      expect(ProductFormValidator.validateConversionFactor(''), null);
      expect(ProductFormValidator.validateConversionFactor('2'), null);
      expect(ProductFormValidator.validateConversionFactor('2.5'), null);
      expect(ProductFormValidator.validateConversionFactor('abc'), 'ضریب تبدیل باید عدد معتبر باشد');
      expect(ProductFormValidator.validateConversionFactor('0'), 'ضریب تبدیل باید بزرگتر از صفر باشد');
      expect(ProductFormValidator.validateConversionFactor('-1'), 'ضریب تبدیل باید بزرگتر از صفر باشد');
    });

    test('should validate lead time correctly', () {
      expect(ProductFormValidator.validateLeadTime(''), null);
      expect(ProductFormValidator.validateLeadTime('7'), null);
      expect(ProductFormValidator.validateLeadTime('365'), null);
      expect(ProductFormValidator.validateLeadTime('abc'), 'زمان تحویل باید عدد صحیح باشد');
      expect(ProductFormValidator.validateLeadTime('-1'), 'زمان تحویل نمی‌تواند منفی باشد');
      expect(ProductFormValidator.validateLeadTime('366'), 'زمان تحویل نمی‌تواند بیشتر از ۳۶۵ روز باشد');
    });

    test('should validate form data correctly', () {
      final validData = ProductFormData(
        name: 'کالای معتبر',
        baseSalesPrice: 100000,
        salesTaxRate: 9,
        unitConversionFactor: 2,
      );

      final invalidData = ProductFormData(
        name: '', // invalid
        baseSalesPrice: -100, // invalid
        salesTaxRate: 101, // invalid
        unitConversionFactor: 0, // invalid
      );

      expect(ProductFormValidator.isFormValid(validData), true);
      expect(ProductFormValidator.isFormValid(invalidData), false);

      final errors = ProductFormValidator.validateFormData(invalidData);
      expect(errors.containsKey('name'), true);
      expect(errors.containsKey('baseSalesPrice'), true);
      expect(errors.containsKey('salesTaxRate'), true);
      expect(errors.containsKey('unitConversionFactor'), true);
    });
  });
}
