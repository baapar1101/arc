import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/core/api_client.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import 'package:hesabix_ui/services/admin_currencies_service.dart';

/// مدیریت ارزهای سیستم: اعشار، گرد کردن، افزودن و حذف (با شرایط).
class CurrenciesAdminPage extends StatefulWidget {
  const CurrenciesAdminPage({super.key});

  @override
  State<CurrenciesAdminPage> createState() => _CurrenciesAdminPageState();
}

class _CurrenciesAdminPageState extends State<CurrenciesAdminPage> {
  final _svc = AdminCurrenciesService(ApiClient());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _svc.list();
      if (mounted) {
        setState(() => _rows = list);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openEdit({Map<String, dynamic>? row}) async {
    final t = AppLocalizations.of(context);
    final isNew = row == null;
    final nameCtrl = TextEditingController(text: row?['name']?.toString() ?? '');
    final titleCtrl = TextEditingController(text: row?['title']?.toString() ?? '');
    final symbolCtrl = TextEditingController(text: row?['symbol']?.toString() ?? '');
    final codeCtrl = TextEditingController(text: row?['code']?.toString() ?? '');
    var dp = int.tryParse(row?['decimal_places']?.toString() ?? '') ?? 2;
    var round = row?['round_monetary_amounts'] != false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(isNew ? 'ارز جدید' : 'ویرایش ارز'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'نام انگلیسی (یکتا)'),
                      enabled: isNew,
                    ),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'عنوان فارسی'),
                    ),
                    TextField(
                      controller: symbolCtrl,
                      decoration: const InputDecoration(labelText: 'نماد'),
                    ),
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: 'کد (مثل IRR، USD)'),
                      enabled: isNew,
                    ),
                    Row(
                      children: [
                        Text('تعداد اعشار: $dp'),
                        Expanded(
                          child: Slider(
                            value: dp.toDouble(),
                            min: 0,
                            max: 8,
                            divisions: 8,
                            label: '$dp',
                            onChanged: (v) => setLocal(() => dp = v.round()),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: const Text('گرد کردن مبالغ در محاسبات'),
                      value: round,
                      onChanged: (v) => setLocal(() => round = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(t.save),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;

    try {
      if (isNew) {
        await _svc.create({
          'name': nameCtrl.text.trim(),
          'title': titleCtrl.text.trim(),
          'symbol': symbolCtrl.text.trim(),
          'code': codeCtrl.text.trim(),
          'decimal_places': dp,
          'round_monetary_amounts': round,
        });
      } else {
        final id = (row['id'] as num).toInt();
        await _svc.update(id, {
          'title': titleCtrl.text.trim(),
          'symbol': symbolCtrl.text.trim(),
          'decimal_places': dp,
          'round_monetary_amounts': round,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.saved)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final t = AppLocalizations.of(context);
    final id = (row['id'] as num).toInt();
    Map<String, dynamic> check = const {};
    try {
      check = await _svc.deleteCheck(id);
    } catch (_) {}

    if (!mounted) return;

    final canDelete = check['can_delete'] == true;
    final blockers = (check['blockers'] as List?) ?? const [];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف ارز'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${row['code']} — ${row['title']}'),
              if (!canDelete) ...[
                const SizedBox(height: 12),
                const Text(
                  'به‌دلیل موارد زیر حذف ممکن نیست:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...blockers.map((b) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $b'),
                    )),
              ] else
                const Text('آیا از حذف این ارز اطمینان دارید؟'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          if (canDelete)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t.delete),
            ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _svc.delete(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.saved)));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settingsCurrenciesAdmin),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add),
        label: const Text('ارز جدید'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        t.settingsCurrenciesAdminDescription,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('کد')),
                            DataColumn(label: Text('عنوان')),
                            DataColumn(label: Text('نماد')),
                            DataColumn(label: Text('اعشار')),
                            DataColumn(label: Text('گرد')),
                            DataColumn(label: Text('عملیات')),
                          ],
                          rows: _rows.map((r) {
                            return DataRow(
                              cells: [
                                DataCell(Text('${r['code']}')),
                                DataCell(Text('${r['title']}')),
                                DataCell(Text('${r['symbol']}')),
                                DataCell(Text('${r['decimal_places'] ?? 2}')),
                                DataCell(Text((r['round_monetary_amounts'] != false) ? 'بله' : 'خیر')),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _openEdit(row: r),
                                        tooltip: t.edit,
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                                        onPressed: () => _confirmDelete(r),
                                        tooltip: t.delete,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
