import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart' show SnackBarHelper;

/// ارزیابی کیفیت پاسخ AI (regression سناریوها).
class AIEvalAdminPage extends StatefulWidget {
  const AIEvalAdminPage({super.key});

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
      if (mounted) SnackBarHelper.show(context, message: 'زمان‌بندی ذخیره شد');
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
      if (mounted) SnackBarHelper.show(context, message: 'سناریوهای پیش‌فرض اضافه شدند');
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
        message: 'نتیجه: ${run?['passed_cases']}/${run?['total_cases']} موفق',
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
      appBar: AppBar(
        title: const Text('ارزیابی کیفیت AI'),
        actions: [
          TextButton(onPressed: _seed, child: const Text('سناریوهای پیش‌فرض')),
          FilledButton(
            onPressed: _running ? null : _run,
            child: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('اجرای دستی'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'زمان‌بندی خودکار',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('فعال'),
                          subtitle: Text(
                            _schedule?['last_run_at'] != null
                                ? 'آخرین اجرا: ${_schedule!['last_run_at']} — نرخ: ${_schedule!['last_pass_rate']}%'
                                : 'پیش‌فرض: هر روز ۳:۰۰ (Asia/Tehran)',
                          ),
                          value: _scheduleEnabled,
                          onChanged: (v) => setState(() => _scheduleEnabled = v),
                        ),
                        TextField(
                          controller: _cronCtrl,
                          decoration: const InputDecoration(
                            labelText: 'عبارت cron',
                            hintText: '0 3 * * *',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _minPassCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'حداقل نرخ قبولی (%)',
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _savingSchedule ? null : _saveSchedule,
                          child: _savingSchedule
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('ذخیره زمان‌بندی'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('سناریوها (${_cases.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._cases.map(
                  (c) => Card(
                    child: ListTile(
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
                  Text('آخرین اجرا', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...((_lastResult!['results'] as List?) ?? []).map((r) {
                    final m = Map<String, dynamic>.from(r as Map);
                    final passed = m['passed'] as bool? ?? false;
                    return ListTile(
                      leading: Icon(
                        passed ? Icons.check_circle : Icons.cancel,
                        color: passed ? Colors.green : Colors.red,
                      ),
                      title: Text(m['case_name'] as String? ?? ''),
                      subtitle: Text('${m['latency_ms']} ms'),
                    );
                  }),
                ],
                const SizedBox(height: 16),
                Text('اجراهای اخیر', style: Theme.of(context).textTheme.titleMedium),
                ..._runs.take(10).map(
                      (r) => ListTile(
                        dense: true,
                        title: Text('اجرا #${r['id']} — ${r['status']}'),
                        trailing: Text('${r['passed_cases']}/${r['total_cases']}'),
                      ),
                    ),
              ],
            ),
    );
  }
}
