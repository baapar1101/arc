import 'package:flutter_test/flutter_test.dart';
import 'package:hesabix_ui/widgets/ai/ai_visualization_spec.dart';

void main() {
  group('AIChartSpec.yAxisBounds', () {
    test('positive values keep minY at 0', () {
      const spec = AIChartSpec(
        type: 'bar',
        title: 'فروش',
        labels: ['الف', 'ب'],
        values: [100, 200],
      );
      final (minY, maxY) = spec.yAxisBounds;
      expect(minY, 0);
      expect(maxY, closeTo(230, 0.001));
      expect(spec.yGridInterval, closeTo(57.5, 0.001));
    });

    test('all-negative debt values do not collapse maxY while minY auto-expands', () {
      // دادهٔ واقعی گفت‌وگوی «گزارش بدهی دو نفر» (session 892):
      // maxY=1 و interval=0.25 با minY≈-132e6 حدود ۵۰۰ میلیون خط شبکه می‌ساخت.
      const spec = AIChartSpec(
        type: 'bar',
        title: 'بدهی دو بدهکار برتر',
        labels: ['مبین امین', 'سید جعفر حسینی راد'],
        values: [-132000000, -120000000],
      );
      final (minY, maxY) = spec.yAxisBounds;
      expect(minY, lessThan(-132000000));
      expect(maxY, 0);
      final gridCount = (maxY - minY) / spec.yGridInterval;
      expect(gridCount, closeTo(4, 0.01));
      expect(spec.yGridInterval, greaterThan(1e6));
    });

    test('mixed signs include zero on the axis', () {
      const spec = AIChartSpec(
        type: 'bar',
        title: 'سود و زیان',
        labels: ['الف', 'ب'],
        values: [-50, 80],
      );
      final (minY, maxY) = spec.yAxisBounds;
      expect(minY, closeTo(-57.5, 0.001));
      expect(maxY, closeTo(92, 0.001));
    });

    test('parses chart fence JSON with negative values', () {
      const raw = '''
{
  "type": "bar",
  "title": "بدهی دو بدهکار برتر",
  "labels": ["مبین امین", "سید جعفر حسینی راد"],
  "values": [-132000000, -120000000],
  "unit": "ریال"
}
''';
      final spec = AIChartSpec.tryParse(raw);
      expect(spec, isNotNull);
      expect(spec!.hasData, isTrue);
      expect(spec.yGridInterval, greaterThan(1e6));
    });
  });
}
