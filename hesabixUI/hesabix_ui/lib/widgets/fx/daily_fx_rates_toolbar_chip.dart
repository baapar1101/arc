import 'package:hesabix_ui/theme/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/business_route_paths.dart';
import 'package:hesabix_ui/services/business_currency_rate_service.dart';
import 'package:hesabix_ui/services/business_fx_global_rate_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/number_formatters.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/multi_currency_gate.dart';

/// نوار ابزار نرخ ارز روز — فقط برای کسب‌وکار چندارزی.
///
/// نمایش فشرده آخرین نرخ‌ها + دیالوگ ثبت دستی / از اسنپ‌شات مرکزی.
class DailyFxRatesToolbarChip extends StatefulWidget {
  const DailyFxRatesToolbarChip({
    super.key,
    required this.businessId,
    required this.authStore,
    this.iconColor,
    this.iconOnly = false,
  });

  final int businessId;
  final AuthStore authStore;
  final Color? iconColor;

  /// در نوار فشردهٔ موبایل فقط آیکن + نقطهٔ تازگی، بدون متن نرخ.
  final bool iconOnly;

  @override
  State<DailyFxRatesToolbarChip> createState() => _DailyFxRatesToolbarChipState();
}

class _DailyFxRatesToolbarChipState extends State<DailyFxRatesToolbarChip> {
  late final BusinessCurrencyRateService _rateService;
  late final BusinessFxGlobalRateService _globalService;

  bool _loading = false;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic>? _base;
  DateTime? _loadedAt;
  String? _error;

  static const _cacheTtl = Duration(seconds: 45);

  @override
  void initState() {
    super.initState();
    _rateService = BusinessCurrencyRateService(ApiClient());
    _globalService = BusinessFxGlobalRateService(ApiClient());
    widget.authStore.addListener(_onAuthChanged);
    if (widget.authStore.isMultiCurrency) {
      _load(silent: true);
    }
  }

  @override
  void dispose() {
    widget.authStore.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (widget.authStore.isMultiCurrency) {
      _load(silent: true);
    } else {
      setState(() {
        _items = const [];
        _error = null;
      });
    }
  }

