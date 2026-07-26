import 'package:flutter/material.dart';

import '../../services/hscript_report_service.dart';
import '../../utils/error_extractor.dart';
import '../../utils/snackbar_helper.dart';

Future<String?> showHScriptRecipesSheet({
  required BuildContext context,
  required int businessId,
  required HScriptReportService service,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _RecipesSheet(businessId: businessId, service: service),
  );
}

class _RecipesSheet extends StatefulWidget {
  const _RecipesSheet({required this.businessId, required this.service});

  final int businessId;
  final HScriptReportService service;

  @override
  State<_RecipesSheet> createState() => _RecipesSheetState();
}

class _RecipesSheetState extends State<_RecipesSheet> {
  bool _loading = true;
  String _query = '';
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.service.listRecipes(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      SnackBarHelper.showError(context, message: ErrorExtractor.forContext(e, context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _query.trim().isEmpty
        ? _items
        : _items.where((e) {
            final hay = '${e['title']} ${e['description']} ${e['tags']}'.toLowerCase();
            return hay.contains(_query.trim().toLowerCase());
          }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('دستورپخت‌های آماده', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'یک الگو را انتخاب کنید تا در ادیتور قرار بگیرد.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'جستجو…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(child: Text('موردی یافت نشد', style: TextStyle(color: cs.onSurfaceVariant)))
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final code = item['source_code']?.toString() ?? '';
                            return Material(
                              color: cs.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: code.isEmpty ? null : () => Navigator.pop(context, code),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.dashboard_customize_outlined, color: cs.primary),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              item['title']?.toString() ?? 'بدون عنوان',
                                              style: Theme.of(context).textTheme.titleMedium,
                                            ),
                                          ),
                                          if (code.isNotEmpty)
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, code),
                                              child: const Text('اعمال'),
                                            ),
                                        ],
                                      ),
                                      if ((item['description']?.toString() ?? '').isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          item['description'].toString(),
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                      if (code.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            code.split('\n').take(6).join('\n'),
                                            textDirection: TextDirection.ltr,
                                            textAlign: TextAlign.left,
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11.5,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
