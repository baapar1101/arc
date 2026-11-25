import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/product/product_label_pdf_text.dart';
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/arabic.dart' as pdf_arabic;

void main() {
  test('Persian sentence words are reversed for LTR PDF painting', () {
    const input = 'اسکن کنید و پرداخت کنید';
    final shaped = shapePdfPersianText(input);
    final tokens = shaped.split(' ');
    expect(tokens.first, pdf_arabic.convert('کنید'));
    expect(tokens.last, pdf_arabic.convert('اسکن'));
  });

  test('Latin phrases are not word-reversed a second time', () {
    const input = 'Scan to pay';
    expect(shapePdfPersianText(input), pdf_arabic.convert(input));
  });
}
