import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../services/business_storage_service.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/date_input_field.dart';
import '../../../widgets/office_automation/oa_letter_editor.dart';
import '../../../widgets/office_automation/oa_letter_paper.dart';
import '../../../widgets/office_automation/oa_searchable_field.dart';
import '../../../widgets/office_automation/oa_ui.dart';
import 'oa_letter_print.dart';

class OaLetterPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;
  final int? letterId;
  final int? positionId;

  const OaLetterPage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
    this.letterId,
    this.positionId,
  });

  @override
  State<OaLetterPage> createState() => _OaLetterPageState();
}

class _OaLetterPageState extends State<OaLetterPage> with SingleTickerProviderStateMixin {
  final OfficeAutomationService _svc = OfficeAutomationService();
  final _storage = BusinessStorageService(ApiClient());
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _sender = TextEditingController();
  final _senderOrg = TextEditingController();
  final _receiver = TextEditingController();
  final _receiverOrg = TextEditingController();

  TabController? _mobileTabs;
  bool _loading = true;
  Map<String, dynamic> _letter = const {};
  List<Map<String, dynamic>> _positions = [];
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _formats = [];
  Map<String, dynamic> _settings = const {};
  int? _positionId;
  int? _senderPositionId;
  int? _receiverPositionId;
  int? _formatId;
  int? _templateId;
  Map<String, dynamic>? _senderPosition;
  Map<String, dynamic>? _receiverPosition;
  String _kind = 'internal';
  String _urgency = 'normal';
  String _confidentiality = 'normal';
  String _bodyFormat = 'markdown';
  DateTime? _letterDate;
  DateTime? _followUpAt;
  MemoryImage? _letterhead;
  MemoryImage? _background;

