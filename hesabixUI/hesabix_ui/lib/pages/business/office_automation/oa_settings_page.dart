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
  List<Map<String, dynamic>> _signatures = [];
  List<Map<String, dynamic>> _signPaths = [];
  List<Map<String, dynamic>> _rules = [];
  List<Map<String, dynamic>> _ece = [];
  List<Map<String, dynamic>> _positions = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this);
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
      _signatures = await _svc.listSignatures(businessId: widget.businessId);
      _signPaths = await _svc.listSignPaths(businessId: widget.businessId);
      _rules = await _svc.listCartableRules(businessId: widget.businessId);
      _ece = await _svc.listEce(businessId: widget.businessId);
      _positions = await _svc.listPositions(businessId: widget.businessId, includeInactive: true);
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
            Tab(text: t.oaSignatures),
            Tab(text: t.oaSignPath),
            Tab(text: t.oaCartableRules),
            Tab(text: t.oaEce),
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
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(t.oaImageSignatureNote),
                      ),
                    ),
                    Expanded(
                      child: _listPane(
                  empty: t.oaEmptySignatures,
                  onAdd: () => _editSignature(),
                  children: [
                    for (final s in _signatures)
                      ListTile(
                        leading: Icon(s['is_default'] == true ? Icons.draw : Icons.draw_outlined),
                        title: Text('${s['title']}'),
                        subtitle: Text(s['is_default'] == true ? t.oaMakeDefault : ''),
                        onTap: () => _editSignature(existing: s),
                      ),
                  ],
                      ),
                    ),
                  ],
                ),
                _listPane(
                  empty: t.oaEmptySignPaths,
                  onAdd: () => _editSignPath(),
                  children: [
                    for (final p in _signPaths)
                      ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text('${p['name']}'),
                        subtitle: Text('${p['letter_kind'] ?? t.oaAllKinds} · ${(p['steps'] as List? ?? const []).length}'),
                        onTap: () => _editSignPath(existing: p),
                      ),
                  ],
                ),
                _listPane(
                  empty: t.oaEmptyRules,
                  onAdd: () => _editRule(),
                  children: [
                    for (final r in _rules)
                      ListTile(
                        leading: const Icon(Icons.rule_outlined),
                        title: Text('${r['name']}'),
                        subtitle: Text('${r['conditions'] ?? ''}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            final id = oaId(r['id']);
                            if (id == null) return;
                            try {
                              await _svc.deleteCartableRule(businessId: widget.businessId, ruleId: id);
                              await _load();
                            } catch (e) {
                              if (!context.mounted) return;
                              SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                            }
                          },
                        ),
                        onTap: () => _editRule(existing: r),
                      ),
                  ],
                ),
                _listPane(
                  empty: t.oaEmptyEce,
                  onAdd: _importEceDialog,
                  children: [
                    for (final m in _ece)
                      ListTile(
                        leading: Icon(m['direction'] == 'in' ? Icons.call_received : Icons.call_made),
                        title: Text('${m['receipt_number'] ?? m['to_email'] ?? m['from_email'] ?? m['id']}'),
                        subtitle: Text(
                          [
                            m['direction'] == 'in' ? t.oaKindIncoming : t.oaKindOutgoing,
                            '${m['status'] ?? ''}',
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _editSignature({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final title = TextEditingController(text: '${existing?['title'] ?? t.oaSignature}');
    var isDefault = existing?['is_default'] == true;
    String? fileId = existing?['image_file_id']?.toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaSignatures),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: title, decoration: InputDecoration(labelText: t.oaFormatName)),
                SwitchListTile(title: Text(t.oaMakeDefault), value: isDefault, onChanged: (v) => setLocal(() => isDefault = v)),
                OaFileImageField(
                  businessId: widget.businessId,
                  label: t.oaSignatureImage,
                  fileId: fileId,
                  onChanged: (id) => setLocal(() => fileId = id),
                ),
              ],
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
      if (oaId(existing?['id']) != null) 'id': oaId(existing?['id']),
      'title': title.text.trim(),
      'is_default': isDefault,
      'image_file_id': fileId,
    };
    title.dispose();
    if (ok != true) return;
    try {
      await _svc.upsertSignature(businessId: widget.businessId, payload: payload);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _editSignPath({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    var kind = (existing?['letter_kind'] as String?) ?? 'outgoing';
    var requireBefore = existing?['require_before_register'] == true;
    final steps = List<Map<String, dynamic>>.from((existing?['steps'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
    if (steps.isEmpty) steps.add({'position_id': null, 'is_required': true});
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaSignPath),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: name, decoration: InputDecoration(labelText: t.oaTemplateName)),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: InputDecoration(labelText: t.oaLetterKind),
                    items: [
                      DropdownMenuItem(value: 'outgoing', child: Text(t.oaKindOutgoing)),
                      DropdownMenuItem(value: 'internal', child: Text(t.oaKindInternal)),
                      DropdownMenuItem(value: 'incoming', child: Text(t.oaKindIncoming)),
                    ],
                    onChanged: (v) => setLocal(() => kind = v ?? 'outgoing'),
                  ),
                  SwitchListTile(title: Text(t.oaRequireBeforeRegister), value: requireBefore, onChanged: (v) => setLocal(() => requireBefore = v)),
                  for (var i = 0; i < steps.length; i++)
                    DropdownButtonFormField<int?>(
                      initialValue: oaId(steps[i]['position_id']),
                      decoration: InputDecoration(labelText: '${t.oaToPosition} ${i + 1}'),
                      items: [
                        for (final p in _positions)
                          DropdownMenuItem(value: oaId(p['id']), child: Text('${p['title'] ?? p['code']}')),
                      ],
                      onChanged: (v) => setLocal(() => steps[i]['position_id'] = v),
                    ),
                  TextButton.icon(
                    onPressed: () => setLocal(() => steps.add({'position_id': null, 'is_required': true})),
                    icon: const Icon(Icons.add),
                    label: Text(t.add),
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
      if (oaId(existing?['id']) != null) 'id': oaId(existing?['id']),
      'name': name.text.trim(),
      'letter_kind': kind,
      'require_before_register': requireBefore,
      'steps': [
        for (var i = 0; i < steps.length; i++)
          if (oaId(steps[i]['position_id']) != null)
            {'position_id': oaId(steps[i]['position_id']), 'sort_order': i, 'is_required': true},
      ],
    };
    name.dispose();
    if (ok != true || (payload['name'] as String).isEmpty) return;
    try {
      await _svc.saveSignPath(businessId: widget.businessId, payload: payload);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _editRule({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    final needle = TextEditingController(text: '${(existing?['conditions'] as Map?)?['subject_contains'] ?? ''}');
    var markSeen = (existing?['actions'] as Map?)?['mark_seen'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaCartableRules),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: InputDecoration(labelText: t.oaTemplateName)),
                const SizedBox(height: 8),
                TextField(controller: needle, decoration: InputDecoration(labelText: t.oaSubjectContains)),
                SwitchListTile(title: Text(t.oaMarkSeen), value: markSeen, onChanged: (v) => setLocal(() => markSeen = v)),
              ],
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
      if (oaId(existing?['id']) != null) 'id': oaId(existing?['id']),
      'name': name.text.trim(),
      'conditions': {if (needle.text.trim().isNotEmpty) 'subject_contains': needle.text.trim()},
      'actions': {'mark_seen': markSeen},
    };
    name.dispose();
    needle.dispose();
    if (ok != true || (payload['name'] as String).isEmpty) return;
    try {
      await _svc.saveCartableRule(businessId: widget.businessId, payload: payload);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _importEceDialog() async {
    final t = AppLocalizations.of(context);
    final xml = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.oaImportEce),
        content: SizedBox(
          width: 520,
          child: TextField(controller: xml, maxLines: 12, decoration: InputDecoration(labelText: t.oaEceXml, border: const OutlineInputBorder())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaImportEce)),
        ],
      ),
    );
    final text = xml.text.trim();
    xml.dispose();
    if (ok != true || text.isEmpty) return;
    try {
      final positions = await _svc.listMyPositions(businessId: widget.businessId);
      final pid = oaId(positions.isNotEmpty ? positions.first['id'] : null);
      if (pid == null) throw Exception(t.oaNoPositions);
      await _svc.importEce(businessId: widget.businessId, positionId: pid, xml: text);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
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
