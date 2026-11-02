import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';

class OaArchivePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const OaArchivePage({super.key, required this.businessId, required this.authStore});

  @override
  State<OaArchivePage> createState() => _OaArchivePageState();
}

class _OaArchivePageState extends State<OaArchivePage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  bool _loading = true;
  List<Map<String, dynamic>> _folders = [];
  List<Map<String, dynamic>> _letters = [];
  int? _selectedFolderId;

  bool get _canArchive =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'archive') ||
      widget.authStore.hasBusinessPermission('office_automation', 'admin');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final folders = await _svc.listArchiveFolders(businessId: widget.businessId);
      final letters = await _svc.searchLetters(businessId: widget.businessId, q: '', limit: 80);
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _letters = letters;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  List<Map<String, dynamic>> get _visibleLetters {
    if (_selectedFolderId == null) return _letters;
    return _letters.where((l) => oaId(l['archive_folder_id']) == _selectedFolderId).toList();
  }

  Future<void> _editFolder({Map<String, dynamic>? existing}) async {
    final t = AppLocalizations.of(context);
    final fa = TextEditingController(text: '${(existing?['name_i18n'] as Map?)?['fa'] ?? existing?['title'] ?? ''}');
    final en = TextEditingController(text: '${(existing?['name_i18n'] as Map?)?['en'] ?? ''}');
    final code = TextEditingController(text: '${existing?['code'] ?? ''}');
    int? parentId = oaId(existing?['parent_id']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? t.oaNewArchiveFolder : t.oaArchiveFolders),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: fa, decoration: InputDecoration(labelText: t.persian)),
                const SizedBox(height: 8),
                TextField(controller: en, decoration: InputDecoration(labelText: t.english)),
                const SizedBox(height: 8),
                TextField(controller: code, decoration: InputDecoration(labelText: t.oaCode)),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: parentId,
                  decoration: InputDecoration(labelText: t.oaParentFolder),
                  items: [
                    DropdownMenuItem(value: null, child: Text(t.oaNoParent)),
                    for (final f in _folders)
                      if (oaId(f['id']) != oaId(existing?['id']))
                        DropdownMenuItem(value: oaId(f['id']), child: Text('${f['title'] ?? f['code']}')),
                  ],
                  onChanged: (v) => setLocal(() => parentId = v),
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
      'name_i18n': {'fa': fa.text.trim(), 'en': en.text.trim()},
      if (code.text.trim().isNotEmpty) 'code': code.text.trim(),
      'parent_id': parentId,
    };
    fa.dispose();
    en.dispose();
    code.dispose();
    if (ok != true) return;
    try {
      await _svc.saveArchiveFolder(businessId: widget.businessId, payload: payload);
      await _load();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final tree = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          selected: _selectedFolderId == null,
          leading: const Icon(Icons.folder_open_outlined),
          title: Text(t.oaAllLetters),
          onTap: () => setState(() => _selectedFolderId = null),
        ),
        for (final f in _folders)
          ListTile(
            selected: oaId(f['id']) == _selectedFolderId,
            leading: const Icon(Icons.folder_outlined),
            title: Text('${f['title'] ?? f['code']}'),
            subtitle: Text('${f['code'] ?? ''}'),
            onTap: () => setState(() => _selectedFolderId = oaId(f['id'])),
            trailing: _canArchive
                ? IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editFolder(existing: f))
                : null,
          ),
      ],
    );
    final letters = _visibleLetters.isEmpty
        ? Center(child: Text(t.oaEmptyFolder))
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _visibleLetters.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final row = _visibleLetters[i];
              return Card(
                child: ListTile(
                  title: Text('${row['subject'] ?? ''}'),
                  subtitle: Text('${row['secretariat_number'] ?? t.oaDrafts}'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.go(
                    context.businessPanelUrl(widget.businessId, 'office-automation/letters/${row['id']}'),
                  ),
                ),
              );
            },
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaArchiveTree),
        actions: [
          if (_canArchive)
            IconButton(tooltip: t.oaNewArchiveFolder, icon: const Icon(Icons.create_new_folder_outlined), onPressed: () => _editFolder()),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wide
              ? Row(
                  children: [
                    SizedBox(width: 300, child: tree),
                    const VerticalDivider(width: 1),
                    Expanded(child: letters),
                  ],
                )
              : Column(
                  children: [
                    SizedBox(height: 220, child: tree),
                    const Divider(height: 1),
                    Expanded(child: letters),
                  ],
                ),
    );
  }
}
