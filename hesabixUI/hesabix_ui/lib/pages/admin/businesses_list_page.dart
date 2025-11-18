import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hesabix_ui/widgets/data_table/data_table.dart';
import 'package:hesabix_ui/core/calendar_controller.dart';
import 'package:hesabix_ui/utils/date_formatters.dart' as date_formatters;
import 'package:hesabix_ui/services/business_api_service.dart';
import 'package:hesabix_ui/utils/number_normalizer.dart';

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
          onRowTap: (item) => _showBusinessDetailsDialog(context, item),
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

class _BusinessDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> business;

  const _BusinessDetailsDialog({required this.business});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final businessName = business['name'] as String? ?? 'نامشخص';

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
                    child: Text(
                      businessName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
                length: 2, // تعداد تب‌ها
                child: Column(
                  children: [
                    TabBar(
                      tabs: const [
                        Tab(text: 'اطلاعات کسب و کار'),
                        Tab(text: 'کیف پول'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildBusinessInfoTab(theme),
                          _WalletTab(businessId: business['id'] as int),
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

  Widget _buildBusinessInfoTab(ThemeData theme) {
    final owner = business['owner'] as Map<String, dynamic>?;
    final defaultCurrency = business['default_currency'] as Map<String, dynamic>?;
    final currencies = business['currencies'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(theme, 'اطلاعات اصلی'),
          _buildInfoCard(
            theme,
            [
              _buildInfoRow(theme, 'شناسه', business['id']?.toString() ?? '-'),
              _buildInfoRow(theme, 'نام کسب و کار', business['name'] ?? '-'),
              _buildInfoRow(theme, 'نوع کسب و کار', business['business_type'] ?? '-'),
              _buildInfoRow(theme, 'زمینه فعالیت', business['business_field'] ?? '-'),
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
              _buildInfoRow(theme, 'تلفن', business['phone'] ?? '-'),
              _buildInfoRow(theme, 'موبایل', business['mobile'] ?? '-'),
              _buildInfoRow(theme, 'آدرس', business['address'] ?? '-'),
              if (business['province'] != null || business['city'] != null)
                _buildInfoRow(
                  theme,
                  'موقعیت',
                  '${business['province'] ?? ''}${business['province'] != null && business['city'] != null ? '، ' : ''}${business['city'] ?? ''}',
                ),
              _buildInfoRow(theme, 'کد پستی', business['postal_code'] ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          
          _buildSectionTitle(theme, 'اطلاعات ثبت'),
          _buildInfoCard(
            theme,
            [
              _buildInfoRow(theme, 'شناسه ملی', business['national_id'] ?? '-'),
              _buildInfoRow(theme, 'شماره ثبت', business['registration_number'] ?? '-'),
              _buildInfoRow(theme, 'شناسه اقتصادی', business['economic_id'] ?? '-'),
              _buildInfoRow(
                theme,
                'تاریخ ایجاد',
                date_formatters.DateFormatters.formatServerDateTime(business['created_at']),
              ),
              _buildInfoRow(
                theme,
                'آخرین بروزرسانی',
                date_formatters.DateFormatters.formatServerDateTime(business['updated_at']),
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
