import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart';

/// تأیید/رد مهارت‌های AI در انتظار بررسی (مدیر سیستم).
class AISkillsAdminPage extends StatefulWidget {
  const AISkillsAdminPage({super.key});

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
      SnackBarHelper.show(context, message: '$created مهارت رسمی اضافه شد');
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
      SnackBarHelper.show(context, message: 'مهارت تأیید و منتشر شد');
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
        title: const Text('رد مهارت'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'دلیل (اختیاری)'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('رد')),
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
      SnackBarHelper.show(context, message: 'مهارت رد شد');
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
      appBar: AppBar(
        title: const Text('بررسی مهارت‌های AI'),
        actions: [
          IconButton(
            onPressed: _busy ? null : () => context.push('/user/profile/system-settings/ai-marketplace'),
            tooltip: 'تنظیمات مارکت‌پلیس',
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            onPressed: _busy ? null : _seedOfficial,
            tooltip: 'Seed مهارت‌های رسمی',
            icon: const Icon(Icons.cloud_download_outlined),
          ),
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('مهارتی در انتظار تأیید نیست'))
              : ListView.separated(
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
                      title: Text(item['title']?.toString() ?? ''),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['description']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (item['price_amount'] != null)
                            Text('قیمت: ${item['price_amount']}'),
                          if (moderation != null)
                            Text(
                              'moderation: ${moderation['decision']} (spam: ${moderation['spam_score']})',
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
                                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                  onPressed: _busy ? null : () => _approve(packageId),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
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