  bool get _cacheFresh {
    if (_loadedAt == null) return false;
    return DateTime.now().difference(_loadedAt!) < _cacheTtl;
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (!widget.authStore.isMultiCurrency) return;
    if (_loading) return;
    if (!force && _cacheFresh && _items.isNotEmpty) return;

    if (!silent) setState(() => _loading = true);
    try {
      final data = await _rateService.latest(businessId: widget.businessId);
      if (!mounted) return;
      final items = (data['items'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _items = items;
        _base = data['base_currency'] is Map
            ? Map<String, dynamic>.from(data['base_currency'] as Map)
            : null;
        _loadedAt = DateTime.now();
        _error = null;
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

  String _shortRate(dynamic raw) {
    if (raw == null) return '—';
    final policy = widget.authStore.currentBusiness?.fxRevaluationPolicy;
    final unit = policy?['rate_display_unit']?.toString();
    final baseCode = widget.authStore.currentBusiness?.defaultCurrency?.code;
    final s = formatFxRateForDisplay(
      raw,
      rateDisplayUnit: unit,
      baseCurrencyCode: baseCode,
    );
    // فشرده‌سازی نمایش‌های خیلی بلند
    final n = double.tryParse(s.replaceAll(',', ''));
    if (n == null) return s;
    if (n >= 1000000) {
      final m = n / 1000000;
      return '${m.toStringAsFixed(m >= 10 ? 1 : 2)}M';
    }
    if (n >= 1000) {
      return formatWithThousands(n, decimalPlaces: n >= 10000 ? 0 : 1);
    }
    return s;
  }

  Color _freshnessColor(ThemeData theme) {
    if (_items.isEmpty) return theme.colorScheme.outline;
    final ages = _items
        .map((e) => (e['age_hours'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    if (ages.isEmpty) return theme.colorScheme.error;
    final maxAge = ages.reduce((a, b) => a > b ? a : b);
    if (maxAge <= 6) return const Color(0xFF2E7D32);
    if (maxAge <= 24) return const Color(0xFFF9A825);
    return theme.colorScheme.error;
  }

  String _summaryLabel() {
    if (_loading && _items.isEmpty) return 'نرخ…';
    if (_error != null && _items.isEmpty) return 'نرخ!';
    if (_items.isEmpty) return 'نرخ ارز';
    final parts = <String>[];
    for (final it in _items.take(3)) {
      final code = '${it['currency_code'] ?? ''}';
      final rate = _shortRate(it['rate']);
      if (code.isEmpty) continue;
      parts.add('$code $rate');
    }
    if (parts.isEmpty) return 'نرخ ارز';
    final more = _items.length > 3 ? ' +${_items.length - 3}' : '';
    return '${parts.join(' · ')}$more';
  }

  Future<void> _openSheet() async {
    await _load(force: true);
    if (!mounted) return;
    await showGlassModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return _FxRatesSheet(
          businessId: widget.businessId,
          authStore: widget.authStore,
          items: _items,
          base: _base,
          rateService: _rateService,
          globalService: _globalService,
          onChanged: () => _load(force: true),
        );
      },
    );
    if (mounted) await _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return MultiCurrencyGate(
      isMultiCurrency: widget.authStore.isMultiCurrency,
      child: AnimatedBuilder(
        animation: widget.authStore,
        builder: (context, _) {
          if (!widget.authStore.isMultiCurrency) {
            return const SizedBox.shrink();
          }
          final theme = Theme.of(context);
          final fg = widget.iconColor ?? theme.colorScheme.onSurface;
          final dot = _freshnessColor(theme);
          final missing = _items.where((e) => e['missing'] == true).length;
          final tooltip = missing > 0
              ? 'نرخ روز — $missing ارز بدون نرخ'
              : widget.iconOnly
                  ? '${_summaryLabel()} — نرخ روز ارزهای فرعی'
                  : 'نرخ روز ارزهای فرعی';

          Widget freshnessDot({double size = 7}) {
            return Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dot.withValues(alpha: 0.45),
                    blurRadius: 4,
                  ),
                ],
              ),
            );
          }

          if (widget.iconOnly) {
            return IconButton(
              tooltip: tooltip,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                minimumSize: const Size(38, 38),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _openSheet,
              icon: SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.currency_exchange, size: 21, color: fg.withValues(alpha: 0.95)),
                    PositionedDirectional(
                      top: -1,
                      end: -1,
                      child: _loading
                          ? SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.4,
                                color: fg.withValues(alpha: 0.7),
                              ),
                            )
                          : freshnessDot(size: 7),
                    ),
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Tooltip(
              message: tooltip,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _openSheet,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: fg.withValues(alpha: 0.22)),
                      color: fg.withValues(alpha: 0.06),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        freshnessDot(),
                        const SizedBox(width: 7),
                        Icon(Icons.currency_exchange, size: 16, color: fg.withValues(alpha: 0.9)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _summaryLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                              height: 1.1,
                            ),
                          ),
                        ),
                        if (_loading) ...[
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: fg.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FxRatesSheet extends StatefulWidget {
  const _FxRatesSheet({
    required this.businessId,
    required this.authStore,
    required this.items,
    required this.base,
    required this.rateService,
    required this.globalService,
    required this.onChanged,
  });

  final int businessId;
  final AuthStore authStore;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic>? base;
  final BusinessCurrencyRateService rateService;
  final BusinessFxGlobalRateService globalService;
  final VoidCallback onChanged;

  @override
  State<_FxRatesSheet> createState() => _FxRatesSheetState();
}

class _FxRatesSheetState extends State<_FxRatesSheet> {
  late List<Map<String, dynamic>> _items;
  final Map<int, TextEditingController> _controllers = {};
  bool _saving = false;
  bool _applyingGlobal = false;

  @override
  void initState() {
    super.initState();
    _items = widget.items.map((e) => Map<String, dynamic>.from(e)).toList();
    for (final it in _items) {
      final id = (it['currency_id'] as num?)?.toInt();
      if (id == null) continue;
      _controllers[id] = TextEditingController(
        text: it['rate'] == null ? '' : formatFxRateForDisplay(it['rate']),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveManual() async {
    final canAdd = widget.authStore.hasBusinessPermission('currency_revaluation', 'add');
    if (!canAdd) {
      SnackBarHelper.showError(context, message: 'مجوز ثبت نرخ ندارید');
      return;
    }
    final payloadItems = <Map<String, dynamic>>[];
    for (final it in _items) {
      final id = (it['currency_id'] as num?)?.toInt();
      if (id == null) continue;
      final raw = _controllers[id]?.text.trim() ?? '';
      if (raw.isEmpty) continue;
      final rate = parseFormattedDouble(raw);
      if (rate == null || rate <= 0) {
        SnackBarHelper.showError(context, message: 'نرخ ${it['currency_code']} نامعتبر است');
        return;
      }
      payloadItems.add({'currency_id': id, 'rate': rate});
    }
    if (payloadItems.isEmpty) {
      SnackBarHelper.showError(context, message: 'حداقل یک نرخ وارد کنید');
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await widget.rateService.bulkCreate(
        widget.businessId,
        {'items': payloadItems, 'note': 'ثبت از نوار ابزار نرخ روز'},
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: '${res['count'] ?? payloadItems.length} نرخ ثبت شد');
      widget.onChanged();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyFromGlobal() async {
    final canAdd = widget.authStore.hasBusinessPermission('currency_revaluation', 'add');
    if (!canAdd) {
      SnackBarHelper.showError(context, message: 'مجوز ثبت نرخ ندارید');
      return;
    }
    setState(() => _applyingGlobal = true);
    try {
      final latest = await widget.globalService.latest(businessId: widget.businessId);
      final globalItems = (latest['items'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (globalItems.isEmpty) {
        if (!mounted) return;
        SnackBarHelper.showError(
          context,
          message: 'اسنپ‌شات مرکزی خالی است. از مدیریت کل، واکشی نرخ را انجام دهید.',
        );
        return;
      }
      if (latest['stale'] == true && mounted) {
        final age = latest['max_age_hours'];
        final cont = await showGlassDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('اسنپ‌شات قدیمی'),
            content: Text(
              'آخرین واکشی مرکزی حدود ${age ?? '—'} ساعت پیش بوده است. ادامه می‌دهید؟',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ادامه')),
            ],
          ),
        );
        if (cont != true) return;
      }
      final applyItems = <Map<String, dynamic>>[
        for (final g in globalItems)
          if (g['business_currency_id'] != null)
            {
              'currency_id': g['business_currency_id'],
              'symbol': g['symbol'],
            },
      ];
      final res = await widget.globalService.applyFromGlobal(
        businessId: widget.businessId,
        items: applyItems,
        note: 'از نرخ روز (نوار ابزار)',
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: '${res['count'] ?? applyItems.length} نرخ از اسنپ‌شات ثبت شد');
      widget.onChanged();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _applyingGlobal = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseCode = '${widget.base?['code'] ?? 'پایه'}';
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'نرخ روز ارز',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '۱ واحد ارز فرعی = نرخ × $baseCode',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ثبت دستی یا دریافت از اسنپ‌شات مرکزی نرخ روز',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'صفحه تاریخچه نرخ‌ها',
                      onPressed: () {
                        Navigator.pop(context);
                        final path = BusinessRoutePaths.uri(
                          widget.businessId,
                          0,
                          'currency-revaluation',
                        );
                        context.go(path);
                      },
                      icon: const Icon(Icons.open_in_new),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final it = _items[index];
                    final id = (it['currency_id'] as num?)?.toInt();
                    final missing = it['missing'] == true;
                    final age = (it['age_hours'] as num?)?.toDouble();
                    final note = (it['note'] ?? '').toString().trim();
                    final effectiveAtRaw = it['effective_at'];
                    String? effectiveLabel;
                    if (effectiveAtRaw != null) {
                      final dt = DateTime.tryParse(effectiveAtRaw.toString());
                      if (dt != null) {
                        final local = dt.toLocal();
                        effectiveLabel =
                            '${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}'
                            ' ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
                      }
                    }
                    String sourceLabel = 'ثبت‌شده';
                    if (note.contains('اسنپ') || note.contains('نرخ روز') || note.contains('global') || note.contains('auto')) {
                      sourceLabel = 'از اسنپ‌شات / همگام‌سازی';
                    } else if (note.contains('نوار ابزار') || note.contains('دستی') || note.isNotEmpty) {
                      sourceLabel = note.length > 42 ? '${note.substring(0, 42)}…' : (note.isEmpty ? 'ثبت دستی' : note);
                    }
                    final ctrl = id != null ? _controllers[id] : null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: missing
                              ? theme.colorScheme.error.withValues(alpha: 0.35)
                              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${it['currency_code'] ?? ''}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${it['currency_title'] ?? ''}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (missing)
                                  Chip(
                                    label: const Text('بدون نرخ'),
                                    visualDensity: VisualDensity.compact,
                                    labelStyle: TextStyle(
                                      color: theme.colorScheme.error,
                                      fontSize: 11,
                                    ),
                                    backgroundColor: theme.colorScheme.error.withValues(alpha: 0.1),
                                    side: BorderSide.none,
                                    padding: EdgeInsets.zero,
                                  )
                                else if (age != null)
                                  Text(
                                    age < 1
                                        ? 'تازه'
                                        : age < 24
                                            ? '${age.toStringAsFixed(0)}س'
                                            : '${(age / 24).toStringAsFixed(1)}روز',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                            if (!missing) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (effectiveLabel != null)
                                    Text(
                                      'مؤثر از: $effectiveLabel',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  Text(
                                    sourceLabel,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 10),
                            TextField(
                              controller: ctrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                EnglishDigitsFormatter(),
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                              ],
                              decoration: InputDecoration(
                                labelText: 'نرخ به $baseCode',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                suffixText: baseCode,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving || _applyingGlobal ? null : _applyFromGlobal,
                          icon: _applyingGlobal
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                          label: const Text('از نرخ روز'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _saving || _applyingGlobal ? null : _saveManual,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('ثبت نرخ‌ها'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
