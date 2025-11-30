import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/utils/date_formatters.dart' as date_formatters;
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';
import '../../core/api_client.dart';
import '../../services/document_monetization_service.dart';
import '../../utils/snackbar_helper.dart';

class BusinessesListPage extends StatefulWidget {
  const BusinessesListPage({super.key});

  @override
  State<BusinessesListPage> createState() => _BusinessesListPageState();
}

class _BusinessesListPageState extends State<BusinessesListPage> {
  CalendarController? _calendarController;

  @override
  void initState() {
    super.initState();
    _initCalendarController();
  }

  Future<void> _initCalendarController() async {
    try {
      final cc = await CalendarController.load();
      if (mounted) {
        setState(() => _calendarController = cc);
      }
    } catch (_) {
      // Calendar controller not required for this page
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مدیریت کسب و کارها',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/user/profile/system-settings'),
        ),
      ),
      body: DataTableWidget<Map<String, dynamic>>(
        config: DataTableConfig<Map<String, dynamic>>(
          endpoint: '/api/v1/admin/businesses/list',
          title: 'مدیریت کسب و کارها',
          subtitle: 'مشاهده و مدیریت لیست همه کسب و کارهای سیستم',
          columns: [
            TextColumn(
              'id',
              'شناسه',
              width: ColumnWidth.small,
              sortable: true,
            ),
            TextColumn(
              'name',
              'نام کسب و کار',
              width: ColumnWidth.large,
              sortable: true,
              searchable: true,
            ),
            TextColumn(
              'business_type',
              'نوع کسب و کار',
              width: ColumnWidth.medium,
              sortable: true,
            ),
            TextColumn(
              'business_field',
              'زمینه فعالیت',
              width: ColumnWidth.medium,
              sortable: true,
            ),
            CustomColumn(
              'owner',
              'مالک',
              width: ColumnWidth.large,
              builder: (item, index) {
                final owner = item['owner'] as Map<String, dynamic>?;
                if (owner == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'نامشخص',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                
                final fullName = owner['full_name'] as String? ?? 
                                '${owner['first_name'] ?? ''} ${owner['last_name'] ?? ''}'.trim();
                final email = owner['email'] as String?;
                final mobile = owner['mobile'] as String?;
                
                // تمیز کردن شماره موبایل (حذف + و اضافه کردن 0 در صورت نیاز)
                String? cleanMobile;
                if (mobile != null && mobile.isNotEmpty) {
                  cleanMobile = mobile.replaceAll('+', '');
                  if (cleanMobile.startsWith('98') && cleanMobile.length == 12) {
                    cleanMobile = '0${cleanMobile.substring(2)}';
                  } else if (!cleanMobile.startsWith('0') && cleanMobile.length == 10) {
                    cleanMobile = '0$cleanMobile';
                  }
                }
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (fullName.isNotEmpty)
                        Text(
                          fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (email != null && email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (cleanMobile != null && cleanMobile.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          cleanMobile,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
            TextColumn(
              'phone',
              'تلفن',
              width: ColumnWidth.medium,
              searchable: true,
              formatter: (item) => item['phone'] as String? ?? '-',
            ),
            TextColumn(
              'mobile',
              'موبایل',
              width: ColumnWidth.medium,
              searchable: true,
              formatter: (item) => item['mobile'] as String? ?? '-',
            ),
            TextColumn(
              'national_id',
              'شناسه ملی',
              width: ColumnWidth.medium,
              searchable: true,
              formatter: (item) => item['national_id'] as String? ?? '-',
            ),
            TextColumn(
              'province',
              'استان',
              width: ColumnWidth.medium,
              sortable: true,
              formatter: (item) {
                final province = item['province'] as String?;
                final city = item['city'] as String?;
                if (province == null && city == null) return '-';
                if (province != null && city != null) return '$province، $city';
                return province ?? city ?? '-';
              },
            ),
            CustomColumn(
              'status',
              'وضعیت',
              width: ColumnWidth.medium,
              builder: (item, index) {
                final isDeleted = item['is_deleted'] as bool? ?? false;
                final isDeletionPending = item['is_deletion_pending'] as bool? ?? false;
                
                if (isDeleted || isDeletionPending) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'در حال حذف',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'فعال',
                      style: TextStyle(
                        color: Colors.green.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
            DateColumn(
              'created_at',
              'تاریخ ایجاد',
              width: ColumnWidth.medium,
              sortable: true,
              showTime: false,
            ),
          ],
          searchFields: ['name', 'phone', 'mobile', 'national_id', 'economic_id'],
          defaultSortBy: 'created_at',
          defaultSortDesc: true,
          defaultPageSize: 20,
          pageSizeOptions: const [10, 20, 50, 100],
          showSearch: true,
          showFilters: true,
          showPagination: true,
          enableSorting: true,
          enableGlobalSearch: true,
          showRefreshButton: true,
          showBackButton: false,
          emptyStateMessage: 'کسب و کاری یافت نشد',
          tableId: 'admin_businesses',
          onRowTap: (item) {
            // جلوگیری از ورود به کسب و کار حذف شده
            final isDeleted = item['is_deleted'] as bool? ?? false;
            if (isDeleted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('این کسب و کار حذف شده است و نمی‌توان به آن دسترسی داشت. می‌توانید آن را بازیابی کنید.'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            _showBusinessDetailsDialog(context, item);
          },
        ),
        fromJson: (json) => Map<String, dynamic>.from(json),
        calendarController: _calendarController,
      ),
    );
  }

  void _showBusinessDetailsDialog(BuildContext context, Map<String, dynamic> business) {
    showDialog(
      context: context,
      builder: (context) => _BusinessDetailsDialog(business: business),
    );
  }
}

class _BusinessDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> business;

  const _BusinessDetailsDialog({required this.business});

  @override
  State<_BusinessDetailsDialog> createState() => _BusinessDetailsDialogState();
}

class _BusinessDetailsDialogState extends State<_BusinessDetailsDialog> {
  bool _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final businessName = widget.business['name'] as String? ?? 'نامشخص';
    final isDeleted = widget.business['is_deleted'] as bool? ?? false;
    final isDeletionPending = widget.business['is_deletion_pending'] as bool? ?? false;
    final businessId = widget.business['id'] as int?;

    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width > 900 ? 800 : 600,
        height: MediaQuery.of(context).size.height > 700 ? 650 : 550,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.business,
                    color: theme.colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          businessName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isDeleted || isDeletionPending)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade300,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'در حال حذف',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isDeleted || isDeletionPending) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isRestoring ? null : () => _handleRestore(context),
                      icon: _isRestoring
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.restore, size: 18),
                      label: Text(_isRestoring ? 'در حال بازیابی...' : 'بازیابی'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.onPrimary,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Tabs
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'اطلاعات کسب و کار'),
                        Tab(text: 'کیف پول'),
                        Tab(text: 'سیاست‌ها و پکیج‌ها'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildBusinessInfoTab(theme),
                          _WalletTab(businessId: widget.business['id'] as int),
                          _BusinessPoliciesTab(businessId: widget.business['id'] as int),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRestore(BuildContext context) async {
    if (widget.business['id'] == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بازیابی کسب و کار'),
        content: Text(
          'آیا مطمئن هستید که می‌خواهید کسب و کار "${widget.business['name']}" را بازیابی کنید؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('بازیابی'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRestoring = true;
    });

    try {
      await BusinessApiService.restoreBusiness(widget.business['id'] as int);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('کسب و کار با موفقیت بازیابی شد'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در بازیابی کسب و کار: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  Widget _buildBusinessInfoTab(ThemeData theme) {
    final owner = widget.business['owner'] as Map<String, dynamic>?;
    final defaultCurrency = widget.business['default_currency'] as Map<String, dynamic>?;
    final currencies = widget.business['currencies'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(theme, 'اطلاعات اصلی'),
          _buildInfoCard(
            theme,
            [
              _buildInfoRow(theme, 'شناسه', widget.business['id']?.toString() ?? '-'),
              _buildInfoRow(theme, 'نام کسب و کار', widget.business['name'] ?? '-'),
              _buildInfoRow(theme, 'نوع کسب و کار', widget.business['business_type'] ?? '-'),
              _buildInfoRow(theme, 'زمینه فعالیت', widget.business['business_field'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          
          if (owner != null) ...[
            _buildSectionTitle(theme, 'اطلاعات مالک'),
            _buildInfoCard(
              theme,
              [
                _buildInfoRow(theme, 'نام کامل', owner['full_name'] ?? '-'),
                _buildInfoRow(theme, 'ایمیل', owner['email'] ?? '-'),
                _buildInfoRow(theme, 'موبایل', _cleanMobileNumber(owner['mobile'])),
              ],
            ),
            const SizedBox(height: 16),
          ],
          
          _buildSectionTitle(theme, 'اطلاعات تماس'),
          _buildInfoCard(
            theme,
            [
              _buildInfoRow(theme, 'تلفن', widget.business['phone'] ?? '-'),
              _buildInfoRow(theme, 'موبایل', widget.business['mobile'] ?? '-'),
              _buildInfoRow(theme, 'آدرس', widget.business['address'] ?? '-'),
              if (widget.business['province'] != null || widget.business['city'] != null)
                _buildInfoRow(
                  theme,
                  'موقعیت',
                  '${widget.business['province'] ?? ''}${widget.business['province'] != null && widget.business['city'] != null ? '، ' : ''}${widget.business['city'] ?? ''}',
                ),
              _buildInfoRow(theme, 'کد پستی', widget.business['postal_code'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildSectionTitle(theme, 'اطلاعات ثبت'),
          _buildInfoCard(
            theme,
            [
              _buildInfoRow(theme, 'شناسه ملی', widget.business['national_id'] ?? '-'),
              _buildInfoRow(theme, 'شماره ثبت', widget.business['registration_number'] ?? '-'),
              _buildInfoRow(theme, 'شناسه اقتصادی', widget.business['economic_id'] ?? '-'),
              _buildInfoRow(
                theme,
                'تاریخ ایجاد',
                date_formatters.DateFormatters.formatServerDateTime(widget.business['created_at']),
              ),
              _buildInfoRow(
                theme,
                'آخرین بروزرسانی',
                date_formatters.DateFormatters.formatServerDateTime(widget.business['updated_at']),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (defaultCurrency != null || currencies.isNotEmpty) ...[
            _buildSectionTitle(theme, 'اطلاعات ارز'),
            _buildInfoCard(
              theme,
              [
                if (defaultCurrency != null)
                  _buildInfoRow(
                    theme,
                    'ارز پیش‌فرض',
                    '${defaultCurrency['title']} (${defaultCurrency['symbol']})',
                  ),
                if (currencies.isNotEmpty)
                  _buildInfoRow(
                    theme,
                    'ارزهای فعال',
                    currencies
                        .map((c) => '${c['title']} (${c['symbol']})')
                        .join('، '),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme, List<Widget> children) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _cleanMobileNumber(dynamic mobile) {
    if (mobile == null || mobile.toString().isEmpty) return '-';
    String cleaned = mobile.toString().replaceAll('+', '');
    if (cleaned.startsWith('98') && cleaned.length == 12) {
      cleaned = '0${cleaned.substring(2)}';
    } else if (!cleaned.startsWith('0') && cleaned.length == 10) {
      cleaned = '0$cleaned';
    }
    return cleaned;
  }
}

class _WalletTab extends StatefulWidget {
  final int businessId;

  const _WalletTab({required this.businessId});

  @override
  State<_WalletTab> createState() => _WalletTabState();
}

class _WalletTabState extends State<_WalletTab> {
  Map<String, dynamic>? _walletData;
  bool _isLoading = false;
  bool _isLoadingWallet = true;
  String? _errorMessage;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadWalletData() async {
    setState(() {
      _isLoadingWallet = true;
      _errorMessage = null;
    });

    try {
      final data = await BusinessApiService.getBusinessWalletAdmin(widget.businessId);
      if (mounted) {
        setState(() {
          _walletData = data;
          _isLoadingWallet = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoadingWallet = false;
        });
      }
    }
  }

  Future<void> _addGiftBalance() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // استفاده از parseFormattedDouble برای تبدیل مقدار فرمت‌شده به عدد
      final amount = parseFormattedDouble(_amountController.text);
      if (amount == null || amount <= 0) {
        throw Exception('مبلغ نامعتبر است');
      }

      await BusinessApiService.addGiftBalanceAdmin(
        businessId: widget.businessId,
        amount: amount,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        reason: _reasonController.text.isEmpty ? null : _reasonController.text,
      );

      // پاک کردن فرم
      _amountController.clear();
      _descriptionController.clear();
      _reasonController.clear();

      // بارگذاری مجدد اطلاعات کیف‌پول
      await _loadWalletData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('موجودی هدیه با موفقیت اضافه شد'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoadingWallet) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _walletData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'خطا در دریافت اطلاعات کیف‌پول',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadWalletData,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // نمایش اطلاعات کیف‌پول
          if (_walletData != null) ...[
            _buildSectionTitle(theme, 'وضعیت کیف‌پول'),
            _buildWalletInfoCard(theme, _walletData!),
            const SizedBox(height: 24),
          ],

          // فرم افزودن موجودی هدیه
          _buildSectionTitle(theme, 'افزودن موجودی هدیه'),
          _buildGiftForm(theme),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildWalletInfoCard(ThemeData theme, Map<String, dynamic> walletData) {
    final availableBalance = walletData['available_balance'] as double? ?? 0.0;
    final pendingBalance = walletData['pending_balance'] as double? ?? 0.0;
    final status = walletData['status'] as String? ?? 'active';
    final currencyCode = walletData['base_currency_code'] as String? ?? 'IRR';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              theme,
              'موجودی قابل استفاده',
              _formatCurrency(availableBalance, currencyCode),
              Colors.green[700],
              FontWeight.bold,
            ),
            const Divider(height: 24),
            _buildInfoRow(
              theme,
              'موجودی در انتظار',
              _formatCurrency(pendingBalance, currencyCode),
              Colors.orange[700],
            ),
            const Divider(height: 24),
            _buildInfoRow(
              theme,
              'وضعیت',
              status == 'active' ? 'فعال' : 'معلق',
              status == 'active' ? Colors.green : Colors.red,
            ),
            const Divider(height: 24),
            _buildInfoRow(theme, 'ارز پایه', currencyCode),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    String label,
    String value, [
    Color? valueColor,
    FontWeight? valueFontWeight,
  ]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: valueColor,
            fontWeight: valueFontWeight ?? FontWeight.normal,
          ),
        ),
      ],
    );
  }

  String _formatCurrency(double amount, String currencyCode) {
    final formatted = amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$formatted $currencyCode';
  }

  Widget _buildGiftForm(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'مبلغ *',
                  hintText: 'مبلغ هدیه را وارد کنید (مثلاً 1,000,000)',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  const EnglishDigitsFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'^[\d,]*\.?\d*')),
                  const ThousandsSeparatorInputFormatter(allowDecimal: true),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'مبلغ الزامی است';
                  }
                  // استفاده از parseFormattedDouble برای تبدیل مقدار فرمت‌شده به عدد
                  final amount = parseFormattedDouble(value);
                  if (amount == null || amount <= 0) {
                    return 'مبلغ باید بزرگتر از صفر باشد';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'توضیحات',
                  hintText: 'توضیحات (اختیاری)',
                  prefixIcon: Icon(Icons.description),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'دلیل',
                  hintText: 'دلیل افزودن موجودی (اختیاری)',
                  prefixIcon: Icon(Icons.info_outline),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _addGiftBalance,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.card_giftcard),
                label: Text(_isLoading ? 'در حال افزودن...' : 'افزودن موجودی هدیه'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessPoliciesTab extends StatefulWidget {
  final int businessId;
  const _BusinessPoliciesTab({required this.businessId});

  @override
  State<_BusinessPoliciesTab> createState() => _BusinessPoliciesTabState();
}

class _BusinessPoliciesTabState extends State<_BusinessPoliciesTab> {
  final DocumentMonetizationService _service = DocumentMonetizationService(ApiClient());
  bool _loading = true;
  bool _assigningPlan = false;
  bool _deleting = false;
  String? _error;
  int? _selectedPlanId;
  List<Map<String, dynamic>> _policies = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _plans = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final policies = await _service.listBusinessPoliciesAdmin(widget.businessId);
      final plans = await _service.listSubscriptionPlans(onlyActive: true);
      setState(() {
        _policies = policies;
        _plans = plans;
        if (_selectedPlanId == null && plans.isNotEmpty) {
          _selectedPlanId = plans.first['id'] as int?;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _assignPlan() async {
    if (_selectedPlanId == null) {
      _showSnack('پلن را انتخاب کنید');
      return;
    }
    setState(() => _assigningPlan = true);
    try {
      await _service.assignSubscriptionToBusiness(
        widget.businessId,
        {'plan_id': _selectedPlanId, 'auto_renew': false},
      );
      _showSnack('پلن با موفقیت اعمال شد');
    } catch (e) {
      _showSnack('خطا در اعمال پلن: $e');
    } finally {
      if (mounted) {
        setState(() => _assigningPlan = false);
      }
    }
  }

  Future<void> _deletePolicy(int policyId) async {
    setState(() => _deleting = true);
    try {
      await _service.deleteBusinessPolicyAdmin(widget.businessId, policyId);
      await _loadData();
      _showSnack('سیاست حذف شد');
    } catch (e) {
      _showSnack('خطا در حذف سیاست: $e');
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _openPolicyDialog({Map<String, dynamic>? initial}) async {
    final formKey = GlobalKey<FormState>();
    final titleCtrl = TextEditingController(text: initial?['title'] ?? '');
    final priorityCtrl = TextEditingController(text: initial?['priority']?.toString() ?? '120');
    final configCtrl = TextEditingController(
      text: initial == null ? '{\n  "fee_amount": 0\n}' : const JsonEncoder.withIndent('  ').convert(initial['config'] ?? {}),
    );
    bool isActive = initial?['is_active'] ?? true;
    String policyType = (initial?['policy_type'] ?? 'per_document') as String;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setInnerState) => AlertDialog(
            title: Text(initial == null ? 'سیاست جدید' : 'ویرایش سیاست'),
            content: SizedBox(
              width: 480,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(labelText: 'عنوان'),
                        validator: (v) => v == null || v.isEmpty ? 'عنوان الزامی است' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: policyType,
                        decoration: const InputDecoration(labelText: 'نوع سیاست'),
                        items: const [
                          DropdownMenuItem(value: 'free', child: Text('رایگان')),
                          DropdownMenuItem(value: 'subscription', child: Text('اشتراک')),
                          DropdownMenuItem(value: 'per_document', child: Text('به‌ازای هر سند')),
                          DropdownMenuItem(value: 'volume', child: Text('حجمی/تناوبی')),
                          DropdownMenuItem(value: 'hybrid', child: Text('ترکیبی')),
                        ],
                        onChanged: (v) => setInnerState(() => policyType = v ?? policyType),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: priorityCtrl,
                        decoration: const InputDecoration(labelText: 'اولویت'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) => v == null || v.isEmpty ? 'اولویت الزامی است' : null,
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('فعال'),
                        value: isActive,
                        onChanged: (v) => setInnerState(() => isActive = v),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: configCtrl,
                        decoration: const InputDecoration(
                          labelText: 'پیکربندی (JSON)',
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'پیکربندی الزامی است';
                          try {
                            jsonDecode(v);
                            return null;
                          } catch (_) {
                            return 'فرمت JSON نامعتبر است';
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  if (!context.mounted) return;
                  final ctx = context;
                  try {
                    final config = jsonDecode(configCtrl.text) as Map<String, dynamic>;
                    final payload = <String, dynamic>{
                      'title': titleCtrl.text.trim(),
                      'policy_type': policyType,
                      'priority': int.parse(priorityCtrl.text.trim()),
                      'is_active': isActive,
                      'config': config,
                    };
                    if (initial != null) {
                      payload['id'] = initial['id'];
                    }
                    await _service.saveBusinessPolicyAdmin(widget.businessId, payload);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    _loadData();
                  } catch (e) {
                    _showSnack('خطا در ذخیره سیاست: $e');
                  }
                },
                child: const Text('ذخیره'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('تعیین پکیج اشتراک برای کسب‌وکار', style: TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'به‌روزرسانی پلن‌ها',
                        onPressed: _loadData,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedPlanId,
                    items: _plans
                        .map(
                          (plan) => DropdownMenuItem<int>(
                            value: plan['id'] as int?,
                            child: Text('${plan['name']} (${plan['period_months']} ماه)'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedPlanId = v),
                    decoration: const InputDecoration(
                      labelText: 'انتخاب پکیج',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _assigningPlan ? null : _assignPlan,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(_assigningPlan ? 'در حال اعمال...' : 'اعمال پکیج'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('سیاست‌های فعال', style: TextStyle(fontWeight: FontWeight.bold)),
                      FilledButton.icon(
                        onPressed: () => _openPolicyDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('سیاست جدید'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_policies.isEmpty)
                    const Text('سیاستی ثبت نشده است', textAlign: TextAlign.center)
                  else
                    ..._policies.map((policy) {
                      final status = policy['is_active'] == true ? 'فعال' : 'غیرفعال';
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text(policy['title'] as String? ?? '-'),
                          subtitle: Text('نوع: ${policy['policy_type']} | اولویت: ${policy['priority']} | وضعیت: $status'),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                tooltip: 'ویرایش',
                                onPressed: () => _openPolicyDialog(initial: policy),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: _deleting ? 'در حال حذف...' : 'حذف',
                                onPressed: _deleting ? null : () => _deletePolicy(policy['id'] as int),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    SnackBarHelper.show(context, message: message);
  }
}
