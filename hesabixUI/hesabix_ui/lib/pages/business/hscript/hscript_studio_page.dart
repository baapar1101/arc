import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../services/hscript_report_service.dart';
import '../../../services/job_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/hscript_code_extract.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/web/web_utils.dart' as web_utils;
import '../../../widgets/ai/ai_chat_dialog.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/data_table/helpers/file_saver.dart';
import '../../../widgets/hscript/hscript_code_editor.dart';
import '../../../widgets/hscript/hscript_plan_banner.dart';
import '../../../widgets/hscript/hscript_spec_renderer.dart';
import '../../../widgets/permission/access_denied_page.dart';

const _kDefaultScript = '''report.calendar("jalali")
report.dashboard(columns=12)
report.title("داشبورد فروش")
rows = invoices.all(limit=50)
report.kpi("تعداد فاکتور", rows.count(), span=4)
report.kpi("جمع بدهکار", rows.sum("total_debit"), format="currency", span=4)
report.card("وضعیت", "آماده", subtitle="پیش‌نمایش", span=4)
report.row_break()
top_rows = rows.top(10, by="total_debit")
report.bar_chart(top_rows, x="code", y="total_debit", title="بیشترین بدهکار", span=6)
report.table(rows.limit(15), columns=["code", "document_date", "total_debit", "total_credit"], title="آخرین فاکتورها", span=6)
''';

/// استودیوی طراحی و اجرای گزارش HScript.
class HScriptStudioPage extends StatefulWidget {
  const HScriptStudioPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.reportId,
  });

  final int businessId;
  final AuthStore authStore;
  final int? reportId;

  @override
  State<HScriptStudioPage> createState() => _HScriptStudioPageState();
}

class _HScriptStudioPageState extends State<HScriptStudioPage> {
  late final HScriptReportService _service;
  late final JobService _jobs;
  final _titleCtrl = TextEditingController(text: 'گزارش جدید');
  final _codeCtrl = TextEditingController(text: _kDefaultScript);
  final _paramsCtrl = TextEditingController(text: '{\n  \n}');

  bool _loading = false;
  bool _running = false;
  bool _useAsync = false;
  String? _jobStatusMsg;
  int? _reportId;
  String _status = 'draft';
  Map<String, dynamic>? _spec;
  Map<String, dynamic>? _error;
  Map<String, dynamic>? _stats;
  String? _validateMsg;

  bool get _canView => widget.authStore.hasBusinessPermission('reports', 'view');
  bool get _canExport => widget.authStore.hasBusinessPermission('reports', 'export');

