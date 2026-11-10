import 'package:flutter/material.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';
import 'admin_compact_scaffold.dart';
import '../../theme/tokens/extensions.dart';

/// تأیید/رد مهارت‌های AI در انتظار بررسی (مدیر سیستم).
class AISkillsAdminPage extends StatefulWidget {
  final bool embedded;
  const AISkillsAdminPage({super.key, this.embedded = false});

  @override
  State<AISkillsAdminPage> createState() => _AISkillsAdminPageState();
}

class _AISkillsAdminPageState extends State<AISkillsAdminPage> {
  final ApiClient _api = ApiClient();
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _api.get<Map<String, dynamic>>('/api/v1/admin/ai/skills/pending');
      final data = res.data?['data'] as Map<String, dynamic>? ?? {};
      final list = (data['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _seedOfficial() async {
    setState(() => _busy = true);
    try {
      final res = await _api.post<Map<String, dynamic>>('/api/v1/admin/ai/skills/seed-official');
      final created = res.data?['data']?['created'] ?? 0;
      if (!mounted) return;
      SnackBarHelper.show(context, message: adminTx(context, '$created مهارت رسمی اضافه شد', '$created official skills added'));
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(int packageId) async {
    setState(() => _busy = true);
    try {
      await _api.post('/api/v1/admin/ai/skills/packages/$packageId/approve');
      if (!mounted) return;
      SnackBarHelper.show(context, message: adminTx(context, 'مهارت تأیید و منتشر شد', 'Skill approved and published'));
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(int packageId) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(adminTx(context, 'رد مهارت', 'Reject skill')),
        content: TextField(
          controller: reasonCtrl,
          decoration: InputDecoration(
            isDense: true,
            labelText: adminTx(context, 'دلیل (اختیاری)', 'Reason (optional)'),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(adminTx(context, 'انصراف', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(adminTx(context, 'رد', 'Reject'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _api.post(
        '/api/v1/admin/ai/skills/packages/$packageId/reject',
        data: {'reason': reasonCtrl.text.trim()},
      );
      if (!mounted) return;
      SnackBarHelper.show(context, message: adminTx(context, 'مهارت رد شد', 'Skill rejected'));
      await _load();
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: ErrorExtractor.forContext(e, context), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: aiHubAppBar(
        embedded: widget.embedded,
        title: Text(adminTx(context, 'بررسی مهارت‌ها', 'Skill review')),
        actions: [
          IconButton(
            onPressed: _busy ? null : _seedOfficial,
            tooltip: adminTx(context, 'افزودن مهارت‌های رسمی', 'Add official skills'),
            icon: const Icon(Icons.cloud_download_outlined, size: 20),
          ),
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: adminTx(context, 'بازخوانی', 'Refresh'),
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(adminTx(context, 'مهارتی در انتظار تأیید نیست', 'No skills waiting for review')))
              : ListView.separated(
                  padding: context.settingsHub.pagePadding,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    final id = item['id'];
                    final packageId = id is int ? id : int.tryParse('$id');
                    final mod = item['compatibility_report'] is Map
                        ? Map<String, dynamic>.from(item['compatibility_report'] as Map)
                        : <String, dynamic>{};
                    final moderation = mod['moderation'] is Map
                        ? Map<String, dynamic>.from(mod['moderation'] as Map)
                        : null;
                    return ListTile(
                      dense: true,
                      title: Text(
                        item['title']?.toString() ?? '',
                        style: context.settingsHub.cardTitleStyle(
                          Theme.of(context).textTheme,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['description']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (item['price_amount'] != null)
                            Text('${adminTx(context, 'قیمت', 'Price')}: ${item['price_amount']}'),
                          if (moderation != null)
                            Text(
                              '${adminTx(context, 'بررسی', 'Review')}: ${moderation['decision']} (${adminTx(context, 'هرزنامه', 'Spam')}: ${moderation['spam_score']})',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: packageId == null
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: adminTx(context, 'تأیید', 'Approve'),
                                  icon: Icon(Icons.check_circle_outline, color: SemanticColorResolver.positive(context)),
                                  onPressed: _busy ? null : () => _approve(packageId),
                                ),
                                IconButton(
                                  tooltip: adminTx(context, 'رد', 'Reject'),
                                  icon: Icon(Icons.cancel_outlined, color: SemanticColorResolver.negative(context)),
                                  onPressed: _busy ? null : () => _reject(packageId),
                                ),
                              ],
                            ),
                    );
                  },
                ),
    );
  }
}
