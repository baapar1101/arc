import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart' as Hd;
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/models/business_user_model.dart';
import 'package:hesabix_ui/services/business_user_service.dart';
import 'package:hesabix_ui/services/distribution_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/distribution/distribution_ui_helpers.dart';
import 'package:hesabix_ui/widgets/jalali_date_picker.dart';

/// مدیریت هدف فروش ویزیتورها (داخل تب مدیریت).
class DistributionTargetsSection extends StatefulWidget {
  final int businessId;
  final DistributionService service;
  final CalendarController calendarController;

  const DistributionTargetsSection({
    super.key,
    required this.businessId,
    required this.service,
    required this.calendarController,
  });

  @override
  State<DistributionTargetsSection> createState() => _DistributionTargetsSectionState();
}

class _DistributionTargetsSectionState extends State<DistributionTargetsSection> {
  List<dynamic> _items = [];
  bool _loading = false;

  bool get _jalali => widget.calendarController.isJalali;

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final items = await widget.service.listTargets(businessId: widget.businessId);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _showCreate() async {
    final t = AppLocalizations.of(context);
    int? userId;
    String periodType = 'month';
    String metric = 'amount';
    DateTime periodStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final amountCtl = TextEditingController();
    List<BusinessUser> users = const [];
    try {
      users = (await BusinessUserService(ApiClient()).getBusinessUsers(widget.businessId)).users;
    } catch (_) {}

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(t.distributionTargetCreate),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: userId,
                  decoration: InputDecoration(
                    labelText: t.distributionSelectVisitor,
                    border: const OutlineInputBorder(),
                  ),
                  items: users
                      .map(
                        (u) => DropdownMenuItem(
                          value: u.userId,
                          child: Text(u.userName.isNotEmpty ? u.userName : '${u.userId}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => userId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: periodType,
                  decoration: InputDecoration(
                    labelText: t.distributionTargetPeriodType,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'day', child: Text(t.distributionTargetPeriodDay)),
                    DropdownMenuItem(value: 'month', child: Text(t.distributionTargetPeriodMonth)),
                  ],
                  onChanged: (v) => setD(() {
                    periodType = v ?? 'month';
                    if (periodType == 'month') {
                      periodStart = DateTime(periodStart.year, periodStart.month, 1);
                    }
                  }),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: metric,
                  decoration: InputDecoration(
                    labelText: t.distributionTargetMetric,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'amount', child: Text(t.distributionMetricAmount)),
                    DropdownMenuItem(value: 'visits', child: Text(t.distributionMetricVisits)),
                    DropdownMenuItem(value: 'sku_qty', child: Text(t.distributionMetricSkuQty)),
                    DropdownMenuItem(value: 'coverage_pct', child: Text(t.distributionMetricCoverage)),
                  ],
                  onChanged: (v) => setD(() => metric = v ?? 'amount'),
                ),
                ListTile(
                  title: Text(Hd.HesabixDateUtils.formatForDisplay(periodStart, _jalali)),
                  subtitle: Text(t.distributionSelectDate),
                  onTap: () async {
                    final d = await showAdaptiveDatePicker(
                      context: context,
                      calendarController: widget.calendarController,
                      initialDate: periodStart,
                    );
                    if (d != null) {
                      setD(() {
                        periodStart = periodType == 'month' ? DateTime(d.year, d.month, 1) : d;
                      });
                    }
                  },
                ),
                TextField(
                  controller: amountCtl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: metric == 'amount'
                        ? t.distributionTargetAmount
                        : t.distributionTargetValue,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: userId == null
                  ? null
                  : () async {
                      try {
                        await widget.service.upsertTarget(
                          businessId: widget.businessId,
                          payload: {
                            'user_id': userId,
                            'period_type': periodType,
                            'period_start': _iso(periodStart),
                            'metric': metric,
                            'target_amount': double.tryParse(amountCtl.text.trim()) ?? 0,
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _reload();
                        if (mounted) {
                          SnackBarHelper.showSuccess(context, message: t.distributionSettingsSaved);
                        }
                      } catch (e) {
                        if (mounted) {
                          SnackBarHelper.showError(
                            context,
                            message: ErrorExtractor.forContext(e, context),
                          );
                        }
                      }
                    },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Text(t.distributionTargetsTitle, style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _showCreate,
                icon: const Icon(Icons.flag_outlined),
                label: Text(t.distributionTargetCreate),
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(t.distributionTargetsEmpty),
          )
        else
          ..._items.map((raw) {
            final m = Map<String, dynamic>.from(raw as Map);
            final pct = m['achievement_percent'];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.flag),
                title: Text(m['user_name']?.toString() ?? 'user ${m['user_id']}'),
                subtitle: Text(
                  '${distributionPeriodTypeLabel(t, m['period_type']?.toString())}'
                  ' · ${m['metric'] ?? 'amount'}'
                  ' · ${m['period_start']} → ${m['period_end']}\n'
                  '${t.distributionTargetAmount}: ${m['target_amount']} · '
                  '${t.distributionSalesLinked}: ${m['actual_amount'] ?? 0}'
                  '${pct != null ? ' ($pct%)' : ''}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final id = int.tryParse('${m['id']}');
                    if (id == null) return;
                    try {
                      await widget.service.deleteTarget(
                        businessId: widget.businessId,
                        targetId: id,
                      );
                      await _reload();
                    } catch (e) {
                      if (mounted) {
                        SnackBarHelper.showError(
                          context,
                          message: ErrorExtractor.forContext(e, context),
                        );
                      }
                    }
                  },
                ),
              ),
            );
          }),
      ],
    );
  }
}
