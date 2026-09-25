import 'package:hesabix_ui/theme/glass.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../services/repair_shop_service.dart';
import '../../../models/repair_order_model.dart';
import '../../../core/api_client.dart';
import '../../../core/calendar_controller.dart';
import '../../../core/date_utils.dart';
import '../../../utils/error_extractor.dart';
import '../../../widgets/date_input_field.dart';
import '../../../widgets/business_subpage_back_leading.dart';
import 'repair_shop_calendar_utils.dart';
import 'package:hesabix_ui/theme/semantic_color_resolver.dart';

/// صفحه لیست سفارشات تعمیر
class RepairOrdersListPage extends StatefulWidget {
  final int businessId;
  final CalendarController calendarController;

  const RepairOrdersListPage({
    super.key,
    required this.businessId,
    required this.calendarController,
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
  DateTime? _fromDate;
  DateTime? _toDate;
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

  Color _statusColorFor(BuildContext context, String? status) {
    final map = <String, Color>{
    'received': SemanticColorResolver.info(context),
    'assigned': Colors.purple,
    'in_progress': SemanticColorResolver.warning(context),
    'waiting_parts': Colors.amber,
    'testing': Colors.cyan,
    'completed_fixed': SemanticColorResolver.positive(context),
    'completed_unfixable': SemanticColorResolver.negative(context),
    'ready_for_pickup': Colors.teal,
    'delivered': Colors.grey,
    'cancelled': Colors.black54,
    };
    return map[status] ?? Colors.grey;
  }


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
        search: _searchController.text.trim().isNotEmpty
            ? _searchController.text.trim()
            : null,
        fromDate: _fromDate != null
            ? HesabixDateUtils.formatForApiDate(_fromDate!)
            : null,
        toDate: _toDate != null
            ? HesabixDateUtils.formatForApiDate(_toDate!)
            : null,
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

  Future<void> _openDateFilterSheet() async {
    DateTime? fromDate = _fromDate;
    DateTime? toDate = _toDate;

    final applied = await showGlassModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'فیلتر تاریخ دریافت',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  DateInputField(
                    labelText: 'از تاریخ',
                    value: fromDate,
                    calendarController: widget.calendarController,
                    onChanged: (value) => setModalState(() => fromDate = value),
                  ),
                  const SizedBox(height: 12),
                  DateInputField(
                    labelText: 'تا تاریخ',
                    value: toDate,
                    calendarController: widget.calendarController,
                    onChanged: (value) => setModalState(() => toDate = value),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            fromDate = null;
                            toDate = null;
                          });
                        },
                        child: const Text('پاک کردن'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('اعمال'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {
        _fromDate = fromDate;
        _toDate = toDate;
      });
      _loadOrders();
    }
  }

  bool get _hasDateFilter => _fromDate != null || _toDate != null;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.calendarController,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: const Text('مدیریت تعمیرگاه'),
            leading: hesabixBackAppBarLeading(context, businessId: widget.businessId),
            actions: [
              IconButton(
                icon: Icon(
                  Icons.date_range,
                  color: _hasDateFilter ? colorScheme.primary : null,
                ),
                tooltip: 'فیلتر تاریخ',
                onPressed: _openDateFilterSheet,
              ),
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
                              color: _statusColorFor(context, entry.key),
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
      },
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: colorScheme.error),
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
        _buildSearchBar(theme, colorScheme),
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
    final isJalali = widget.calendarController.isJalali;

    return Container(
      padding: const EdgeInsets.all(16),
      color: colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasDateFilter) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    'از ${HesabixDateUtils.formatForDisplay(_fromDate, isJalali)} '
                    'تا ${HesabixDateUtils.formatForDisplay(_toDate, isJalali)}',
                  ),
                  onDeleted: () {
                    setState(() {
                      _fromDate = null;
                      _toDate = null;
                    });
                    _loadOrders();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                        ),
                        onChanged: (value) {
                          _debounceTimer?.cancel();
                          _debounceTimer = Timer(
                            const Duration(milliseconds: 500),
                            _loadOrders,
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: ListenableBuilder(
                        listenable: _searchController,
                        builder: (context, _) {
                          if (_searchController.text.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _debounceTimer?.cancel();
                              _loadOrders();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildStatChip(
                'کل: $_totalOrders',
                Icons.receipt_long,
                colorScheme.primary,
              ),
            ],
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

  Widget _buildOrderCard(
    RepairOrderListItem order,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final status = order.status;
    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColorFor(context, status);
    final isJalali = widget.calendarController.isJalali;
    final receivedLabel = RepairShopCalendarUtils.formatDateTime(
      order.receivedAt,
      isJalali,
    );

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
              Row(
                children: [
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
                        SizedBox(width: 6),
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
              Row(
                children: [
                  Icon(Icons.report_problem_outlined, size: 18, color: SemanticColorResolver.warning(context)),
                  SizedBox(width: 8),
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
              Row(
                children: [
                  if (order.technicianName != null) ...[
                    Icon(Icons.engineering, size: 16, color: colorScheme.tertiary),
                    const SizedBox(width: 4),
                    Text(order.technicianName!, style: theme.textTheme.bodySmall),
                    const SizedBox(width: 16),
                  ],
                  const Spacer(),
                  if (order.finalCost > 0) ...[
                    Icon(Icons.payments, size: 16, color: SemanticColorResolver.positive(context)),
                    SizedBox(width: 4),
                    Text(
                      order.formattedFinalCost,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: SemanticColorResolver.positive(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'دریافت: $receivedLabel',
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
    if (result == true) {
      _loadOrders();
    }
  }
}
