import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/pages/business/pay_page_poster_pdf.dart';

void main() {
  test('poster display URL drops http(s) but keeps /u/ for typing', () {
    expect(
      payPagePosterDisplayUrl('https://hesabix.ir/u/hesabixacc'),
      'hesabix.ir/u/hesabixacc',
    );
    expect(
      payPagePosterDisplayUrl('http://hesabix.ir/u/shop-ali'),
      'hesabix.ir/u/shop-ali',
    );
    expect(
      payPagePosterDisplayUrl('HTTPS://hesabix.ir/u/shop-ali/'),
      'hesabix.ir/u/shop-ali',
    );
    expect(
      payPagePosterDisplayUrl('hesabix.ir/u/shop-ali'),
      'hesabix.ir/u/shop-ali',
    );
    expect(
      payPagePosterDisplayUrl('https://hesabix.ir/shop-ali'),
      'hesabix.ir/shop-ali',
    );
  });
}
