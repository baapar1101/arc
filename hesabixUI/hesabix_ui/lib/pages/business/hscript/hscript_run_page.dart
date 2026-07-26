import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../services/hscript_report_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/web/web_utils.dart' as web_utils;
import '../../../widgets/business_subpage_back_leading.dart';
import '../../../widgets/data_table/helpers/file_saver.dart';
import '../../../widgets/hscript/hscript_params_form.dart';
import '../../../widgets/hscript/hscript_spec_renderer.dart';
import '../../../widgets/permission/access_denied_page.dart';

/// حالت فقط‌اجرا برای کاربران بدون دسترسی write (Dual-mode lite).
class HScriptRunPage extends StatefulWidget {
  const HScriptRunPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.reportId,
  });

  final int businessId;
  final AuthStore authStore;
  final int reportId;

  @override
  State<HScriptRunPage> createState() => _HScriptRunPageState();
}

class _HScriptRunPageState extends State<HScriptRunPage> {
  late final HScriptReportService _service;
  bool _loading = true;
  bool _running = false;
  String _title = '';
  String _status = '';
  Map<String, dynamic> _paramValues = {};
  List<Map<String, dynamic>> _paramFields = const [];
  Map<String, dynamic>? _spec;
  Map<String, dynamic>? _error;
  Map<String, dynamic>? _stats;

  bool get _canView => widget.authStore.canViewHScript();
  bool get _canExport => widget.authStore.canExportHScript();

  @override
  void initState() {
    super.initState();
    _service = HScriptReportService(ApiClient());
    if (_canView) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getReport(
        businessId: widget.businessId,
        reportId: widget.reportId,
      );
      if (!mounted) return;
      final params = data['default_params'];
      final map = params is Map ? Map<String, dynamic>.from(params) : <String, dynamic>{};
      final fields = (data['param_schema'] is Map && data['param_schema']['fields'] is List)
          ? (data['param_schema']['fields'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _title = data['title']?.toString() ?? 'گزارش';
        _status = data['status']?.toString() ?? '';
        _paramValues = map;
        _paramFields = fields;
        _loading = false;
      });
      if (_status != 'published') {
        SnackBarHelper.showError(context, message: 'فقط گزارش‌های منتشرشده قابل اجرا در این حالت هستند');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _run() async {
    if (_status != 'published') return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final res = await _service.runSaved(
        businessId: widget.businessId,
        reportId: widget.reportId,
        params: _paramValues,
        preview: false,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        if (res['ok'] == true) {
          _spec = res['spec'] is Map ? Map<String, dynamic>.from(res['spec'] as Map) : null;
          _error = null;
          _stats = res['stats'] is Map ? Map<String, dynamic>.from(res['stats'] as Map) : null;
        } else {
          _error = res['error'] is Map
              ? Map<String, dynamic>.from(res['error'] as Map)
              : {'message': 'اجرا ناموفق'};
          _spec = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _running = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _exportPdf() async {
    if (!_canExport) return;
    setState(() => _running = true);
    try {
      final bytes = await _service.exportPdfAdhoc(
        businessId: widget.businessId,
        spec: _spec,
        params: _paramValues,
      );
      final name = '${_title.isEmpty ? 'hscript-report' : _title}.pdf';
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

  @override
  Widget build(BuildContext context) {
    if (!_canView) return const AccessDeniedPage();
    final cs = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(
        leading: businessSubpageBackLeading(context, widget.businessId),
        title: Text(_title.isEmpty ? 'اجرای گزارش' : _title),
        actions: [
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Chip(label: Text(_status), visualDensity: VisualDensity.compact),
            ),
          IconButton(
            tooltip: 'اجرا',
            onPressed: _running || _status != 'published' ? null : _run,
            icon: const Icon(Icons.play_arrow),
          ),
          if (_canExport)
            IconButton(
              tooltip: 'PDF',
              onPressed: _running || _spec == null ? null : _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_running) const LinearProgressIndicator(minHeight: 2),
                if (_stats != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'گام‌ها: ${_stats!['steps'] ?? '—'} · ${(_stats!['duration_ms'] ?? '—')}ms',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            SizedBox(width: 320, child: _paramsPane(cs)),
                            VerticalDivider(width: 1, color: cs.outlineVariant),
                            Expanded(child: HScriptSpecRenderer(spec: _spec, error: _error)),
                          ],
                        )
                      : Column(
                          children: [
                            SizedBox(height: 220, child: _paramsPane(cs)),
                            Expanded(child: HScriptSpecRenderer(spec: _spec, error: _error)),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _paramsPane(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('پارامترها', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: HScriptParamsForm(
                  fields: _paramFields,
                  values: _paramValues,
                  onChanged: (v) => setState(() => _paramValues = v),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _running || _status != 'published' ? null : _run,
            icon: const Icon(Icons.play_arrow),
            label: const Text('اجرای گزارش'),
          ),
          if (_paramFields.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                jsonEncode(_paramValues),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
