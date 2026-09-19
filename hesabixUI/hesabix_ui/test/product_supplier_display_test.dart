import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/utils/product_supplier_display.dart';

void main() {
  group('product supplier display', () {
    test('preferred name uses preferred row then first', () {
      expect(preferredSupplierNameOf({'suppliers': []}), isNull);
      expect(
        preferredSupplierNameOf({
          'suppliers': [
            {'name': 'الف'},
            {'name': 'ب', 'is_preferred': true},
          ],
        }),
        'ب',
      );
      expect(
        preferredSupplierNameOf({'preferred_supplier_name': 'از لیست'}),
        'از لیست',
      );
    });

    test('column label adds extra count', () {
      expect(
        formatProductSuppliersColumn({
          'suppliers': [
            {'name': 'شرکت الف', 'is_preferred': true},
            {'name': 'شرکت ب'},
          ],
        }),
        'شرکت الف  +1',
      );
      expect(formatProductSuppliersColumn({'suppliers': []}), '-');
    });

    test('merge keeps list category_name when GET omits it', () {
      final merged = mergeProductDetailMaps(
        {
          'id': 1,
          'category_name': 'لوازم',
          'suppliers': [
            {'id': 8, 'name': 'قدیمی'},
          ],
        },
        {
          'id': 1,
          'name': 'کالا',
          'category_name': null,
          'suppliers': [
            {'id': 9, 'name': 'جدید', 'phone': '021'},
          ],
        },
      );
      expect(merged['category_name'], 'لوازم');
      expect(merged['name'], 'کالا');
      expect((merged['suppliers'] as List).first['name'], 'جدید');
    });
  });
}
