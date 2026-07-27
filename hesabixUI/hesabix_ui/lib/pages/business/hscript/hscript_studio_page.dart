import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../models/ai_models.dart';
import '../../../services/ai_service.dart';
import '../../../services/hscript_report_service.dart';
import '../../../services/job_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/hscript_code_extract.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/ai/ai_chat_dialog.dart';
import '../../../widgets/ai/ai_chat_model_chip.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/hscript/hscript_code_editor.dart';
import '../../../widgets/hscript/hscript_outline_panel.dart';
import '../../../widgets/hscript/hscript_params_form.dart';
import '../../../widgets/hscript/hscript_plan_banner.dart';
import '../../../widgets/hscript/hscript_recipes_sheet.dart';
import '../../../widgets/hscript/hscript_schedules_sheet.dart';
import '../../../widgets/hscript/hscript_spec_renderer.dart';
import '../../../widgets/hscript/hscript_versions_sheet.dart';
import '../../../widgets/permission/access_denied_page.dart';
import 'package:hesabix_ui/services/bytes_export/bytes_export_service.dart';

const _kDefaultScript = '''# @param limit integer "سقف فاکتور" default=50
report.calendar("jalali")
report.number_format(style="western")
report.dashboard(columns=12)
report.title("داشبورد فروش")
rows = invoices.this_month(limit=params.get("limit", 50))
report.kpi("تعداد فاکتور", rows.count(), format="integer", span=4)
report.kpi("جمع بدهکار", rows.sum("total_debit"), format="currency", span=4)
report.card("وضعیت", "آماده", subtitle="پیش‌نمایش", span=4)
report.row_break()
top_rows = rows.top(10, by="total_debit")
report.bar_chart(top_rows, x="code", y="total_debit", title="بیشترین بدهکار", span=6)
report.table(rows.limit(15), columns=["code", "document_date", "total_debit", "total_credit"], formats={"total_debit": "currency", "total_credit": "currency"}, title="آخرین فاکتورها", span=6)
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
  final _paramsJsonCtrl = TextEditingController(text: '{\n  "limit": 50\n}');

  bool _loading = false;
  bool _running = false;
  bool _useAsync = false;
  bool _paramsAsJson = false;
  bool _showOutline = true;
  String? _jobStatusMsg;
  int? _reportId;
  String _status = 'draft';
  Map<String, dynamic>? _spec;
  Map<String, dynamic>? _error;
  Map<String, dynamic>? _stats;
  String? _validateMsg;
  List<Map<String, dynamic>> _paramFields = const [];
  Map<String, dynamic> _paramValues = {'limit': 50};
  Timer? _schemaDebounce;

  bool get _canView => widget.authStore.canViewHScript();
  bool get _canWrite => widget.authStore.canWriteHScript();
  bool get _canPublish => widget.authStore.canPublishHScript();
  bool get _canExport => widget.authStore.canExportHScript();
  bool get _canSchedule => widget.authStore.canScheduleHScript();

  @override
  void initState() {
    super.initState();
    _service = HScriptReportService(ApiClient());
    _jobs = JobService(apiClient: ApiClient());
    _reportId = widget.reportId;
    _codeCtrl.addListener(_onCodeChanged);
    if (_canView && !_canWrite && _reportId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(context.businessPanelUrl(widget.businessId, 'hscript/run/$_reportId'));
      });
      return;
    }
    if (_canView && _reportId != null) {
      _loadReport();
    } else if (_canView) {
      _refreshParamSchema();
    }
  }

  @override
  void dispose() {
    _schemaDebounce?.cancel();
    _codeCtrl.removeListener(_onCodeChanged);
    _titleCtrl.dispose();
    _codeCtrl.dispose();
    _paramsJsonCtrl.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    _schemaDebounce?.cancel();
    _schemaDebounce = Timer(const Duration(milliseconds: 700), _refreshParamSchema);
  }

  Future<void> _refreshParamSchema() async {
    try {
      final schema = await _service.inferParamSchema(
        businessId: widget.businessId,
        sourceCode: _codeCtrl.text,
        defaultParams: _paramValues,
        params: _paramValues,
      );
      if (!mounted) return;
      final fields = (schema['fields'] is List)
          ? (schema['fields'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final nextValues = Map<String, dynamic>.from(_paramValues);
      for (final f in fields) {
        final name = f['name']?.toString();
        if (name == null || name.isEmpty) continue;
        if (!nextValues.containsKey(name) && f.containsKey('default')) {
          nextValues[name] = f['default'];
        }
      }
      setState(() {
        _paramFields = fields;
        _paramValues = nextValues;
        if (!_paramsAsJson) {
          _paramsJsonCtrl.text = const JsonEncoder.withIndent('  ').convert(nextValues);
        }
      });
    } catch (_) {
      // schema کمکی است؛ خطا را بی‌صدا نادیده می‌گیریم
    }
  }

  Map<String, dynamic>? _parseParams() {
    if (!_paramsAsJson) {
      return Map<String, dynamic>.from(_paramValues);
    }
    final raw = _paramsJsonCtrl.text.trim();
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

  void _syncJsonFromValues() {
    _paramsJsonCtrl.text = const JsonEncoder.withIndent('  ').convert(_paramValues);
  }

  void _syncValuesFromJson() {
    final parsed = _parseParams();
    if (parsed == null) return;
    setState(() => _paramValues = parsed);
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getReport(
        businessId: widget.businessId,
        reportId: _reportId!,
      );
      if (!mounted) return;
      final params = data['default_params'];
      final map = params is Map ? Map<String, dynamic>.from(params) : <String, dynamic>{};
      final schemaFields = (data['param_schema'] is Map && data['param_schema']['fields'] is List)
          ? (data['param_schema']['fields'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _titleCtrl.text = data['title']?.toString() ?? '';
        _codeCtrl.text = data['source_code']?.toString() ?? '';
        _status = data['status']?.toString() ?? 'draft';
        _paramValues = map;
        _paramFields = schemaFields;
        _paramsJsonCtrl.text = const JsonEncoder.withIndent('  ').convert(map);
        _loading = false;
      });
      if (schemaFields.isEmpty) {
        await _refreshParamSchema();
      }
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
        _error = ok
            ? null
            : (res['error'] is Map
                ? Map<String, dynamic>.from(res['error'] as Map)
                : {'message': 'خطای نحوی'});
      });
      if (ok) {
        SnackBarHelper.show(context, message: 'اسکریپت معتبر است');
        await _refreshParamSchema();
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
    final result = await showDialog<_HScriptAiAssistResult>(
      context: context,
      builder: (ctx) => _HScriptAiAssistDialog(businessId: widget.businessId),
    );
    if (result == null || result.intent.isEmpty || !mounted) return;

    String docsBlock = '';
    try {
      final ctxData = await _service.assistContext(
        businessId: widget.businessId,
        query: result.intent,
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
    } catch (_) {}

    final current = _codeCtrl.text.trim();
    final prompt = StringBuffer()
      ..writeln('کمک کن یک اسکریپت HScript برای گزارش سفارشی حسابیکس بنویسم/اصلاح کنم.')
      ..writeln('درخواست کاربر: ${result.intent}')
      ..writeln()
      ..writeln('قواعد:')
      ..writeln('- فقط HScript امن (بدون import/SQL/فایل/شبکه)')
      ..writeln('- از invoices/customers/persons/products/payments/banks/warehouses/debtors/creditors استفاده کن')
      ..writeln('- در صورت نیاز where/join/pivot و # @param بنویس')
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
      initialModelCode: result.modelCode,
      onApplyHScriptCode: (code) {
        if (!mounted) return;
        setState(() => _codeCtrl.text = code);
        _refreshParamSchema();
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
    await _refreshParamSchema();
    if (!mounted) return;
    SnackBarHelper.show(context, message: 'اسکریپت از کلیپ‌بورد اعمال شد');
  }

  Future<void> _openRecipes() async {
    final code = await showHScriptRecipesSheet(
      context: context,
      businessId: widget.businessId,
      service: _service,
    );
    if (code == null || code.isEmpty || !mounted) return;
    final replace = _codeCtrl.text.trim().isEmpty ||
        await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('اعمال دستورپخت'),
                content: const Text('اسکریپت فعلی با دستورپخت جایگزین شود؟'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('جایگزینی')),
                ],
              ),
            ) ==
            true;
    if (replace != true || !mounted) return;
    setState(() => _codeCtrl.text = code);
    await _refreshParamSchema();
    if (!mounted) return;
    SnackBarHelper.show(context, message: 'دستورپخت اعمال شد');
  }

  Future<void> _openVersions() async {
    if (_reportId == null) {
      SnackBarHelper.showError(context, message: 'ابتدا گزارش را ذخیره کنید');
      return;
    }
    final restored = await showHScriptVersionsSheet(
      context: context,
      businessId: widget.businessId,
      reportId: _reportId!,
      service: _service,
    );
    if (restored == null || !mounted) return;
    setState(() {
      _codeCtrl.text = restored['source_code']?.toString() ?? _codeCtrl.text;
      _status = restored['status']?.toString() ?? _status;
      _titleCtrl.text = restored['title']?.toString() ?? _titleCtrl.text;
    });
    await _refreshParamSchema();
    if (!mounted) return;
    SnackBarHelper.show(context, message: 'نسخه بازگردانی شد');
  }

  Future<void> _showRuns() async {
    if (_reportId == null) {
      SnackBarHelper.showError(context, message: 'ابتدا گزارش را ذخیره کنید');
      return;
    }
    try {
      final runs = await _service.listRuns(
        businessId: widget.businessId,
        reportId: _reportId!,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          if (runs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('هنوز اجرایی ثبت نشده است.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: runs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = runs[i];
              final ok = r['status'] == 'success';
              return ListTile(
                leading: Icon(
                  ok ? Icons.check_circle_outline : Icons.error_outline,
                  color: ok ? cs.primary : cs.error,
                ),
                title: Text(ok ? 'موفق' : (r['error_message']?.toString() ?? 'ناموفق')),
                subtitle: Text(
                  '${r['created_at'] ?? ''} · ${r['duration_ms'] ?? '—'}ms'
                  '${r['is_preview'] == true ? ' · پیش‌نمایش' : ''}',
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _openSchedule() async {
    if (_reportId == null) {
      SnackBarHelper.showError(context, message: 'ابتدا گزارش را ذخیره و منتشر کنید');
      return;
    }
    if (_status != 'published') {
      SnackBarHelper.showError(context, message: 'فقط گزارش منتشرشده قابل زمان‌بندی است');
      return;
    }
    await showHScriptSchedulesSheet(
      context: context,
      businessId: widget.businessId,
      reportId: _reportId!,
      reportTitle: _titleCtrl.text.trim().isEmpty ? 'گزارش' : _titleCtrl.text.trim(),
      service: _service,
    );
  }

  Future<void> _archive() async {
    if (_reportId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بایگانی گزارش'),
        content: const Text('این گزارش بایگانی شود؟ بعداً از فهرست بایگانی قابل دسترسی است.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بایگانی')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final archived = await _service.archiveReport(
        businessId: widget.businessId,
        reportId: _reportId!,
      );
      if (!mounted) return;
      setState(() => _status = archived['status']?.toString() ?? 'archived');
      SnackBarHelper.show(context, message: 'گزارش بایگانی شد');
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _save() async {
    final params = _parseParams();
    if (params == null) return;
    setState(() {
      _paramValues = params;
      _running = true;
    });
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
      final result = await BytesExportService.export(
        bytes: bytes,
        filename: name,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      setState(() => _running = false);
      BytesExportService.showFeedback(
        context,
        result,
        successOverride: 'PDF آماده شد',
      );
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
      final result = await BytesExportService.export(
        bytes: bytes,
        filename: name,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      setState(() => _running = false);
      BytesExportService.showFeedback(
        context,
        result,
        successOverride: 'Excel آماده شد',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_canView) return const AccessDeniedPage();
    if (!_canWrite) return const AccessDeniedPage();
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
            tooltip: 'دستورپخت‌ها',
            onPressed: _running ? null : _openRecipes,
            icon: const Icon(Icons.dashboard_customize_outlined),
          ),
          IconButton(
            tooltip: 'از AI بساز',
            onPressed: _running ? null : _openAiAssist,
            icon: const Icon(Icons.auto_awesome),
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
          if (_canPublish)
            IconButton(
              tooltip: 'انتشار',
              onPressed: _running ? null : _publish,
              icon: const Icon(Icons.publish_outlined),
            ),
          PopupMenuButton<String>(
            tooltip: 'بیشتر',
            onSelected: (v) {
              switch (v) {
                case 'async':
                  setState(() => _useAsync = !_useAsync);
                case 'outline':
                  setState(() => _showOutline = !_showOutline);
                case 'clipboard':
                  _applyFromClipboard();
                case 'versions':
                  _openVersions();
                case 'runs':
                  _showRuns();
                case 'schedule':
                  _openSchedule();
                case 'archive':
                  _archive();
                case 'pdf':
                  _exportPdf();
                case 'excel':
                  _exportExcel();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'async',
                checked: _useAsync,
                child: const Text('اجرای پس‌زمینه'),
              ),
              CheckedPopupMenuItem(
                value: 'outline',
                checked: _showOutline,
                child: const Text('نمایش ساختار خروجی'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'clipboard', child: Text('اعمال از کلیپ‌بورد')),
              const PopupMenuItem(value: 'versions', child: Text('تاریخچه نسخه‌ها')),
              const PopupMenuItem(value: 'runs', child: Text('سابقه اجرا')),
              if (_canSchedule && _reportId != null && _status == 'published')
                const PopupMenuItem(value: 'schedule', child: Text('زمان‌بندی تحویل')),
              if (_canPublish && _reportId != null && _status != 'archived')
                const PopupMenuItem(value: 'archive', child: Text('بایگانی')),
              if (_canExport) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'pdf', child: Text('خروجی PDF')),
                const PopupMenuItem(value: 'excel', child: Text('خروجی Excel')),
              ],
            ],
          ),
          const SizedBox(width: 4),
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
                      'گام‌ها: ${_stats!['steps'] ?? '—'} · Gateway: ${_stats!['gateway_calls'] ?? '—'} · ${(_stats!['duration_ms'] ?? '—')}ms'
                      '${_useAsync ? ' · پس‌زمینه' : ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            Expanded(flex: 5, child: _editorPane(cs)),
                            VerticalDivider(width: 1, color: cs.outlineVariant),
                            Expanded(flex: 5, child: _previewPane(cs)),
                          ],
                        )
                      : DefaultTabController(
                          length: 2,
                          child: Column(
                            children: [
                              const TabBar(tabs: [
                                Tab(text: 'کد و پارامتر'),
                                Tab(text: 'پیش‌نمایش'),
                              ]),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _editorPane(cs),
                                    _previewPane(cs),
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
          Row(
            children: [
              Text('پارامترها', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('فرم'), icon: Icon(Icons.tune, size: 16)),
                  ButtonSegment(value: true, label: Text('JSON'), icon: Icon(Icons.data_object, size: 16)),
                ],
                selected: {_paramsAsJson},
                onSelectionChanged: (s) {
                  final asJson = s.first;
                  if (asJson) {
                    _syncJsonFromValues();
                  } else {
                    _syncValuesFromJson();
                  }
                  setState(() => _paramsAsJson = asJson);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(8),
                color: cs.surfaceContainerLowest,
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _paramsAsJson
                    ? Directionality(
                        textDirection: TextDirection.ltr,
                        child: TextField(
                          controller: _paramsJsonCtrl,
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
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          onChanged: (_) {
                            try {
                              final decoded = jsonDecode(_paramsJsonCtrl.text);
                              if (decoded is Map) {
                                _paramValues = Map<String, dynamic>.from(decoded);
                              }
                            } catch (_) {}
                          },
                        ),
                      )
                    : HScriptParamsForm(
                        fields: _paramFields,
                        values: _paramValues,
                        onChanged: (v) {
                          setState(() {
                            _paramValues = v;
                            _syncJsonFromValues();
                          });
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewPane(ColorScheme cs) {
    final preview = HScriptSpecRenderer(spec: _spec, error: _error);
    if (!_showOutline || MediaQuery.sizeOf(context).width < 1000) {
      return preview;
    }
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text('ساختار خروجی', style: Theme.of(context).textTheme.titleSmall),
              ),
              Expanded(child: HScriptOutlinePanel(spec: _spec)),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: cs.outlineVariant),
        Expanded(child: preview),
      ],
    );
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

class _HScriptAiAssistResult {
  const _HScriptAiAssistResult({required this.intent, this.modelCode});

  final String intent;
  final String? modelCode;
}

class _HScriptAiAssistDialog extends StatefulWidget {
  const _HScriptAiAssistDialog({required this.businessId});

  final int businessId;

  @override
  State<_HScriptAiAssistDialog> createState() => _HScriptAiAssistDialogState();
}

class _HScriptAiAssistDialogState extends State<_HScriptAiAssistDialog> {
  late final TextEditingController _intentCtrl;
  late final AIService _aiService;
  List<AIModelCatalogItem> _models = [];
  String? _selectedModelCode;
  bool _modelsLoading = true;

  @override
  void initState() {
    super.initState();
    _intentCtrl = TextEditingController();
    _aiService = AIService(ApiClient());
    _loadModels();
  }

  @override
  void dispose() {
    _intentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    setState(() => _modelsLoading = true);
    try {
      final result = await _aiService.listAvailableAIModelsResult(
        businessId: widget.businessId,
      );
      final models = result.models;
      final preferred = result.preferredModelCode;
      if (!mounted) return;

      bool hasCode(String? code) => code != null && models.any((m) => m.code == code);

      String? selected;
      if (hasCode(preferred)) {
        selected = preferred;
      } else {
        for (final m in models) {
          if (m.isDefault) {
            selected = m.code;
            break;
          }
        }
        selected ??= models.where((m) => m.isAuto).map((m) => m.code).firstOrNull;
        selected ??= models.isNotEmpty ? models.first.code : null;
      }

      setState(() {
        _models = models;
        _selectedModelCode = selected;
        _modelsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _modelsLoading = false);
    }
  }

  void _submit() {
    final intent = _intentCtrl.text.trim();
    if (intent.isEmpty) return;
    Navigator.pop(
      context,
      _HScriptAiAssistResult(intent: intent, modelCode: _selectedModelCode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('از AI بساز / اصلاح کن'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _intentCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'مثلاً: گزارش بدهکاران برتر با KPI و نمودار',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('مدل:', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AIChatModelChip(
                      models: _models,
                      selectedCode: _selectedModelCode,
                      loading: _modelsLoading,
                      onChanged: (code) {
                        setState(() => _selectedModelCode = code);
                        if (code != null) {
                          _aiService.setPreferredModel(
                            modelCode: code,
                            businessId: widget.businessId,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _submit, child: const Text('ادامه')),
      ],
    );
  }
}
