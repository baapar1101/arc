import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/business_nav.dart';
import '../../core/calendar_controller.dart';
import '../../core/date_utils.dart';
import '../../core/hesabix_back.dart';
import '../../l10n/app_localizations.dart';
import '../../services/ai_mcp_connections_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

class AiMcpConnectionsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;
  final CalendarController? calendarController;

  const AiMcpConnectionsPage({
    super.key,
    required this.businessId,
    required this.authStore,
    this.calendarController,
  });

  @override
  State<AiMcpConnectionsPage> createState() => _AiMcpConnectionsPageState();
}

class _AiMcpConnectionsPageState extends State<AiMcpConnectionsPage> {
  late final AiMcpConnectionsService _service;
  bool _loading = true;
  String? _error;
  AiMcpConnectionsList? _data;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = AiMcpConnectionsService(ApiClient());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  bool get _jalali => widget.calendarController?.isJalali ?? true;

  bool get _viewerIsOwner {
    if (_data?.viewerIsOwner == true) return true;
    final business = widget.authStore.currentBusiness;
    return business?.id == widget.businessId && business?.isOwner == true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.listConnections(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  String _formatWhen(String? raw) {
    final parsed = DateTime.tryParse(raw ?? '');
    if (parsed == null) return '';
    return HesabixDateUtils.formatForDisplay(parsed.toLocal(), _jalali);
  }

  String _clientLabel(AppLocalizations t, AiMcpConnection item) {
    switch (item.clientKind) {
      case 'chatgpt':
        return t.aiMcpClientChatgpt;
      case 'claude':
        return t.aiMcpClientClaude;
      case 'manual':
        return t.aiMcpClientManual;
      default:
        return item.clientName.isNotEmpty ? item.clientName : t.aiMcpClientOauth;
    }
  }

  String _statusLabel(AppLocalizations t, String status) {
    switch (status) {
      case 'expired':
        return t.aiMcpStatusExpired;
      case 'revoked':
        return t.aiMcpStatusRevoked;
      case 'membership_inactive':
        return t.aiMcpStatusMembershipInactive;
      default:
        return t.aiMcpStatusActive;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'expired':
      case 'membership_inactive':
        return scheme.tertiary;
      case 'revoked':
        return scheme.outline;
      default:
        return scheme.primary;
    }
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    SnackBarHelper.showSuccess(context, message: AppLocalizations.of(context).aiMcpUrlCopied);
  }

  Future<void> _revoke(AiMcpConnection item) async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.aiMcpRevokeConfirmTitle),
        content: Text(t.aiMcpRevokeConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(t.aiMcpRevoke),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.revoke(connectionId: item.id);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.aiMcpRevoked);
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeAll() async {
    final t = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.aiMcpRevokeAllConfirmTitle),
        content: Text(t.aiMcpRevokeAllConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(t.aiMcpRevokeAll),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final count = await _service.revokeAll(businessId: widget.businessId);
      if (!mounted) return;
      SnackBarHelper.showSuccess(context, message: t.aiMcpRevokeAllDone(count));
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(AiMcpConnection item) async {
    final t = AppLocalizations.of(context);
    if (item.status == 'revoked' || item.status == 'expired') {
      SnackBarHelper.showInfo(context, message: t.aiMcpCannotEditRevoked);
      return;
    }
    if (item.status == 'membership_inactive') {
      SnackBarHelper.showInfo(context, message: t.aiMcpCannotEditInactive);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _AiMcpPermissionsDialog(service: _service, connection: item),
    );
    if (saved == true && mounted) {
      SnackBarHelper.showSuccess(context, message: t.aiMcpAccessSaved);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final data = _data;
    final pluginActive = data?.plugin['is_active'] == true;
    final pluginReason = (data?.plugin['reason'] ?? '').toString();
    final pluginExpired = pluginReason.contains('expired');
    return Scaffold(
      appBar: AppBar(
        title: Text(t.aiMcpConnectionsTitle),
        leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
        actions: [
          if (_viewerIsOwner && (data?.items.any((item) => item.status == 'active') ?? false))
            TextButton(
              onPressed: _busy ? null : _revokeAll,
              child: Text(t.aiMcpRevokeAll),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: Text(t.retry)),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(t.aiMcpConnectionsSubtitle, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 12),
                      if (!pluginActive)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.info_outline),
                            title: Text(
                              pluginExpired ? t.aiMcpPluginExpiredBanner : t.aiMcpPluginInactiveBanner,
                            ),
                            trailing: TextButton(
                              onPressed: () => context.go(
                                context.businessPanelUrl(widget.businessId, 'plugin-marketplace'),
                              ),
                              child: Text(t.aiMcpOpenMarketplace),
                            ),
                          ),
                        ),
                      if ((data?.serverUrl ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.aiMcpConnectHint),
                                const SizedBox(height: 12),
                                Text(t.aiMcpServerUrlLabel, style: Theme.of(context).textTheme.labelLarge),
                                const SizedBox(height: 6),
                                SelectableText(data!.serverUrl),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton.icon(
                                    onPressed: () => _copyUrl(data.serverUrl),
                                    icon: const Icon(Icons.copy_outlined, size: 18),
                                    label: Text(t.aiMcpCopyUrl),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (data == null || data.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: Text(t.aiMcpEmpty)),
                        )
                      else
                        ...data.items.map(_connectionCard),
                    ],
                  ),
                ),
    );
  }

