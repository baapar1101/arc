import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../core/api_client.dart';
import '../../../services/business_storage_service.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/date_input_field.dart';

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

class _OaLetterPageState extends State<OaLetterPage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _sender = TextEditingController();
  final _senderOrg = TextEditingController();
  final _receiver = TextEditingController();
  final _receiverOrg = TextEditingController();

  bool _loading = true;
  Map<String, dynamic> _letter = const {};
  List<Map<String, dynamic>> _positions = [];
  int? _positionId;
  String _kind = 'internal';
  String _urgency = 'normal';
  String _confidentiality = 'normal';
  DateTime? _letterDate;
  DateTime? _followUpAt;

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

  @override
  void initState() {
    super.initState();
    _positionId = widget.positionId;
    _letterDate = DateTime.now();
    _load();
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    _sender.dispose();
    _senderOrg.dispose();
    _receiver.dispose();
    _receiverOrg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _positions = await _svc.listMyPositions(businessId: widget.businessId);
      _positionId ??= _positions.isNotEmpty ? oaId(_positions.first['id']) : null;
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
        _letterDate = HesabixDateUtils.parseApiDate(_letter['letter_date'], rawValue: _letter['letter_date_raw']) ??
            _letterDate;
        _followUpAt = HesabixDateUtils.parseApiDate(_letter['follow_up_at'], rawValue: _letter['follow_up_at_raw']);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _payload() => {
        'subject': _subject.text.trim(),
        'body': _body.text,
        'letter_kind': _kind,
        'urgency': _urgency,
        'confidentiality': _confidentiality,
        'sender_name': _sender.text.trim(),
        'sender_org': _senderOrg.text.trim(),
        'receiver_name': _receiver.text.trim(),
        'receiver_org': _receiverOrg.text.trim(),
        if (_letterDate != null) 'letter_date': HesabixDateUtils.formatForApiDate(_letterDate!),
      };

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
    List<Map<String, dynamic>> all;
    try {
      all = await _svc.listPositions(businessId: widget.businessId);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      return;
    }
    if (!mounted) return;
    int? toId;
    String kind = 'action';
    final instruction = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(t.oaRefer),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(labelText: t.oaToPosition),
                    items: [
                      for (final p in all)
                        if (oaId(p['id']) != null)
                          DropdownMenuItem(value: oaId(p['id']), child: Text('${p['title'] ?? p['code']}')),
                    ],
                    onChanged: (v) => toId = v,
                  ),
                  DropdownButtonFormField<String>(
                    value: kind,
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
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaRefer)),
            ],
          ),
        );
      },
    );
    instruction.dispose();
    if (ok != true || toId == null) return;
    try {
      await _svc.referLetter(
        businessId: widget.businessId,
        letterId: widget.letterId!,
        positionId: _positionId!,
        payload: {
          'recipients': [
            {'to_position_id': toId, 'kind': kind, 'instruction': instruction.text.trim()},
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

  Future<void> _printLetter() async {
    if (widget.letterId == null) return;
    try {
      final data = await _svc.getLetterPrint(
        businessId: widget.businessId,
        letterId: widget.letterId!,
        positionId: _positionId,
      );
      final font = await PdfGoogleFonts.notoNaskhArabicRegular();
      final doc = pw.Document();
      final paraphs = List<Map>.from(data['paraphs'] as List? ?? const []);
      final letterDate = HesabixDateUtils.formatApiDateForDisplay(
        data['letter_date'],
        widget.calendarController.isJalali,
        rawValue: data['letter_date_raw'],
        fallback: '',
      );
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (_) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text('${data['secretariat_number'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 12)),
                if (letterDate.isNotEmpty) pw.Text(letterDate, style: pw.TextStyle(font: font, fontSize: 10)),
                pw.SizedBox(height: 8),
                pw.Text('${data['subject'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 16)),
                pw.SizedBox(height: 8),
                if ((data['sender_name'] ?? '').toString().isNotEmpty)
                  pw.Text('${data['sender_name']} ${data['sender_org'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 10)),
                if ((data['receiver_name'] ?? '').toString().isNotEmpty)
                  pw.Text('${data['receiver_name']} ${data['receiver_org'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 10)),
                pw.SizedBox(height: 12),
                pw.Text('${data['body'] ?? ''}', style: pw.TextStyle(font: font, fontSize: 11)),
                pw.SizedBox(height: 16),
                for (final p in paraphs)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Text(
                      '${p['position_title'] ?? ''}: ${p['text'] ?? ''}',
                      style: pw.TextStyle(font: font, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await Printing.layoutPdf(onLayout: (_) => doc.save());
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
    final related = TextEditingController();
    String kind = 'related';
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaLink),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: related,
                  decoration: InputDecoration(labelText: t.oaRelatedLetter),
                  keyboardType: TextInputType.number,
                ),
                DropdownButtonFormField<String>(
                  value: kind,
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
    final relatedId = int.tryParse(related.text.trim());
    related.dispose();
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.letterId == null ? t.oaNewLetter : (_letter['subject']?.toString() ?? t.oaMenu)),
        actions: [
          if (widget.letterId != null)
            IconButton(tooltip: t.oaPrint, icon: const Icon(Icons.print_outlined), onPressed: _printLetter),
          if (_isDraft && _canCompose)
            IconButton(tooltip: t.oaSaveDraft, icon: const Icon(Icons.save_outlined), onPressed: _saveDraft),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_letter['secretariat_number'] != null)
                  Text('${t.oaRegistry}: ${_letter['secretariat_number']}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _positionId,
                  decoration: InputDecoration(labelText: t.oaPosition),
                  items: [
                    for (final p in _positions)
                      if (oaId(p['id']) != null)
                        DropdownMenuItem(value: oaId(p['id']), child: Text('${p['title'] ?? p['code']}')),
                  ],
                  onChanged: _isDraft ? (v) => setState(() => _positionId = v) : null,
                ),
                const SizedBox(height: 12),
                TextField(controller: _subject, decoration: InputDecoration(labelText: t.oaSubject), enabled: _isDraft),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _kind,
                  decoration: InputDecoration(labelText: t.oaLetterKind),
                  items: [
                    DropdownMenuItem(value: 'internal', child: Text(t.oaKindInternal)),
                    DropdownMenuItem(value: 'incoming', child: Text(t.oaKindIncoming)),
                    DropdownMenuItem(value: 'outgoing', child: Text(t.oaKindOutgoing)),
                  ],
                  onChanged: _isDraft ? (v) => setState(() => _kind = v ?? 'internal') : null,
                ),
                const SizedBox(height: 12),
                DateInputField(
                  value: _letterDate,
                  onChanged: _isDraft ? (v) => setState(() => _letterDate = v) : null,
                  labelText: t.oaLetterDate,
                  calendarController: widget.calendarController,
                  enabled: _isDraft,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _urgency,
                  decoration: InputDecoration(labelText: t.oaUrgency),
                  items: [
                    DropdownMenuItem(value: 'normal', child: Text(t.oaUrgencyNormal)),
                    DropdownMenuItem(value: 'urgent', child: Text(t.oaUrgencyUrgent)),
                    DropdownMenuItem(value: 'immediate', child: Text(t.oaUrgencyImmediate)),
                  ],
                  onChanged: _isDraft ? (v) => setState(() => _urgency = v ?? 'normal') : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _confidentiality,
                  decoration: InputDecoration(labelText: t.oaConfidential),
                  items: [
                    DropdownMenuItem(value: 'normal', child: Text(t.oaConfidentialNormal)),
                    DropdownMenuItem(value: 'confidential', child: Text(t.oaConfidentialRestricted)),
                  ],
                  onChanged: _isDraft ? (v) => setState(() => _confidentiality = v ?? 'normal') : null,
                ),
                const SizedBox(height: 12),
                TextField(controller: _body, maxLines: 8, decoration: InputDecoration(labelText: t.oaBody), enabled: _isDraft),
                const SizedBox(height: 12),
                TextField(controller: _sender, decoration: InputDecoration(labelText: t.oaSender), enabled: _isDraft),
                const SizedBox(height: 8),
                TextField(controller: _senderOrg, decoration: InputDecoration(labelText: t.oaSenderOrg), enabled: _isDraft),
                const SizedBox(height: 8),
                TextField(controller: _receiver, decoration: InputDecoration(labelText: t.oaReceiver), enabled: _isDraft),
                const SizedBox(height: 8),
                TextField(controller: _receiverOrg, decoration: InputDecoration(labelText: t.oaReceiverOrg), enabled: _isDraft),
                if (!_isDraft && widget.letterId != null) ...[
                  const SizedBox(height: 12),
                  DateInputField(
                    value: _followUpAt,
                    onChanged: (v) => setState(() => _followUpAt = v),
                    labelText: t.oaFollowUpDate,
                    calendarController: widget.calendarController,
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_isDraft && _canCompose)
                      FilledButton.icon(onPressed: _saveDraft, icon: const Icon(Icons.save_outlined), label: Text(t.oaSaveDraft)),
                    if (_isDraft && _canCompose)
                      FilledButton.icon(onPressed: _register, icon: const Icon(Icons.verified_outlined), label: Text(t.oaRegister)),
                    if (!_isDraft && !_isArchived && _canRefer)
                      FilledButton.icon(onPressed: _refer, icon: const Icon(Icons.forward_outlined), label: Text(t.oaRefer)),
                    if (!_isDraft && !_isArchived && _canRefer)
                      FilledButton.icon(onPressed: _paraph, icon: const Icon(Icons.draw_outlined), label: Text(t.oaParaph)),
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
                            if (!context.mounted) return;
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
                            if (!context.mounted) return;
                            context.go(dest);
                          } catch (e) {
                            if (!context.mounted) return;
                            SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: Text(t.delete),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(t.oaParaph, style: Theme.of(context).textTheme.titleMedium),
                for (final p in List<Map>.from(_letter['paraphs'] as List? ?? const []))
                  ListTile(title: Text('${p['text']}'), subtitle: Text('${p['position_title'] ?? ''}')),
                const SizedBox(height: 12),
                Text(t.oaAttach, style: Theme.of(context).textTheme.titleMedium),
                for (final a in List<Map>.from(_letter['attachments'] as List? ?? const []))
                  ListTile(
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
                                if (!context.mounted) return;
                                SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
                              }
                            },
                          )
                        : null,
                    onTap: () async {
                      final fallbackName = a['original_name']?.toString() ?? t.oaAttach;
                      final bytes = await BusinessStorageService(ApiClient()).downloadFile(
                        businessId: widget.businessId,
                        fileId: a['file_storage_id'].toString(),
                      );
                      if (!context.mounted || bytes.isEmpty) return;
                      SnackBarHelper.showSuccess(context, message: fallbackName);
                    },
                  ),
                const SizedBox(height: 12),
                Text(t.oaLink, style: Theme.of(context).textTheme.titleMedium),
                for (final l in List<Map>.from(_letter['links'] as List? ?? const []))
                  ListTile(
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
                const SizedBox(height: 12),
                Text(t.oaRefer, style: Theme.of(context).textTheme.titleMedium),
                for (final r in List<Map>.from(_letter['referrals'] as List? ?? const []))
                  ListTile(
                    title: Text('${r['from_position_title'] ?? ''} → ${r['to_position_title'] ?? ''}'),
                    subtitle: Text('${r['kind']} · ${r['status']} ${r['instruction'] ?? ''}'),
                  ),
              ],
            ),
    );
  }
}
