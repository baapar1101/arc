import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../l10n/app_localizations.dart';
import '../../services/report_template_service.dart';
import '../../utils/number_normalizer.dart';

class ReportTemplatesPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  const ReportTemplatesPage({super.key, required this.businessId, required this.authStore});

  @override
  State<ReportTemplatesPage> createState() => _ReportTemplatesPageState();
}

class _ReportTemplatesPageState extends State<ReportTemplatesPage> {
  late final ReportTemplateService _service;
  final _moduleCtrl = TextEditingController(text: 'invoices');
  final _subtypeCtrl = TextEditingController(text: 'list');
  String? _statusFilter; // draft/published/null

  bool _loading = false;
  List<Map<String, dynamic>> _items = const [];

  // Create/Edit form
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _htmlCtrl = TextEditingController(text: "<html><head></head><body><h3>{{ title_text }}</h3></body></html>");
  final _cssCtrl = TextEditingController(text: "body { font-family: Tahoma, Arial; }");
  final _headerCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  // Page settings
  String? _paperSize = 'A4'; // A4, Letter, ...
  String? _orientation = 'portrait'; // portrait, landscape
  final _marginTopCtrl = TextEditingController(text: '10');
  final _marginRightCtrl = TextEditingController(text: '10');
  final _marginBottomCtrl = TextEditingController(text: '10');
  final _marginLeftCtrl = TextEditingController(text: '10');

  bool get _canWrite => widget.authStore.hasBusinessPermission('report_templates', 'write');

