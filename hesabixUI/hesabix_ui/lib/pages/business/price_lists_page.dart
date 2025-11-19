import 'package:flutter/material.dart';
import 'package:hesabix_ui/l10n/app_localizations.dart';
import '../../services/price_list_service.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../utils/date_formatters.dart';

class PriceListsPage extends StatefulWidget {
  final int businessId;
  final AuthStore authStore;

  const PriceListsPage({super.key, required this.businessId, required this.authStore});

  @override
  State<PriceListsPage> createState() => _PriceListsPageState();
}

class _PriceListsPageState extends State<PriceListsPage> {
  final _svc = PriceListService(apiClient: ApiClient());
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _priceLists = [];
  bool _loading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadPriceLists();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPriceLists() async {
    setState(() => _loading = true);
    try {
      final result = await _svc.listPriceLists(
        businessId: widget.businessId,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      final items = result['items'] as List<dynamic>? ?? [];
      setState(() {
        _priceLists = items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در بارگذاری لیست‌ها: $e')),
        );
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _loadPriceLists();
  }


  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'جستجو در لیست‌های قیمت',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: const OutlineInputBorder(),
            ),
            onChanged: _onSearchChanged,
          ),
        ),
        // Header with create button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.priceLists,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: _loadPriceLists,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'تازه‌سازی',
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await _openCreateDialog(context);
                      if (ok == true) {
                        _loadPriceLists();
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('ایجاد لیست قیمت'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(),
        // Price lists list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _priceLists.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.price_change_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'هیچ لیست قیمتی یافت نشد'
                                : 'هیچ لیست قیمتی وجود ندارد',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                          if (_searchQuery.isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'برای شروع، یک لیست قیمت جدید ایجاد کنید',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[500],
                                  ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _priceLists.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final priceList = _priceLists[index];
                        final isActive = priceList['is_active'] == true;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isActive 
                                  ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.1),
                              child: Icon(
                                Icons.price_change,
                                color: isActive 
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    priceList['name']?.toString() ?? 'بدون نام',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: isActive ? null : Colors.grey,
                                    ),
                                  ),
                                ),
                                if (!isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'غیرفعال',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              'ایجاد شده: ${DateFormatters.formatServerDate(priceList['created_at_formatted'])}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _openEditDialog(context, priceList),
                                  tooltip: 'ویرایش',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deletePriceList(context, priceList),
                                  tooltip: 'حذف',
                                ),
                              ],
                            ),
                            onTap: () => _openEditDialog(context, priceList),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<bool?> _openCreateDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    String name = '';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ایجاد لیست قیمت'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'نام لیست قیمت',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'نام لیست قیمت ضروری است' : null,
                  onChanged: (v) => name = v,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                await _svc.createPriceList(
                  businessId: widget.businessId,
                  payload: {'name': name.trim()},
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(true);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('لیست قیمت با موفقیت ایجاد شد')),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('خطا در ایجاد لیست قیمت: $e')),
                );
              }
            },
            child: const Text('ایجاد'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditDialog(BuildContext context, Map<String, dynamic> priceList) async {
    final formKey = GlobalKey<FormState>();
    String name = priceList['name']?.toString() ?? '';
    bool isActive = priceList['is_active'] == true;
    final priceListId = priceList['id'] as int;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ویرایش لیست قیمت'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: name,
                  decoration: const InputDecoration(
                    labelText: 'نام لیست قیمت',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'نام لیست قیمت ضروری است' : null,
                  onChanged: (v) => name = v,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('فعال'),
                  subtitle: const Text('لیست قیمت در دسترس باشد'),
                  value: isActive,
                  onChanged: (value) => setState(() => isActive = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                await _svc.updatePriceList(
                  businessId: widget.businessId,
                  priceListId: priceListId,
                  payload: {
                    'name': name.trim(),
                    'is_active': isActive,
                  },
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(true);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('لیست قیمت با موفقیت بروزرسانی شد')),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('خطا در ویرایش لیست قیمت: $e')),
                );
              }
            },
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );

    if (result == true) {
      _loadPriceLists();
    }
  }

  Future<void> _deletePriceList(BuildContext context, Map<String, dynamic> priceList) async {
    final priceListName = priceList['name']?.toString() ?? 'بدون نام';
    final priceListId = priceList['id'] as int;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف لیست قیمت'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('آیا از حذف لیست قیمت "$priceListName" اطمینان دارید؟'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تمام آیتم‌های قیمت این لیست نیز حذف خواهند شد.',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!context.mounted) return;
      final ctx = context;
      try {
        final success = await _svc.deletePriceList(
          businessId: widget.businessId,
          priceListId: priceListId,
        );
        
        if (!ctx.mounted) return;
        if (success) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('لیست قیمت "$priceListName" با موفقیت حذف شد')),
          );
          _loadPriceLists(); // Refresh the list
        } else {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('خطا در حذف لیست قیمت')),
          );
        }
      } catch (e) {
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('خطا در حذف لیست قیمت: $e')),
        );
      }
    }
  }
}