  @override
  void initState() {
    super.initState();
    _service = HScriptReportService(ApiClient());
    _jobs = JobService(apiClient: ApiClient());
    _reportId = widget.reportId;
    if (_canView && _reportId != null) {
      _loadReport();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _codeCtrl.dispose();
    _paramsCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _parseParams() {
    final raw = _paramsCtrl.text.trim();
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const FormatException('params باید object باشد');
    } catch (e) {
      SnackBarHelper.showError(context, message: 'JSON پارامترها نامعتبر است');
      return null;
    }
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getReport(
        businessId: widget.businessId,
        reportId: _reportId!,
      );
      if (!mounted) return;
      setState(() {
        _titleCtrl.text = data['title']?.toString() ?? '';
        _codeCtrl.text = data['source_code']?.toString() ?? '';
        _status = data['status']?.toString() ?? 'draft';
        final params = data['default_params'];
        if (params is Map) {
          _paramsCtrl.text = const JsonEncoder.withIndent('  ').convert(params);
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _validate() async {
    setState(() {
      _running = true;
      _validateMsg = null;
    });
    try {
      final res = await _service.validate(
        businessId: widget.businessId,
        sourceCode: _codeCtrl.text,
      );
      if (!mounted) return;
      final ok = res['ok'] == true;
      setState(() {
        _running = false;
        _validateMsg = ok ? 'نحو اسکریپت معتبر است' : null;
        _error = ok ? null : (res['error'] is Map ? Map<String, dynamic>.from(res['error'] as Map) : {'message': 'خطای نحوی'});
        if (ok) _spec = _spec; // keep preview
      });
      if (ok) {
        SnackBarHelper.show(context, message: 'اسکریپت معتبر است');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _run() async {
    final params = _parseParams();
    if (params == null) return;
    setState(() {
      _running = true;
      _error = null;
      _validateMsg = null;
      _jobStatusMsg = _useAsync ? 'در صف اجرا…' : null;
    });
    try {
      final res = await _service.runAdhoc(
        businessId: widget.businessId,
        sourceCode: _codeCtrl.text,
        params: params,
        persist: false,
        asyncMode: _useAsync,
      );
      if (!mounted) return;

      if (res['async'] == true && res['job_id'] != null) {
        final jobId = res['job_id'].toString();
        setState(() => _jobStatusMsg = 'در حال اجرا در پس‌زمینه…');
        final poll = await _jobs.pollUntilComplete(
          jobId,
          interval: const Duration(milliseconds: 800),
          timeout: const Duration(minutes: 10),
          onProgress: (p, msg) {
            if (!mounted) return;
            setState(() => _jobStatusMsg = msg ?? 'پیشرفت: $p٪');
          },
        );
        if (!mounted) return;
        if (poll.isFailed) {
          setState(() {
            _running = false;
            _jobStatusMsg = null;
            _error = {'code': 'JOB_FAILED', 'message': poll.errorMessage ?? 'اجرای پس‌زمینه ناموفق بود'};
            _spec = null;
          });
          return;
        }
        final result = poll.result ?? const <String, dynamic>{};
        _applyRunResult(result);
        return;
      }

      _applyRunResult(res);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _jobStatusMsg = null;
      });
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  void _applyRunResult(Map<String, dynamic> res) {
    setState(() {
      _running = false;
      _jobStatusMsg = null;
      if (res['ok'] == true || res['success'] == true) {
        _spec = res['spec'] is Map ? Map<String, dynamic>.from(res['spec'] as Map) : null;
        _error = null;
        _stats = res['stats'] is Map ? Map<String, dynamic>.from(res['stats'] as Map) : null;
      } else {
        _error = res['error'] is Map
            ? Map<String, dynamic>.from(res['error'] as Map)
            : {'message': 'اجرا ناموفق'};
        _spec = null;
        _stats = res['stats'] is Map ? Map<String, dynamic>.from(res['stats'] as Map) : null;
      }
    });
  }

  Future<void> _openAiAssist() async {
    final intentCtrl = TextEditingController();
    final intent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('از AI بساز / اصلاح کن'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: intentCtrl,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'مثلاً: گزارش فروش ماه با KPI و نمودار میله‌ای',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, intentCtrl.text.trim()),
            child: const Text('ادامه'),
          ),
        ],
      ),
    );
    intentCtrl.dispose();
    if (intent == null || intent.isEmpty || !mounted) return;

    String docsBlock = '';
    try {
      final ctxData = await _service.assistContext(
        businessId: widget.businessId,
        query: intent,
        sourceCode: _codeCtrl.text,
      );
      final docs = ctxData['docs'];
      if (docs is List && docs.isNotEmpty) {
        final buf = StringBuffer('\n\n# مستندات بازیابی‌شده\n');
        for (final d in docs.take(4)) {
          if (d is! Map) continue;
          buf.writeln('## ${d['title'] ?? d['doc_id']}');
          buf.writeln(d['content'] ?? '');
          buf.writeln();
        }
        docsBlock = buf.toString();
      }
    } catch (_) {
      // بدون docs هم می‌توان ادامه داد
    }

    final current = _codeCtrl.text.trim();
    final prompt = StringBuffer()
      ..writeln('کمک کن یک اسکریپت HScript برای گزارش سفارشی حسابیکس بنویسم/اصلاح کنم.')
      ..writeln('درخواست کاربر: $intent')
      ..writeln()
      ..writeln('قواعد:')
      ..writeln('- فقط HScript امن (بدون import/SQL/فایل/شبکه)')
      ..writeln('- از invoices/customers/products/payments و report.* استفاده کن')
      ..writeln('- از ابزارهای hscript_retrieve_docs، hscript_validate_script و در صورت نیاز hscript_run_preview استفاده کن')
      ..writeln('- اسکریپت نهایی را داخل بلوک ```hscript بگذار')
      ..writeln();
    if (current.isNotEmpty) {
      prompt
        ..writeln('اسکریپت فعلی:')
        ..writeln('```hscript')
        ..writeln(current)
        ..writeln('```');
    }
    if (docsBlock.isNotEmpty) prompt.writeln(docsBlock);

    if (!mounted) return;
    await AIChatDialog.show(
      context,
      authStore: widget.authStore,
      businessId: widget.businessId,
      calendarController: ApiClient.getCalendarController(),
      initialPrompt: prompt.toString(),
      autoSendInitialPrompt: true,
      onApplyHScriptCode: (code) {
        if (!mounted) return;
        setState(() => _codeCtrl.text = code);
        SnackBarHelper.show(context, message: 'اسکریپت از AI به ادیتور اعمال شد');
      },
    );
  }

  Future<void> _applyFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final extracted = HScriptCodeExtract.extract(data?.text);
    if (!mounted) return;
    if (extracted == null || extracted.isEmpty) {
      SnackBarHelper.showError(context, message: 'اسکریپت معتبری در کلیپ‌بورد یافت نشد');
      return;
    }
    setState(() => _codeCtrl.text = extracted);
    SnackBarHelper.show(context, message: 'اسکریپت از کلیپ‌بورد اعمال شد');
  }

  Future<void> _save() async {
    final params = _parseParams();
    if (params == null) return;
    setState(() => _running = true);
    try {
      if (_reportId == null) {
        final created = await _service.createReport(
          businessId: widget.businessId,
          title: _titleCtrl.text.trim().isEmpty ? 'گزارش بدون عنوان' : _titleCtrl.text.trim(),
          sourceCode: _codeCtrl.text,
          defaultParams: params,
        );
        if (!mounted) return;
        setState(() {
          _reportId = (created['id'] as num?)?.toInt();
          _status = created['status']?.toString() ?? 'draft';
          _running = false;
        });
        SnackBarHelper.show(context, message: 'گزارش ذخیره شد');
      } else {
        final updated = await _service.updateReport(
          businessId: widget.businessId,
          reportId: _reportId!,
          title: _titleCtrl.text.trim(),
          sourceCode: _codeCtrl.text,
          defaultParams: params,
        );
        if (!mounted) return;
        setState(() {
          _status = updated['status']?.toString() ?? _status;
          _running = false;
        });
        SnackBarHelper.show(context, message: 'تغییرات ذخیره شد');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _publish() async {
    if (_reportId == null) {
      await _save();
      if (_reportId == null) return;
    } else {
      await _save();
    }
    setState(() => _running = true);
    try {
      final published = await _service.publishReport(
        businessId: widget.businessId,
        reportId: _reportId!,
      );
      if (!mounted) return;
      setState(() {
        _status = published['status']?.toString() ?? 'published';
        _running = false;
      });
      SnackBarHelper.show(context, message: 'گزارش منتشر شد');
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _exportPdf() async {
    if (!_canExport) {
      SnackBarHelper.showError(context, message: 'دسترسی خروجی PDF ندارید');
      return;
    }
    final params = _parseParams();
    if (params == null) return;
    setState(() => _running = true);
    try {
      final bytes = _spec != null
          ? await _service.exportPdfAdhoc(
              businessId: widget.businessId,
              spec: _spec,
              params: params,
            )
          : await _service.exportPdfAdhoc(
              businessId: widget.businessId,
              sourceCode: _codeCtrl.text,
              params: params,
            );
      final name = '${_titleCtrl.text.trim().isEmpty ? 'hscript-report' : _titleCtrl.text.trim()}.pdf';
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(bytes, name, mimeType: 'application/pdf');
      } else {
        await FileSaver.saveBytes(bytes, name);
      }
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarHelper.show(context, message: 'PDF آماده شد');
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _exportExcel() async {
    if (!_canExport) {
      SnackBarHelper.showError(context, message: 'دسترسی خروجی Excel ندارید');
      return;
    }
    final params = _parseParams();
    if (params == null) return;
    setState(() => _running = true);
    try {
      final bytes = _spec != null
          ? await _service.exportExcelAdhoc(
              businessId: widget.businessId,
              spec: _spec,
              params: params,
            )
          : await _service.exportExcelAdhoc(
              businessId: widget.businessId,
              sourceCode: _codeCtrl.text,
              params: params,
            );
      final name = '${_titleCtrl.text.trim().isEmpty ? 'hscript-report' : _titleCtrl.text.trim()}.xlsx';
      if (kIsWeb) {
        await web_utils.saveBytesAsFileWeb(
          bytes,
          name,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      } else {
        await FileSaver.saveBytes(bytes, name);
      }
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarHelper.show(context, message: 'Excel آماده شد');
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView) return const AccessDeniedPage();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: businessSubpageBackLeading(context, widget.businessId),
        title: Text(_reportId == null ? 'استودیو HScript' : 'ویرایش گزارش HScript'),
        actions: [
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Chip(label: Text(_statusLabel(_status)), visualDensity: VisualDensity.compact),
            ),
          IconButton(
            tooltip: _useAsync ? 'اجرای پس‌زمینه روشن' : 'اجرای همگام',
            onPressed: _running
                ? null
                : () => setState(() => _useAsync = !_useAsync),
            icon: Icon(_useAsync ? Icons.cloud_queue : Icons.bolt),
          ),
          IconButton(
            tooltip: 'از AI بساز',
            onPressed: _running ? null : _openAiAssist,
            icon: const Icon(Icons.auto_awesome),
          ),
          IconButton(
            tooltip: 'اعمال اسکریپت از کلیپ‌بورد',
            onPressed: _running ? null : _applyFromClipboard,
            icon: const Icon(Icons.content_paste_go),
          ),
          IconButton(
            tooltip: 'اعتبارسنجی',
            onPressed: _running ? null : _validate,
            icon: const Icon(Icons.rule),
          ),
          IconButton(
            tooltip: 'اجرا / پیش‌نمایش',
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.play_arrow),
          ),
          IconButton(
            tooltip: 'ذخیره',
            onPressed: _running ? null : _save,
            icon: const Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: 'انتشار',
            onPressed: _running ? null : _publish,
            icon: const Icon(Icons.publish_outlined),
          ),
          IconButton(
            tooltip: 'PDF',
            onPressed: _running ? null : _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Excel',
            onPressed: _running ? null : _exportExcel,
            icon: const Icon(Icons.table_view_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                HScriptPlanBanner(businessId: widget.businessId, service: _service),
                if (_running) const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'عنوان گزارش',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                if (_validateMsg != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(_validateMsg!, style: TextStyle(color: cs.primary)),
                    ),
                  ),
                if (_jobStatusMsg != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      _jobStatusMsg!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.primary),
                    ),
                  ),
                if (_stats != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'گام‌ها: ${_stats!['steps'] ?? '—'} · Gateway: ${_stats!['gateway_calls'] ?? '—'} · ${(_stats!['duration_ms'] ?? '—')}ms',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            Expanded(flex: 5, child: _editorPane(cs)),
                            VerticalDivider(width: 1, color: cs.outlineVariant),
                            Expanded(flex: 5, child: _previewPane()),
                          ],
                        )
                      : DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              const TabBar(tabs: [
                                Tab(text: 'کد'),
                                Tab(text: 'پیش‌نمایش'),
                              ]),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _editorPane(cs),
                                    _previewPane(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _editorPane(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            flex: 7,
            child: HScriptCodeEditor(
              controller: _codeCtrl,
              label: 'اسکریپت HScript',
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            flex: 3,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _paramsCtrl,
                maxLines: null,
                expands: true,
                textAlign: TextAlign.left,
                textAlignVertical: TextAlignVertical.top,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.45,
                ),
                decoration: InputDecoration(
                  labelText: 'params (JSON)',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: cs.surfaceContainerLowest,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewPane() {
    return HScriptSpecRenderer(spec: _spec, error: _error);
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'published':
        return 'منتشرشده';
      case 'archived':
        return 'بایگانی';
      default:
        return 'پیش‌نویس';
    }
  }
}
