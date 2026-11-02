import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/office_automation/oa_file_image_field.dart';
import '../../../widgets/office_automation/oa_letter_editor.dart';
import '../../../widgets/office_automation/oa_ui.dart';

class OaSettingsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OaSettingsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<OaSettingsPage> createState() => _OaSettingsPageState();
}

class _OaSettingsPageState extends State<OaSettingsPage> with SingleTickerProviderStateMixin {
  final OfficeAutomationService _svc = OfficeAutomationService();
  final _incoming = TextEditingController();
  final _outgoing = TextEditingController();
  final _internal = TextEditingController();
  final _footer = TextEditingController();
  late TabController _tabs;
  bool _loading = true;
  bool _enabled = true;
  String _calendar = 'jalali';
  String _paperSize = 'a4';
  String _orientation = 'portrait';
  String _bodyFormat = 'markdown';
  String? _letterheadId;
  String? _backgroundId;
  int _mTop = 20, _mRight = 20, _mBottom = 20, _mLeft = 20;
  int? _defaultFormatId;
  List<Map<String, dynamic>> _formats = [];
  List<Map<String, dynamic>> _templates = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _incoming.dispose();
    _outgoing.dispose();
    _internal.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _svc.getSettings(businessId: widget.businessId);
      _formats = await _svc.listFormats(businessId: widget.businessId, includeInactive: true);
      _templates = await _svc.listTemplates(businessId: widget.businessId, includeInactive: true);
      _enabled = data['enabled'] != false;
      _calendar = (data['numbering_calendar'] ?? 'jalali').toString();
      _incoming.text = (data['incoming_prefix'] ?? 'IN').toString();
      _outgoing.text = (data['outgoing_prefix'] ?? 'OUT').toString();
      _internal.text = (data['internal_prefix'] ?? 'INT').toString();
      _letterheadId = (data['letterhead_file_id'] ?? '').toString().isEmpty ? null : data['letterhead_file_id'].toString();
      _backgroundId = (data['background_file_id'] ?? '').toString().isEmpty ? null : data['background_file_id'].toString();
      _footer.text = (data['footer_text'] ?? '').toString();
      _paperSize = (data['paper_size'] ?? 'a4').toString();
      _orientation = (data['paper_orientation'] ?? 'portrait').toString();
      _bodyFormat = (data['default_body_format'] ?? 'markdown').toString();
      _defaultFormatId = oaId(data['default_format_id']);
      _mTop = (data['margin_top'] as num?)?.toInt() ?? 20;
      _mRight = (data['margin_right'] as num?)?.toInt() ?? 20;
      _mBottom = (data['margin_bottom'] as num?)?.toInt() ?? 20;
      _mLeft = (data['margin_left'] as num?)?.toInt() ?? 20;
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      await _svc.updateSettings(
        businessId: widget.businessId,
        payload: {
          'enabled': _enabled,
          'numbering_calendar': _calendar,
          'incoming_prefix': _incoming.text.trim(),
          'outgoing_prefix': _outgoing.text.trim(),
          'internal_prefix': _internal.text.trim(),
          'letterhead_file_id': _letterheadId,
          'background_file_id': _backgroundId,
          'footer_text': _footer.text.trim(),
          'paper_size': _paperSize,
          'paper_orientation': _orientation,
          'margin_top': _mTop,
          'margin_right': _mRight,
          'margin_bottom': _mBottom,
          'margin_left': _mLeft,
          'default_body_format': _bodyFormat,
          'default_format_id': _defaultFormatId,
        },
      );
      if (mounted) SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).save);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _editFormat({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    final footer = TextEditingController(text: '${existing?['footer_text'] ?? ''}');
    var paper = (existing?['paper_size'] ?? 'a4').toString();
    var orientation = (existing?['paper_orientation'] ?? 'portrait').toString();
    var isDefault = existing?['is_default'] == true;
    var mTop = (existing?['margin_top'] as num?)?.toInt() ?? 20;
    var mRight = (existing?['margin_right'] as num?)?.toInt() ?? 20;
    var mBottom = (existing?['margin_bottom'] as num?)?.toInt() ?? 20;
    var mLeft = (existing?['margin_left'] as num?)?.toInt() ?? 20;
    String? letterhead = existing?['letterhead_file_id']?.toString();
    String? background = existing?['background_file_id']?.toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? t.oaNewFormat : t.oaLetterFormat),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: name, decoration: InputDecoration(labelText: t.oaFormatName)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: paper,
                    decoration: InputDecoration(labelText: t.oaPaperSize),
                    items: [
                      DropdownMenuItem(value: 'a4', child: Text(t.oaPaperA4)),
                      DropdownMenuItem(value: 'a5', child: Text(t.oaPaperA5)),
                      DropdownMenuItem(value: 'letter', child: Text(t.oaPaperLetter)),
                    ],
                    onChanged: (v) => setLocal(() => paper = v ?? 'a4'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: orientation,
                    decoration: InputDecoration(labelText: t.oaPaperOrientation),
                    items: [
                      DropdownMenuItem(value: 'portrait', child: Text(t.oaPortrait)),
                      DropdownMenuItem(value: 'landscape', child: Text(t.oaLandscape)),
                    ],
                    onChanged: (v) => setLocal(() => orientation = v ?? 'portrait'),
                  ),
                  SwitchListTile(title: Text(t.oaMakeDefault), value: isDefault, onChanged: (v) => setLocal(() => isDefault = v)),
                  Text(t.oaMargins),
                  Row(
                    children: [
                      Expanded(child: _numField(t.oaMarginTop, mTop, (v) => setLocal(() => mTop = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _numField(t.oaMarginRight, mRight, (v) => setLocal(() => mRight = v))),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _numField(t.oaMarginBottom, mBottom, (v) => setLocal(() => mBottom = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _numField(t.oaMarginLeft, mLeft, (v) => setLocal(() => mLeft = v))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OaFileImageField(
                    businessId: widget.businessId,
                    label: t.oaLetterhead,
                    fileId: letterhead,
                    onChanged: (id) => setLocal(() => letterhead = id),
                  ),
                  const SizedBox(height: 8),
                  OaFileImageField(
                    businessId: widget.businessId,
                    label: t.oaBackground,
                    fileId: background,
                    onChanged: (id) => setLocal(() => background = id),
                  ),
                  TextField(controller: footer, decoration: InputDecoration(labelText: t.oaFooter), maxLines: 2),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    final payload = {
      'name': name.text.trim(),
      'paper_size': paper,
      'paper_orientation': orientation,
      'is_default': isDefault,
      'margin_top': mTop,
      'margin_right': mRight,
      'margin_bottom': mBottom,
      'margin_left': mLeft,
      'letterhead_file_id': letterhead,
      'background_file_id': background,
      'footer_text': footer.text.trim(),
    };
    name.dispose();
    footer.dispose();
    if (ok != true || (payload['name'] as String).isEmpty) return;
    try {
      final id = oaId(existing?['id']);
      if (id == null) {
        await _svc.createFormat(businessId: widget.businessId, payload: payload);
      } else {
        await _svc.updateFormat(businessId: widget.businessId, formatId: id, payload: payload);
      }
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _editTemplate({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    final subject = TextEditingController(text: '${existing?['subject'] ?? ''}');
    final body = TextEditingController(text: '${existing?['body'] ?? ''}');
    var kind = existing?['letter_kind']?.toString();
    var formatId = oaId(existing?['format_id']);
    var bodyFormat = (existing?['body_format'] ?? 'markdown').toString();
    var isDefault = existing?['is_default'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? t.oaNewTemplate : t.oaLetterTemplate),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: name, decoration: InputDecoration(labelText: t.oaTemplateName)),
                  TextField(controller: subject, decoration: InputDecoration(labelText: t.oaSubject)),
                  DropdownButtonFormField<String?>(
                    initialValue: kind,
                    decoration: InputDecoration(labelText: t.oaLetterKind),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(t.oaAllKinds)),
                      DropdownMenuItem(value: 'internal', child: Text(t.oaKindInternal)),
                      DropdownMenuItem(value: 'incoming', child: Text(t.oaKindIncoming)),
                      DropdownMenuItem(value: 'outgoing', child: Text(t.oaKindOutgoing)),
                    ],
                    onChanged: (v) => setLocal(() => kind = v),
                  ),
                  DropdownButtonFormField<int?>(
                    initialValue: _formats.any((e) => oaId(e['id']) == formatId) ? formatId : null,
                    decoration: InputDecoration(labelText: t.oaLetterFormat),
                    items: [
                      DropdownMenuItem<int?>(value: null, child: Text(t.oaDefaultFormat)),
                      for (final f in _formats)
                        if (oaId(f['id']) != null) DropdownMenuItem(value: oaId(f['id']), child: Text('${f['name']}')),
                    ],
                    onChanged: (v) => setLocal(() => formatId = v),
                  ),
                  SwitchListTile(title: Text(t.oaMakeDefault), value: isDefault, onChanged: (v) => setLocal(() => isDefault = v)),
                  const SizedBox(height: 8),
                  OaLetterEditor(
                    controller: body,
                    bodyFormat: bodyFormat == 'html' ? 'html' : 'markdown',
                    onFormatChanged: (v) => setLocal(() => bodyFormat = v),
                    minHeight: 180,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        ),
      ),
    );
    final payload = {
      'name': name.text.trim(),
      'subject': subject.text.trim(),
      'body': body.text,
      'body_format': bodyFormat,
      'letter_kind': kind,
      'format_id': formatId,
      'is_default': isDefault,
    };
    name.dispose();
    subject.dispose();
    body.dispose();
    if (ok != true || (payload['name'] as String).isEmpty) return;
    try {
      final id = oaId(existing?['id']);
      if (id == null) {
        await _svc.createTemplate(businessId: widget.businessId, payload: payload);
      } else {
        await _svc.updateTemplate(businessId: widget.businessId, templateId: id, payload: payload);
      }
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _numField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      initialValue: '$value',
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      onChanged: (v) => onChanged(int.tryParse(v) ?? value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaSettings),
        actions: [IconButton(icon: const Icon(Icons.save_outlined), onPressed: _save)],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(text: t.oaNumbering),
            Tab(text: t.oaStationery),
            Tab(text: t.oaFormats),
            Tab(text: t.oaTemplates),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    OaSectionCard(
                      child: Column(
                        children: [
                          SwitchListTile(title: Text(t.oaEnabled), value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
                          DropdownButtonFormField<String>(
                            initialValue: _calendar,
                            decoration: InputDecoration(labelText: t.oaNumberingCalendar),
                            items: [
                              DropdownMenuItem(value: 'jalali', child: Text(t.oaJalali)),
                              DropdownMenuItem(value: 'gregorian', child: Text(t.oaGregorian)),
                            ],
                            onChanged: (v) => setState(() => _calendar = v ?? 'jalali'),
                          ),
                          const SizedBox(height: 12),
                          TextField(controller: _incoming, decoration: InputDecoration(labelText: t.oaIncomingPrefix)),
                          const SizedBox(height: 8),
                          TextField(controller: _outgoing, decoration: InputDecoration(labelText: t.oaOutgoingPrefix)),
                          const SizedBox(height: 8),
                          TextField(controller: _internal, decoration: InputDecoration(labelText: t.oaInternalPrefix)),
                        ],
                      ),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    OaSectionCard(
                      title: t.oaStationery,
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _paperSize,
                            decoration: InputDecoration(labelText: t.oaPaperSize),
                            items: [
                              DropdownMenuItem(value: 'a4', child: Text(t.oaPaperA4)),
                              DropdownMenuItem(value: 'a5', child: Text(t.oaPaperA5)),
                              DropdownMenuItem(value: 'letter', child: Text(t.oaPaperLetter)),
                            ],
                            onChanged: (v) => setState(() => _paperSize = v ?? 'a4'),
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: _orientation,
                            decoration: InputDecoration(labelText: t.oaPaperOrientation),
                            items: [
                              DropdownMenuItem(value: 'portrait', child: Text(t.oaPortrait)),
                              DropdownMenuItem(value: 'landscape', child: Text(t.oaLandscape)),
                            ],
                            onChanged: (v) => setState(() => _orientation = v ?? 'portrait'),
                          ),
                          DropdownButtonFormField<int?>(
                            initialValue: _formats.any((e) => oaId(e['id']) == _defaultFormatId) ? _defaultFormatId : null,
                            decoration: InputDecoration(labelText: t.oaDefaultFormat),
                            items: [
                              DropdownMenuItem<int?>(value: null, child: Text(t.oaDefaultFormat)),
                              for (final f in _formats)
                                if (oaId(f['id']) != null)
                                  DropdownMenuItem(value: oaId(f['id']), child: Text('${f['name']}')),
                            ],
                            onChanged: (v) => setState(() => _defaultFormatId = v),
                          ),
                          DropdownButtonFormField<String>(
                            initialValue: _bodyFormat == 'html' ? 'html' : 'markdown',
                            decoration: InputDecoration(labelText: t.oaDefaultBodyFormat, helperText: t.oaDefaultBodyHint),
                            items: [
                              DropdownMenuItem(value: 'markdown', child: Text(t.oaMarkdown)),
                              DropdownMenuItem(value: 'html', child: Text(t.oaHtml)),
                            ],
                            onChanged: (v) => setState(() => _bodyFormat = v ?? 'markdown'),
                          ),
                          const SizedBox(height: 8),
                          Text(t.oaMargins),
                          Row(
                            children: [
                              Expanded(child: _numField(t.oaMarginTop, _mTop, (v) => setState(() => _mTop = v))),
                              const SizedBox(width: 8),
                              Expanded(child: _numField(t.oaMarginRight, _mRight, (v) => setState(() => _mRight = v))),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(child: _numField(t.oaMarginBottom, _mBottom, (v) => setState(() => _mBottom = v))),
                              const SizedBox(width: 8),
                              Expanded(child: _numField(t.oaMarginLeft, _mLeft, (v) => setState(() => _mLeft = v))),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OaFileImageField(
                            businessId: widget.businessId,
                            label: t.oaLetterhead,
                            fileId: _letterheadId,
                            onChanged: (id) => setState(() => _letterheadId = id),
                          ),
                          const SizedBox(height: 12),
                          OaFileImageField(
                            businessId: widget.businessId,
                            label: t.oaBackground,
                            fileId: _backgroundId,
                            onChanged: (id) => setState(() => _backgroundId = id),
                          ),
                          const SizedBox(height: 8),
                          TextField(controller: _footer, decoration: InputDecoration(labelText: t.oaFooter), maxLines: 2),
                          const SizedBox(height: 12),
                          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(t.save)),
                        ],
                      ),
                    ),
                  ],
                ),
                _listPane(
                  empty: t.oaEmptyFormats,
                  onAdd: () => _editFormat(),
                  children: [
                    for (final f in _formats)
                      ListTile(
                        leading: Icon(f['is_default'] == true ? Icons.star : Icons.description_outlined),
                        title: Text('${f['name']}'),
                        subtitle: Text('${f['paper_size']} · ${f['paper_orientation']}'),
                        onTap: () => _editFormat(existing: f),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final id = oaId(f['id']);
                            if (id == null) return;
                            try {
                              await _svc.deleteFormat(businessId: widget.businessId, formatId: id);
                              await _load();
                            } catch (e) {
                              if (!context.mounted) return;
                              SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                            }
                          },
                        ),
                      ),
                  ],
                ),
                _listPane(
                  empty: t.oaEmptyTemplates,
                  onAdd: () => _editTemplate(),
                  children: [
                    for (final tpl in _templates)
                      ListTile(
                        leading: Icon(tpl['is_default'] == true ? Icons.star : Icons.article_outlined),
                        title: Text('${tpl['name']}'),
                        subtitle: Text('${tpl['letter_kind'] ?? t.oaAllKinds} · ${tpl['body_format']}'),
                        onTap: () => _editTemplate(existing: tpl),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final id = oaId(tpl['id']);
                            if (id == null) return;
                            try {
                              await _svc.deleteTemplate(businessId: widget.businessId, templateId: id);
                              await _load();
                            } catch (e) {
                              if (!context.mounted) return;
                              SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _listPane({required String empty, required VoidCallback onAdd, required List<Widget> children}) {
    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(AppLocalizations.of(context).add)),
          ),
        ),
        Expanded(
          child: children.isEmpty
              ? Center(child: Text(empty))
              : ListView(children: children),
        ),
      ],
    );
  }
}
