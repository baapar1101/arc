import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/services/crm_service.dart';
import 'package:hesabix_ui/utils/error_extractor.dart';

class CrmGlobalSearchDialog extends StatefulWidget {
  const CrmGlobalSearchDialog({
    super.key,
    required this.businessId,
    required this.crmService,
  });

  final int businessId;
  final CrmService crmService;

  static Future<void> show(
    BuildContext context, {
    required int businessId,
    required CrmService crmService,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CrmGlobalSearchDialog(businessId: businessId, crmService: crmService),
    );
  }

  @override
  State<CrmGlobalSearchDialog> createState() => _CrmGlobalSearchDialogState();
}

class _CrmGlobalSearchDialogState extends State<CrmGlobalSearchDialog> {
  final TextEditingController _query = TextEditingController();
  int _generation = 0;
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _result = const {};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final text = raw.trim();
    final generation = ++_generation;
    if (text.length < 2) {
      setState(() {
        _loading = false;
        _error = null;
        _result = const {};
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.crmService.searchCrm(businessId: widget.businessId, query: text);
      if (!mounted || generation != _generation) return;
      setState(() {
        _result = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = ErrorExtractor.forContext(e, context);
        _loading = false;
      });
    }
  }

  void _open(String path) {
    Navigator.of(context).pop();
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final leads = _list('leads');
    final deals = _list('deals');
    final persons = _list('persons');
    final base = '/business/${widget.businessId}/crm';
    return AlertDialog(
      title: const Text('جست‌وجوی CRM'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'نام، موبایل، کد یا عنوان',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ..._section('سرنخ‌ها', leads, (item) => _open('$base/leads/${item['id']}')),
                  ..._section('فرصت‌ها', deals, (item) => _open('$base/deals/${item['id']}')),
                  ..._section(
                    'اشخاص',
                    persons,
                    (item) => _open('$base/customer-360?personId=${item['id']}'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('بستن')),
      ],
    );
  }

  List<Map<String, dynamic>> _list(String key) {
    final raw = _result[key];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Widget> _section(String title, List<Map<String, dynamic>> items, ValueChanged<Map<String, dynamic>> onTap) {
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      for (final item in items)
        ListTile(
          dense: true,
          title: Text(item['name']?.toString() ?? item['title']?.toString() ?? ''),
          subtitle: Text(
            [item['code'], item['subtitle']].where((part) => part != null && part.toString().isNotEmpty).join(' · '),
          ),
          onTap: () => onTap(item),
        ),
    ];
  }
}
