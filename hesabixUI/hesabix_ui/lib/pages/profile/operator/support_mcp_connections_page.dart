import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/core/date_utils.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/pages/admin/admin_compact_scaffold.dart';
import 'package:hesabix_ui/services/support_mcp_connections_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

class SupportMcpConnectionsPage extends StatefulWidget {
  final CalendarController? calendarController;

  const SupportMcpConnectionsPage({
    super.key,
    this.calendarController,
  });

  @override
  State<SupportMcpConnectionsPage> createState() => _SupportMcpConnectionsPageState();
}

class _SupportMcpConnectionsPageState extends State<SupportMcpConnectionsPage> {
  late final SupportMcpConnectionsService _service;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  SupportMcpConnectionsList? _data;

  @override
  void initState() {
    super.initState();
    _service = SupportMcpConnectionsService(ApiClient());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  bool get _jalali => widget.calendarController?.isJalali ?? true;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.listConnections();
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

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    SnackBarHelper.showSuccess(context, message: message);
  }

  Future<void> _create() async {
    final t = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final created = await _service.createConnection();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(adminTx(context, 'توکن اتصال MCP', 'MCP connection token')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                adminTx(
                  context,
                  'این توکن فقط همین یک‌بار نمایش داده می‌شود. آن را در دستیار هوش مصنوعی به‌صورت Bearer ذخیره کنید.',
                  'This token is shown only once. Store it as a Bearer credential in your AI assistant.',
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(created.serverUrl),
              const SizedBox(height: 8),
              SelectableText(created.token),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _copy(created.serverUrl, t.aiMcpUrlCopied),
              child: Text(t.aiMcpCopyUrl),
            ),
            TextButton(
              onPressed: () => _copy(
                created.token,
                adminTx(context, 'توکن کپی شد', 'Token copied'),
              ),
              child: Text(adminTx(context, 'کپی توکن', 'Copy token')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.close),
            ),
          ],
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(SupportMcpConnection item) async {
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

  String _statusLabel(AppLocalizations t, String status) {
    switch (status) {
      case 'expired':
        return t.aiMcpStatusExpired;
      case 'revoked':
        return t.aiMcpStatusRevoked;
      default:
        return t.aiMcpStatusActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final data = _data;
    return AdminCompactScaffold(
      title: adminTx(context, 'MCP پشتیبانی', 'Support MCP'),
      subtitle: adminTx(
        context,
        'اتصال دستیار هوش مصنوعی به میز تیکت‌ها',
        'Connect an AI assistant to the support desk',
      ),
      backFallback: '/user/profile/operator',
      actions: [
        IconButton(
          tooltip: t.refresh,
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
        IconButton(
          tooltip: adminTx(context, 'اتصال جدید', 'New connection'),
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add, size: 20),
        ),
      ],
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
                      Text(
                        adminTx(
                          context,
                          'آدرس سرور را در ChatGPT یا Claude به‌عنوان Custom MCP اضافه کنید و توکن Bearer را فقط روی همین نشانی استفاده کنید. این اتصال به کسب‌وکار مشتری وصل نیست.',
                          'Add this server URL as a custom MCP in ChatGPT or Claude and use the Bearer token only on this endpoint. This connection is not bound to a customer business.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if ((data?.serverUrl ?? '').isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.aiMcpServerUrlLabel, style: Theme.of(context).textTheme.labelLarge),
                                const SizedBox(height: 6),
                                SelectableText(data!.serverUrl),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton.icon(
                                    onPressed: () => _copy(data.serverUrl, t.aiMcpUrlCopied),
                                    icon: const Icon(Icons.copy_outlined, size: 18),
                                    label: Text(t.aiMcpCopyUrl),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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

  Widget _connectionCard(SupportMcpConnection item) {
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
                Chip(label: Text(item.name)),
                Chip(label: Text(_statusLabel(t, item.status))),
              ],
            ),
            if (who.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(t.aiMcpConnectedBy(who), style: Theme.of(context).textTheme.titleSmall),
            ],
            const SizedBox(height: 4),
            Text([connected, lastUsed, expires].where((part) => part.isNotEmpty).join(' · ')),
            if (item.canManage && item.status != 'revoked') ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : () => _revoke(item),
                child: Text(t.aiMcpRevoke),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