  Future<void> _openBuilderDialogAdvanced({Map<String, dynamic>? initialDesign, Map<String, dynamic>? initialAssets, int? existingTemplateId}) async {
    Map<String, dynamic> design = {
      'css': (initialDesign?['css'] ?? '').toString(),
      'header': List<Map<String, dynamic>>.from((initialDesign?['header'] as List?) ?? const []),
      'blocks': List<Map<String, dynamic>>.from((initialDesign?['blocks'] as List?) ?? const []),
      'footer': List<Map<String, dynamic>>.from((initialDesign?['footer'] as List?) ?? const []),
    };
    Map<String, dynamic> assets = {
      'images': Map<String, String>.from(((initialAssets?['images']) as Map? ?? const <String, String>{})),
    };
    // history stacks
    final List<String> _history = <String>[];
    final List<String> _future = <String>[];
    String _snap() => jsonEncode(design);
    void _pushHistory() {
      _history.add(_snap());
      _future.clear();
    }
    void _undo(void Function(void Function()) setSt) {
      if (_history.isEmpty) return;
      _future.add(_snap());
      final last = _history.removeLast();
      final m = jsonDecode(last) as Map<String, dynamic>;
      design = {
        'css': (m['css'] ?? '').toString(),
        'header': List<Map<String, dynamic>>.from((m['header'] as List?) ?? const []),
        'blocks': List<Map<String, dynamic>>.from((m['blocks'] as List?) ?? const []),
        'footer': List<Map<String, dynamic>>.from((m['footer'] as List?) ?? const []),
      };
      setSt(() {});
    }
    void _redo(void Function(void Function()) setSt) {
      if (_future.isEmpty) return;
      _history.add(_snap());
      final next = _future.removeLast();
      final m = jsonDecode(next) as Map<String, dynamic>;
      design = {
        'css': (m['css'] ?? '').toString(),
        'header': List<Map<String, dynamic>>.from((m['header'] as List?) ?? const []),
        'blocks': List<Map<String, dynamic>>.from((m['blocks'] as List?) ?? const []),
        'footer': List<Map<String, dynamic>>.from((m['footer'] as List?) ?? const []),
      };
    }
    final cssCtrl = TextEditingController(text: (design['css'] ?? '').toString());
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          List<Map<String, dynamic>> hdr = List<Map<String, dynamic>>.from(design['header'] as List);
          List<Map<String, dynamic>> body = List<Map<String, dynamic>>.from(design['blocks'] as List);
          List<Map<String, dynamic>> ftr = List<Map<String, dynamic>>.from(design['footer'] as List);
          final t = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(existingTemplateId == null ? t.templateBuilderNew : t.templateBuilderEdit),
            content: SizedBox(
              width: 860,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _undo(setSt),
                          icon: const Icon(Icons.undo),
                          label: Text(t.undo),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            _redo(setSt);
                            setSt(() {});
                          },
                          icon: const Icon(Icons.redo),
                          label: Text(t.redo),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DefaultTabController(
                      length: 3,
                      child: Column(
                        children: [
                          TabBar(tabs: [
                            Tab(text: t.header),
                            Tab(text: t.body),
                            Tab(text: t.footer),
                          ]),
                          SizedBox(
                            height: 420,
                            child: TabBarView(
                              children: [
                                _builderBlocksTab(ctx, setSt, hdr, onChanged: () {
                                  design['header'] = hdr;
                                  _pushHistory();
                                }),
                                _builderBlocksTab(ctx, setSt, body, onChanged: () {
                                  design['blocks'] = body;
                                  _pushHistory();
                                }),
                                _builderBlocksTab(ctx, setSt, ftr, onChanged: () {
                                  design['footer'] = ftr;
                                  _pushHistory();
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(t.globalCssOptional, style: Theme.of(context).textTheme.titleSmall),
                    TextField(
                      controller: cssCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'styles...'),
                      onChanged: (v) => design['css'] = v,
                    ),
                    const SizedBox(height: 12),
                    // برای ثبت تصاویر می‌توانید نام asset را در بلوک Image تنظیم کنید
                    // و Data URI را مستقیماً در همان بلوک وارد کنید.
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final res = await _service.preview(
                            businessId: widget.businessId,
                            engine: 'builder',
                            design: design,
                            assets: assets,
                            context: const <String, dynamic>{},
                          );
                          if (!mounted) return;
                          final html = (res['html'] ?? '').toString();
                          await showDialog(
                            context: context,
                            builder: (pvCtx) {
                              final t2 = AppLocalizations.of(context);
                              return AlertDialog(
                                title: Text(t2.previewHtmlOutput),
                                content: SizedBox(
                                  width: 800,
                                  child: SingleChildScrollView(
                                    child: SelectableText(html.isEmpty ? t2.empty : html),
                                  ),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(pvCtx), child: Text(t2.close)),
                                ],
                              );
                            },
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.previewError(e.toString()))));
                        }
                      },
                      icon: const Icon(Icons.visibility),
                      label: Text(t.previewPdf),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.close)),
              FilledButton(
                onPressed: () async {
                  try {
                    if (existingTemplateId == null) {
                      final id = await _service.createTemplate(
                        businessId: widget.businessId,
                        moduleKey: _moduleCtrl.text.trim().isEmpty ? 'invoices' : _moduleCtrl.text.trim(),
                        subtype: _subtypeCtrl.text.trim().isEmpty ? 'detail' : _subtypeCtrl.text.trim(),
                        name: _nameCtrl.text.trim().isEmpty ? 'Template (Builder)' : _nameCtrl.text.trim(),
                        description: _descCtrl.text.trim().isEmpty ? 'Created by visual builder' : _descCtrl.text.trim(),
                        contentHtml: '<html><body></body></html>',
                        assets: {'builder_design': design, ...assets},
                        engine: 'builder',
                        paperSize: _paperSize,
                        orientation: _orientation,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.createdWithId(id))));
                    } else {
                      await _service.updateTemplate(
                        businessId: widget.businessId,
                        templateId: existingTemplateId,
                        changes: {'assets': {'builder_design': design, ...assets}, 'engine': 'builder'},
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.updated)));
                    }
                    await _fetch();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.error}: $e')));
                  }
                },
                child: Text(existingTemplateId == null ? t.createTemplateBuilder : t.saveChanges),
              ),
            ],
          );
        },
      ),
    );

  }

  Widget _builderBlocksTab(BuildContext context, void Function(void Function()) setSt, List<Map<String, dynamic>> blocks, {required VoidCallback onChanged}) {
    final t = AppLocalizations.of(context);
    return Column(
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: () {
                blocks.add({'type': 'text', 'props': {'text': 'متن {{ title_text }}', 'align': 'right', 'showIf': ''}});
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.text_fields, size: 18),
              label: Text(t.addText),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                blocks.add({'type': 'divider', 'props': {'thickness': 1.0, 'showIf': ''}});
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.horizontal_rule, size: 18),
              label: Text(t.divider),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                blocks.add({'type': 'spacer', 'props': {'height': 12.0, 'showIf': ''}});
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.space_bar, size: 18),
              label: Text(t.spacer),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                blocks.add({'type': 'image', 'props': {'src': 'https://example.com/logo.png', 'width': 120, 'height': null, 'alt': 'Logo', 'showIf': ''}});
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(t.addImage),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                blocks.add({'type': 'qr', 'props': {'src': 'asset:qr', 'size': 120, 'showIf': ''}});
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.qr_code, size: 18),
              label: Text(t.addQr),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                // اطلاعات طرفین
                blocks.addAll([
                  {'type': 'text', 'props': {'text': '<b>فروشنده:</b> {{ business.name }} — {{ business.address|default(\'\') }}', 'align': 'right', 'showIf': ''}},
                  {'type': 'text', 'props': {'text': '<b>خریدار:</b> {{ invoice.customer.name }} — {{ invoice.customer.address|default(\'\') }}', 'align': 'right', 'showIf': ''}},
                ]);
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.people_alt_outlined, size: 18),
              label: Text(t.partyInfo),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                blocks.add({
                  'type': 'totals',
                  'props': {
                    'items': [
                      {'title': 'جمع اقلام', 'expr': "items|sum(attribute='amount')", 'format': 'money'},
                      {'title': 'مالیات', 'expr': "tax_total", 'format': 'money'},
                      {'title': 'جمع کل', 'expr': "grand_total", 'format': 'money'},
                    ],
                    'showIf': '',
                  },
                });
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.summarize, size: 18),
              label: Text(t.addTotals),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                // مهر/امضا به‌صورت تصاویر asset
                blocks.addAll([
                  {'type': 'image', 'props': {'src': 'asset:stamp', 'width': 140, 'height': null, 'alt': 'Stamp', 'showIf': ''}},
                  {'type': 'image', 'props': {'src': 'asset:sign', 'width': 140, 'height': null, 'alt': 'Signature', 'showIf': ''}},
                ]);
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.edit, size: 18),
              label: Text(t.stampSignature),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                // واترمارک متنی ساده
                blocks.add({
                  'type': 'text',
                  'props': {
                    'text': '<div style="position:relative;"><span style="opacity:0.15; font-size:64px; transform:rotate(-30deg); display:inline-block;">WATERMARK</span></div>',
                    'align': 'center',
                    'showIf': ''
                  },
                });
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.water_damage_outlined, size: 18),
              label: Text(t.watermark),
            ),
            OutlinedButton.icon(
              onPressed: () {
                blocks.add({
                  'type': 'table',
                  'props': {
                    'items': 'items',
                    'columns': [
                      {'key': 'name', 'title': 'نام', 'format': ''},
                      {'key': 'qty', 'title': 'تعداد', 'format': ''},
                      {'key': 'price', 'title': 'قیمت', 'format': 'money'},
                      {'key': 'amount', 'title': 'مبلغ', 'format': 'money'},
                    ],
                    'showIf': '',
                  },
                });
                onChanged();
                setSt(() {});
              },
              icon: const Icon(Icons.table_chart, size: 18),
              label: Text(t.addTable),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: blocks.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = blocks.removeAt(oldIndex);
              blocks.insert(newIndex, item);
              onChanged();
              setSt(() {});
            },
            itemBuilder: (c, i) {
              final b = blocks[i];
              final type = (b['type'] ?? '').toString();
              if (type == 'text') {
                final textCtrl = TextEditingController(text: (b['props']?['text'] ?? '').toString());
                final showIfCtrl = TextEditingController(text: (b['props']?['showIf'] ?? '').toString());
                String align = (b['props']?['align'] ?? '').toString();
                return Card(
                  key: ValueKey('text_$i'),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.text_fields),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: textCtrl,
                                decoration: InputDecoration(labelText: t.textWithVariable),
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['text'] = v;
                                },
                              ),
                            ),
                            IconButton(
                              tooltip: 'Duplicate',
                              onPressed: () {
                                blocks.insert(i + 1, Map<String, dynamic>.from(b));
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.copy),
                            ),
                            IconButton(
                              tooltip: 'Up',
                              onPressed: i == 0 ? null : () {
                                final cur = blocks.removeAt(i);
                                blocks.insert(i - 1, cur);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: 'Down',
                              onPressed: i >= blocks.length - 1 ? null : () {
                                final cur = blocks.removeAt(i);
                                blocks.insert(i + 1, cur);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.arrow_downward),
                            ),
                            IconButton(
                              onPressed: () {
                                blocks.removeAt(i);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SizedBox(
                              width: 160,
                              child: DropdownButtonFormField<String>(
                                value: (align.isEmpty ? null : align),
                                items: [
                                  DropdownMenuItem(value: 'left', child: Text(t.left)),
                                  DropdownMenuItem(value: 'center', child: Text(t.center)),
                                  DropdownMenuItem(value: 'right', child: Text(t.right)),
                                ],
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['align'] = v ?? '';
                                },
                                decoration: InputDecoration(labelText: t.alignment),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: showIfCtrl,
                                decoration: InputDecoration(labelText: t.showIfCondition),
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['showIf'] = v;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              } else if (type == 'image') {
                final srcCtrl = TextEditingController(text: (b['props']?['src'] ?? '').toString());
                final altCtrl = TextEditingController(text: (b['props']?['alt'] ?? '').toString());
                final showIfCtrl = TextEditingController(text: (b['props']?['showIf'] ?? '').toString());
                final widthCtrl = TextEditingController(text: (b['props']?['width']?.toString() ?? ''));
                final heightCtrl = TextEditingController(text: (b['props']?['height']?.toString() ?? ''));
                return Card(
                  key: ValueKey('img_$i'),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.image_outlined),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: srcCtrl,
                                decoration: const InputDecoration(labelText: 'src (URL یا {{ var }})'),
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['src'] = v;
                                },
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                blocks.removeAt(i);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: widthCtrl,
                                decoration: const InputDecoration(labelText: 'width (px)'),
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  if (v.trim().isEmpty) {
                                    b['props']['width'] = null;
                                  } else {
                                    final n = int.tryParse(v.trim());
                                    if (n == null) {
                                      b['props']['width'] = null;
                                    } else {
                                      final step = 4;
                                      b['props']['width'] = ((n / step).round() * step);
                                    }
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: heightCtrl,
                                decoration: const InputDecoration(labelText: 'height (px)'),
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  if (v.trim().isEmpty) {
                                    b['props']['height'] = null;
                                  } else {
                                    final n = int.tryParse(v.trim());
                                    if (n == null) {
                                      b['props']['height'] = null;
                                    } else {
                                      final step = 4;
                                      b['props']['height'] = ((n / step).round() * step);
                                    }
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: altCtrl,
                                decoration: const InputDecoration(labelText: 'alt'),
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['alt'] = v;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(labelText: 'asset name (assets.images[name])'),
                                onSubmitted: (v) {
                                  if (v.trim().isEmpty) return;
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['src'] = 'asset:${v.trim()}';
                                  srcCtrl.text = b['props']['src'];
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(labelText: 'data URI (paste)'),
                                onSubmitted: (v) {
                                  if (v.trim().isEmpty) return;
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['src'] = v.trim();
                                  srcCtrl.text = b['props']['src'];
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                                final f = res?.files.isNotEmpty == true ? res!.files.first : null;
                                if (f == null) return;
                                final bytes = f.bytes;
                                if (bytes == null) return;
                                String ext = '';
                                if (f.extension != null && f.extension!.isNotEmpty) {
                                  ext = f.extension!.toLowerCase();
                                } else if (f.name.contains('.')) {
                                  ext = f.name.split('.').last.toLowerCase();
                                }
                                String mime = 'image/png';
                                if (ext == 'jpg' || ext == 'jpeg') mime = 'image/jpeg';
                                if (ext == 'gif') mime = 'image/gif';
                                final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
                                b['props'] ??= <String, dynamic>{};
                                b['props']['src'] = dataUri;
                                srcCtrl.text = dataUri;
                                (context as Element).markNeedsBuild();
                              } catch (_) {}
                            },
                            icon: const Icon(Icons.file_upload, size: 18),
                            label: const Text('انتخاب فایل و درج Data URI'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: showIfCtrl,
                          decoration: const InputDecoration(labelText: 'showIf (اختیاری، Jinja condition)'),
                          onChanged: (v) {
                            b['props'] ??= <String, dynamic>{};
                            b['props']['showIf'] = v;
                          },
                        ),
                      ],
                    ),
                  ),
                );
              } else if (type == 'table') {
                final itemsVarCtrl = TextEditingController(text: (b['props']?['items'] ?? 'items').toString());
                final cols = List<Map<String, dynamic>>.from((b['props']?['columns'] as List?) ?? const []);
                final showIfCtrl = TextEditingController(text: (b['props']?['showIf'] ?? '').toString());
                return Card(
                  key: ValueKey('table_$i'),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.table_chart),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: itemsVarCtrl,
                                decoration: const InputDecoration(labelText: 'نام آرایه (مثلاً items)'),
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['items'] = v;
                                },
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                blocks.removeAt(i);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ...cols.asMap().entries.map((e) {
                              final col = e.value;
                              final keyCtrl = TextEditingController(text: (col['key'] ?? '').toString());
                              final titleCtrl = TextEditingController(text: (col['title'] ?? '').toString());
                              return SizedBox(
                                width: 280,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: keyCtrl,
                                        decoration: const InputDecoration(labelText: 'key'),
                                        onChanged: (v) {
                                          col['key'] = v;
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: TextField(
                                        controller: titleCtrl,
                                        decoration: const InputDecoration(labelText: 'title'),
                                        onChanged: (v) {
                                          col['title'] = v;
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          children: cols.asMap().entries.map((e) {
                            final col = e.value;
                            String fmt = (col['format'] ?? '').toString();
                            return DropdownButton<String>(
                              value: fmt.isEmpty ? null : fmt,
                              hint: const Text('format'),
                              items: const [
                                DropdownMenuItem(value: 'money', child: Text('money')),
                                DropdownMenuItem(value: 'date', child: Text('date')),
                                DropdownMenuItem(value: '', child: Text('none')),
                              ],
                              onChanged: (v) {
                                col['format'] = v ?? '';
                                setSt(() {});
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: showIfCtrl,
                          decoration: const InputDecoration(labelText: 'showIf (اختیاری، Jinja condition)'),
                          onChanged: (v) {
                            b['props'] ??= <String, dynamic>{};
                            b['props']['showIf'] = v;
                          },
                        ),
                      ],
                    ),
                  ),
                );
              } else if (type == 'totals') {
                final items = List<Map<String, dynamic>>.from((b['props']?['items'] as List?) ?? const []);
                final showIfCtrl = TextEditingController(text: (b['props']?['showIf'] ?? '').toString());
                return Card(
                  key: ValueKey('totals_$i'),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.summarize),
                            const SizedBox(width: 8),
                            Text('Totals', style: Theme.of(context).textTheme.titleMedium),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: () {
                                items.add({'title': 'آیتم', 'expr': '0', 'format': ''});
                                b['props'] ??= <String, dynamic>{};
                                b['props']['items'] = items;
                                setSt(() {});
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('افزودن ردیف'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...items.asMap().entries.map((e) {
                          final idx = e.key;
                          final it = e.value;
                          final titleCtrl = TextEditingController(text: (it['title'] ?? '').toString());
                          final exprCtrl = TextEditingController(text: (it['expr'] ?? '').toString());
                          String fmt = (it['format'] ?? '').toString();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: titleCtrl,
                                    decoration: const InputDecoration(labelText: 'عنوان'),
                                    onChanged: (v) => it['title'] = v,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: exprCtrl,
                                    decoration: const InputDecoration(labelText: 'expr (مثلاً items|sum(attribute=\"amount\"))'),
                                    onChanged: (v) => it['expr'] = v,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                DropdownButton<String>(
                                  value: fmt.isEmpty ? null : fmt,
                                  hint: const Text('format'),
                                  items: const [
                                    DropdownMenuItem(value: 'money', child: Text('money')),
                                    DropdownMenuItem(value: 'date', child: Text('date')),
                                    DropdownMenuItem(value: '', child: Text('none')),
                                  ],
                                  onChanged: (v) {
                                    it['format'] = v ?? '';
                                    setSt(() {});
                                  },
                                ),
                                IconButton(
                                  onPressed: () {
                                    items.removeAt(idx);
                                    b['props'] ??= <String, dynamic>{};
                                    b['props']['items'] = items;
                                    setSt(() {});
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        TextField(
                          controller: showIfCtrl,
                          decoration: const InputDecoration(labelText: 'showIf (اختیاری، Jinja condition)'),
                          onChanged: (v) {
                            b['props'] ??= <String, dynamic>{};
                            b['props']['showIf'] = v;
                          },
                        ),
                      ],
                    ),
                  ),
                );
              } else if (type == 'divider') {
                final thicknessCtrl = TextEditingController(text: (b['props']?['thickness']?.toString() ?? '1'));
                return Card(
                  key: ValueKey('divider_$i'),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.horizontal_rule),
                            const SizedBox(width: 8),
                            const Text('Divider'),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Duplicate',
                              onPressed: () {
                                blocks.insert(i + 1, Map<String, dynamic>.from(b));
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.copy),
                            ),
                            IconButton(
                              tooltip: 'Up',
                              onPressed: i == 0 ? null : () {
                                final cur = blocks.removeAt(i);
                                blocks.insert(i - 1, cur);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: 'Down',
                              onPressed: i >= blocks.length - 1 ? null : () {
                                final cur = blocks.removeAt(i);
                                blocks.insert(i + 1, cur);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.arrow_downward),
                            ),
                            IconButton(
                              onPressed: () {
                                blocks.removeAt(i);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: thicknessCtrl,
                                decoration: const InputDecoration(labelText: 'thickness (px)'),
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['thickness'] = double.tryParse(v.trim()) ?? 1.0;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              } else if (type == 'spacer') {
                final heightCtrl = TextEditingController(text: (b['props']?['height']?.toString() ?? '12'));
                return Card(
                  key: ValueKey('spacer_$i'),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.space_bar),
                            const SizedBox(width: 8),
                            const Text('Spacer'),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Duplicate',
                              onPressed: () {
                                blocks.insert(i + 1, Map<String, dynamic>.from(b));
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.copy),
                            ),
                            IconButton(
                              tooltip: 'Up',
                              onPressed: i == 0 ? null : () {
                                final cur = blocks.removeAt(i);
                                blocks.insert(i - 1, cur);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: 'Down',
                              onPressed: i >= blocks.length - 1 ? null : () {
                                final cur = blocks.removeAt(i);
                                blocks.insert(i + 1, cur);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.arrow_downward),
                            ),
                            IconButton(
                              onPressed: () {
                                blocks.removeAt(i);
                                onChanged();
                                setSt(() {});
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: heightCtrl,
                                decoration: const InputDecoration(labelText: 'height (px)'),
                                onChanged: (v) {
                                  b['props'] ??= <String, dynamic>{};
                                  b['props']['height'] = double.tryParse(v.trim()) ?? 12.0;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }
              return ListTile(key: ValueKey('blk_$i'), title: Text(t.blockType(type)));
            },
          ),
        ),
      ],
    );
  }
  @override
  void initState() {
    super.initState();
    _service = ReportTemplateService(ApiClient());
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final items = await _service.listTemplates(
        businessId: widget.businessId,
        moduleKey: _moduleCtrl.text.trim().isEmpty ? null : _moduleCtrl.text.trim(),
        subtype: _subtypeCtrl.text.trim().isEmpty ? null : _subtypeCtrl.text.trim(),
        status: _statusFilter,
      );
      setState(() {
        _items = items;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createDialog() async {
    final t = AppLocalizations.of(context);
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.templates),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'نام قالب'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'توضیحات'),
                  ),
                  const SizedBox(height: 12),
                  Text('تنظیمات صفحه', style: Theme.of(context).textTheme.titleSmall),
                  Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: _paperSize,
                          decoration: InputDecoration(
                            labelText: t.pageSize,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'A4', child: Text('A4')),
                            DropdownMenuItem(value: 'Letter', child: Text('Letter')),
                          ],
                          onChanged: (v) => setState(() => _paperSize = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: _orientation,
                          decoration: InputDecoration(
                            labelText: t.orientation,
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(value: 'portrait', child: Text(t.portrait)),
                            DropdownMenuItem(value: 'landscape', child: Text(t.landscape)),
                          ],
                          onChanged: (v) => setState(() => _orientation = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginTopCtrl,
                                decoration: InputDecoration(
                                  labelText: t.marginTop,
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginRightCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'راست (mm)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginBottomCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'پایین (mm)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginLeftCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'چپ (mm)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DefaultTabController(
                    length: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          labelColor: Theme.of(context).colorScheme.primary,
                          tabs: const [
                            Tab(text: 'HTML'),
                            Tab(text: 'CSS'),
                            Tab(text: 'Header'),
                            Tab(text: 'Footer'),
                          ],
                        ),
                        SizedBox(
                          height: 320,
                          child: TabBarView(
                            children: [
                              TextField(
                                controller: _htmlCtrl,
                                maxLines: 14,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'HTML محتوا (Jinja2 variables allowed)',
                                ),
                              ),
                              TextField(
                                controller: _cssCtrl,
                                maxLines: 14,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'CSS اختیاری',
                                ),
                              ),
                              TextField(
                                controller: _headerCtrl,
                                maxLines: 14,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'HTML هدر (اختیاری)',
                                ),
                              ),
                              TextField(
                                controller: _footerCtrl,
                                maxLines: 14,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'HTML فوتر (اختیاری)',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
            FilledButton(
              onPressed: () async {
                try {
                  Map<String, dynamic>? margins;
                  double? _parse(String s) {
                    try {
                      if (s.trim().isEmpty) return null;
                      return double.parse(s.trim());
                    } catch (_) {
                      return null;
                    }
                  }
                  final mt = _parse(_marginTopCtrl.text);
                  final mr = _parse(_marginRightCtrl.text);
                  final mb = _parse(_marginBottomCtrl.text);
                  final ml = _parse(_marginLeftCtrl.text);
                  margins = {
                    if (mt != null) 'top': mt,
                    if (mr != null) 'right': mr,
                    if (mb != null) 'bottom': mb,
                    if (ml != null) 'left': ml,
                  };
                  if (margins.isEmpty) margins = null;
                  final id = await _service.createTemplate(
                    businessId: widget.businessId,
                    moduleKey: _moduleCtrl.text.trim().isEmpty ? 'invoices' : _moduleCtrl.text.trim(),
                    subtype: _subtypeCtrl.text.trim().isEmpty ? 'list' : _subtypeCtrl.text.trim(),
                    name: _nameCtrl.text.trim().isEmpty ? 'Template' : _nameCtrl.text.trim(),
                    description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                    contentHtml: _htmlCtrl.text,
                    contentCss: _cssCtrl.text.trim().isEmpty ? null : _cssCtrl.text,
                    headerHtml: _headerCtrl.text.trim().isEmpty ? null : _headerCtrl.text,
                    footerHtml: _footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text,
                    paperSize: _paperSize,
                    orientation: _orientation,
                    margins: margins,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.templateCreatedWithId(id))));
                  await _fetch();
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t.createError(e.toString()))));
                }
              },
              child: Text(t.create),
            ),
          ],
        );
      },
    );
  }

  Future<void> _togglePublish(Map<String, dynamic> item) async {
    final published = (item['status'] == 'published');
    final next = !published;
    await _service.publish(
      businessId: widget.businessId,
      templateId: (item['id'] as num).toInt(),
      published: next,
    );
    await _fetch();
  }

  Future<void> _previewTemplate(Map<String, dynamic> item) async {
    try {
      final full = await _service.getTemplate(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
      );
      final res = await _service.preview(
        businessId: widget.businessId,
        contentHtml: (full['content_html'] ?? '').toString(),
        contentCss: (full['content_css'] ?? '').toString().isEmpty ? null : (full['content_css'] ?? '').toString(),
        headerHtml: (full['header_html'] ?? '').toString().isEmpty ? null : (full['header_html'] ?? '').toString(),
        footerHtml: (full['footer_html'] ?? '').toString().isEmpty ? null : (full['footer_html'] ?? '').toString(),
        context: const <String, dynamic>{},
      );
      if (!mounted) return;
      final len = res['content_length'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('پیش‌نمایش موفق (طول PDF: $len بایت)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در پیش‌نمایش: $e')));
    }
  }

  Future<void> _editDialog(Map<String, dynamic> item) async {
    Map<String, dynamic> full = const <String, dynamic>{};
    bool isBuilder = false;
    try {
      full = await _service.getTemplate(
        businessId: widget.businessId,
        templateId: (item['id'] as num).toInt(),
      );
      isBuilder = (full['engine'] ?? '').toString() == 'builder';
      _nameCtrl.text = (full['name'] ?? '').toString();
      _descCtrl.text = (full['description'] ?? '').toString();
      _htmlCtrl.text = (full['content_html'] ?? '').toString();
      _cssCtrl.text = (full['content_css'] ?? '').toString();
      _headerCtrl.text = (full['header_html'] ?? '').toString();
      _footerCtrl.text = (full['footer_html'] ?? '').toString();
      _paperSize = (full['paper_size'] ?? _paperSize)?.toString();
      _orientation = (full['orientation'] ?? _orientation)?.toString();
      final margins = (full['margins'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      _marginTopCtrl.text = (margins['top']?.toString() ?? _marginTopCtrl.text);
      _marginRightCtrl.text = (margins['right']?.toString() ?? _marginRightCtrl.text);
      _marginBottomCtrl.text = (margins['bottom']?.toString() ?? _marginBottomCtrl.text);
      _marginLeftCtrl.text = (margins['left']?.toString() ?? _marginLeftCtrl.text);
    } catch (_) {}

    if (!context.mounted) return;
    final ctx = context;
    await showDialog(
      context: ctx,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('ویرایش قالب'),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isBuilder)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final assets = (full['assets'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
                          final design = (assets['builder_design'] as Map?)?.cast<String, dynamic>();
                          _openBuilderDialogAdvanced(
                            initialDesign: design ?? const <String, dynamic>{},
                            initialAssets: assets,
                            existingTemplateId: (item['id'] as num).toInt(),
                          );
                        },
                        icon: const Icon(Icons.view_quilt),
                        label: const Text('ویرایش در سازنده بصری'),
                      ),
                    ),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'نام قالب'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(labelText: 'توضیحات'),
                  ),
                  const SizedBox(height: 12),
                  Text('تنظیمات صفحه', style: Theme.of(context).textTheme.titleSmall),
                  Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: _paperSize,
                          decoration: const InputDecoration(labelText: 'سایز صفحه', isDense: true, border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'A4', child: Text('A4')),
                            DropdownMenuItem(value: 'Letter', child: Text('Letter')),
                          ],
                          onChanged: (v) => setState(() => _paperSize = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: _orientation,
                          decoration: const InputDecoration(labelText: 'جهت', isDense: true, border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 'portrait', child: Text('Portrait')),
                            DropdownMenuItem(value: 'landscape', child: Text('Landscape')),
                          ],
                          onChanged: (v) => setState(() => _orientation = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginTopCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'بالا (mm)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginRightCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'راست (mm)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginBottomCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'پایین (mm)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _marginLeftCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'چپ (mm)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  EnglishDigitsFormatter(),
                                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DefaultTabController(
                    length: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          labelColor: Theme.of(context).colorScheme.primary,
                          tabs: const [
                            Tab(text: 'HTML'),
                            Tab(text: 'CSS'),
                            Tab(text: 'Header'),
                            Tab(text: 'Footer'),
                          ],
                        ),
                        SizedBox(
                          height: 320,
                          child: TabBarView(
                            children: [
                              TextField(
                                controller: _htmlCtrl,
                                maxLines: 14,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'HTML محتوا (Jinja2 variables allowed)',
                                ),
                              ),
                              TextField(
                                controller: _cssCtrl,
                                maxLines: 14,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'CSS اختیاری',
                                ),
                              ),
                              TextField(
                                controller: _headerCtrl,
                                maxLines: 14,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'HTML هدر (اختیاری)',
                                ),
                              ),
                              TextField(
                                controller: _footerCtrl,
                                maxLines: 14,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'HTML فوتر (اختیاری)',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
            TextButton(
              onPressed: () async {
                await _previewTemplate(item);
              },
              child: const Text('پیش‌نمایش'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  Map<String, dynamic>? margins;
                  double? _parse(String s) {
                    try {
                      if (s.trim().isEmpty) return null;
                      return double.parse(s.trim());
                    } catch (_) {
                      return null;
                    }
                  }
                  final mt = _parse(_marginTopCtrl.text);
                  final mr = _parse(_marginRightCtrl.text);
                  final mb = _parse(_marginBottomCtrl.text);
                  final ml = _parse(_marginLeftCtrl.text);
                  margins = {
                    if (mt != null) 'top': mt,
                    if (mr != null) 'right': mr,
                    if (mb != null) 'bottom': mb,
                    if (ml != null) 'left': ml,
                  };
                  if (margins.isEmpty) margins = null;
                  final changes = <String, dynamic>{
                    'name': _nameCtrl.text.trim(),
                    'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                    'content_html': _htmlCtrl.text,
                    'content_css': _cssCtrl.text.trim().isEmpty ? null : _cssCtrl.text,
                    'header_html': _headerCtrl.text.trim().isEmpty ? null : _headerCtrl.text,
                    'footer_html': _footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text,
                    'paper_size': _paperSize,
                    'orientation': _orientation,
                    if (margins != null) 'margins': margins,
                  };
                  await _service.updateTemplate(
                    businessId: widget.businessId,
                    templateId: (item['id'] as num).toInt(),
                    changes: changes,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  await _fetch();
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('خطا در ویرایش: $e')));
                }
              },
              child: const Text('ذخیره'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setDefault(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تایید'),
        content: const Text('این قالب به‌عنوان پیش‌فرض تنظیم شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تایید')),
        ],
      ),
    );
    if (ok != true) return;
    await _service.setDefault(
      businessId: widget.businessId,
      moduleKey: (_moduleCtrl.text.trim().isEmpty ? 'invoices' : _moduleCtrl.text.trim()),
      subtype: (_subtypeCtrl.text.trim().isEmpty ? 'list' : _subtypeCtrl.text.trim()),
      templateId: (item['id'] as num).toInt(),
    );
    await _fetch();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف قالب'),
        content: const Text('آیا از حذف این قالب مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await _service.deleteTemplate(
      businessId: widget.businessId,
      templateId: (item['id'] as num).toInt(),
    );
    await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${t.templates} (${_moduleCtrl.text}${_subtypeCtrl.text.isNotEmpty ? '/${_subtypeCtrl.text}' : ''})'),
        actions: [
          if (_canWrite)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FilledButton.icon(
                onPressed: _createDialog,
                icon: const Icon(Icons.add),
                label: const Text('قالب جدید'),
              ),
            ),
          if (_canWrite)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OutlinedButton.icon(
                onPressed: _openBuilderDialogAdvanced,
                icon: const Icon(Icons.view_quilt),
                label: const Text('سازنده بصری'),
              ),
            ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () async {
              // Export: از آیتم انتخاب‌شده‌ای وجود ندارد؛ ساده‌ترین حالت: اگر تنها یک آیتم انتخاب نیست، پیغام
              if (_items.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('موردی برای خروجی وجود ندارد')));
                return;
              }
              try {
                // فعلاً اولین مورد را به‌عنوان نمونه خروجی می‌گیریم؛ در آینده selection اضافه می‌شود
                final item = _items.first;
                if (!context.mounted) return;
                final ctx = context;
                final full = await _service.getTemplate(
                  businessId: widget.businessId,
                  templateId: (item['id'] as num).toInt(),
                );
                if (!ctx.mounted) return;
                await showDialog(
                  context: ctx,
                  builder: (ctx) {
                    return AlertDialog(
                      title: const Text('خروجی JSON قالب'),
                      content: SizedBox(
                        width: 700,
                          child: SingleChildScrollView(
                          child: SelectableText(
                            JsonEncoder.withIndent('  ').convert({
                              'module_key': full['module_key'],
                              'subtype': full['subtype'],
                              'name': full['name'],
                              'description': full['description'],
                              'content_html': full['content_html'],
                              'content_css': full['content_css'],
                              'header_html': full['header_html'],
                              'footer_html': full['footer_html'],
                              'paper_size': full['paper_size'],
                              'orientation': full['orientation'],
                              'margins': full['margins'],
                              'assets': full['assets'],
                            }),
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
                      ],
                    );
                  },
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا در خروجی: $e')));
              }
            },
            icon: const Icon(Icons.file_download),
            label: const Text('Export JSON'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final ctrl = TextEditingController();
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Import JSON'),
                  content: SizedBox(
                    width: 700,
                    child: TextField(
                      controller: ctrl,
                      minLines: 10,
                      maxLines: 18,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'JSON قالب را اینجا Paste کنید',
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ورود')),
                  ],
                ),
              );
              if (ok == true) {
                if (!context.mounted) return;
                final ctx = context;
                try {
                  final data = jsonDecode(ctrl.text) as Map<String, dynamic>;
                  _moduleCtrl.text = (data['module_key'] ?? _moduleCtrl.text).toString();
                  _subtypeCtrl.text = (data['subtype'] ?? _subtypeCtrl.text).toString();
                  _nameCtrl.text = (data['name'] ?? _nameCtrl.text).toString();
                  _descCtrl.text = (data['description'] ?? _descCtrl.text).toString();
                  _htmlCtrl.text = (data['content_html'] ?? _htmlCtrl.text).toString();
                  _cssCtrl.text = (data['content_css'] ?? _cssCtrl.text).toString();
                  _headerCtrl.text = (data['header_html'] ?? _headerCtrl.text).toString();
                  _footerCtrl.text = (data['footer_html'] ?? _footerCtrl.text).toString();
                  _paperSize = (data['paper_size'] ?? _paperSize)?.toString();
                  _orientation = (data['orientation'] ?? _orientation)?.toString();
                  final margins = (data['margins'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
                  _marginTopCtrl.text = (margins['top']?.toString() ?? _marginTopCtrl.text);
                  _marginRightCtrl.text = (margins['right']?.toString() ?? _marginRightCtrl.text);
                  _marginBottomCtrl.text = (margins['bottom']?.toString() ?? _marginBottomCtrl.text);
                  _marginLeftCtrl.text = (margins['left']?.toString() ?? _marginLeftCtrl.text);
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('وارد شد. می‌توانید ذخیره کنید.')));
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('JSON نامعتبر: $e')));
                }
              }
            },
            icon: const Icon(Icons.file_upload),
            label: const Text('Import JSON'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _moduleCtrl,
                    decoration: const InputDecoration(labelText: 'module_key (مثلاً: invoices)'),
                    onSubmitted: (_) => _fetch(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _subtypeCtrl,
                    decoration: const InputDecoration(labelText: 'subtype (مثلاً: list یا detail)'),
                    onSubmitted: (_) => _fetch(),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (!context.mounted) return;
                    final ctx = context;
                    try {
                      final data = await _service.schema(
                        businessId: widget.businessId,
                        moduleKey: _moduleCtrl.text.trim().isEmpty ? 'invoices' : _moduleCtrl.text.trim(),
                        subtype: _subtypeCtrl.text.trim().isEmpty ? null : _subtypeCtrl.text.trim(),
                      );
                      if (!ctx.mounted) return;
                      final keys = (data['keys'] as List? ?? const []).cast<Map>();
                      await showDialog(
                        context: ctx,
                        builder: (ctx) {
                          return AlertDialog(
                            title: const Text('متغیرهای قابل استفاده'),
                            content: SizedBox(
                              width: 500,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: keys.map((m) {
                                    final name = (m['name'] ?? '').toString();
                                    final desc = (m['desc'] ?? '').toString();
                                    return ListTile(
                                      dense: true,
                                      title: Text(name),
                                      subtitle: desc.isNotEmpty ? Text(desc) : null,
                                      trailing: IconButton(
                                        tooltip: 'درج در HTML',
                                        icon: const Icon(Icons.input),
                                        onPressed: () {
                                          _htmlCtrl.text += '{{ $name }}';
                                          (ctx as Element).markNeedsBuild();
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
                            ],
                          );
                        },
                      );
                    } catch (e) {
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('خطا در دریافت schema: $e')));
                    }
                  },
                  icon: const Icon(Icons.help_outline),
                  label: const Text('راهنمای متغیرها'),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: _statusFilter,
                  hint: const Text('همه وضعیت‌ها'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('همه')),
                    DropdownMenuItem(value: 'published', child: Text('منتشر شده')),
                    DropdownMenuItem(value: 'draft', child: Text('پیش‌نویس')),
                  ],
                  onChanged: (v) {
                    setState(() => _statusFilter = v);
                    _fetch();
                  },
                ),
                const Spacer(),
                IconButton(onPressed: _fetch, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: Text(t.presetInvoicesList),
                    onPressed: () {
                      _moduleCtrl.text = 'invoices';
                      _subtypeCtrl.text = 'list';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetInvoicesDetail),
                    onPressed: () {
                      _moduleCtrl.text = 'invoices';
                      _subtypeCtrl.text = 'detail';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetReceiptsPaymentsList),
                    onPressed: () {
                      _moduleCtrl.text = 'receipts_payments';
                      _subtypeCtrl.text = 'list';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetReceiptsPaymentsDetail),
                    onPressed: () {
                      _moduleCtrl.text = 'receipts_payments';
                      _subtypeCtrl.text = 'detail';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetExpenseIncomeList),
                    onPressed: () {
                      _moduleCtrl.text = 'expense_income';
                      _subtypeCtrl.text = 'list';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetDocumentsList),
                    onPressed: () {
                      _moduleCtrl.text = 'documents';
                      _subtypeCtrl.text = 'list';
                      _fetch();
                    },
                  ),
                  ActionChip(
                    label: Text(t.presetDocumentsDetail),
                    onPressed: () {
                      _moduleCtrl.text = 'documents';
                      _subtypeCtrl.text = 'detail';
                      _fetch();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? const Center(child: Text('قالبی یافت نشد'))
                      : Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (ctx, idx) {
                              final it = _items[idx];
                              final isDefault = it['is_default'] == true;
                              final status = (it['status'] ?? '').toString();
                              return ListTile(
                                title: Text(it['name']?.toString() ?? '-'),
                                subtitle: Text(
                                  'status: $status   module: ${it['module_key']}   subtype: ${it['subtype'] ?? '-'}   version: ${it['version'] ?? '-'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                leading: Icon(isDefault ? Icons.star : Icons.description),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: status == 'published' ? 'به پیش‌نویس برگردان' : 'انتشار',
                                        onPressed: () => _togglePublish(it),
                                        icon: Icon(status == 'published' ? Icons.visibility_off : Icons.publish),
                                      ),
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: 'پیش‌نمایش',
                                        onPressed: () => _previewTemplate(it),
                                        icon: const Icon(Icons.visibility),
                                      ),
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: 'ویرایش',
                                        onPressed: () => _editDialog(it),
                                        icon: const Icon(Icons.edit),
                                      ),
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: 'تنظیم به‌عنوان پیش‌فرض',
                                        onPressed: () => _setDefault(it),
                                        icon: const Icon(Icons.star),
                                      ),
                                    if (_canWrite)
                                      IconButton(
                                        tooltip: 'حذف',
                                        onPressed: () => _delete(it),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

}

