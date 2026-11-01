import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth_store.dart';
import '../../../core/business_nav.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../services/office_automation_service.dart';
import '../../../utils/error_extractor.dart';
import '../../../utils/snackbar_helper.dart';

class OaCartablePage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController calendarController;

  const OaCartablePage({
    super.key,
    required this.businessId,
    required this.authStore,
    required this.calendarController,
  });

  @override
  State<OaCartablePage> createState() => _OaCartablePageState();
}

class _OaCartablePageState extends State<OaCartablePage> with SingleTickerProviderStateMixin {
  final OfficeAutomationService _svc = OfficeAutomationService();
  final TextEditingController _search = TextEditingController();

  late TabController _tabs;
  bool _loading = true;
  List<Map<String, dynamic>> _positions = [];
  int? _positionId;
  Map<String, dynamic> _counts = const {};
  List<Map<String, dynamic>> _items = [];
  int _total = 0;

  static const _folders = ['inbox', 'action', 'cc', 'drafts', 'sent', 'followup', 'archive', 'registry'];

  bool get _canCompose =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'compose');

  bool get _canAdmin =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'admin');

  bool get _secretariat {
    final pos = _positions.cast<Map?>().firstWhere(
      (p) => oaId(p?['id']) == _positionId,
      orElse: () => null,
    );
    return pos?['is_secretariat'] == true;
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _folders.length, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _loadFolder();
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  String get _prefKey => 'oa_position_${widget.businessId}';

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_prefKey);
      final dash = await _svc.getDashboard(businessId: widget.businessId, positionId: saved);
      final positions = List<Map<String, dynamic>>.from(dash['my_positions'] as List? ?? const []);
      final active = (dash['active_position_id'] as num?)?.toInt() ??
          (positions.isNotEmpty ? oaId(positions.first['id']) : null);
      if (!mounted) return;
      setState(() {
        _positions = positions;
        _positionId = active;
        _counts = Map<String, dynamic>.from(dash['counts'] as Map? ?? const {});
      });
      if (active != null) {
        await prefs.setInt(_prefKey, active);
        await _loadFolder();
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _loadFolder() async {
    if (_positionId == null) return;
    final folder = _folders[_tabs.index];
    if (folder == 'registry' && !_secretariat) {
      setState(() {
        _items = [];
        _total = 0;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await _svc.listCartable(
        businessId: widget.businessId,
        positionId: _positionId!,
        folder: folder,
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      final dash = await _svc.getDashboard(businessId: widget.businessId, positionId: _positionId);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(data['items'] as List? ?? const []);
        _total = (data['total'] as num?)?.toInt() ?? _items.length;
        _counts = Map<String, dynamic>.from(dash['counts'] as Map? ?? const {});
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  String _folderLabel(AppLocalizations t, String folder) {
    switch (folder) {
      case 'inbox':
        return t.oaInbox;
      case 'action':
        return t.oaAction;
      case 'cc':
        return t.oaCc;
      case 'drafts':
        return t.oaDrafts;
      case 'sent':
        return t.oaSent;
      case 'followup':
        return t.oaFollowUp;
      case 'archive':
        return t.oaArchive;
      case 'registry':
        return t.oaRegistry;
      default:
        return folder;
    }
  }

  Future<void> _switchPosition(int? id) async {
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, id);
    setState(() => _positionId = id);
    await _loadFolder();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaMenu),
        actions: [
          if (_canAdmin)
            IconButton(
              tooltip: t.oaOrg,
              icon: const Icon(Icons.account_tree_outlined),
              onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'office-automation/org')),
            ),
          if (_canAdmin)
            IconButton(
              tooltip: t.oaSettings,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'settings/office-automation')),
            ),
          IconButton(tooltip: t.refresh, icon: const Icon(Icons.refresh), onPressed: _bootstrap),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            for (final folder in _folders)
              Tab(
                text: '${_folderLabel(t, folder)}${_countSuffix(folder)}',
              ),
          ],
        ),
      ),
      floatingActionButton: _canCompose && _positionId != null
          ? FloatingActionButton.extended(
              onPressed: () => context.go(
                context.businessPanelUrl(widget.businessId, 'office-automation/new'),
                extra: {'positionId': _positionId},
              ),
              icon: const Icon(Icons.note_add_outlined),
              label: Text(t.oaNewLetter),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _positionId,
                    decoration: InputDecoration(
                      labelText: t.oaPosition,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final p in _positions)
                        if (oaId(p['id']) != null)
                          DropdownMenuItem(
                            value: oaId(p['id']),
                            child: Text('${p['title'] ?? p['code']}${p['occupancy_kind'] == 'delegate' ? ' (${t.oaDelegate})' : ''}'),
                          ),
                    ],
                    onChanged: _switchPosition,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: t.search,
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _loadFolder),
                    ),
                    onSubmitted: (_) => _loadFolder(),
                  ),
                ),
              ],
            ),
          ),
          if (_positions.isEmpty)
            Expanded(child: Center(child: Text(t.oaNoPositions)))
          else if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_total == 0 || _items.isEmpty)
            Expanded(child: Center(child: Text(t.oaEmptyFolder)))
          else
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = _items[index];
                  final number = (row['secretariat_number'] ?? '').toString();
                  final subject = (row['subject'] ?? '').toString();
                  final status = (row['status'] ?? '').toString();
                  return ListTile(
                    leading: Icon(_statusIcon(status)),
                    title: Text(subject),
                    subtitle: Text([
                      if (number.isNotEmpty) number,
                      status,
                      if (row['referral_kind'] != null) row['referral_kind'].toString(),
                    ].join(' · ')),
                    trailing: Text(
                      HesabixDateUtils.formatApiDateForDisplay(
                        row['letter_date'],
                        widget.calendarController.isJalali,
                        rawValue: row['letter_date_raw'],
                        fallback: '',
                      ),
                    ),
                    onTap: () => context.go(
                      context.businessPanelUrl(widget.businessId, 'office-automation/letters/${row['id']}'),
                      extra: {'positionId': _positionId},
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _countSuffix(String folder) {
    final n = _counts[folder];
    if (n is num && n > 0) return ' ($n)';
    return '';
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'draft':
        return Icons.edit_note;
      case 'in_circulation':
        return Icons.forward_outlined;
      case 'archived':
        return Icons.inventory_2_outlined;
      default:
        return Icons.mail_outline;
    }
  }
}