  bool get _isDraft => (_letter['status'] ?? 'draft') == 'draft';
  bool get _isArchived => (_letter['status'] ?? '') == 'archived';
  bool get _canCompose =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'compose');
  bool get _canRefer =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'refer');
  bool get _canArchive =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'archive');
  bool get _canAdmin =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'admin');

  @override
  void initState() {
    super.initState();
    _mobileTabs = TabController(length: 2, vsync: this, initialIndex: widget.letterId == null ? 0 : 1);
    _positionId = widget.positionId;
    _letterDate = DateTime.now();
    _subject.addListener(() => setState(() {}));
    _body.addListener(() => setState(() {}));
    _sender.addListener(() => setState(() {}));
    _receiver.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _mobileTabs?.dispose();
    _subject.dispose();
    _body.dispose();
    _sender.dispose();
    _senderOrg.dispose();
    _receiver.dispose();
    _receiverOrg.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _formatOf(int? id) {
    if (id == null) return null;
    for (final f in _formats) {
      if (oaId(f['id']) == id) return f;
    }
    return null;
  }

  Future<void> _loadStationeryImages() async {
    final fmt = _formatOf(_formatId);
    final headId = (fmt?['letterhead_file_id'] ?? _settings['letterhead_file_id'] ?? '').toString();
    final bgId = (fmt?['background_file_id'] ?? _settings['background_file_id'] ?? '').toString();
    MemoryImage? head;
    MemoryImage? bg;
    try {
      if (headId.isNotEmpty) {
        final bytes = await _storage.downloadFile(businessId: widget.businessId, fileId: headId);
        if (bytes.isNotEmpty) {
          head = MemoryImage(Uint8List.fromList(bytes));
        }
      }
      if (bgId.isNotEmpty) {
        final bytes = await _storage.downloadFile(businessId: widget.businessId, fileId: bgId);
        if (bytes.isNotEmpty) {
          bg = MemoryImage(Uint8List.fromList(bytes));
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _letterhead = head;
        _background = bg;
      });
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.listMyPositions(businessId: widget.businessId),
        _svc.listTemplates(businessId: widget.businessId),
        _svc.listFormats(businessId: widget.businessId),
        _svc.getSettings(businessId: widget.businessId),
      ]);
      _positions = results[0] as List<Map<String, dynamic>>;
      _templates = results[1] as List<Map<String, dynamic>>;
      _formats = results[2] as List<Map<String, dynamic>>;
      _settings = results[3] as Map<String, dynamic>;
      _positionId ??= _positions.isNotEmpty ? oaId(_positions.first['id']) : null;
      _bodyFormat = (_settings['default_body_format'] ?? 'markdown').toString();
      _formatId ??= oaId(_settings['default_format_id']);
      if (_formatId == null) {
        for (final f in _formats) {
          if (f['is_default'] == true) {
            _formatId = oaId(f['id']);
            break;
          }
        }
      }
      if (widget.letterId != null && _positionId != null) {
        _letter = await _svc.getLetter(
          businessId: widget.businessId,
          letterId: widget.letterId!,
          positionId: _positionId,
        );
        _subject.text = (_letter['subject'] ?? '').toString();
        _body.text = (_letter['body'] ?? '').toString();
        _sender.text = (_letter['sender_name'] ?? '').toString();
        _senderOrg.text = (_letter['sender_org'] ?? '').toString();
        _receiver.text = (_letter['receiver_name'] ?? '').toString();
        _receiverOrg.text = (_letter['receiver_org'] ?? '').toString();
        _kind = (_letter['letter_kind'] ?? 'internal').toString();
        _urgency = (_letter['urgency'] ?? 'normal').toString();
        _confidentiality = (_letter['confidentiality'] ?? 'normal').toString();
        _bodyFormat = (_letter['body_format'] ?? _bodyFormat).toString();
        if (_bodyFormat == 'plain') _bodyFormat = 'markdown';
        _senderPositionId = oaId(_letter['sender_position_id']);
        _receiverPositionId = oaId(_letter['receiver_position_id']);
        _formatId = oaId(_letter['format_id']) ?? _formatId;
        _templateId = oaId(_letter['template_id']);
        if (_senderPositionId != null) {
          _senderPosition = {
            'id': _senderPositionId,
            'title': _letter['sender_position_title'] ?? _sender.text,
            'org_unit_title': _letter['sender_unit_title'] ?? _senderOrg.text,
          };
        }
        if (_receiverPositionId != null) {
          _receiverPosition = {
            'id': _receiverPositionId,
            'title': _letter['receiver_position_title'] ?? _receiver.text,
            'org_unit_title': _letter['receiver_unit_title'] ?? _receiverOrg.text,
          };
        }
        _letterDate = HesabixDateUtils.parseApiDate(_letter['letter_date'], rawValue: _letter['letter_date_raw']) ??
            _letterDate;
        _followUpAt = HesabixDateUtils.parseApiDate(_letter['follow_up_at'], rawValue: _letter['follow_up_at_raw']);
      }
      await _loadStationeryImages();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (!_isDraft && widget.letterId != null) {
          _mobileTabs?.index = 1;
        }
      }
    }
  }

  Map<String, dynamic> _payload() => {
        'subject': _subject.text.trim(),
        'body': _body.text,
        'body_format': _bodyFormat,
        'letter_kind': _kind,
        'urgency': _urgency,
        'confidentiality': _confidentiality,
        'sender_name': _sender.text.trim(),
        'sender_org': _senderOrg.text.trim(),
        'receiver_name': _receiver.text.trim(),
        'receiver_org': _receiverOrg.text.trim(),
        'sender_position_id': _senderPositionId,
        'receiver_position_id': _receiverPositionId,
        'format_id': _formatId,
        'template_id': _templateId,
        if (_letterDate != null) 'letter_date': HesabixDateUtils.formatForApiDate(_letterDate!),
      };

  void _applyTemplate(Map<String, dynamic> tpl) {
    setState(() {
      _templateId = oaId(tpl['id']);
      if ((tpl['subject'] ?? '').toString().isNotEmpty) _subject.text = tpl['subject'].toString();
      if (tpl['body'] != null) _body.text = tpl['body'].toString();
      _bodyFormat = (tpl['body_format'] ?? _bodyFormat).toString();
      if ((tpl['letter_kind'] ?? '').toString().isNotEmpty) _kind = tpl['letter_kind'].toString();
      if (oaId(tpl['format_id']) != null) _formatId = oaId(tpl['format_id']);
    });
    _loadStationeryImages();
  }

  Future<void> _saveDraft() async {
    if (_positionId == null) return;
    try {
      if (widget.letterId == null) {
        final created = await _svc.createDraft(
          businessId: widget.businessId,
          positionId: _positionId!,
          payload: _payload(),
        );
        if (!mounted) return;
        context.go(
          context.businessPanelUrl(widget.businessId, 'office-automation/letters/${created['id']}'),
          extra: {'positionId': _positionId},
        );
      } else {
        await _svc.updateDraft(
          businessId: widget.businessId,
          letterId: widget.letterId!,
          positionId: _positionId!,
          payload: _payload(),
        );
        await _load();
        if (mounted) SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).oaSaveDraft);
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _register() async {
    if (_positionId == null) return;
    try {
      var letterId = widget.letterId;
      if (letterId == null) {
        final created = await _svc.createDraft(
          businessId: widget.businessId,
          positionId: _positionId!,
          payload: _payload(),
        );
        letterId = oaId(created['id']);
        if (letterId == null) return;
      } else if (_isDraft) {
        await _svc.updateDraft(
          businessId: widget.businessId,
          letterId: letterId,
          positionId: _positionId!,
          payload: _payload(),
        );
      }
      await _svc.registerLetter(
        businessId: widget.businessId,
        letterId: letterId,
        positionId: _positionId!,
        payload: {'letter_kind': _kind},
      );
      if (!mounted) return;
      if (widget.letterId == null) {
        context.go(
          context.businessPanelUrl(widget.businessId, 'office-automation/letters/$letterId'),
          extra: {'positionId': _positionId},
        );
      } else {
        await _load();
        if (mounted) SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).oaRegister);
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _refer() async {
    if (_positionId == null || widget.letterId == null) return;
    final t = AppLocalizations.of(context);
    final recipients = <Map<String, dynamic>>[];
    var kind = 'action';
    final instruction = TextEditingController();
    Map<String, dynamic>? picked;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaRefer),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OaPositionPicker(
                    businessId: widget.businessId,
                    label: t.oaToPosition,
                    value: picked,
                    onChanged: (v) => setLocal(() => picked = v),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: picked == null
                          ? null
                          : () {
                              final id = oaId(picked?['id']);
                              if (id == null) return;
                              if (recipients.any((r) => oaId(r['to_position_id']) == id)) return;
                              setLocal(() {
                                recipients.add({
                                  'to_position_id': id,
                                  'kind': kind,
                                  'instruction': instruction.text.trim(),
                                  'title': picked?['title'],
                                });
                                picked = null;
                              });
                            },
                      icon: const Icon(Icons.add),
                      label: Text(t.oaAddRecipient),
                    ),
                  ),
                  for (final r in recipients)
                    ListTile(
                      dense: true,
                      title: Text('${r['title'] ?? r['to_position_id']}'),
                      subtitle: Text('${r['kind']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setLocal(() => recipients.remove(r)),
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: InputDecoration(labelText: t.oaReferralKind),
                    items: [
                      DropdownMenuItem(value: 'action', child: Text(t.oaAction)),
                      DropdownMenuItem(value: 'info', child: Text(t.oaCc)),
                      DropdownMenuItem(value: 'signature', child: Text(t.oaSignature)),
                    ],
                    onChanged: (v) => setLocal(() => kind = v ?? 'action'),
                  ),
                  TextField(controller: instruction, decoration: InputDecoration(labelText: t.oaInstruction), maxLines: 3),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaRefer)),
          ],
        ),
      ),
    );
    if (ok == true && recipients.isEmpty && picked != null) {
      final id = oaId(picked?['id']);
      if (id != null) {
        recipients.add({'to_position_id': id, 'kind': kind, 'instruction': instruction.text.trim()});
      }
    }
    final note = instruction.text.trim();
    instruction.dispose();
    if (ok != true || recipients.isEmpty) return;
    try {
      await _svc.referLetter(
        businessId: widget.businessId,
        letterId: widget.letterId!,
        positionId: _positionId!,
        payload: {
          'recipients': [
            for (final r in recipients)
              {'to_position_id': r['to_position_id'], 'kind': r['kind'] ?? kind, 'instruction': (r['instruction'] ?? note)},
          ],
        },
      );
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _paraph() async {
    final text = TextEditingController();
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.oaParaph),
        content: TextField(controller: text, maxLines: 4, decoration: InputDecoration(labelText: t.oaParaph)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
        ],
      ),
    );
    if (ok != true || text.text.trim().isEmpty || _positionId == null || widget.letterId == null) {
      text.dispose();
      return;
    }
    try {
      final pending = List<Map>.from(_letter['referrals'] as List? ?? const [])
          .where((r) => oaId(r['to_position_id']) == _positionId && (r['status'] == 'pending' || r['status'] == 'seen'))
          .toList();
      await _svc.addParaph(
        businessId: widget.businessId,
        letterId: widget.letterId!,
        positionId: _positionId!,
        text: text.text.trim(),
        referralId: pending.isEmpty ? null : oaId(pending.first['id']),
      );
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      text.dispose();
    }
  }

  Future<void> _attach() async {
    if (_positionId == null || widget.letterId == null) return;
    final pick = await FilePicker.platform.pickFiles(withData: true);
    if (pick == null || pick.files.isEmpty || pick.files.first.bytes == null) return;
    final file = pick.files.first;
    try {
      await _svc.uploadAttachment(
        businessId: widget.businessId,
        letterId: widget.letterId!,
        positionId: _positionId!,
        bytes: file.bytes!,
        filename: file.name,
      );
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _actOnReferral(String action) async {
    final pending = List<Map>.from(_letter['referrals'] as List? ?? const [])
        .where((r) => oaId(r['to_position_id']) == _positionId && (r['status'] == 'pending' || r['status'] == 'seen'))
        .toList();
    if (pending.isEmpty || _positionId == null) return;
    final id = oaId(pending.first['id']);
    if (id == null) return;
    try {
      if (action == 'complete') {
        await _svc.completeReferral(businessId: widget.businessId, referralId: id, positionId: _positionId!);
      } else {
        await _svc.returnReferral(businessId: widget.businessId, referralId: id, positionId: _positionId!);
      }
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _setFollowUp() async {
    if (_positionId == null || widget.letterId == null) return;
    try {
      await _svc.setFollowUp(
        businessId: widget.businessId,
        letterId: widget.letterId!,
        positionId: _positionId!,
        followUpAt: _followUpAt == null ? null : HesabixDateUtils.formatForApiDate(_followUpAt!),
      );
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _linkRelated() async {
    if (_positionId == null || widget.letterId == null) return;
    String kind = 'related';
    Map<String, dynamic>? related;
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaLink),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OaLetterPicker(
                  businessId: widget.businessId,
                  label: t.oaSearchLetter,
                  onChanged: (v) => setLocal(() => related = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  items: [
                    DropdownMenuItem(value: 'related', child: Text(t.oaLinkRelated)),
                    DropdownMenuItem(value: 'reply', child: Text(t.oaLinkReply)),
                    DropdownMenuItem(value: 'followup', child: Text(t.oaLinkFollowup)),
                  ],
                  onChanged: (v) => setLocal(() => kind = v ?? 'related'),
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
    final relatedId = oaId(related?['id']);
    if (ok != true || relatedId == null) return;
    try {
      await _svc.linkLetters(
        businessId: widget.businessId,
        letterId: widget.letterId!,
        positionId: _positionId!,
        relatedLetterId: relatedId,
        linkKind: kind,
      );
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _saveAsTemplate() async {
    if (!_canAdmin) return;
    final t = AppLocalizations.of(context);
    final name = TextEditingController(text: _subject.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.oaSaveAsTemplate),
        content: TextField(controller: name, decoration: InputDecoration(labelText: t.oaTemplateName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
        ],
      ),
    );
    final title = name.text.trim();
    name.dispose();
    if (ok != true || title.isEmpty) return;
    try {
      await _svc.createTemplate(
        businessId: widget.businessId,
        payload: {
          'name': title,
          'letter_kind': _kind,
          'subject': _subject.text.trim(),
          'body': _body.text,
          'body_format': _bodyFormat,
          'format_id': _formatId,
        },
      );
      _templates = await _svc.listTemplates(businessId: widget.businessId);
      if (mounted) {
        setState(() {});
        SnackBarHelper.showSuccess(context, message: t.save);
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _paper(AppLocalizations t) {
    final fmt = _formatOf(_formatId);
    final dateText = _letterDate == null
        ? ''
        : HesabixDateUtils.formatApiDateForDisplay(
            HesabixDateUtils.formatForApiDate(_letterDate!),
            widget.calendarController.isJalali,
            fallback: '',
          );
    return OaLetterPaper(
      subject: _subject.text,
      body: _body.text,
      bodyFormat: _bodyFormat,
      sender: [_sender.text, _senderOrg.text].where((s) => s.trim().isNotEmpty).join(' · '),
      receiver: [_receiver.text, _receiverOrg.text].where((s) => s.trim().isNotEmpty).join(' · '),
      number: (_letter['secretariat_number'] ?? '').toString(),
      dateText: dateText,
      footer: (fmt?['footer_text'] ?? _settings['footer_text'] ?? '').toString(),
      letterhead: _letterhead,
      background: _background,
      marginTop: (fmt?['margin_top'] ?? _settings['margin_top'] ?? 20) as int? ?? 20,
      marginRight: (fmt?['margin_right'] ?? _settings['margin_right'] ?? 20) as int? ?? 20,
      marginBottom: (fmt?['margin_bottom'] ?? _settings['margin_bottom'] ?? 20) as int? ?? 20,
      marginLeft: (fmt?['margin_left'] ?? _settings['margin_left'] ?? 20) as int? ?? 20,
      confidentiality: _confidentiality,
      urgency: _urgency,
      paraphs: [
        for (final p in List<Map>.from(_letter['paraphs'] as List? ?? const []))
          '${p['position_title'] ?? ''}: ${p['text'] ?? ''}',
      ],
    );
  }

  Widget _composeForm(AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OaSectionCard(
          title: t.oaMetadata,
          child: Column(
            children: [
              OaSearchableField(
                label: t.oaPosition,
                hint: t.oaSearchPosition,
                emptyText: t.oaNoPositions,
                enabled: _isDraft,
                prefixIcon: Icons.badge_outlined,
                value: () {
                  Map<String, dynamic>? mine;
                  for (final p in _positions) {
                    if (oaId(p['id']) == _positionId) mine = p;
                  }
                  return mine == null ? null : oaPositionItem(mine);
                }(),
                onChanged: (item) {
                  if (!_isDraft) return;
                  setState(() => _positionId = item == null ? null : int.tryParse(item.id));
                },
                onSearch: (q) async {
                  final needle = q.trim().toLowerCase();
                  final rows = needle.isEmpty
                      ? _positions
                      : _positions.where((p) => oaPositionLabel(p).toLowerCase().contains(needle)).toList();
                  return [for (final p in rows) oaPositionItem(p)];
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subject,
                enabled: _isDraft,
                decoration: InputDecoration(labelText: t.oaSubject, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _kind,
                      decoration: InputDecoration(labelText: t.oaLetterKind, border: const OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: 'internal', child: Text(t.oaKindInternal)),
                        DropdownMenuItem(value: 'incoming', child: Text(t.oaKindIncoming)),
                        DropdownMenuItem(value: 'outgoing', child: Text(t.oaKindOutgoing)),
                      ],
                      onChanged: _isDraft ? (v) => setState(() => _kind = v ?? 'internal') : null,
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _urgency,
                      decoration: InputDecoration(labelText: t.oaUrgency, border: const OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: 'normal', child: Text(t.oaUrgencyNormal)),
                        DropdownMenuItem(value: 'urgent', child: Text(t.oaUrgencyUrgent)),
                        DropdownMenuItem(value: 'immediate', child: Text(t.oaUrgencyImmediate)),
                      ],
                      onChanged: _isDraft ? (v) => setState(() => _urgency = v ?? 'normal') : null,
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _confidentiality,
                      decoration: InputDecoration(labelText: t.oaConfidential, border: const OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: 'normal', child: Text(t.oaConfidentialNormal)),
                        DropdownMenuItem(value: 'confidential', child: Text(t.oaConfidentialRestricted)),
                      ],
                      onChanged: _isDraft ? (v) => setState(() => _confidentiality = v ?? 'normal') : null,
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DateInputField(
                      value: _letterDate,
                      onChanged: _isDraft ? (v) => setState(() => _letterDate = v) : null,
                      labelText: t.oaLetterDate,
                      calendarController: widget.calendarController,
                      enabled: _isDraft,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OaSectionCard(
          title: t.oaLetterTemplate,
          child: Column(
            children: [
              DropdownButtonFormField<int?>(
                initialValue: _templates.any((e) => oaId(e['id']) == _templateId) ? _templateId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: t.oaSelectTemplate, border: const OutlineInputBorder()),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(t.oaAllKinds)),
                  for (final tpl in _templates)
                    if (oaId(tpl['id']) != null)
                      DropdownMenuItem(value: oaId(tpl['id']), child: Text('${tpl['name']}')),
                ],
                onChanged: _isDraft
                    ? (id) {
                        if (id == null) {
                          setState(() => _templateId = null);
                          return;
                        }
                        final tpl = _templates.firstWhere((e) => oaId(e['id']) == id, orElse: () => {});
                        if (tpl.isNotEmpty) _applyTemplate(tpl);
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _formats.any((e) => oaId(e['id']) == _formatId) ? _formatId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: t.oaSelectFormat, border: const OutlineInputBorder()),
                items: [
                  DropdownMenuItem<int?>(value: null, child: Text(t.oaDefaultFormat)),
                  for (final f in _formats)
                    if (oaId(f['id']) != null)
                      DropdownMenuItem(value: oaId(f['id']), child: Text('${f['name']}')),
                ],
                onChanged: _isDraft
                    ? (id) {
                        setState(() => _formatId = id);
                        _loadStationeryImages();
                      }
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OaSectionCard(
          title: '${t.oaSender} / ${t.oaReceiver}',
          child: Column(
            children: [
              OaPositionPicker(
                businessId: widget.businessId,
                label: t.oaSender,
                value: _senderPosition,
                valueId: _senderPositionId,
                enabled: _isDraft,
                onChanged: (v) {
                  setState(() {
                    _senderPosition = v;
                    _senderPositionId = oaId(v?['id']);
                    if (v != null) {
                      _sender.text = (v['title'] ?? v['holder_name'] ?? _sender.text).toString();
                      _senderOrg.text = (v['org_unit_title'] ?? _senderOrg.text).toString();
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sender,
                enabled: _isDraft,
                decoration: InputDecoration(labelText: t.oaCustomParty, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _senderOrg,
                enabled: _isDraft,
                decoration: InputDecoration(labelText: t.oaSenderOrg, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              OaPositionPicker(
                businessId: widget.businessId,
                label: t.oaReceiver,
                value: _receiverPosition,
                valueId: _receiverPositionId,
                enabled: _isDraft,
                onChanged: (v) {
                  setState(() {
                    _receiverPosition = v;
                    _receiverPositionId = oaId(v?['id']);
                    if (v != null) {
                      _receiver.text = (v['title'] ?? v['holder_name'] ?? _receiver.text).toString();
                      _receiverOrg.text = (v['org_unit_title'] ?? _receiverOrg.text).toString();
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _receiver,
                enabled: _isDraft,
                decoration: InputDecoration(labelText: t.oaCustomParty, border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _receiverOrg,
                enabled: _isDraft,
                decoration: InputDecoration(labelText: t.oaReceiverOrg, border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OaSectionCard(
          title: t.oaBody,
          child: OaLetterEditor(
            controller: _body,
            bodyFormat: _bodyFormat,
            enabled: _isDraft,
            onFormatChanged: (v) => setState(() => _bodyFormat = v),
          ),
        ),
        if (!_isDraft && widget.letterId != null) ...[
          const SizedBox(height: 12),
          DateInputField(
            value: _followUpAt,
            onChanged: (v) => setState(() => _followUpAt = v),
            labelText: t.oaFollowUpDate,
            calendarController: widget.calendarController,
          ),
        ],
      ],
    );
  }

  List<Widget> _actionButtons(AppLocalizations t) {
    return [
      if (_isDraft && _canCompose)
        FilledButton.icon(onPressed: _saveDraft, icon: const Icon(Icons.save_outlined), label: Text(t.oaSaveDraft)),
      if (_isDraft && _canCompose)
        FilledButton.icon(onPressed: _register, icon: const Icon(Icons.verified_outlined), label: Text(t.oaRegister)),
      if (_isDraft && _canAdmin)
        OutlinedButton.icon(onPressed: _saveAsTemplate, icon: const Icon(Icons.bookmark_add_outlined), label: Text(t.oaSaveAsTemplate)),
      if (!_isDraft && !_isArchived && _canRefer)
        FilledButton.icon(onPressed: _refer, icon: const Icon(Icons.forward_outlined), label: Text(t.oaRefer)),
      if (!_isDraft && !_isArchived && _canRefer)
        FilledButton.tonalIcon(onPressed: _paraph, icon: const Icon(Icons.draw_outlined), label: Text(t.oaParaph)),
      if (_canCompose && !_isArchived)
        OutlinedButton.icon(onPressed: _attach, icon: const Icon(Icons.attach_file), label: Text(t.oaAttach)),
      if (!_isDraft && !_isArchived && _canRefer)
        OutlinedButton.icon(onPressed: () => _actOnReferral('complete'), icon: const Icon(Icons.done), label: Text(t.oaComplete)),
      if (!_isDraft && !_isArchived && _canRefer)
        OutlinedButton.icon(onPressed: () => _actOnReferral('return'), icon: const Icon(Icons.undo), label: Text(t.oaReturn)),
      if (!_isDraft && !_isArchived && _canRefer)
        OutlinedButton.icon(onPressed: _setFollowUp, icon: const Icon(Icons.event_outlined), label: Text(t.oaFollowUp)),
      if (!_isDraft && !_isArchived && _canRefer)
        OutlinedButton.icon(onPressed: _linkRelated, icon: const Icon(Icons.link), label: Text(t.oaLink)),
      if (!_isDraft && !_isArchived && _canArchive)
        OutlinedButton.icon(
          onPressed: () async {
            if (_positionId == null || widget.letterId == null) return;
            try {
              await _svc.archiveLetter(
                businessId: widget.businessId,
                letterId: widget.letterId!,
                positionId: _positionId!,
              );
              await _load();
            } catch (e) {
              if (!mounted) return;
              SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
            }
          },
          icon: const Icon(Icons.inventory_2_outlined),
          label: Text(t.oaArchive),
        ),
      if (_isDraft && widget.letterId != null && _canCompose)
        TextButton.icon(
          onPressed: () async {
            try {
              final dest = context.businessPanelUrl(widget.businessId, 'office-automation');
              await _svc.deleteDraft(
                businessId: widget.businessId,
                letterId: widget.letterId!,
                positionId: _positionId!,
              );
              if (!mounted) return;
              context.go(dest);
            } catch (e) {
              if (!mounted) return;
              SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: Text(t.delete),
        ),
    ];
  }

  Widget _sidePanels(AppLocalizations t) {
    final paraphs = List<Map>.from(_letter['paraphs'] as List? ?? const []);
    final attachments = List<Map>.from(_letter['attachments'] as List? ?? const []);
    final links = List<Map>.from(_letter['links'] as List? ?? const []);
    final referrals = List<Map>.from(_letter['referrals'] as List? ?? const []);
    final timeline = List<Map>.from(_letter['timeline'] as List? ?? const []);
    return Column(
      children: [
        OaSectionCard(
          title: t.oaParaph,
          child: paraphs.isEmpty
              ? Text(t.oaEmptyFolder)
              : Column(
                  children: [
                    for (final p in paraphs)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.draw_outlined),
                        title: Text('${p['text']}'),
                        subtitle: Text('${p['position_title'] ?? ''}'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        OaSectionCard(
          title: t.oaAttach,
          child: attachments.isEmpty
              ? Text(t.oaEmptyFolder)
              : Column(
                  children: [
                    for (final a in attachments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.attach_file),
                        title: Text('${a['title'] ?? a['original_name']}'),
                        trailing: _canCompose && !_isArchived
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final attachmentId = oaId(a['id']);
                                  if (_positionId == null || attachmentId == null) return;
                                  try {
                                    await _svc.removeAttachment(
                                      businessId: widget.businessId,
                                      attachmentId: attachmentId,
                                      positionId: _positionId!,
                                    );
                                    await _load();
                                  } catch (e) {
                                    if (!mounted) return;
                                    SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                                  }
                                },
                              )
                            : null,
                        onTap: () async {
                          final fallbackName = a['original_name']?.toString() ?? t.oaAttach;
                          final bytes = await _storage.downloadFile(
                            businessId: widget.businessId,
                            fileId: a['file_storage_id'].toString(),
                          );
                          if (!mounted || bytes.isEmpty) return;
                          SnackBarHelper.showSuccess(context, message: fallbackName);
                        },
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        OaSectionCard(
          title: t.oaCirculation,
          child: referrals.isEmpty
              ? Text(t.oaEmptyFolder)
              : Column(
                  children: [
                    for (final r in referrals)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          r['kind'] == 'info' ? Icons.visibility_outlined : Icons.forward_outlined,
                        ),
                        title: Text('${r['from_position_title'] ?? ''} → ${r['to_position_title'] ?? ''}'),
                        subtitle: Text('${r['kind']} · ${r['status']} ${r['instruction'] ?? ''}'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        OaSectionCard(
          title: t.oaLink,
          child: links.isEmpty
              ? Text(t.oaEmptyFolder)
              : Column(
                  children: [
                    for (final l in links)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.link),
                        title: Text('${l['related_subject'] ?? l['related_letter_id']}'),
                        subtitle: Text('${l['link_kind'] ?? ''} ${l['related_number'] ?? ''}'),
                        onTap: () {
                          final relatedId = l['related_letter_id'];
                          if (relatedId == null) return;
                          context.go(
                            context.businessPanelUrl(widget.businessId, 'office-automation/letters/$relatedId'),
                            extra: {'positionId': _positionId},
                          );
                        },
                      ),
                  ],
                ),
        ),
        if (timeline.isNotEmpty) ...[
          const SizedBox(height: 12),
          OaSectionCard(
            title: t.oaTimeline,
            child: Column(
              children: [
                for (final a in timeline)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.history, size: 18),
                    title: Text('${a['action']}'),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final wide = ResponsiveHelper.widthOf(context) >= 1100;
    final title = widget.letterId == null ? t.oaNewLetter : (_letter['subject']?.toString() ?? t.oaViewLetter);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: wide || _mobileTabs == null
            ? null
            : TabBar(
                controller: _mobileTabs,
                tabs: [
                  Tab(text: _isDraft ? t.oaCompose : t.oaDocument),
                  Tab(text: t.oaLetterPreview),
                ],
              ),
        actions: [
          if (widget.letterId != null)
            IconButton(
              tooltip: t.oaPrint,
              icon: const Icon(Icons.print_outlined),
              onPressed: () async {
                try {
                  await oaPrintLetter(
                    businessId: widget.businessId,
                    letterId: widget.letterId!,
                    positionId: _positionId,
                    calendar: widget.calendarController,
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                }
              },
            ),
          if (_isDraft && _canCompose)
            IconButton(tooltip: t.oaSaveDraft, icon: const Icon(Icons.save_outlined), onPressed: _saveDraft),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(spacing: 8, runSpacing: 8, children: _actionButtons(t)),
                ),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: _isDraft ? 5 : 4,
                              child: ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  _composeForm(t),
                                  const SizedBox(height: 16),
                                  _sidePanels(t),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: _isDraft ? 4 : 5,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                                child: ColoredBox(
                                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(16),
                                    child: _paper(t),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : TabBarView(
                          controller: _mobileTabs,
                          children: [
                            ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                _composeForm(t),
                                const SizedBox(height: 16),
                                _sidePanels(t),
                              ],
                            ),
                            ListView(
                              padding: const EdgeInsets.all(16),
                              children: [_paper(t)],
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}
