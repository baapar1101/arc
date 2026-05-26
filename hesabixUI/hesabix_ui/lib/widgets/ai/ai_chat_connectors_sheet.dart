import 'package:flutter/material.dart';
import 'package:hesabix_ui/services/ai_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';
import 'package:hesabix_ui/utils/snackbar_helper.dart' show SnackBarHelper;

Future<void> showAIChatConnectorsSheet({
  required BuildContext context,
  required AIService aiService,
  required int? businessId,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AIChatConnectorsSheet(
      aiService: aiService,
      businessId: businessId,
    ),
  );
}

class _AIChatConnectorsSheet extends StatefulWidget {
  final AIService aiService;
  final int? businessId;

  const _AIChatConnectorsSheet({
    required this.aiService,
    required this.businessId,
  });

  @override
  State<_AIChatConnectorsSheet> createState() => _AIChatConnectorsSheetState();
}

class _AIChatConnectorsSheetState extends State<_AIChatConnectorsSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.aiService.listConnectors(businessId: widget.businessId);
      if (!mounted) return;
      setState(() => _items = rows);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addConnector() async {
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var method = 'GET';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('کانکتور HTTP'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'عنوان'),
                ),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'https://api.example.com/data?x={{param}}',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: method,
                  decoration: const InputDecoration(labelText: 'متد'),
                  items: const [
                    DropdownMenuItem(value: 'GET', child: Text('GET')),
                    DropdownMenuItem(value: 'POST', child: Text('POST')),
                  ],
                  onChanged: (v) => setLocal(() => method = v ?? 'GET'),
                ),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'توضیح برای AI'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ذخیره')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.aiService.createConnector(
        title: titleCtrl.text.trim(),
        url: urlCtrl.text.trim(),
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        httpMethod: method,
        businessId: widget.businessId,
      );
      await _load();
      if (mounted) SnackBarHelper.show(context, message: 'کانکتور اضافه شد');
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(
          context,
          message: ErrorExtractor.forContext(e, context),
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'کانکتورهای خارجی',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'دستیار می‌تواند با invoke_business_connector این APIها را صدا بزند.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _addConnector,
            icon: const Icon(Icons.add_link, size: 20),
            label: const Text('کانکتور جدید'),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_items.isEmpty)
            const Text('کانکتوری تعریف نشده است.')
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final c = _items[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c['title'] as String? ?? ''),
                    subtitle: Text(
                      '${c['http_method']} · ${c['name']}\n${c['url']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await widget.aiService.deleteConnector(
                          connectorId: c['id'] as int,
                          businessId: widget.businessId,
                        );
                        await _load();
                      },
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