  Widget _connectionCard(AiMcpConnection item) {
    final t = AppLocalizations.of(context);
    final lastUsed = item.lastUsedAt == null || item.lastUsedAt!.isEmpty
        ? t.aiMcpNeverUsed
        : t.aiMcpLastUsed(_formatWhen(item.lastUsedAt));
    final connected = item.createdAt == null ? '' : t.aiMcpConnectedAt(_formatWhen(item.createdAt));
    final expires = item.expiresAt == null ? '' : t.aiMcpExpiresAt(_formatWhen(item.expiresAt));
    final who = item.userName.isEmpty ? (item.userEmail ?? '') : item.userName;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(_clientLabel(t, item))),
                Chip(
                  label: Text(_statusLabel(t, item.status)),
                  avatar: Icon(Icons.circle, size: 10, color: _statusColor(context, item.status)),
                ),
                Chip(label: Text(item.writeEnabled ? t.aiMcpReadWrite : t.aiMcpReadOnly)),
              ],
            ),
            const SizedBox(height: 8),
            if (who.isNotEmpty) Text(t.aiMcpConnectedBy(who), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              item.unrestrictedTools
                  ? t.aiMcpUnrestrictedTools
                  : t.aiMcpToolCount(item.toolCount ?? item.toolPermissions?.length ?? 0),
            ),
            const SizedBox(height: 4),
            Text([connected, lastUsed, expires].where((part) => part.isNotEmpty).join(' · ')),
            if (item.canManage && item.status != 'revoked') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  if (item.isLive)
                    FilledButton.tonal(
                      onPressed: _busy ? null : () => _edit(item),
                      child: Text(t.aiMcpChangeAccess),
                    ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _revoke(item),
                    child: Text(t.aiMcpRevoke),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiMcpPermissionsDialog extends StatefulWidget {
  final AiMcpConnectionsService service;
  final AiMcpConnection connection;

  const _AiMcpPermissionsDialog({
    required this.service,
    required this.connection,
  });

  @override
  State<_AiMcpPermissionsDialog> createState() => _AiMcpPermissionsDialogState();
}

class _AiMcpPermissionsDialogState extends State<_AiMcpPermissionsDialog> {
  bool _loading = true;
  String? _error;
  AiMcpConnectionCatalog? _catalog;
  final Set<String> _selected = {};
  final Set<String> _original = {};
  bool _enableWrites = false;
  bool _originalWrites = false;
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await widget.service.getCatalog(connectionId: widget.connection.id);
      if (!mounted) return;
      final initial = catalog.unrestrictedTools
          ? catalog.tools.map((tool) => tool.name)
          : catalog.selected;
      setState(() {
        _catalog = catalog;
        _selected
          ..clear()
          ..addAll(initial.where((name) => catalog.tools.any((tool) => tool.name == name)));
        _original
          ..clear()
          ..addAll(_selected);
        _enableWrites = catalog.writeEnabled;
        _originalWrites = catalog.writeEnabled;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  AiMcpTool? _toolNamed(String name) {
    final tools = _catalog?.tools;
    if (tools == null) return null;
    for (final tool in tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  List<AiMcpTool> get _visible {
    final catalog = _catalog;
    if (catalog == null) return const [];
    final query = _query.trim().toLowerCase();
    return catalog.tools.where((tool) {
      if (!_enableWrites && !tool.readOnly) return false;
      if (query.isEmpty) return true;
      return tool.name.toLowerCase().contains(query) ||
          tool.description.toLowerCase().contains(query) ||
          tool.category.toLowerCase().contains(query);
    }).toList();
  }

  Map<String, List<AiMcpTool>> get _grouped {
    final grouped = <String, List<AiMcpTool>>{};
    for (final tool in _visible) {
      grouped.putIfAbsent(tool.category, () => []).add(tool);
    }
    return grouped;
  }

  bool get _keepsUnrestricted => keepsUnrestrictedMcpGrant(
        originallyUnrestricted: widget.connection.unrestrictedTools,
        enableWrites: _enableWrites,
        tools: _catalog?.tools ?? const [],
        selected: _selected,
      );

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final added = _selected.difference(_original);
    final writeNewlyOn = _enableWrites && !_originalWrites;
    final denyAll = !_keepsUnrestricted && _selected.isEmpty;
    String? confirmBody;
    if (writeNewlyOn) {
      confirmBody = t.aiMcpWritesNeedConfirm;
    } else if (denyAll) {
      confirmBody = t.aiMcpDenyAllConfirm;
    } else if (added.isNotEmpty) {
      confirmBody = t.aiMcpWidenConfirm;
    }
    if (confirmBody != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t.aiMcpChangeAccess),
          content: Text(confirmBody!),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.aiMcpSaveAccess)),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _saving = true);
    try {
      final selected = _enableWrites
          ? _selected.toList()
          : _selected.where((name) {
              final tool = _toolNamed(name);
              return tool == null || tool.readOnly;
            }).toList();
      await widget.service.updatePermissions(
        connectionId: widget.connection.id,
        toolPermissions: selected,
        enableWrites: _enableWrites,
        unrestrictedTools: _keepsUnrestricted,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(t.aiMcpPermissionsTitle),
      content: SizedBox(
        width: 560,
        height: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.aiMcpEnableWrites),
                        subtitle: Text(t.aiMcpEnableWritesHint),
                        value: _enableWrites,
                        onChanged: _saving
                            ? null
                            : (value) {
                                setState(() {
                                  _enableWrites = value;
                                  if (!value) {
                                    _selected.removeWhere((name) {
                                      final tool = _toolNamed(name);
                                      return tool != null && !tool.readOnly;
                                    });
                                  }
                                });
                              },
                      ),
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: t.aiMcpSearchTools,
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _visible.isEmpty
                            ? Center(child: Text(t.aiMcpNoTools))
                            : ListView(
                                children: _grouped.entries.map((entry) {
                                  final names = entry.value.map((tool) => tool.name).toSet();
                                  final allOn = names.every(_selected.contains);
                                  return ExpansionTile(
                                    title: Text('${entry.key} (${entry.value.length})'),
                                    trailing: Checkbox(
                                      value: allOn,
                                      onChanged: _saving
                                          ? null
                                          : (value) {
                                              setState(() {
                                                if (value == true) {
                                                  _selected.addAll(names);
                                                } else {
                                                  _selected.removeAll(names);
                                                }
                                              });
                                            },
                                    ),
                                    children: entry.value
                                        .map(
                                          (tool) => CheckboxListTile(
                                            dense: true,
                                            value: _selected.contains(tool.name),
                                            title: Text(tool.name),
                                            subtitle: tool.description.isEmpty ? null : Text(tool.description),
                                            onChanged: _saving
                                                ? null
                                                : (value) {
                                                    setState(() {
                                                      if (value == true) {
                                                        _selected.add(tool.name);
                                                      } else {
                                                        _selected.remove(tool.name);
                                                      }
                                                    });
                                                  },
                                          ),
                                        )
                                        .toList(),
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(t.cancel),
        ),
        FilledButton(
          onPressed: _saving || _loading || _error != null ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t.aiMcpSaveAccess),
        ),
      ],
    );
  }
}
