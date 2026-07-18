import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/auth_store.dart';
import 'package:hesabix_ui/core/permission_guard.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/business_fx_auto_sync_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/widgets/business_subpage_back_leading.dart';
import 'package:hesabix_ui/widgets/multi_currency_gate.dart';

/// زمان‌بندی خودکار ثبت نرخ تسعیر از اسنپ‌شات مرکزی + آفست per ارز.
class FxAutoSyncSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const FxAutoSyncSettingsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<FxAutoSyncSettingsPage> createState() => _FxAutoSyncSettingsPageState();
}

class _CurrencyRuleDraft {
  _CurrencyRuleDraft({
    required this.currencyId,
    required this.code,
    required this.title,
    this.enabled = true,
    this.offsetType = 'none',
    this.offsetDirection = 'up',
    this.offsetValue = '0',
  });

  final int currencyId;
  final String code;
  final String title;
  bool enabled;
  String offsetType;
  String offsetDirection;
  String offsetValue;
  String? referenceRate;
  String? finalRate;
  String? previewStatus;
  String? previewMessage;
}

class _FxAutoSyncSettingsPageState extends State<FxAutoSyncSettingsPage> {
  final _svc = BusinessFxAutoSyncService(ApiClient());

  bool _loading = true;
  bool _saving = false;
  bool _running = false;
  bool _previewing = false;

  bool _enabled = false;
  String _scheduleMode = 'interval';
  int _intervalHours = 6;
  List<int> _allowedIntervals = const [1, 2, 3, 6, 12, 24];
  final List<String> _dailyTimes = [];
  final _newTimeController = TextEditingController();
  bool _skipIfUnchanged = true;
  final _minChangeController = TextEditingController(text: '0.01');
  bool _blockIfStale = true;
  final _staleHoursController = TextEditingController(text: '24');
  String? _timezone;
  String? _lastRunAt;
  String? _lastRunStatus;
  String? _lastRunMessage;
  String? _nextRunAt;
  String? _previewWarning;

