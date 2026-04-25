import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/permission_guard.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_currency_rate_service.dart';
import 'package:hesabix_ui/services/currency_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/widgets/date_input_field.dart';

/// مدیریت تاریخچه نرخ تسعیر ارزهای فعال نسبت به ارز اصلی؛ چند نرخ در یک روز با زمان مؤثر متفاوت مجاز است.
class CurrencyRevaluationPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const CurrencyRevaluationPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<CurrencyRevaluationPage> createState() => _CurrencyRevaluationPageState();
}

class _CurrencyRevaluationPageState extends State<CurrencyRevaluationPage> {
  late final BusinessCurrencyRateService _service;
  late final CurrencyService _currencyService;
  static final _dtFmt = DateFormat('yyyy-MM-dd HH:mm');
  int _listVersion = 0;

  bool get _canAdd => widget.authStore.hasBusinessPermission('currency_revaluation', 'add');
  bool get _canEdit => widget.authStore.hasBusinessPermission('currency_revaluation', 'edit');
  bool get _canDelete => widget.authStore.hasBusinessPermission('currency_revaluation', 'delete');

  List<Map<String, dynamic>> _secondaryCurrencies = [];
  int? _filterCurrencyId;

  @override
  void initState() {
    super.initState();
    _service = BusinessCurrencyRateService(ApiClient());
    _currencyService = CurrencyService(ApiClient());
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    try {
      final list = await _currencyService.listBusinessCurrencies(businessId: widget.businessId);
      final secondary = <Map<String, dynamic>>[];
      for (final c in list) {
        if (c['is_default'] != true) {
          secondary.add(c);
        }
      }
      if (mounted) {
        setState(() => _secondaryCurrencies = secondary);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'بارگذاری ارزها: ${ErrorExtractor.forContext(e, context)}',
        );
      }
    }
  }

  void _bumpListVersion() {
    if (mounted) {
      setState(() => _listVersion++);
    }
  }

  String _formatEffective(dynamic v) {
    if (v == null) return '—';
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d == null) return v;
      return _dtFmt.format(d.toLocal());
    }
    return '$v';
  }

  DateTime? _parseEffective(Map<String, dynamic> row) {
    final v = row['effective_at'];
    if (v is String) {
      return DateTime.tryParse(v);
    }
    return null;
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  Future<void> _openEdit({Map<String, dynamic>? row}) async {
    if (row == null && !_canAdd) return;
    if (row != null && !_canEdit) return;
    if (_secondaryCurrencies.isEmpty) {
      if (mounted) {
        SnackBarHelper.showError(
          context,
          message: 'ابتدا از تنظیمات کسب‌وکار، ارزهای جانبی به کسب‌وکار اضافه کنید.',
        );
      }
      return;
    }

    int? curId;
    if (row != null) {
      final x = row['currency_id'] ?? (row['currency'] is Map ? (row['currency'] as Map)['id'] : null);
      if (x is int) {
        curId = x;
      } else {
        curId = int.tryParse('$x');
      }
    } else {
      curId = _toInt(_secondaryCurrencies.first['id']);
    }
    var effective = _parseEffective(row ?? {}) ?? DateTime.now();
    final rateCtrl = TextEditingController(
      text: row != null && row['rate'] != null
          ? formatFxRateForDisplay(row['rate'])
          : '',
    );
    final noteCtrl = TextEditingController(
      text: row != null && row['note'] != null ? '${row['note']}' : '',
    );

    if (!context.mounted) return;
    final t = AppLocalizations.of(context);
    final cal = widget.calendarController;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(row == null ? t.add : t.edit),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '۱ واحد ارز = نرخ × ۱ واحد از ارز اصلی کسب‌وکار',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: curId,
                      items: _secondaryCurrencies
                          .map(
                            (c) => DropdownMenuItem<int>(
                              value: _toInt(c['id']),
                              child: Text('${c['code'] ?? c['name']} — ${c['title'] ?? ''}'),
                            ),
                          )
                          .toList(),
                      onChanged: row != null
                          ? null
                          : (v) {
                              setLocal(() {
                                curId = v;
                              });
                            },
                      decoration: const InputDecoration(
                        labelText: 'ارز',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DateInputField(
                      calendarController: cal,
                      value: effective,
                      labelText: 'تاریخ مؤثر',
                      hintText: 'انتخاب تاریخ',
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      onChanged: (d) {
                        if (d == null) return;
                        setLocal(() {
                          effective = DateTime(
                            d.year,
                            d.month,
                            d.day,
                            effective.hour,
                            effective.minute,
                            effective.second,
                            effective.millisecond,
                            effective.microsecond,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: const Text('ساعت مؤثر'),
                      subtitle: Text(
                        TimeOfDay.fromDateTime(effective).format(ctx),
                      ),
                      onTap: () async {
                        final tm = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(effective),
                        );
                        if (tm == null) return;
                        setLocal(() {
                          effective = DateTime(
                            effective.year,
                            effective.month,
                            effective.day,
                            tm.hour,
                            tm.minute,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: rateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'نرخ',
                        hintText: 'مثال: 58,500.25',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: const [
                        NumberInputFormatter(allowDecimal: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'یادداشت (اختیاری)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(t.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(t.save),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    if (curId == null) {
      SnackBarHelper.showError(context, message: 'ارز را انتخاب کنید');
      return;
    }
    final rateStr = rateCtrl.text.trim();
    if (rateStr.isEmpty) {
      SnackBarHelper.showError(context, message: 'نرخ را وارد کنید');
      return;
    }
    final rateNum = parseFormattedNumber(rateStr);
    if (rateNum == null) {
      SnackBarHelper.showError(context, message: 'نرخ معتبر نیست');
      return;
    }
    final body = <String, dynamic>{
      'currency_id': curId,
      'effective_at': effective.toUtc().toIso8601String(),
      'rate': rateNum.toString(),
      if (noteCtrl.text.trim().isNotEmpty) 'note': noteCtrl.text.trim(),
    };
    try {
      if (row == null) {
        await _service.create(widget.businessId, body);
        if (mounted) SnackBarHelper.show(context, message: 'ثبت شد');
      } else {
        final id = _toInt(row['id']);
        if (id == null) return;
        await _service.update(widget.businessId, id, body);
        if (mounted) SnackBarHelper.show(context, message: 'ذخیره شد');
      }
      _bumpListVersion();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    if (!_canDelete) return;
    final id = _toInt(row['id']);
    if (id == null) return;
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.delete),
        content: const Text('این نرخ حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.delete)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await _service.delete(widget.businessId, id);
      if (mounted) SnackBarHelper.show(context, message: 'حذف شد');
      _bumpListVersion();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (!widget.authStore.hasBusinessPermission('currency_revaluation', 'view')) {
      return PermissionGuard.buildAccessDeniedPage();
    }
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _secondaryCurrencies.isEmpty
                  ? Text(
                      'ارز جانبی فعال نیست. از تنظیمات کسب‌وکار، ارز اضافه کنید.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            value: _filterCurrencyId,
                            decoration: const InputDecoration(
                              labelText: 'فیلتر ارز',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text('همه'),
                              ),
                              ..._secondaryCurrencies.map(
                                (c) => DropdownMenuItem<int?>(
                                  value: _toInt(c['id']),
                                  child: Text('${c['code'] ?? c['name'] ?? c['id']}'),
                                ),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _filterCurrencyId = v;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: DataTableWidget<Map<String, dynamic>>(
              key: ValueKey('crr_${_filterCurrencyId ?? 'all'}_$_listVersion'),
              config: DataTableConfig<Map<String, dynamic>>(
                tableId: 'currency_revaluation_rates',
                endpoint: '/api/v1/businesses/${widget.businessId}/currency-rates',
                httpMethod: 'GET',
                pageSizeQueryParam: 'take',
                title: t.currencyRevaluation,
                subtitle: '۱ واحد ارز = نرخ × ۱ واحد ارز اصلی کسب‌وکار',
                showBackButton: true,
                onBack: () {
                  if (context.canPop()) {
                    context.pop();
                  }
                },
                showTableIcon: true,
                showSearch: false,
                enableGlobalSearch: false,
                showExportButtons: false,
                showColumnSettingsButton: false,
                enableColumnSettings: false,
                showRefreshButton: true,
                enableSorting: false,
                showColumnSearch: false,
                defaultPageSize: 20,
                additionalParams: {
                  if (_filterCurrencyId != null) 'currency_id': _filterCurrencyId,
                },
                customHeaderActions: [
                  if (_canAdd)
                    IconButton(
                      onPressed: () {
                        _openEdit();
                      },
                      icon: const Icon(Icons.add),
                      tooltip: t.add,
                    ),
                ],
                columns: [
                  TextColumn(
                    'effective_at',
                    'زمان مؤثر',
                    sortable: false,
                    searchable: false,
                    width: ColumnWidth.large,
                    formatter: (r) => _formatEffective(r['effective_at']),
                  ),
                  TextColumn(
                    'currency',
                    'ارز',
                    sortable: false,
                    searchable: false,
                    width: ColumnWidth.small,
                    formatter: (r) {
                      final c = r['currency'];
                      if (c is Map) {
                        return '${c['code'] ?? c['id'] ?? ''}';
                      }
                      return '${r['currency_id'] ?? '—'}';
                    },
                  ),
                  TextColumn(
                    'rate',
                    'نرخ به پایه',
                    sortable: false,
                    searchable: false,
                    width: ColumnWidth.medium,
                    formatter: (r) =>
                        r['rate'] == null ? '—' : formatFxRateForDisplay(r['rate']),
                  ),
                  TextColumn(
                    'note',
                    'یادداشت',
                    sortable: false,
                    searchable: true,
                    width: ColumnWidth.large,
                    formatter: (r) => r['note']?.toString() ?? '',
                  ),
                  ActionColumn(
                    'actions',
                    t.actions,
                    sortable: false,
                    showOnHover: false,
                    actions: [
                      if (_canEdit)
                        DataTableAction(
                          icon: Icons.edit_outlined,
                          label: t.edit,
                          onTap: (it) {
                            if (it is Map<String, dynamic>) {
                              _openEdit(row: it);
                            }
                          },
                        ),
                      if (_canDelete)
                        DataTableAction(
                          icon: Icons.delete_outline,
                          label: t.delete,
                          isDestructive: true,
                          onTap: (it) {
                            if (it is Map<String, dynamic>) {
                              _confirmDelete(it);
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
              fromJson: (m) => m,
              calendarController: widget.calendarController,
            ),
          ),
        ],
      ),
    );
  }
}
