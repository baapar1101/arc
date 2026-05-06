import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../services/product_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/date_formatters.dart';
import '../../utils/number_formatters.dart';
import '../jalali_date_picker.dart';

/// تب خلاصهٔ بازرگانی محصول؛ میانگین موزون قیمت به ارز پایهٔ کسب‌وکار (منطق تسعیر سند مانند شخص‌حساب).
class ProductCommercialInsightsTab extends StatefulWidget {
  final int businessId;
  final int productId;

  const ProductCommercialInsightsTab({
    super.key,
    required this.businessId,
    required this.productId,
  });

  @override
  State<ProductCommercialInsightsTab> createState() => _ProductCommercialInsightsTabState();
}

enum _Preset { month1, month3, month6, year, custom }

class _ProductCommercialInsightsTabState extends State<ProductCommercialInsightsTab> {
  final _service = ProductService();
  static const _bucketChoices = {'day': 'روز', 'week': 'هفته', 'month': 'ماه'};

  String _bucket = 'month';
  _Preset _preset = _Preset.year;
  DateTime? _customFrom;
  DateTime? _customTo;

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  ({DateTime from, DateTime to}) _rangeForPreset() {
    final now = _dateOnly(DateTime.now());
    switch (_preset) {
      case _Preset.month1:
        return (from: now.subtract(const Duration(days: 30)), to: now);
      case _Preset.month3:
        return (from: now.subtract(const Duration(days: 90)), to: now);
      case _Preset.month6:
        return (from: now.subtract(const Duration(days: 182)), to: now);
      case _Preset.year:
        return (from: now.subtract(const Duration(days: 365)), to: now);
      case _Preset.custom:
        final a = _customFrom ?? now.subtract(const Duration(days: 365));
        final b = _customTo ?? now;
        var lo = _dateOnly(a);
        var hi = _dateOnly(b);
        if (lo.isAfter(hi)) {
          final t = lo;
          lo = hi;
          hi = t;
        }
        return (from: lo, to: hi);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final span = _rangeForPreset();
    try {
      final raw = await _service.getCommercialInsights(
        businessId: widget.businessId,
        productId: widget.productId,
        dateFrom: span.from,
        dateTo: span.to,
        bucket: _bucket,
      );
      if (!mounted) return;
      setState(() {
        _data = raw;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  int _decimals() {
    final m = _data['meta'];
    if (m is Map<String, dynamic>) {
      final v = m['price_decimal_places'];
      if (v is int && v >= 0) return v.clamp(0, 6);
      if (v is num) return v.toInt().clamp(0, 6);
    }
    return 2;
  }

  String _currencySuffix() {
    final b = _data['base_currency'];
    if (b is Map<String, dynamic>) {
      final sym = b['symbol']?.toString() ?? '';
      final code = b['code']?.toString() ?? '';
      if (sym.isNotEmpty) return ' $sym';
      if (code.isNotEmpty) return ' $code';
    }
    return '';
  }

  String _fmtMoney(num? value) {
    if (value == null) return '-';
    return '${formatWithThousands(value, decimalPlaces: _decimals())}${_currencySuffix()}';
  }

  String _fmtQty(num? value) {
    if (value == null) return '-';
    return formatWithThousands(value, decimalPlaces: 3);
  }

  double? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Widget _kv(String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              k,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: 7,
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lastCard({
    required String title,
    required Map<String, dynamic>? payload,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            if (payload == null)
              Text(
                'داده‌ای نیست',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              )
            else ...[
              _kv(
                'تاریخ سند',
                DateFormatters.formatServerDate(payload['document_date']?.toString()),
              ),
              _kv('طرف تجاری', (payload['person_name'] ?? '-').toString()),
              _kv('کد سند', (payload['document_code'] ?? '-').toString()),
              _kv('مقدار', _fmtQty(_parseNum(payload['quantity']))),
              _kv(
                'قیمت واحد به ارز پایه',
                _fmtMoney(_parseNum(payload['unit_price_base_currency'])),
              ),
              _kv('نرخ سند به پایه', _fmtQty(_parseNum(payload['fx_rate_document_to_base']))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendRow(Color color, String text) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
  }

  Widget _chart() {
    final theme = Theme.of(context);
    final chartRaw = _data['chart'];
    if (chartRaw is! List) {
      return const SizedBox(height: 200, child: Center(child: Text('دادهٔ نمودار موجود نیست.')));
    }
    final pts = chartRaw.whereType<Map<String, dynamic>>().toList();
    if (pts.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'برای بازهٔ انتخاب‌شده نقطهٔ نموداری نیست.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
        ),
      );
    }

    final labels = pts.map((e) => e['bucket_label']?.toString() ?? e['bucket']?.toString() ?? '').toList();
    var maxY = 1.0;
    for (final row in pts) {
      final a = _parseNum(row['avg_purchase_base']);
      final b = _parseNum(row['avg_sale_base']);
      if (a != null && a > maxY) maxY = a;
      if (b != null && b > maxY) maxY = b;
    }

    List<FlSpot> spots(String field) {
      final out = <FlSpot>[];
      for (var i = 0; i < pts.length; i++) {
        final y = _parseNum(pts[i][field]);
        if (y != null) {
          out.add(FlSpot(i.toDouble(), y));
        }
      }
      return out;
    }

    final spotsP = spots('avg_purchase_base');
    final spotsS = spots('avg_sale_base');
    maxY *= 1.15;

    String laneLabel(LineBarSpot sp) {
      if (spotsP.isEmpty) return 'فروش';
      if (spotsS.isEmpty) return 'خرید';
      try {
        return sp.barIndex == 0 ? 'خرید' : 'فروش';
      } catch (_) {
        return '';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendRow(theme.colorScheme.tertiary, 'میانگین موزون خرید (پایه)'),
            const SizedBox(width: 16),
            _legendRow(theme.colorScheme.primary, 'میانگین موزون فروش (پایه)'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                horizontalInterval: maxY > 5 ? maxY / 4 : maxY / 2,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: theme.colorScheme.outline.withValues(alpha: 0.15), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    getTitlesWidget: (v, m) => Text(
                      formatWithThousands(v, decimalPlaces: _decimals()),
                      style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt().clamp(0, labels.length - 1);
                      final t = labels[i];
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Transform.rotate(
                          angle: labels.length > 8 ? -0.5 : 0,
                          child: Text(
                            t,
                            style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (pts.length - 1).toDouble().clamp(0, double.infinity),
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                if (spotsP.isNotEmpty)
                  LineChartBarData(
                    isCurved: true,
                    color: theme.colorScheme.tertiary,
                    barWidth: 2.5,
                    spots: spotsP,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, p, b, i) =>
                          FlDotCirclePainter(radius: 3, color: theme.colorScheme.tertiary),
                    ),
                    belowBarData: BarAreaData(show: true, color: theme.colorScheme.tertiary.withValues(alpha: 0.06)),
                  ),
                if (spotsS.isNotEmpty)
                  LineChartBarData(
                    isCurved: true,
                    color: theme.colorScheme.primary,
                    barWidth: 2.5,
                    spots: spotsS,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (s, p, b, i) =>
                          FlDotCirclePainter(radius: 3, color: theme.colorScheme.primary),
                    ),
                    belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withValues(alpha: 0.06)),
                  ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  tooltipMargin: 6,
                  getTooltipItems: (list) {
                    return list.map((spot) {
                      final idx = spot.x.round().clamp(0, pts.length - 1);
                      final bucket = pts[idx];
                      final isPur = laneLabel(spot) == 'خرید';
                      final qtyField = isPur ? 'purchase_qty' : 'sale_qty';
                      final qty = _parseNum(bucket[qtyField]);
                      final qStr = qty != null ? ' · مقدار ${formatWithThousands(qty, decimalPlaces: 3)}' : '';
                      return LineTooltipItem(
                        '${laneLabel(spot)}: ${_fmtMoney(spot.y)}$_currencySuffix()$qStr',
                        TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _partyBlock(String title, List<dynamic> raw) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (raw.isEmpty)
          Text('داده‌ای نیست', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))
        else
          ...raw.take(5).map((item) {
            if (item is! Map<String, dynamic>) return const SizedBox.shrink();
            final name = (item['name'] ?? '—').toString();
            final avg = _fmtMoney(_parseNum(item['avg_unit_price_base']));
            final q = _fmtQty(_parseNum(item['total_qty']));
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text('میانگین واحد به پایه: $avg  ·  مجموع مقدار: $q'),
            );
          }),
      ],
    );
  }

  Future<void> _pickCustomDate({required bool isStart}) async {
    final initial = isStart
        ? (_customFrom ?? _dateOnly(DateTime.now()).subtract(const Duration(days: 365)))
        : (_customTo ?? _dateOnly(DateTime.now()));
    final picked = await showAdaptiveDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _customFrom = _dateOnly(picked);
      } else {
        _customTo = _dateOnly(picked);
      }
      _preset = _Preset.custom;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    final eligible = _data['eligible'] == true;
    final meta = _data['meta'];
    final note = meta is Map<String, dynamic> ? (meta['note']?.toString() ?? '') : '';
    final totals = _data['totals'];
    final topSup = _data['top_suppliers'];
    final topBuy = _data['top_buyers'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _bucketChoices.containsKey(_bucket) ? _bucket : 'month',
                items: _bucketChoices.entries
                    .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) async {
                  if (v == null || v == _bucket) return;
                  setState(() => _bucket = v);
                  await _load();
                },
              ),
              DropdownButton<_Preset>(
                value: _preset,
                items: const [
                  DropdownMenuItem(value: _Preset.month1, child: Text('۳۰ روز')),
                  DropdownMenuItem(value: _Preset.month3, child: Text('۹۰ روز')),
                  DropdownMenuItem(value: _Preset.month6, child: Text('۶ ماه')),
                  DropdownMenuItem(value: _Preset.year, child: Text('یک سال')),
                  DropdownMenuItem(value: _Preset.custom, child: Text('سفارشی')),
                ],
                onChanged: (v) async {
                  if (v == null || v == _preset) return;
                  setState(() => _preset = v);
                  await _load();
                },
              ),
              if (_preset == _Preset.custom) ...[
                OutlinedButton.icon(
                  onPressed: () => _pickCustomDate(isStart: true),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _customFrom != null
                        ? DateFormatters.formatServerDate(_customFrom!.toIso8601String())
                        : 'از تاریخ',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickCustomDate(isStart: false),
                  icon: const Icon(Icons.event),
                  label: Text(
                    _customTo != null
                        ? DateFormatters.formatServerDate(_customTo!.toIso8601String())
                        : 'تا تاریخ',
                  ),
                ),
              ],
              IconButton.filledTonal(onPressed: _load, tooltip: 'بازنشانی', icon: const Icon(Icons.refresh)),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              note,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (!eligible) ...[
            const SizedBox(height: 24),
            Text(
              'این خلاصه برای این محصول یا پیکربندی کسب‌وکار در دسترس نیست.',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
            ),
          ] else ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _lastCard(
                        title: 'آخرین خرید',
                        payload: _data['last_purchase'] as Map<String, dynamic>?,
                        icon: Icons.shopping_cart_outlined,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(height: 12),
                      _lastCard(
                        title: 'آخرین فروش',
                        payload: _data['last_sale'] as Map<String, dynamic>?,
                        icon: Icons.point_of_sale_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: _lastCard(
                        title: 'آخرین خرید',
                        payload: _data['last_purchase'] as Map<String, dynamic>?,
                        icon: Icons.shopping_cart_outlined,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _lastCard(
                        title: 'آخرین فروش',
                        payload: _data['last_sale'] as Map<String, dynamic>?,
                        icon: Icons.point_of_sale_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (totals is Map<String, dynamic>) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('جمع در بازه', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _kv('مقدار خرید', _fmtQty(_parseNum(totals['purchase_qty']))),
                      _kv('مقدار فروش', _fmtQty(_parseNum(totals['sale_qty']))),
                      _kv('تعداد خطوط خرید', (totals['purchase_lines'] ?? '-').toString()),
                      _kv('تعداد خطوط فروش', (totals['sale_lines'] ?? '-').toString()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'روند میانگین موزون قیمت واحد (ارز پایه)',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _chart(),
            const SizedBox(height: 24),
            if (topSup is List<dynamic>) _partyBlock('تأمین‌کنندگان پرحجم در بازه', topSup),
            const SizedBox(height: 16),
            if (topBuy is List<dynamic>) _partyBlock('خریداران پرحجم در بازه', topBuy),
            const SizedBox(height: 16),
            _recentStrip(),
          ],
        ],
      ),
    );
  }

  Widget _recentStrip() {
    final raw = _data['recent_events'];
    if (raw is! List<dynamic> || raw.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final rows = raw.whereType<Map<String, dynamic>>().take(15).toList();
    return Card(
      child: ExpansionTile(
        title: Text(
          'رویدادهای اخیر (خطوط فاکتور)',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        children: rows
            .map(
              (e) => ListTile(
                dense: true,
                leading: Icon(
                  (e['lane']?.toString() == 'purchase') ? Icons.south_east_outlined : Icons.north_east_outlined,
                  size: 20,
                  color:
                      e['lane']?.toString() == 'purchase' ? theme.colorScheme.tertiary : theme.colorScheme.primary,
                ),
                title: Text(
                  '${(e['lane']?.toString() == 'purchase') ? 'خرید' : 'فروش'} '
                  '• ${DateFormatters.formatServerDate(e['document_date'])} • ${e['person_name'] ?? '—'}',
                  style: theme.textTheme.bodySmall,
                ),
                subtitle: Text(
                  '${e['document_code']} — ${_fmtQty(_parseNum(e['quantity']))} واحد؛ '
                  'قیمت واحد به پایه ${_fmtMoney(_parseNum(e['unit_price_base_currency']))}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
