import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../../services/pay_page_abuse_reports_service.dart';
import '../../utils/error_extractor.dart';
import 'admin_compact_scaffold.dart';

class PayPageAbuseReportsAdminPage extends StatefulWidget {
  const PayPageAbuseReportsAdminPage({super.key});

  @override
  State<PayPageAbuseReportsAdminPage> createState() =>
      _PayPageAbuseReportsAdminPageState();
}

class _PayPageAbuseReportsAdminPageState
    extends State<PayPageAbuseReportsAdminPage> {
  late final PayPageAbuseReportsService _service;
  bool _loading = true;
  String? _error;
  String? _status;
  List<Map<String, dynamic>> _items = const [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _service = PayPageAbuseReportsService(ApiClient());
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.list(status: _status);
      if (!mounted) return;
      setState(() {
        _items = (data['items'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _total = (data['total'] as num?)?.toInt() ?? _items.length;
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

  String _statusLabel(AppLocalizations t, String? status) {
    switch (status) {
      case 'reviewed':
        return t.payPageAbuseStatusReviewed;
      case 'dismissed':
        return t.payPageAbuseStatusDismissed;
      default:
        return t.payPageAbuseStatusNew;
    }
  }

  Future<void> _review(Map<String, dynamic> item) async {
    final t = AppLocalizations.of(context);
    final noteCtrl = TextEditingController(text: '${item['admin_note'] ?? ''}');
    String nextStatus = '${item['status'] ?? 'new'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.payPageAbuseReviewTitle),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${item['reason_label'] ?? item['reason'] ?? ''}'),
                const SizedBox(height: 8),
                Text('${item['details'] ?? ''}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: nextStatus,
                  items: [
                    DropdownMenuItem(value: 'new', child: Text(t.payPageAbuseStatusNew)),
                    DropdownMenuItem(value: 'reviewed', child: Text(t.payPageAbuseStatusReviewed)),
                    DropdownMenuItem(value: 'dismissed', child: Text(t.payPageAbuseStatusDismissed)),
                  ],
                  onChanged: (v) => nextStatus = v ?? nextStatus,
                  decoration: InputDecoration(labelText: t.payPageStatus),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: t.payPageAbuseAdminNote),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.save)),
          ],
        );
      },
    );
    if (ok != true) return;
    try {
      await _service.update(
        int.parse('${item['id']}'),
        status: nextStatus,
        adminNote: noteCtrl.text.trim(),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ErrorExtractor.forContext(e, context))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AdminCompactScaffold(
      title: t.settingsPayPageAbuseReports,
      subtitle: adminTx(context, 'گزارش‌های سوءاستفاده از صفحهٔ پرداخت', 'Payment page abuse reports'),
      actions: [
        IconButton(
          tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
          onPressed: _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(t.all),
                  selected: _status == null,
                  onSelected: (_) {
                    setState(() => _status = null);
                    _load();
                  },
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(t.payPageAbuseStatusNew),
                  selected: _status == 'new',
                  onSelected: (_) {
                    setState(() => _status = 'new');
                    _load();
                  },
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(t.payPageAbuseStatusReviewed),
                  selected: _status == 'reviewed',
                  onSelected: (_) {
                    setState(() => _status = 'reviewed');
                    _load();
                  },
                ),
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(t.payPageAbuseStatusDismissed),
                  selected: _status == 'dismissed',
                  onSelected: (_) {
                    setState(() => _status = 'dismissed');
                    _load();
                  },
                ),
                Text('$_total'),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: Center(child: Text(_error!, textAlign: TextAlign.center)))
          else if (_items.isEmpty)
            Expanded(child: Center(child: Text(t.payPageAbuseEmpty)))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Card(
                    child: ListTile(
                      title: Text('/u/${item['username'] ?? ''} · ${item['reason_label'] ?? ''}'),
                      subtitle: Text(
                        '${_statusLabel(t, '${item['status']}')}\n${item['details'] ?? ''}',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      onTap: () => _review(item),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
