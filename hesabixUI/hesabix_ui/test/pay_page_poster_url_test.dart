import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/pages/business/pay_page_poster_pdf.dart';

void main() {
  test('poster display URL drops https and /u/ for distant reading', () {
    expect(
      payPagePosterDisplayUrl('https://hesabix.ir/u/hesabixacc'),
      'hesabix.ir/hesabixacc',
    );
    expect(
      payPagePosterDisplayUrl('http://hesabix.ir/u/shop-ali'),
      'hesabix.ir/shop-ali',
    );
  });
}
