import 'package:flutter/material.dart';
import '../../services/warehouse_service.dart';

class WarehouseDocsPage extends StatefulWidget {
  final int businessId;
  const WarehouseDocsPage({super.key, required this.businessId});

  @override
  State<WarehouseDocsPage> createState() => _WarehouseDocsPageState();
}

class _WarehouseDocsPageState extends State<WarehouseDocsPage> {
  final _svc = WarehouseService();
  bool _loading = true;
  String? _error;
  List<dynamic> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _svc.search(businessId: widget.businessId, limit: 50);
      setState(() { _items = List<dynamic>.from(res['items'] ?? const []); });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حواله‌های انبار')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final it = _items[index] as Map<String, dynamic>;
                      return ListTile(
                        title: Text('${it['code'] ?? '-'} • ${it['doc_type'] ?? ''} • ${it['status'] ?? ''}'),
                        subtitle: Text(it['document_date'] ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.publish),
                          onPressed: (it['status'] == 'draft') ? () async {
                            try {
                              await _svc.postDoc(businessId: widget.businessId, docId: it['id']);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('حواله پست شد')),
                              );
                              _load();
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطا در پست حواله: $e')),
                              );
                            }
                          } : null,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
