import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart' show SnackBarHelper;
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

/// ارزیابی کیفیت پاسخ AI (regression سناریوها).
class AIEvalAdminPage extends StatefulWidget {
  final bool embedded;
  const AIEvalAdminPage({super.key, this.embedded = false});

  @override
  State<AIEvalAdminPage> createState() => _AIEvalAdminPageState();
}

class _AIEvalAdminPageState extends State<AIEvalAdminPage> {
  late final AIService _ai;
  bool _loading = true;
  bool _running = false;
  bool _savingSchedule = false;
  List<Map<String, dynamic>> _cases = [];
  List<Map<String, dynamic>> _runs = [];
  Map<String, dynamic>? _lastResult;
  Map<String, dynamic>? _schedule;
  final _cronCtrl = TextEditingController();
  final _minPassCtrl = TextEditingController(text: '70');
  bool _scheduleEnabled = false;

  @override
  void initState() {
    super.initState();
    _ai = AIService(ApiClient());
    _load();
  }

  @override
  void dispose() {
    _cronCtrl.dispose();
    _minPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cases = await _ai.listEvalCases();
      final runs = await _ai.listEvalRuns();
      final schedule = await _ai.getEvalSchedule();
      if (!mounted) return;
      setState(() {
        _cases = cases;
        _runs = runs;
        _schedule = schedule;
        _scheduleEnabled = schedule['enabled'] as bool? ?? false;
        _cronCtrl.text = schedule['cron_expression'] as String? ?? '0 3 * * *';
        _minPassCtrl.text = '${schedule['min_pass_rate'] ?? 70}';
      });
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSchedule() async {
    setState(() => _savingSchedule = true);
    try {
      final minPass = int.tryParse(_minPassCtrl.text.trim()) ?? 70;
      await _ai.updateEvalSchedule({
        'enabled': _scheduleEnabled,
        'cron_expression': _cronCtrl.text.trim(),
        'min_pass_rate': minPass,
      });
      await _load();
      if (mounted) SnackBarHelper.show(context, message: adminTx(context, 'زمان‌بندی ذخیره شد', 'Schedule saved'));
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _savingSchedule = false);
    }
  }

  Future<void> _seed() async {
    try {
      await _ai.seedDefaultEvalCases();
      await _load();
      if (mounted) SnackBarHelper.show(context, message: adminTx(context, 'سناریوهای پیش‌فرض اضافه شدند', 'Default scenarios added'));
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _lastResult = null;
    });
    try {
      final result = await _ai.runEvalSuite();
      if (!mounted) return;
      setState(() => _lastResult = result);
      await _load();
      final run = result['run'] as Map<String, dynamic>?;
      SnackBarHelper.show(
        context,
        message: '${adminTx(context, 'نتیجه', 'Result')}: ${run?['passed_cases']}/${run?['total_cases']} ${adminTx(context, 'موفق', 'passed')}',
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: aiHubAppBar(
        embedded: widget.embedded,
        title: Text(adminTx(context, 'ارزیابی کیفیت', 'Quality evaluation')),
        actions: [
          TextButton(onPressed: _seed, child: Text(adminTx(context, 'سناریوهای پیش‌فرض', 'Default cases'))),
          FilledButton(
            onPressed: _running ? null : _run,
            child: _running
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(adminTx(context, 'اجرای دستی', 'Run now')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: context.settingsHub.pagePadding,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          adminTx(context, 'زمان‌بندی خودکار', 'Automatic schedule'),
                          style: context.settingsHub.cardTitleStyle(
                            Theme.of(context).textTheme,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(adminTx(context, 'فعال', 'Enabled')),
                          subtitle: Text(
                            _schedule?['last_run_at'] != null
                                ? '${adminTx(context, 'آخرین اجرا', 'Last run')}: ${_schedule!['last_run_at']} — ${adminTx(context, 'نرخ', 'Rate')}: ${_schedule!['last_pass_rate']}%'
                                : adminTx(context, 'پیش‌فرض: هر روز ۳:۰۰ به وقت تهران', 'Default: every day at 03:00 Asia/Tehran'),
                          ),
                          value: _scheduleEnabled,
                          onChanged: (v) => setState(() => _scheduleEnabled = v),
                        ),
                        TextField(
                          controller: _cronCtrl,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: adminTx(context, 'عبارت cron', 'Cron expression'),
                            hintText: '0 3 * * *',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _minPassCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: adminTx(context, 'حداقل نرخ قبولی (٪)', 'Minimum pass rate (%)'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _savingSchedule ? null : _saveSchedule,
                          child: _savingSchedule
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(adminTx(context, 'ذخیره زمان‌بندی', 'Save schedule')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${adminTx(context, 'سناریوها', 'Cases')} (${_cases.length})',
                  style: context.settingsHub.cardTitleStyle(
                    Theme.of(context).textTheme,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                ..._cases.map(
                  (c) => Card(
                    child: ListTile(
                      dense: true,
                      title: Text(c['name'] as String? ?? ''),
                      subtitle: Text(
                        (c['user_message'] as String? ?? '').length > 120
                            ? '${(c['user_message'] as String).substring(0, 120)}…'
                            : c['user_message'] as String? ?? '',
                      ),
                      trailing: (c['use_tools'] as bool? ?? false)
                          ? const Chip(label: Text('tools'))
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_lastResult != null) ...[
                  Text(
                    adminTx(context, 'آخرین اجرا', 'Latest run'),
                    style: context.settingsHub.cardTitleStyle(
                      Theme.of(context).textTheme,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...((_lastResult!['results'] as List?) ?? []).map((r) {
                    final m = Map<String, dynamic>.from(r as Map);
                    final passed = m['passed'] as bool? ?? false;
                    return ListTile(
                      leading: Icon(
                        passed ? Icons.check_circle : Icons.cancel,
                        color: passed ? SemanticColorResolver.positive(context) : SemanticColorResolver.negative(context),
                      ),
                      title: Text(m['case_name'] as String? ?? ''),
                      subtitle: Text('${m['latency_ms']} ms'),
                    );
                  }),
                ],
                const SizedBox(height: 16),
                Text(
                  adminTx(context, 'اجراهای اخیر', 'Recent runs'),
                  style: context.settingsHub.cardTitleStyle(
                    Theme.of(context).textTheme,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                ..._runs.take(10).map(
                      (r) => ListTile(
                        dense: true,
                        title: Text('${adminTx(context, 'اجرا', 'Run')} #${r['id']} — ${r['status']}'),
                        trailing: Text('${r['passed_cases']}/${r['total_cases']}'),
                      ),
                    ),
              ],
            ),
    );
  }
}
