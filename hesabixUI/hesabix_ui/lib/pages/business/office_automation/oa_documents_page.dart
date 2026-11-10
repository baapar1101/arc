import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../../../services/business_storage_service.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/office_automation/oa_ui.dart';

class OaDocumentsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OaDocumentsPage({
    super.key,
    required this.businessId,
    required this.authStore,
  });

  @override
  State<OaDocumentsPage> createState() => _OaDocumentsPageState();
}

class _OaDocumentsPageState extends State<OaDocumentsPage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  final BusinessStorageService _storage = BusinessStorageService(ApiClient());
  final TextEditingController _query = TextEditingController();
  bool _loading = true;
  int? _positionId;
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic>? _open;

  bool get _canCompose =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'compose');

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final dash = await _svc.getDashboard(businessId: widget.businessId, positionId: _positionId);
      final active = _positionId ?? (dash['active_position_id'] as num?)?.toInt();
      final found = active == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              (await _svc.searchDocuments(
                businessId: widget.businessId,
                positionId: active,
                q: _query.text.trim(),
              ))['items'] as List? ??
                  const [],
            );
      if (!mounted) return;
      setState(() {
        _positionId = active;
        _items = found;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<String?> _uploadPicked() async {
    final pick = await FilePicker.platform.pickFiles(withData: true);
    if (pick == null || pick.files.isEmpty || pick.files.first.bytes == null) return null;
    final file = pick.files.first;
    final saved = await _storage.uploadFile(
      businessId: widget.businessId,
      fileBytes: file.bytes!,
      filename: file.name,
      moduleContext: 'office_automation',
    );
    return saved['file_id']?.toString();
  }

  Future<void> _register() async {
    if (_positionId == null || !_canCompose) return;
    final t = AppLocalizations.of(context);
    final title = TextEditingController();
    var confidentiality = 'normal';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(t.oaRegisterDocument),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: InputDecoration(labelText: t.oaDocumentTitle)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: confidentiality,
                decoration: InputDecoration(labelText: t.oaConfidentiality),
                items: ['normal', 'confidential', 'highly_confidential', 'secret']
                    .map((value) => DropdownMenuItem(value: value, child: Text(oaConfidentialityLabel(t, value))))
                    .toList(),
                onChanged: (value) => setLocal(() => confidentiality = value ?? 'normal'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.oaRegisterDocument)),
          ],
        ),
      ),
    );
    final chosenTitle = title.text.trim();
    title.dispose();
    if (accepted != true || chosenTitle.isEmpty) return;
    try {
      final fileId = await _uploadPicked();
      if (fileId == null || fileId.isEmpty) return;
      await _svc.registerDocument(
        businessId: widget.businessId,
        positionId: _positionId!,
        title: chosenTitle,
        fileStorageId: fileId,
        confidentiality: confidentiality,
      );
      await _reload();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _openDocument(int id) async {
    if (_positionId == null) return;
    try {
      final doc = await _svc.getDocument(businessId: widget.businessId, documentId: id, positionId: _positionId!);
      if (!mounted) return;
      setState(() => _open = doc);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _addVersion() async {
    final id = oaId(_open?['id']);
    if (id == null || _positionId == null || !_canCompose) return;
    try {
      final fileId = await _uploadPicked();
      if (fileId == null || fileId.isEmpty) return;
      final doc = await _svc.addDocumentVersion(
        businessId: widget.businessId,
        documentId: id,
        positionId: _positionId!,
        fileStorageId: fileId,
      );
      if (!mounted) return;
      setState(() => _open = doc);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _decide(int suggestionId, bool accept) async {
    if (_positionId == null || !_canCompose) return;
    try {
      final doc = await _svc.decideDocumentSuggestion(
        businessId: widget.businessId,
        suggestionId: suggestionId,
        positionId: _positionId!,
        accept: accept,
      );
      if (!mounted) return;
      setState(() => _open = doc);
      await _reload();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final open = _open;
    return Scaffold(
      appBar: AppBar(title: Text(t.oaDocuments)),
      floatingActionButton: _canCompose
          ? FloatingActionButton.extended(
              onPressed: _register,
              icon: const Icon(Icons.note_add_outlined),
              label: Text(t.oaRegisterDocument),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _query,
                    decoration: InputDecoration(
                      labelText: t.oaDocumentSearch,
                      suffixIcon: IconButton(onPressed: _reload, icon: const Icon(Icons.search)),
                    ),
                    onSubmitted: (_) => _reload(),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _items.isEmpty
                        ? Center(child: Text(t.oaNoDocuments))
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final row = _items[index];
                              return ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                                title: Text(row['title']?.toString() ?? ''),
                                subtitle: Text(oaConfidentialityLabel(t, row['confidentiality']?.toString() ?? 'normal')),
                                onTap: () => _openDocument(oaId(row['id']) ?? 0),
                              );
                            },
                          ),
                  ),
                  if (open != null) ...[
                    const Divider(),
                    Align(alignment: AlignmentDirectional.centerStart, child: Text(open['title']?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(t.oaDocumentVersions),
                    ),
                    ...List<Map>.from(open['versions'] as List? ?? const []).map(
                      (version) => Text('${t.oaVersion} ${version['version_no']}'),
                    ),
                    if (_canCompose)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(onPressed: _addVersion, icon: const Icon(Icons.layers_outlined), label: Text(t.oaAddVersion)),
                      ),
                    ...List<Map>.from(open['suggestions'] as List? ?? const []).map((suggestion) {
                      final id = oaId(suggestion['id']);
                      return ListTile(
                        title: Text('${suggestion['field_key']}: ${suggestion['suggested_value']}'),
                        trailing: id == null || !_canCompose
                            ? null
                            : Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(onPressed: () => _decide(id, true), child: Text(t.oaAcceptSuggestion)),
                                  TextButton(onPressed: () => _decide(id, false), child: Text(t.oaRejectSuggestion)),
                                ],
                              ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}
