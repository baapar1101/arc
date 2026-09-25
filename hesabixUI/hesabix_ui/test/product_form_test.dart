import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/models/product_form_data.dart';
import 'package:hesabix_ui/models/product_supplier_item.dart';
import 'package:hesabix_ui/utils/product_form_validator.dart';

void main() {
  group('ProductFormData Tests', () {
    test('should create default instance', () {
      final formData = ProductFormData();
      
      expect(formData.itemType, 'کالا');
      expect(formData.name, '');
      expect(formData.autoGenerateCode, true);
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
      expect(formData.autoGenerateCode, false);
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

    test('copyWith can clear nullable fields (e.g. default warehouse)', () {
      final original = ProductFormData(
        name: 'کالا',
        defaultWarehouseId: 42,
        taxTypeId: 7,
      );
      final cleared = original.copyWith(
        defaultWarehouseId: null,
        taxTypeId: null,
      );
      expect(cleared.defaultWarehouseId, isNull);
      expect(cleared.taxTypeId, isNull);
      expect(cleared.name, original.name);
    });

    test('should convert to payload', () {
      final formData = ProductFormData(
        name: 'کالای تست',
        code: 'TEST001',
        autoGenerateCode: false,
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

    test('should always include tax fields in payload for backend update', () {
      final formData = ProductFormData(
        name: 'کالای تست',
        taxTypeId: 5,
        taxCode: '1234567890123',
        taxUnitId: 3,
        isSalesTaxable: true,
        salesTaxRate: 9,
      );

      final payload = formData.toPayload();

      expect(payload['tax_type_id'], 5);
      expect(payload['tax_code'], '1234567890123');
      expect(payload['tax_unit_id'], 3);
      expect(payload['is_sales_taxable'], true);
      expect(payload['sales_tax_rate'], 9);
    });

    test('should parse tax ids from numeric API values', () {
      final formData = ProductFormData.fromProduct({
        'name': 'کالا',
        'tax_type_id': 5.0,
        'tax_unit_id': 3,
      });

      expect(formData.taxTypeId, 5);
      expect(formData.taxUnitId, 3);
    });

    test('auto code mode never sends manual code in payload', () {
      final formData = ProductFormData(
        name: 'کالای تست',
        code: 'SHOULD_NOT_SEND',
        autoGenerateCode: true,
      );
      final payload = formData.toPayload();
      expect(payload['code'], isNull);
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

    test('should include suppliers in payload', () {
      final formData = ProductFormData(
        name: 'کالا',
        suppliers: [
          ProductSupplierItem(
            name: 'تأمین الف',
            phone: '02112345678',
            socialContacts: [
              ProductSupplierSocialContact(platformKey: 'whatsapp', value: '09121234567'),
            ],
          ),
        ],
      );

      final payload = formData.toPayload();
      expect(payload['suppliers'], isA<List>());
      final suppliers = payload['suppliers'] as List;
      expect(suppliers, hasLength(1));
      expect(suppliers.first['name'], 'تأمین الف');
      expect(suppliers.first['social_contacts'], hasLength(1));
    });

    test('should parse suppliers from product json', () {
      final formData = ProductFormData.fromProduct({
        'name': 'کالا',
        'suppliers': [
          {
            'id': 1,
            'name': 'شرکت ب',
            'is_preferred': true,
            'social_contacts': [
              {'platform_key': 'telegram', 'value': '@shop'},
            ],
          },
        ],
      });

      expect(formData.suppliers, hasLength(1));
      expect(formData.suppliers.first.name, 'شرکت ب');
      expect(formData.suppliers.first.isPreferred, true);
      expect(formData.suppliers.first.socialContacts.first.value, '@shop');
    });
  });
}
