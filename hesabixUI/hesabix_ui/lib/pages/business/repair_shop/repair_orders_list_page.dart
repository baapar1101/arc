import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:go_router/go_router.dart';
import '../../../services/repair_shop_service.dart';
import '../../../models/repair_order_model.dart';
import '../../../core/api_client.dart';
import '../../../utils/error_extractor.dart';

/// صفحه لیست سفارشات تعمیر
class RepairOrdersListPage extends StatefulWidget {
  final int businessId;

  const RepairOrdersListPage({
    super.key,
    required this.businessId,
  });

  @override
  State<RepairOrdersListPage> createState() => _RepairOrdersListPageState();
}

class _RepairOrdersListPageState extends State<RepairOrdersListPage> {
  late final RepairShopService _service;
  Timer? _debounceTimer;
  
  bool _isLoading = true;
  List<RepairOrderListItem> _orders = [];
  String? _errorMessage;
  int _totalOrders = 0;
  
  // فیلترها
  String? _selectedStatus;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  // وضعیت‌های مختلف
  final Map<String, String> _statusLabels = {
    'received': 'دریافت شده',
    'assigned': 'اختصاص داده شده',
    'in_progress': 'در حال تعمیر',
    'waiting_parts': 'منتظر قطعات',
    'testing': 'در حال تست',
    'completed_fixed': 'تعمیر موفق',
    'completed_unfixable': 'غیرقابل تعمیر',
    'ready_for_pickup': 'آماده تحویل',
    'delivered': 'تحویل داده شده',
    'cancelled': 'لغو شده',
  };
  
  final Map<String, Color> _statusColors = {
    'received': Colors.blue,
    'assigned': Colors.purple,
    'in_progress': Colors.orange,
    'waiting_parts': Colors.amber,
    'testing': Colors.cyan,
    'completed_fixed': Colors.green,
    'completed_unfixable': Colors.red,
    'ready_for_pickup': Colors.teal,
    'delivered': Colors.grey,
    'cancelled': Colors.black54,
  };

  @override
  void initState() {
    super.initState();
    _service = RepairShopService(ApiClient());
    _loadOrders();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _service.listOrders(
        businessId: widget.businessId,
        status: _selectedStatus,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      
      setState(() {
        _orders = response['items'] as List<RepairOrderListItem>;
        _totalOrders = response['total'] as int;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'خطا در بارگذاری سفارشات: ${ErrorExtractor.forContext(e, context)}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت تعمیرگاه'),
        actions: [
          // فیلتر وضعیت
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'فیلتر وضعیت',
            onSelected: (status) {
              setState(() {
                _selectedStatus = status == 'all' ? null : status;
              });
              _loadOrders();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('همه وضعیت‌ها'),
              ),
              const PopupMenuDivider(),
              ..._statusLabels.entries.map(
                (entry) => PopupMenuItem(
                  value: entry.key,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _statusColors[entry.key],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(entry.value),
                    ],
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'تنظیمات تعمیرگاه',
            onPressed: () {
              context.push('/business/${widget.businessId}/repair-shop-settings');
            },
          ),
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'مدیریت تعمیرکاران',
            onPressed: () {
              context.push('/business/${widget.businessId}/repair-shop-technicians');
            },
          ),
        ],
      ),
      body: _buildBody(theme, colorScheme),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewOrder,
        icon: const Icon(Icons.add),
        label: const Text('سفارش جدید'),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadOrders,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 80,
              color: colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'هنوز سفارش تعمیری ثبت نشده است',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'با دکمه زیر اولین سفارش تعمیر را ثبت کنید',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createNewOrder,
              icon: const Icon(Icons.add),
              label: const Text('ثبت سفارش جدید'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // نوار جستجو و آمار
        _buildSearchBar(theme, colorScheme),
        
        // لیست سفارشات
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadOrders,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _orders.length,
              itemBuilder: (context, index) {
                final order = _orders[index];
                return _buildOrderCard(order, theme, colorScheme);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'جستجو (کد، مشتری، شماره تماس، کالا)...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _loadOrders();
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                
                // لغو تایمر قبلی
                _debounceTimer?.cancel();
                
                // ایجاد تایمر جدید برای debounce
                _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                  _loadOrders();
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          // آمار کوتاه
          _buildStatChip(
            'کل: $_totalOrders',
            Icons.receipt_long,
            colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, IconData icon, Color color) {
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.1),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildOrderCard(RepairOrderListItem order, ThemeData theme, ColorScheme colorScheme) {
    final status = order.status;
    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColors[status] ?? Colors.grey;
    
    final receivedAt = order.receivedAt;
    final dateFormat = intl.DateFormat('yyyy/MM/dd HH:mm', 'fa');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openOrderDetail(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // سطر اول: کد و وضعیت
              Row(
                children: [
                  // کد
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      order.code,
                      style: TextStyle(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // وضعیت
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              
              // مشتری
              Row(
                children: [
                  Icon(Icons.person, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.customerName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (order.customerPhone != null)
                    Text(
                      order.customerPhone!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // کالا
              Row(
                children: [
                  Icon(Icons.devices, size: 18, color: colorScheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.productName,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // مشکل
              Row(
                children: [
                  Icon(Icons.report_problem_outlined, size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.problemDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // تعمیرکار و هزینه
              Row(
                children: [
                  // تعمیرکار
                  if (order.technicianName != null) ...[
                    Icon(Icons.engineering, size: 16, color: colorScheme.tertiary),
                    const SizedBox(width: 4),
                    Text(
                      order.technicianName!,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 16),
                  ],
                  
                  const Spacer(),
                  
                  // هزینه
                  if (order.finalCost > 0) ...[
                    Icon(Icons.payments, size: 16, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      order.formattedFinalCost,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: 8),
              
              // تاریخ دریافت
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text(
                    'دریافت: ${dateFormat.format(receivedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openOrderDetail(RepairOrderListItem order) {
    context.push('/business/${widget.businessId}/repair-shop/${order.id}');
  }

  void _createNewOrder() async {
    final result = await context.push('/business/${widget.businessId}/repair-shop/new');
    
    // اگر سفارش ایجاد شد، لیست را refresh کن
    if (result == true) {
      _loadOrders();
    }
  }
}