  final List<_CurrencyRuleDraft> _rules = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newTimeController.dispose();
    _minChangeController.dispose();
    _staleHoursController.dispose();
    super.dispose();
  }

  bool get _canEdit =>
      widget.authStore.hasBusinessPermission('currency_revaluation', 'add') ||
      widget.authStore.hasBusinessPermission('settings', 'business');

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.getSettings(businessId: widget.businessId);
      _applySettings(data);
      await _refreshPreview(silent: true);
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: t.fxAutoSyncLoadError(ErrorExtractor.forContext(e, context)),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySettings(Map<String, dynamic> data) {
    _enabled = data['enabled'] == true;
    _scheduleMode = (data['schedule_mode'] as String?) ?? 'interval';
    _intervalHours = (data['interval_hours'] as num?)?.toInt() ?? 6;
    final allowed = data['allowed_interval_hours'];
    if (allowed is List && allowed.isNotEmpty) {
      _allowedIntervals = allowed.map((e) => (e as num).toInt()).toList()..sort();
    }
    _dailyTimes
      ..clear()
      ..addAll(
        ((data['daily_times'] as List?) ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty),
      );
    _skipIfUnchanged = data['skip_if_unchanged'] != false;
    _minChangeController.text = '${data['min_change_percent'] ?? '0.01'}';
    _blockIfStale = data['block_if_stale'] != false;
    _staleHoursController.text = '${data['stale_after_hours'] ?? 24}';
    _timezone = data['timezone'] as String?;
    _lastRunAt = data['last_run_at']?.toString();
    _lastRunStatus = data['last_run_status'] as String?;
    _lastRunMessage = data['last_run_message'] as String?;
    _nextRunAt = data['next_run_at']?.toString();

    _rules.clear();
    final rawRules = (data['rules'] as List?) ?? const [];
    for (final raw in rawRules) {
      if (raw is! Map) continue;
      final cur = raw['currency'];
      final code = cur is Map ? (cur['code']?.toString() ?? '') : '';
      final title = cur is Map ? (cur['title']?.toString() ?? code) : code;
      final cid = (raw['currency_id'] as num?)?.toInt();
      if (cid == null) continue;
      _rules.add(
        _CurrencyRuleDraft(
          currencyId: cid,
          code: code,
          title: title,
          enabled: raw['enabled'] != false,
          offsetType: (raw['offset_type'] as String?) ?? 'none',
          offsetDirection: (raw['offset_direction'] as String?) ?? 'up',
          offsetValue: '${raw['offset_value'] ?? '0'}',
        ),
      );
    }
  }

  Map<String, dynamic> _payload() {
    return {
      'enabled': _enabled,
      'schedule_mode': _scheduleMode,
      'interval_hours': _intervalHours,
      'daily_times': List<String>.from(_dailyTimes),
      'timezone': _timezone,
      'skip_if_unchanged': _skipIfUnchanged,
      'min_change_percent': _minChangeController.text.trim(),
      'block_if_stale': _blockIfStale,
      'stale_after_hours': int.tryParse(_staleHoursController.text.trim()) ?? 24,
      'rules': _rules
          .map(
            (r) => {
              'currency_id': r.currencyId,
              'enabled': r.enabled,
              'offset_type': r.offsetType,
              'offset_direction': r.offsetDirection,
              'offset_value': r.offsetValue.trim().isEmpty ? '0' : r.offsetValue.trim(),
            },
          )
          .toList(),
    };
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    setState(() => _saving = true);
    try {
      final data = await _svc.saveSettings(
        businessId: widget.businessId,
        payload: _payload(),
      );
      if (!mounted) return;
      _applySettings(data);
      final t = AppLocalizations.of(context);
      SnackBarHelper.show(context, message: t.savedSuccessfully);
      await _refreshPreview(silent: true);
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: t.fxAutoSyncSaveError(ErrorExtractor.forContext(e, context)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshPreview({bool silent = false}) async {
    if (_previewing) return;
    setState(() => _previewing = true);
    try {
      final data = await _svc.preview(
        businessId: widget.businessId,
        draft: _payload(),
      );
      if (!mounted) return;
      _previewWarning = data['warning'] as String?;
      final items = (data['items'] as List?) ?? const [];
      final byId = <int, Map>{};
      for (final raw in items) {
        if (raw is Map && raw['currency_id'] != null) {
          byId[(raw['currency_id'] as num).toInt()] = raw;
        }
      }
      for (final rule in _rules) {
        final item = byId[rule.currencyId];
        if (item == null) continue;
        rule.referenceRate = item['reference_rate']?.toString();
        rule.finalRate = item['final_rate']?.toString();
        rule.previewStatus = item['status']?.toString();
        rule.previewMessage = item['message']?.toString();
      }
      setState(() {});
    } catch (e) {
      if (!silent && mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: t.fxAutoSyncPreviewError(ErrorExtractor.forContext(e, context)),
        );
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _runNow() async {
    if (!_canEdit) return;
    setState(() => _running = true);
    try {
      // ذخیره فعلی تا آفست‌های UI اعمال شوند
      await _svc.saveSettings(businessId: widget.businessId, payload: _payload());
      final out = await _svc.runNow(businessId: widget.businessId);
      if (!mounted) return;
      final t = AppLocalizations.of(context);
      final msg = out['message']?.toString() ?? t.fxAutoSyncRunDone;
      SnackBarHelper.show(context, message: msg);
      await _load();
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context);
        SnackBarHelper.showError(
          context,
          message: t.fxAutoSyncRunError(ErrorExtractor.forContext(e, context)),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _addDailyTime() {
    final raw = _newTimeController.text.trim();
    final m = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$').firstMatch(raw);
    if (m == null) {
      final t = AppLocalizations.of(context);
      SnackBarHelper.showError(context, message: t.fxAutoSyncInvalidTime);
      return;
    }
    final norm = '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
    if (_dailyTimes.contains(norm)) return;
    setState(() {
      _dailyTimes.add(norm);
      _dailyTimes.sort();
      _newTimeController.clear();
    });
  }

  String _fmtDt(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final y = dt.year.toString().padLeft(4, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final mi = dt.minute.toString().padLeft(2, '0');
      return '$y/$mo/$d $h:$mi';
    } catch (_) {
      return raw;
    }
  }

  Color _statusColor(BuildContext context, String? status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'ok':
        return cs.primary;
      case 'partial':
        return Colors.orange.shade700;
      case 'error':
      case 'stale':
      case 'missing_snapshot':
      case 'invalid_rate':
        return cs.error;
      default:
        return cs.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!widget.authStore.hasBusinessPermission('settings', 'business') &&
        !widget.authStore.hasBusinessPermission('currency_revaluation', 'view')) {
      return PermissionGuard.buildAccessDeniedPage();
    }

    return MultiCurrencyGate(
      isMultiCurrency: widget.authStore.isMultiCurrency,
      singleCurrencyChild: Scaffold(
        appBar: AppBar(
          title: Text(t.fxAutoSyncTitle),
          leading: businessSubpageBackLeading(context, widget.businessId),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              t.fxAutoSyncSingleCurrencyHint,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.fxAutoSyncTitle),
          leading: businessSubpageBackLeading(context, widget.businessId),
          actions: [
            if (_canEdit)
              TextButton(
                onPressed: _loading || _saving || _running ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(t.save),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _HeroBanner(t: t),
                  const SizedBox(height: 16),
                  _StatusStrip(
                    t: t,
                    enabled: _enabled,
                    lastRunAt: _fmtDt(_lastRunAt),
                    nextRunAt: _fmtDt(_nextRunAt),
                    lastStatus: _lastRunStatus,
                    lastMessage: _lastRunMessage,
                    statusColor: _statusColor(context, _lastRunStatus),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    value: _enabled,
                    onChanged: _canEdit
                        ? (v) => setState(() => _enabled = v)
                        : null,
                    title: Text(t.fxAutoSyncEnableLabel),
                    subtitle: Text(t.fxAutoSyncSourceHint),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  Text(t.fxAutoSyncScheduleMode, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'interval', label: Text(t.fxAutoSyncModeInterval)),
                      ButtonSegment(value: 'daily_times', label: Text(t.fxAutoSyncModeDaily)),
                    ],
                    selected: {_scheduleMode},
                    onSelectionChanged: _canEdit
                        ? (s) => setState(() => _scheduleMode = s.first)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (_scheduleMode == 'interval')
                    DropdownButtonFormField<int>(
                      value: _allowedIntervals.contains(_intervalHours)
                          ? _intervalHours
                          : _allowedIntervals.first,
                      decoration: InputDecoration(
                        labelText: t.fxAutoSyncIntervalLabel,
                        border: const OutlineInputBorder(),
                      ),
                      items: _allowedIntervals
                          .map(
                            (h) => DropdownMenuItem(
                              value: h,
                              child: Text(t.fxAutoSyncEveryNHours(h)),
                            ),
                          )
                          .toList(),
                      onChanged: _canEdit
                          ? (v) {
                              if (v != null) setState(() => _intervalHours = v);
                            }
                          : null,
                    )
                  else ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final time in _dailyTimes)
                          InputChip(
                            label: Text(time),
                            onDeleted: _canEdit
                                ? () => setState(() => _dailyTimes.remove(time))
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newTimeController,
                            enabled: _canEdit,
                            decoration: InputDecoration(
                              labelText: t.fxAutoSyncAddTimeLabel,
                              hintText: '09:00',
                              border: const OutlineInputBorder(),
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                            ],
                            onSubmitted: (_) => _addDailyTime(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _canEdit ? _addDailyTime : null,
                          child: Text(t.fxAutoSyncAddTime),
                        ),
                      ],
                    ),
                    if (_timezone != null && _timezone!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        t.fxAutoSyncTimezoneHint(_timezone!),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  Text(t.fxAutoSyncOptionsTitle, style: Theme.of(context).textTheme.titleSmall),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _skipIfUnchanged,
                    onChanged: _canEdit
                        ? (v) => setState(() => _skipIfUnchanged = v)
                        : null,
                    title: Text(t.fxAutoSyncSkipUnchanged),
                  ),
                  if (_skipIfUnchanged)
                    TextField(
                      controller: _minChangeController,
                      enabled: _canEdit,
                      decoration: InputDecoration(
                        labelText: t.fxAutoSyncMinChangePercent,
                        border: const OutlineInputBorder(),
                        suffixText: '%',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _blockIfStale,
                    onChanged: _canEdit
                        ? (v) => setState(() => _blockIfStale = v)
                        : null,
                    title: Text(t.fxAutoSyncBlockStale),
                  ),
                  if (_blockIfStale)
                    TextField(
                      controller: _staleHoursController,
                      enabled: _canEdit,
                      decoration: InputDecoration(
                        labelText: t.fxAutoSyncStaleHours,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.fxAutoSyncOffsetsTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _previewing ? null : () => _refreshPreview(),
                        icon: _previewing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(t.fxAutoSyncRefreshPreview),
                      ),
                    ],
                  ),
                  if (_previewWarning != null) ...[
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_previewWarning!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    t.fxAutoSyncOffsetsHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  if (_rules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(t.fxAutoSyncNoSecondaryCurrencies),
                    )
                  else
                    ..._rules.map((rule) => _OffsetCard(
                          rule: rule,
                          canEdit: _canEdit,
                          t: t,
                          onChanged: () => setState(() {}),
                        )),
                  const SizedBox(height: 20),
                  if (_canEdit)
                    FilledButton.icon(
                      onPressed: _loading || _saving || _running ? null : _runNow,
                      icon: _running
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(t.fxAutoSyncRunNow),
                    ),
                ],
              ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.t});
  final AppLocalizations t;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            cs.tertiaryContainer.withValues(alpha: 0.85),
            cs.primaryContainer.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.autorenew_rounded, color: cs.onTertiaryContainer, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.fxAutoSyncHeroTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onTertiaryContainer,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  t.fxAutoSyncIntro,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onTertiaryContainer.withValues(alpha: 0.9),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.t,
    required this.enabled,
    required this.lastRunAt,
    required this.nextRunAt,
    required this.lastStatus,
    required this.lastMessage,
    required this.statusColor,
  });

  final AppLocalizations t;
  final bool enabled;
  final String lastRunAt;
  final String nextRunAt;
  final String? lastStatus;
  final String? lastMessage;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                enabled ? Icons.schedule_rounded : Icons.schedule_outlined,
                size: 18,
                color: enabled ? theme.colorScheme.primary : theme.disabledColor,
              ),
              const SizedBox(width: 8),
              Text(
                enabled ? t.fxAutoSyncStatusActive : t.fxAutoSyncStatusInactive,
                style: theme.textTheme.labelLarge,
              ),
              const Spacer(),
              if (lastStatus != null && lastStatus!.isNotEmpty)
                Text(
                  lastStatus!,
                  style: theme.textTheme.labelMedium?.copyWith(color: statusColor),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              Text('${t.fxAutoSyncLastRun}: $lastRunAt'),
              Text('${t.fxAutoSyncNextRun}: $nextRunAt'),
            ],
          ),
          if (lastMessage != null && lastMessage!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              lastMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _OffsetCard extends StatelessWidget {
  const _OffsetCard({
    required this.rule,
    required this.canEdit,
    required this.t,
    required this.onChanged,
  });

  final _CurrencyRuleDraft rule;
  final bool canEdit;
  final AppLocalizations t;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusOk = rule.previewStatus == null || rule.previewStatus == 'ok';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Text(
                    rule.code.length > 3 ? rule.code.substring(0, 3) : rule.code,
                    style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rule.code, style: theme.textTheme.titleSmall),
                      Text(rule.title, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: rule.enabled,
                  onChanged: canEdit
                      ? (v) {
                          rule.enabled = v;
                          onChanged();
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: rule.offsetType,
                    decoration: InputDecoration(
                      labelText: t.fxAutoSyncOffsetType,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(value: 'none', child: Text(t.fxAutoSyncOffsetNone)),
                      DropdownMenuItem(value: 'percent', child: Text(t.fxAutoSyncOffsetPercent)),
                      DropdownMenuItem(value: 'amount', child: Text(t.fxAutoSyncOffsetAmount)),
                    ],
                    onChanged: canEdit
                        ? (v) {
                            if (v == null) return;
                            rule.offsetType = v;
                            onChanged();
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: rule.offsetDirection,
                    decoration: InputDecoration(
                      labelText: t.fxAutoSyncOffsetDirection,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(value: 'up', child: Text(t.fxAutoSyncOffsetUp)),
                      DropdownMenuItem(value: 'down', child: Text(t.fxAutoSyncOffsetDown)),
                    ],
                    onChanged: canEdit && rule.offsetType != 'none'
                        ? (v) {
                            if (v == null) return;
                            rule.offsetDirection = v;
                            onChanged();
                          }
                        : null,
                  ),
                ),
              ],
            ),
            if (rule.offsetType != 'none') ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: rule.offsetValue,
                enabled: canEdit,
                decoration: InputDecoration(
                  labelText: t.fxAutoSyncOffsetValue,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixText: rule.offsetType == 'percent' ? '%' : null,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => rule.offsetValue = v,
              ),
            ],
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.fxAutoSyncRefRate}: ${rule.referenceRate ?? '—'}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${t.fxAutoSyncFinalRate}: ${rule.finalRate ?? '—'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: statusOk ? theme.colorScheme.primary : theme.colorScheme.error,
                    ),
                  ),
                  if (rule.previewMessage != null && rule.previewMessage!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      rule.previewMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    t.fxAutoSyncPreviewSavedHint,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
