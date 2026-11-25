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
import '../../../utils/responsive_helper.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/office_automation/oa_cartable_board.dart';
import '../../../widgets/office_automation/oa_searchable_field.dart';
import '../../../widgets/office_automation/oa_ui.dart';

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

class _OaCartablePageState extends State<OaCartablePage> {
  final OfficeAutomationService _svc = OfficeAutomationService();
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  List<Map<String, dynamic>> _positions = [];
  int? _positionId;
  Map<String, dynamic> _counts = const {};
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  String _folder = 'inbox';
  String? _dateFrom;
  String? _dateTo;
  List<Map<String, dynamic>> _filters = [];
  bool _boardMode = false;
  Map<String, dynamic> _boardColumns = const {};
  int? _selectedLetterId;
  int? _selectedReferralId;
  String? _selectedReferralStatus;
  Map<String, dynamic>? _preview;
  bool _previewLoading = false;

  static const _folders = ['inbox', 'action', 'cc', 'drafts', 'sent', 'followup', 'overdue', 'archive', 'registry'];

  bool get _canCompose =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'compose');

  bool get _canRefer =>
      widget.authStore.currentBusiness?.isOwner == true ||
      widget.authStore.hasBusinessPermission('office_automation', 'refer');

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
    _bootstrap();
  }

  @override
  void dispose() {
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
      await _loadFilters();
      if (active != null) {
        await prefs.setInt(_prefKey, active);
        if (_boardMode) {
          await _loadBoard();
        } else {
          await _loadFolder();
        }
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
    if (_folder == 'registry' && !_secretariat) {
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
        folder: _folder,
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        dateFrom: _dateFrom,
        dateTo: _dateTo,
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
      case 'overdue':
        return t.oaOverdue;
      case 'archive':
        return t.oaArchive;
      case 'registry':
        return t.oaRegistry;
      default:
        return folder;
    }
  }

  IconData _folderIcon(String folder) {
    switch (folder) {
      case 'inbox':
        return Icons.inbox_outlined;
      case 'action':
        return Icons.task_alt_outlined;
      case 'cc':
        return Icons.copy_all_outlined;
      case 'drafts':
        return Icons.edit_note;
      case 'sent':
        return Icons.send_outlined;
      case 'followup':
        return Icons.event_outlined;
      case 'overdue':
        return Icons.warning_amber_outlined;
      case 'archive':
        return Icons.inventory_2_outlined;
      case 'registry':
        return Icons.verified_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  Future<void> _switchPosition(int? id) async {
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKey, id);
    setState(() => _positionId = id);
    if (_boardMode) {
      await _loadBoard();
    } else {
      await _loadFolder();
    }
  }

  Map<String, dynamic>? get _activePosition {
    for (final p in _positions) {
      if (oaId(p['id']) == _positionId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final wide = ResponsiveHelper.widthOf(context) >= 980;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.oaCartable),
        actions: [
          if (wide) ...[
            if (_canAdmin)
              IconButton(
                tooltip: t.oaOrg,
                icon: const Icon(Icons.account_tree_outlined),
                onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'office-automation/org')),
              ),
            IconButton(
              tooltip: t.oaExternalOrgs,
              icon: const Icon(Icons.apartment_outlined),
              onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'office-automation/external-orgs')),
            ),
            IconButton(
              tooltip: t.oaArchiveTree,
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'office-automation/archive')),
            ),
            IconButton(
              tooltip: t.oaReports,
              icon: const Icon(Icons.bar_chart_outlined),
              onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'office-automation/reports')),
            ),
            if (_canAdmin)
              IconButton(
                tooltip: t.oaSettings,
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'settings/office-automation')),
              ),
          ] else
            PopupMenuButton<String>(
              tooltip: t.oaMorePages,
              onSelected: (path) => context.go(context.businessPanelUrl(widget.businessId, path)),
              itemBuilder: (ctx) => [
                if (_canAdmin) PopupMenuItem(value: 'office-automation/org', child: Text(t.oaOrg)),
                PopupMenuItem(value: 'office-automation/external-orgs', child: Text(t.oaExternalOrgs)),
                PopupMenuItem(value: 'office-automation/archive', child: Text(t.oaArchiveTree)),
                PopupMenuItem(value: 'office-automation/reports', child: Text(t.oaReports)),
                if (_canAdmin) PopupMenuItem(value: 'settings/office-automation', child: Text(t.oaSettings)),
              ],
            ),
            IconButton(
              tooltip: t.oaMyDesk,
              icon: const Icon(Icons.space_dashboard_outlined),
              onPressed: () => context.go(context.businessPanelUrl(widget.businessId, 'office-automation/desk')),
            ),
            IconButton(
              tooltip: _boardMode ? t.oaListView : t.oaBoardView,
              icon: Icon(_boardMode ? Icons.view_list_outlined : Icons.view_kanban_outlined),
              onPressed: _toggleBoard,
            ),
            IconButton(tooltip: t.refresh, icon: const Icon(Icons.refresh), onPressed: _bootstrap),
        ],
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
            child: wide
                ? Row(
                    children: [
                      Expanded(child: _positionField(t)),
                      const SizedBox(width: 12),
                      Expanded(child: _searchField(t)),
                    ],
                  )
                : Column(
                    children: [
                      _positionField(t),
                      const SizedBox(height: 8),
                      _searchField(t),
                    ],
                  ),
          ),
          if (!wide)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final folder in _folders)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        avatar: Icon(_folderIcon(folder), size: 16),
                        label: Text('${_folderLabel(t, folder)}${_countSuffix(folder)}'),
                        selected: _folder == folder,
                        onSelected: (_) {
                          setState(() => _folder = folder);
                          _loadFolder();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _boardMode ? _boardLayout(t, wide) : (wide
                ? Row(
                    children: [
                      SizedBox(width: 240, child: _folderRail(t)),
                      const VerticalDivider(width: 1),
                      Expanded(child: _list(t)),
                    ],
                  )
                : _list(t)),
          ),
        ],
      ),
    );
  }

  Widget _positionField(AppLocalizations t) {
    final active = _activePosition;
    return OaSearchableField(
      label: t.oaActingAs,
      hint: t.oaSearchPosition,
      emptyText: t.oaNoPositions,
      prefixIcon: Icons.badge_outlined,
      value: active == null ? null : oaPositionItem(active),
      onChanged: (item) => _switchPosition(item == null ? null : int.tryParse(item.id)),
      onSearch: (q) async {
        final needle = q.trim().toLowerCase();
        final rows = needle.isEmpty
            ? _positions
            : _positions.where((p) => oaPositionLabel(p).toLowerCase().contains(needle)).toList();
        return [
          for (final p in rows)
            oaPositionItem({
              ...p,
              'title': p['occupancy_kind'] == 'delegate' ? '${p['title'] ?? p['code']} (${t.oaDelegate})' : p['title'],
            }),
        ];
      },
    );
  }

  void _toggleBoard() {
    setState(() => _boardMode = !_boardMode);
    if (_boardMode) {
      _loadBoard();
    } else {
      _loadFolder();
    }
  }

  Future<void> _reloadVisible() {
    if (_boardMode) return _loadBoard();
    return _loadFolder();
  }

  Future<void> _loadBoard() async {
    if (_positionId == null) return;
    setState(() => _loading = true);
    try {
      final data = await _svc.listCartableBoard(
        businessId: widget.businessId,
        positionId: _positionId!,
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _boardColumns = Map<String, dynamic>.from(data['columns'] as Map? ?? const {});
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _openPreview(Map<String, dynamic> row) async {
    final letterId = oaId(row['id']);
    if (letterId == null || _positionId == null) return;
    setState(() {
      _selectedLetterId = letterId;
      _selectedReferralId = oaId(row['referral_id']);
      _selectedReferralStatus = row['referral_status']?.toString();
      _previewLoading = true;
    });
    try {
      final data = await _svc.getLetter(
        businessId: widget.businessId,
        letterId: letterId,
        positionId: _positionId!,
      );
      if (!mounted) return;
      setState(() {
        _preview = data;
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _previewLoading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _moveReferral(Map<String, dynamic> row, String target) async {
    final referralId = oaId(row['referral_id']);
    if (referralId == null || _positionId == null || !_canRefer) return;
    final status = '${row['referral_status'] ?? ''}';
    if (status != 'pending' && status != 'seen') return;
    if (target != 'done' && target != 'returned') return;
    try {
      if (target == 'done') {
        await _svc.completeReferral(businessId: widget.businessId, referralId: referralId, positionId: _positionId!);
      } else {
        await _svc.returnReferral(businessId: widget.businessId, referralId: referralId, positionId: _positionId!);
      }
      _selectedReferralStatus = target;
      await _loadBoard();
      if (_selectedLetterId != null) {
        await _openPreview({...row, 'referral_status': target});
      }
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
      await _loadBoard();
    }
  }

  Future<void> _dropAttachment(List<int> bytes, String filename) async {
    if (!_canCompose || _selectedLetterId == null || _positionId == null) return;
    try {
      await _svc.uploadAttachment(
        businessId: widget.businessId,
        letterId: _selectedLetterId!,
        positionId: _positionId!,
        bytes: bytes,
        filename: filename,
      );
      await _openPreview({
        'id': _selectedLetterId,
        'referral_id': _selectedReferralId,
        'referral_status': _selectedReferralStatus,
      });
      if (mounted) SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).oaAttach);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _boardLayout(AppLocalizations t, bool wide) {
    if (_positions.isEmpty) return Center(child: Text(t.oaNoPositions));
    if (_loading && _boardColumns.isEmpty) return const Center(child: CircularProgressIndicator());
    final board = OaCartableBoard(
      columns: _boardColumns,
      canRefer: _canRefer,
      selectedLetterId: _selectedLetterId,
      onOpen: _openPreview,
      onMove: _moveReferral,
    );
    final preview = _selectedLetterId == null
        ? null
        : OaCartablePreview(
            letter: _preview,
            loading: _previewLoading,
            canRefer: _canRefer,
            canCompose: _canCompose,
            referralStatus: _selectedReferralStatus,
            onClose: () => setState(() {
              _selectedLetterId = null;
              _selectedReferralId = null;
              _preview = null;
            }),
            onOpenFull: () {
              if (_selectedLetterId == null) return;
              context.go(
                context.businessPanelUrl(widget.businessId, 'office-automation/letters/$_selectedLetterId'),
                extra: {'positionId': _positionId},
              );
            },
            onComplete: _selectedReferralId == null
                ? null
                : () => _moveReferral({
                      'id': _selectedLetterId,
                      'referral_id': _selectedReferralId,
                      'referral_status': _selectedReferralStatus,
                    }, 'done'),
            onReturn: _selectedReferralId == null
                ? null
                : () => _moveReferral({
                      'id': _selectedLetterId,
                      'referral_id': _selectedReferralId,
                      'referral_status': _selectedReferralStatus,
                    }, 'returned'),
            onDropFile: _canCompose ? _dropAttachment : null,
          );
    if (preview == null) return board;
    if (!wide) {
      return Column(
        children: [
          SizedBox(height: 220, child: preview),
          const Divider(height: 1),
          Expanded(child: board),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: board),
        const VerticalDivider(width: 1),
        SizedBox(width: 380, child: preview),
      ],
    );
  }

  Future<void> _loadFilters() async {
    try {
      final rows = await _svc.listSavedFilters(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _filters = rows);
    } catch (_) {
      // فیلتر ذخیره‌شده نباید بارگذاری کارتابل را متوقف کند.
    }
  }

  String? _optionalText(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }

  Future<void> _applyFilter(Map<String, dynamic> row) async {
    setState(() {
      final folder = '${row['folder'] ?? ''}'.trim();
      if (_folders.contains(folder)) _folder = folder;
      _search.text = '${row['q'] ?? ''}';
      _dateFrom = _optionalText(row['date_from']);
      _dateTo = _optionalText(row['date_to']);
      _boardMode = false;
    });
    await _loadFolder();
  }

  Future<void> _saveFilter() async {
    final t = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: _search.text.trim());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.oaSaveFilter),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(labelText: t.oaFilterName, border: const OutlineInputBorder()),
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()), child: Text(t.save)),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _svc.saveSavedFilter(
        businessId: widget.businessId,
        name: name,
        folder: _folder,
        q: _search.text.trim(),
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      await _loadFilters();
      if (mounted) SnackBarHelper.showSuccess(context, message: t.oaSaveFilter);
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Future<void> _deleteFilter(int id) async {
    try {
      await _svc.deleteSavedFilter(businessId: widget.businessId, filterId: id);
      await _loadFilters();
    } catch (e) {
      if (mounted) SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  Widget _searchField(AppLocalizations t) {
    return TextField(
      controller: _search,
      decoration: InputDecoration(
        labelText: t.search,
        hintText: t.oaInboxHint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _filterMenu(t),
            IconButton(tooltip: t.search, icon: const Icon(Icons.tune), onPressed: _reloadVisible),
          ],
        ),
      ),
      onSubmitted: (_) => _reloadVisible(),
    );
  }

  Widget _filterMenu(AppLocalizations t) {
    return PopupMenuButton<int>(
      tooltip: t.oaSavedFilters,
      icon: const Icon(Icons.bookmark_border),
      onSelected: (id) {
        if (id == -1) {
          _saveFilter();
          return;
        }
        final row = _filters.cast<Map<String, dynamic>?>().firstWhere(
          (item) => oaId(item?['id']) == id,
          orElse: () => null,
        );
        if (row != null) _applyFilter(row);
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(value: -1, child: Text(t.oaSaveFilter)),
        const PopupMenuDivider(),
        if (_filters.isEmpty)
          PopupMenuItem(enabled: false, child: Text(t.oaNoSavedFilters)),
        for (final row in _filters)
          PopupMenuItem(
            value: oaId(row['id']) ?? 0,
            child: Row(
              children: [
                Expanded(child: Text('${row['name'] ?? ''}', overflow: TextOverflow.ellipsis)),
                IconButton(
                  tooltip: t.delete,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    Navigator.pop(ctx);
                    final id = oaId(row['id']);
                    if (id != null) _deleteFilter(id);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _folderRail(AppLocalizations t) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(t.oaCartable, style: Theme.of(context).textTheme.titleSmall),
        ),
        for (final folder in _folders)
          ListTile(
            selected: _folder == folder,
            leading: Icon(_folderIcon(folder)),
            title: Text(_folderLabel(t, folder)),
            trailing: _countBadge(folder),
            onTap: () {
              setState(() => _folder = folder);
              _loadFolder();
            },
          ),
      ],
    );
  }

  Widget? _countBadge(String folder) {
    final n = _counts[folder];
    if (n is! num || n <= 0) return null;
    return CircleAvatar(
      radius: 12,
      child: Text('${n.toInt()}', style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _list(AppLocalizations t) {
    if (_positions.isEmpty) return Center(child: Text(t.oaNoPositions));
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_total == 0 || _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_folderIcon(_folder), size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(t.oaEmptyFolder),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = _items[index];
        final number = (row['secretariat_number'] ?? '').toString();
        final subject = (row['subject'] ?? '').toString();
        final status = (row['status'] ?? '').toString();
        final urgency = (row['urgency'] ?? 'normal').toString();
        final confidentiality = (row['confidentiality'] ?? 'normal').toString();
        final kind = (row['letter_kind'] ?? '').toString();
        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: oaUrgencyColor(Theme.of(context).colorScheme, urgency).withValues(alpha: 0.12),
              child: Icon(_statusIcon(status), color: oaUrgencyColor(Theme.of(context).colorScheme, urgency)),
            ),
            title: Text(subject, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (number.isNotEmpty) OaStatusChip(label: number, icon: Icons.tag),
                  OaStatusChip(label: oaStatusLabel(t, status)),
                  if (kind.isNotEmpty) OaStatusChip(label: oaKindLabel(t, kind)),
                  if (urgency != 'normal') OaStatusChip(label: oaUrgencyLabel(t, urgency), color: oaUrgencyColor(Theme.of(context).colorScheme, urgency)),
                  if (confidentiality != 'normal')
                    OaStatusChip(
                      label: oaConfidentialityLabel(t, confidentiality),
                      icon: Icons.lock_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  if (row['referral_kind'] != null) OaStatusChip(label: '${row['referral_kind']}'),
                ],
              ),
            ),
            trailing: Text(
              HesabixDateUtils.formatApiDateForDisplay(
                row['letter_date'],
                widget.calendarController.isJalali,
                rawValue: row['letter_date_raw'],
                fallback: '',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: () => context.go(
              context.businessPanelUrl(widget.businessId, 'office-automation/letters/${row['id']}'),
              extra: {'positionId': _positionId},
            ),
          ),
        );
      },
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
