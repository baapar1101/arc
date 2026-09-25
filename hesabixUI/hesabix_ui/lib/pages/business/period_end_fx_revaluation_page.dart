import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/business_subpage_back_leading.dart';
import 'package:hesabix_ui/widgets/multi_currency_gate.dart';

/// تسعیر پایان دوره — پیش‌نمایش و ایجاد سند تعدیلی (نقدی / اشخاص / چک).
class PeriodEndFxRevaluationPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const PeriodEndFxRevaluationPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<PeriodEndFxRevaluationPage> createState() =>
      _PeriodEndFxRevaluationPageState();
}

class _PeriodEndFxRevaluationPageState extends State<PeriodEndFxRevaluationPage> {
  final _api = ApiClient();
  bool _loading = false;
  bool _creating = false;
  Map<String, dynamic>? _preview;

  bool get _canAdd =>
      widget.authStore.hasBusinessPermission('currency_revaluation', 'add');

  static const _kindLabels = <String, String>{
    'bank': 'بانک',
    'cash_register': 'صندوق',
    'petty_cash': 'تنخواه',
    'person': 'اشخاص',
    'check': 'چک',
  };

  static const _kindOrder = <String>[
    'bank',
    'cash_register',
    'petty_cash',
    'person',
    'check',
  ];

  Future<void> _loadPreview() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/period-end-fx-revaluation/preview',
      );
      final data = res.data?['data'] ?? res.data;
      setState(() {
        _preview = data is Map ? Map<String, dynamic>.from(data) : null;
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createDocument() async {
    if (!_canAdd) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ایجاد سند تسعیر'),
        content: const Text(
          'یک سند دستی تعدیلی برای سود/زیان تسعیر تحقق‌نیافته ایجاد می‌شود. '
          'مانده بومی ارز تغییر نمی‌کند. ادامه می‌دهید؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ایجاد'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _creating = true);
    try {
      final res = await _api.post<Map<String, dynamic>>(
        '/api/v1/businesses/${widget.businessId}/period-end-fx-revaluation',
        data: {},
      );
      final data = res.data?['data'] ?? res.data;
      final doc = data is Map ? data['document'] : null;
      final code = doc is Map ? doc['code']?.toString() : null;
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: code != null
              ? 'سند تسعیر $code ایجاد شد'
              : 'سند تسعیر ایجاد شد',
        );
        await _loadPreview();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: ErrorExtractor.forContext(e, context),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.authStore.isMultiCurrency) {
      _loadPreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('تسعیر پایان دوره'),
        leading: businessSubpageBackLeading(context, widget.businessId),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadPreview,
            icon: const Icon(Icons.refresh),
            tooltip: 'بازخوانی',
          ),
        ],
      ),
      body: MultiCurrencyGate(
        isMultiCurrency: widget.authStore.isMultiCurrency,
        singleCurrencyChild: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'این بخش فقط برای کسب‌وکارهای چندارزی فعال است.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        child: _loading && _preview == null
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(theme),
      ),
      floatingActionButton: widget.authStore.isMultiCurrency && _canAdd
          ? FloatingActionButton.extended(
              onPressed: _creating || _loading ? null : _createDocument,
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.post_add),
              label: const Text('ایجاد سند تسعیر'),
            )
          : null,
    );
  }

  Widget _buildBody(ThemeData theme) {
    final p = _preview;
    if (p == null) {
      return const Center(child: Text('پیش‌نمایش در دسترس نیست'));
    }
    final positions = (p['positions'] as List?) ?? const [];
    final base = p['base_currency'] is Map
        ? Map<String, dynamic>.from(p['base_currency'] as Map)
        : <String, dynamic>{};
    final baseCode = base['code']?.toString() ?? 'پایه';

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final raw in positions) {
      final row = Map<String, dynamic>.from(raw as Map);
      final kind = row['kind']?.toString() ?? 'other';
      grouped.putIfAbsent(kind, () => []).add(row);
    }

    final orderedKinds = [
      ..._kindOrder.where(grouped.containsKey),
      ...grouped.keys.where((k) => !_kindOrder.contains(k)),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'مانده‌های پولی ارزی (بانک / صندوق / تنخواه / اشخاص / چک) با نرخ روز به $baseCode مقایسه می‌شوند. '
          'موجودی بومی ارز تغییر نمی‌کند؛ فقط ارزش دفتری پایه تعدیل می‌شود.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _chip(
              theme,
              'اقلام قابل تعدیل',
              '${p['adjustable_count'] ?? 0}',
            ),
            _chip(
              theme,
              'سود تحقق‌نیافته',
              formatWithThousands(
                num.tryParse('${p['total_unrealized_gain_base']}') ?? 0,
                decimalPlaces: 0,
              ),
            ),
            _chip(
              theme,
              'زیان تحقق‌نیافته',
              formatWithThousands(
                num.tryParse('${p['total_unrealized_loss_base']}') ?? 0,
                decimalPlaces: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (positions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'مانده ارزی باز برای تسعیر یافت نشد.',
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          )
        else
          ...orderedKinds.expand((kind) {
            final rows = grouped[kind] ?? const [];
            final label = _kindLabels[kind] ?? kind;
            return [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  '$label (${rows.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...rows.map((row) => _positionTile(theme, row)),
            ];
          }),
        const SizedBox(height: 72),
      ],
    );
  }

  Widget _positionTile(ThemeData theme, Map<String, dynamic> row) {
    final skipped = row['skipped'] == true;
    final err = row['error']?.toString();
    final adj = num.tryParse('${row['adjustment_base']}') ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(row['name']?.toString() ?? ''),
        subtitle: Text(
          [
            '${row['currency_code'] ?? row['currency_id']}',
            'مانده بومی: ${formatWithThousands(num.tryParse('${row['native_balance']}') ?? 0, decimalPlaces: 2)}',
            if (err != null) 'خطا: $err',
            if (row['needs_backfill_warning'] == true)
              'هشدار: ارزش دفتری پایه ناقص است — ابتدا backfill پایه را اجرا کنید',
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: Text(
          skipped ? 'بدون تعدیل' : formatWithThousands(adj, decimalPlaces: 0),
          style: theme.textTheme.titleSmall?.copyWith(
            color: skipped
                ? theme.colorScheme.outline
                : (adj >= 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}
